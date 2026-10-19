import AppKit
import Carbon
import ServiceManagement

// CorkClip — コピーした物を、コルクボードにピンで留めるように取っておく。クリップボードの履歴をこのMacに保存し、⌥⌘V で画面の端から呼び出す。
// Dock には出さず、メニューバーに常駐する（LSUIElement）。corkclip:// と、kobito シリーズの約束の kobito://corkclip/… で呼べる（F-18）。

@main
@MainActor
struct CorkClipApplication {
    static func main() {
        // 起動情報（④）だけを書いて終わる（開発中に約束の確かめに使う。履歴やクリップボードには触れない）。
        if CommandLine.arguments.contains("--write-launch-info") {
            do { try Series.writeLaunchInfo(bundleID: Bundle.main.bundleIdentifier ?? Series.defaultBundleID); exit(0) }
            catch { FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(1) }
        }
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var settings = Settings()
    private var settingsURL: URL!
    private var store: ClipStore!
    private var watcher: PasteboardWatcher!
    private var paster: Paster!
    private var panel: PanelController!
    private var stack: PasteStack!
    private var settingsWindow: SettingsWindowController!
    /// workspace に残したクリップの DB の形（schema/kept/）。
    private var keptSchema: URL!
    private var openHotKey: HotKey?
    private var stackHotKey: HotKey?
    private var statusItem: NSStatusItem!
    private var cleanupTimer: Timer?
    private var pendingURLs: [URL] = []
    private var launched = false
    private var ocrRunning = false
    /// 保存・整理・タグの同期・書き出しは裏の1本のキューで順に行う。
    private let storeQueue = DispatchQueue(label: "io.github.kobito-tools.corkclip.store", qos: .utility)
    /// 文字認識は重いので別のキューで行う。
    private let ocrQueue = DispatchQueue(label: "io.github.kobito-tools.corkclip.ocr", qos: .background)

    // MARK: - 起動

    /// URL は「URL を開く」Apple Event で届く。未起動から開かれたときは didFinishLaunching より前に届くので、ここで受け口を作る。
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleGetURL(_:withReply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let directory = ClipStore.defaultDirectory
        settingsURL = directory.appendingPathComponent("settings.json")
        settings = Settings.load(from: settingsURL)
        let resources = Bundle.main.resourceURL!
        do {
            store = try ClipStore(directory: directory, schemaDirectory: resources.appendingPathComponent("schema"))
        } catch {
            let alert = NSAlert()
            alert.messageText = "履歴のデータを開けませんでした"
            alert.informativeText = "\(directory.path)\n\n\(error)"
            alert.runModal()
            NSApplication.shared.terminate(nil)
            return
        }
        keptSchema = resources.appendingPathComponent("schema/kept")
        paster = Paster(store: store) { [unowned self] in settings }
        watcher = PasteboardWatcher(excludedBundleIDs: { [unowned self] in settings.excludedBundleIDs }) { [unowned self] capture in save(capture) }
        paster.didWrite = { [unowned self] in watcher.skipCurrentChange() }
        watcher.start()

        stack = PasteStack(paster: paster) { [unowned self] in settings.reverseStack }
        stack.onChange = { [weak self] in self?.updateStatusIcon() }

        panel = PanelController(store: store) { [unowned self] in settings }
        panel.onCommand = { [unowned self] command, target in handle(command, target: target) }
        panel.model.onSortChange = { [unowned self] sort in updateSettings { $0.sortOrder = sort } }
        panel.model.onLatexOptionsChange = { [unowned self] options in if settings.latexOptions != options { updateSettings { $0.latexOptions = options } } }
        panel.model.onSaveCombo = { [unowned self] combo in updateSettings { $0.transformCombos.append(combo) } }
        panel.model.shareTargets = { [unowned self] ids in shareTargets(ids) }

        let settingsModel = SettingsModel(settings: settings)
        settingsModel.onChange = { [unowned self] new in applySettings(new) }
        settingsModel.onCleanup = { [unowned self] in cleanupNow() }
        settingsModel.onChooseBasePath = { [unowned self] in chooseBasePath() }
        settingsModel.refreshUsage = { [unowned self] in (try? store.usage()) ?? (0, 0) }
        settingsModel.onClose = { [weak self] in self?.panel.endSettingsPreview() }
        settingsModel.loadTags = { [unowned self] in ((try? store.allTags()) ?? []).map(\.name) }
        settingsWindow = SettingsWindowController(model: settingsModel)

        registerHotKeys(alertOnFailure: true)
        configureStatusItem()
        writeLaunchInfo()

        // 期限切れの整理は、起動時と1時間ごとに行う。文字認識の残りと共有タグもここで進める。
        runCleanup()
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.runCleanup() } }
        scheduleOCR()
        syncTags()
        recordDataset()
        refreshCards()

        launched = true
        pendingURLs.forEach(handle)
        pendingURLs.removeAll()
    }

    // MARK: - 取得したコピー

    private func save(_ capture: Capture) {
        let store = store!, maxItemBytes = settings.maxItemBytes
        let autoTags = settings.autoTags(bundleID: capture.sourceBundleID, appName: capture.sourceAppName, text: capture.plainText)
        storeQueue.async { [weak self] in
            var savedID: Int?
            do {
                let id = try store.save(capture, maxItemBytes: maxItemBytes).id
                for name in autoTags { try store.addTag(try store.findOrCreateTag(name), to: [id], source: "auto") }
                savedID = id
            } catch { NSLog("CorkClip: 保存できませんでした: \(error)") }
            DispatchQueue.main.async {
                guard let self else { return }
                if let savedID, self.stack.isActive { self.stack.push([savedID]) }
                self.panel.refreshIfVisible()
                if let savedID, !autoTags.isEmpty { self.tagsChanged([savedID]) }
                if capture.kind == .image { self.scheduleOCR() }
            }
        }
    }

    // MARK: - 文字認識（F-08）

    private func scheduleOCR() {
        guard !ocrRunning else { return }
        ocrRunning = true
        let store = store!
        ocrQueue.async { [weak self] in
            var done = 0
            while let batch = try? store.pendingOCR(limit: 5), !batch.isEmpty {
                for item in batch {
                    try? store.setOCR(item.id, text: OCR.recognize(item.data))
                    done += 1
                }
            }
            DispatchQueue.main.async {
                self?.ocrRunning = false
                if done > 0 { self?.panel.refreshIfVisible() }
            }
        }
    }

    // MARK: - パネルからの操作

    private func handle(_ command: PanelCommand, target: NSRunningApplication?) {
        switch command {
        case .paste(let ids, let mode):
            if ids.count == 1 { paster.paste(ids[0], mode: mode, into: target) }
            else {
                // 複数選んで ⏎ のときは、文字を改行でつないで貼る。
                let texts = ids.compactMap { try? store.text(of: $0) }
                let joined = texts.map { mode == .joinLines ? LineJoiner.join($0, keepParagraphs: settings.keepParagraphBreaks) : $0 }.joined(separator: "\n")
                guard !joined.isEmpty else { NSSound.beep(); return }
                ids.forEach(paster.markUsed)
                paster.paste(text: joined, into: target)
            }
        case .copyOnly(let id):
            paster.write(id, mode: .original)
        case .pasteText(let text, let copyOnly):
            if copyOnly { paster.write(Paster.textItems(text)) } else { paster.paste(text: text, into: target) }
        case .pasteLatex(let image, let copyOnly):
            let capture = Capture(items: [image.representations], sourceBundleID: Bundle.main.bundleIdentifier, sourceAppName: "数式",
                                  plainText: image.latex.source, latex: image.latex)
            let store = store!
            storeQueue.async { _ = try? store.save(capture, maxItemBytes: .max) }
            if copyOnly { paster.write([image.representations]) } else { paster.deliver([image.representations], into: target, cursorOffset: nil) }
        case .keep(let ids):
            keep(ids, automatic: false)
        case .share(let ids, let target):
            share(ids, to: target)
        case .pushToStack(let ids):
            stack.push(ids)
        case .tagsChanged(let ids):
            tagsChanged(ids)
        case .openSettings:
            settingsWindow.show()
        }
    }

    // MARK: - 共有タグ（F-04）

    /// 基準パスがあれば、このMacの履歴のタグと tags.json を統合する。
    private func syncTags() {
        guard let basePath = settings.basePath, (try? Dataset.read(basePath)) != nil else { return }
        let store = store!
        storeQueue.async {
            do { try store.syncTags(basePath: basePath) } catch { NSLog("CorkClip: 共有タグを同期できません: \(error)") }
        }
    }

    /// ⑥ 基準パスの履歴に、開いている基準パスを記録する（ほかのアプリが保存先を選ぶときの候補になる）。
    private func recordDataset() {
        guard let basePath = settings.basePath, let info = try? Dataset.read(basePath) else { return }
        do { try Series.recordDataset(path: basePath, id: info.datasetId) } catch { NSLog("CorkClip: 基準パスの履歴に書けません: \(error)") }
    }

    private func tagsChanged(_ ids: [Int]) {
        syncTags()
        // 自動で残すタグが付いた物は、まだなら workspace に残す。
        guard settings.workspaceKeep, !settings.autoExportTags.isEmpty, settings.basePath != nil else { return }
        let wanted = Set(settings.autoExportTags.map { $0.lowercased() })
        let targets = ids.filter { id in
            (try? store.exportedAt(id)) == nil && ((try? store.tags(of: id)) ?? []).contains { wanted.contains($0.name.lowercased()) }
        }
        if !targets.isEmpty { keep(targets, automatic: true) }
    }

    // MARK: - workspace に残す（F-17）

    private func keep(_ ids: [Int], automatic: Bool) {
        guard settings.workspaceKeep else { if !automatic { NSSound.beep() }; return }
        guard let basePath = settings.basePath else {
            if !automatic {
                panel.model.show("先に設定の「連携」で基準パスを選んでください")
                panel.hide(animated: false)
                settingsWindow.show()
            }
            return
        }
        guard (try? Dataset.read(basePath)) != nil || (!automatic && createDataset(basePath)) else { return }
        let store = store!, schema = keptSchema!
        let pending = ids.filter { (try? store.exportedAt($0)) == nil }
        guard !pending.isEmpty else { panel.model.show("選んだ項目はもう workspace に残してあります"); return }
        storeQueue.async { [weak self] in
            let now = Date()
            let result: Result<Void, Error> = Result {
                // 共有タグを先にそろえて、カードには tags.json のタグIDを入れる。
                try? store.syncTags(basePath: basePath)
                try WorkspaceCards.keep(pending.compactMap { Self.keptEntry($0, store: store) }, basePath: basePath, schemaDirectory: schema, now: now)
                try store.markExported(pending, at: now)
            }
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.panel.model.show("workspace に残しました（\(WorkspaceCards.title(day: Series.day(now)))・\(pending.count)件）")
                    self?.panel.refreshIfVisible()
                case .failure(let error):
                    let message = (error as? StoreError)?.message ?? "\(error)"
                    if automatic { NSLog("CorkClip: workspace に残せませんでした: \(message)") }
                    else { self?.alert("workspace に残せませんでした", message) }
                }
            }
        }
    }

    private nonisolated static func keptEntry(_ id: Int, store: ClipStore) -> WorkspaceCards.Entry? {
        guard let detail = try? store.detail(id, maxTextLength: ClipStore.maxStoredTextLength) else { return nil }
        let tags = (try? store.tags(of: id)) ?? []
        return WorkspaceCards.Entry(clipID: id, copiedAt: detail.summary.copiedAt, appName: detail.summary.isSnippet ? "定型文" : detail.summary.sourceAppName,
                                    tagNames: tags.map(\.name), tagIDs: tags.map(\.id), text: detail.text, latex: detail.latex?.source,
                                    filePaths: detail.filePaths, ocrText: detail.ocrText, image: detail.imageData.flatMap(png))
    }

    /// 起動時と基準パスを変えたときに、カードを書き直す（以前の書き出し先からの移し替えも、ここで一度だけ行う）。
    private func refreshCards() {
        guard settings.workspaceKeep, let basePath = settings.basePath, (try? Dataset.read(basePath)) != nil else { return }
        let schema = keptSchema!
        storeQueue.async {
            do { try WorkspaceCards.refresh(basePath: basePath, schemaDirectory: schema) } catch { NSLog("CorkClip: カードを書き出せません: \(error)") }
        }
    }

    /// 画像を PNG にそろえる（残す画像・送る画像）。
    private nonisolated static func png(_ data: Data) -> Data? {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return data }
        guard let image = NSImage(data: data), let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    /// 基準パスに共有フォルダ（.kobito-tools）を作る。ID を尋ねる。
    private func createDataset(_ basePath: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "基準パスに共有フォルダを作ります"
        alert.informativeText = "「\(basePath)」に .kobito-tools を作り、kobito シリーズのアプリと共有します。このデータセットの ID（名前）を入力してください。"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = (basePath as NSString).lastPathComponent
        alert.accessoryView = field
        alert.addButton(withTitle: "作る")
        alert.addButton(withTitle: "やめる")
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        do { _ = try Dataset.create(basePath, datasetId: field.stringValue); recordDataset(); return true }
        catch { self.alert("共有フォルダを作れませんでした", (error as? StoreError)?.message ?? "\(error)"); return false }
    }

    private func chooseBasePath() {
        let open = NSOpenPanel()
        open.canChooseDirectories = true
        open.canChooseFiles = false
        open.message = "基準パス（kobito シリーズで共有するフォルダ）を選んでください"
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard open.runModal() == .OK, let url = open.url else { return }
        let basePath = Dataset.basePath(for: url)
        do {
            if try Dataset.read(basePath) == nil, !createDataset(basePath) { return }
        } catch { alert("このフォルダは使えません", (error as? StoreError)?.message ?? "\(error)"); return }
        updateSettings { $0.basePath = basePath }
        settingsWindow.model.datasetID = try? Dataset.read(basePath)?.datasetId
    }

    // MARK: - 送る（F-16）

    /// 選んだ項目の中身（⑦ 受け渡し）。画像は PNG にそろえ、ファイルはパスだけを渡す。
    private func sharePayload(_ ids: [Int]) -> Share.Payload {
        var texts: [String] = [], payload = Share.Payload()
        for id in ids {
            guard let detail = try? store.detail(id, maxTextLength: ClipStore.maxStoredTextLength) else { continue }
            if let data = detail.imageData.flatMap(Self.png) { payload.images.append(Share.Image(name: "クリップ\(payload.images.count + 1).png", mimeType: "image/png", data: data)) }
            if !detail.filePaths.isEmpty { payload.files += detail.filePaths.map { Share.File(path: $0, name: ($0 as NSString).lastPathComponent) } }
            else if let latex = detail.latex { texts.append(latex.source) }
            else if let text = detail.text, !text.isEmpty { texts.append(text) }
        }
        payload.text = texts.joined(separator: "\n\n")
        return payload
    }

    private func shareTargets(_ ids: [Int]) -> [Share.Target] {
        Share.targets(for: sharePayload(ids).kinds)
    }

    private func share(_ ids: [Int], to target: Share.Target) {
        let payload = sharePayload(ids)
        guard !payload.kinds.isDisjoint(with: target.receive.accepts) else { NSSound.beep(); return }
        do {
            try Share.send(payload, to: target)
            if settings.lastShareTarget != target.key { updateSettings { $0.lastShareTarget = target.key } }
        } catch {
            alert("\(target.appName) に送れませんでした", (error as? StoreError)?.message ?? error.localizedDescription)
        }
    }

    // MARK: - 設定

    private func updateSettings(_ change: (inout Settings) -> Void) {
        var new = settings
        change(&new)
        applySettings(new)
        if let model = settingsWindow?.model, model.settings != new { model.settings = new }
    }

    private func applySettings(_ new: Settings) {
        let old = settings
        guard old != new else { return }
        settings = new
        settings.save(to: settingsURL)
        if old.openPanelHotKey != new.openPanelHotKey || old.stackHotKey != new.stackHotKey { registerHotKeys(alertOnFailure: true) }
        if old.basePath != new.basePath || old.workspaceKeep != new.workspaceKeep { syncTags(); recordDataset(); refreshCards() }
        // パネルの見た目を変えたら、設定の画面の横に実物を出して、すぐに反映する。
        let looks = { (value: Settings) in [value.panelWidth, value.panelEdge == .right ? 1 : 0, value.panelScreen == .mouse ? 1 : 0, value.showPreview ? 1 : 0, value.showKobito ? 1 : 0, Double(RowColorMode.allCases.firstIndex(of: value.rowColorMode) ?? 0)] }
        if looks(old) != looks(new), settingsWindow?.isVisible == true { panel.showForSettings() }
    }

    private func registerHotKeys(alertOnFailure: Bool) {
        openHotKey = nil
        stackHotKey = nil
        openHotKey = HotKey(keyCode: settings.openPanelHotKey.keyCode, modifiers: settings.openPanelHotKey.modifiers) { [weak self] in self?.panel.toggle() }
        stackHotKey = HotKey(keyCode: settings.stackHotKey.keyCode, modifiers: settings.stackHotKey.modifiers) { [weak self] in self?.stack.toggle() }
        let failed = [(openHotKey == nil, settings.openPanelHotKey), (stackHotKey == nil, settings.stackHotKey)].filter(\.0).map { $0.1.display }
        if alertOnFailure, !failed.isEmpty {
            alert("ショートカット \(failed.joined(separator: "・")) を登録できませんでした", "ほかのアプリが同じショートカットを使っている可能性があります。設定の「一般」で変えられます。")
        }
    }

    private func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - 整理（F-15）

    private func runCleanup(then completion: ((ClipStore.CleanupReport) -> Void)? = nil) {
        let store = store!, settings = settings
        storeQueue.async {
            let report = (try? store.cleanup(settings: settings)) ?? ClipStore.CleanupReport()
            DispatchQueue.main.async { completion?(report) }
        }
    }

    private func cleanupNow() {
        runCleanup { [weak self] report in
            guard let self else { return }
            self.settingsWindow.model.usage = (try? self.store.usage()) ?? (0, 0)
            self.alert("整理しました", "期限切れや上限を超えた項目を \(report.removedClips) 件、使われなくなった生データを \(report.removedBlobs) 個消しました。")
        }
    }

    // MARK: - URL（F-18）

    /// ④ 起動情報。workspace などが、これを使って CorkClip を起動し、kobito://corkclip/… を渡す。
    private func writeLaunchInfo() {
        do { try Series.writeLaunchInfo(bundleID: Bundle.main.bundleIdentifier ?? Series.defaultBundleID) }
        catch { NSLog("CorkClip: 起動情報を書き出せません: \(error)") }
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue, let url = URL(string: text) else { return }
        let scheme = url.scheme?.lowercased()
        // kobito:// はこのアプリ宛て（kobito://corkclip/…）だけを受け取る。
        guard scheme == "corkclip" || Series.route(url) != nil else { return }
        if launched { handle(url) } else { pendingURLs.append(url) }
    }

    private func handle(_ url: URL) {
        if url.scheme?.lowercased() == "kobito" { handleSeriesURL(url); return }
        let parameters = Dictionary((URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") }) { _, last in last }
        let path = ([url.host ?? ""] + url.pathComponents.filter { $0 != "/" }).filter { !$0.isEmpty }.map { $0.lowercased() }
        switch path.first {
        case "open", nil:
            var query = parameters["query"] ?? ""
            if let tag = parameters["tag"], !tag.isEmpty { query = (query.isEmpty ? "" : query + " ") + "#\(tag)" }
            panel.show(query: query)
        case "latex": panel.show(mode: .latex)
        case "snippet": panel.show(mode: .snippet)
        case "stack":
            switch path.dropFirst().first {
            case "start": stack.start()
            case "stop": stack.stop()
            default: stack.toggle()
            }
        case "pause":
            if let minutes = parameters["minutes"].flatMap(Int.init) { setPaused(true, until: Date().addingTimeInterval(Double(minutes) * 60)) }
            else { setPaused(!watcher.effectivelyPaused, until: nil) }
        case "resume": setPaused(false, until: nil)
        case "settings": settingsWindow.show()
        default: panel.show()
        }
    }

    private func handleSeriesURL(_ url: URL) {
        switch Series.route(url) {
        case .day(let day): panel.show(query: "kept:\(day)")
        case .open(let id): panel.show(query: "id:\(id)")
        case .snippet: panel.show(mode: .snippet)
        case .latex: panel.show(mode: .latex)
        case .settings: settingsWindow.show()
        case .panel, nil: panel.show()
        }
    }

    // MARK: - メニューバー（F-19）

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        // ふだんはコルクボードの絵。スタック中と一時停止中は、それと分かる記号にする。
        let name = stack?.isActive == true ? "square.stack.3d.up.fill" : watcher.effectivelyPaused ? "pause.rectangle" : nil
        let image = name.map { NSImage(systemSymbolName: $0, accessibilityDescription: "CorkClip") } ?? CorkboardIcon.menuBar
        image?.isTemplate = true
        statusItem?.button?.image = image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(item("履歴を開く（\(settings.openPanelHotKey.display)）", #selector(openPanel)))
        menu.addItem(item("数式画像を作る", #selector(openLatex)))
        menu.addItem(item("新しい定型文", #selector(newSnippet)))
        menu.addItem(item(stack.isActive ? "ペーストスタックを終える（\(stack.items.count)件）" : "ペーストスタックを始める（\(settings.stackHotKey.display)）", #selector(toggleStack)))
        menu.addItem(.separator())
        if watcher.effectivelyPaused {
            let until = watcher.pausedUntil.map { "（\(DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short)) まで）" } ?? ""
            menu.addItem(item("取得を再開\(until)", #selector(resume)))
        } else {
            let pause = NSMenuItem(title: "取得を一時停止", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            submenu.addItem(item("再開するまで", #selector(pauseIndefinitely)))
            submenu.addItem(item("15分", #selector(pauseFifteenMinutes)))
            submenu.addItem(item("1時間", #selector(pauseOneHour)))
            pause.submenu = submenu
            menu.addItem(pause)
        }
        if !Paster.isTrusted(prompt: false) {
            menu.addItem(item("貼り付けを許可する（アクセシビリティ）…", #selector(openAccessibilitySettings)))
        }
        menu.addItem(.separator())
        let usage = (try? store.usage()) ?? (count: 0, bytes: 0)
        let summary = NSMenuItem(title: "履歴 \(usage.count)件・\(ByteCountFormatter.string(fromByteCount: Int64(usage.bytes), countStyle: .file))", action: nil, keyEquivalent: "")
        summary.isEnabled = false
        menu.addItem(summary)
        menu.addItem(item("今すぐ整理", #selector(cleanupFromMenu)))
        menu.addItem(item("設定…", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("CorkClip を終了", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openPanel() { panel.show() }
    @objc private func openLatex() { panel.show(mode: .latex) }
    @objc private func newSnippet() { panel.show(mode: .snippet) }
    @objc private func toggleStack() { stack.toggle() }
    @objc private func openSettings() { settingsWindow.show() }
    @objc private func cleanupFromMenu() { cleanupNow() }

    private func setPaused(_ paused: Bool, until: Date?) {
        watcher.isPaused = paused && until == nil
        watcher.pausedUntil = paused ? until : nil
        updateStatusIcon()
        if let until {
            // 期限が来たらアイコンを戻す。
            Timer.scheduledTimer(withTimeInterval: until.timeIntervalSinceNow + 1, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.updateStatusIcon() } }
        }
    }

    @objc private func pauseIndefinitely() { setPaused(true, until: nil) }
    @objc private func pauseFifteenMinutes() { setPaused(true, until: Date().addingTimeInterval(15 * 60)) }
    @objc private func pauseOneHour() { setPaused(true, until: Date().addingTimeInterval(3600)) }
    @objc private func resume() { setPaused(false, until: nil) }

    @objc private func openAccessibilitySettings() {
        _ = Paster.isTrusted(prompt: true)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
