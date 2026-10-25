import Foundation

/// kobito シリーズの約束（docs/kobito-spec/CONTRACTS.md）のうち、PC 固有領域に置くもの。
///
///   ~/Library/Application Support/kobito-tools/
///     apps/<アプリID>.json   ④ 起動情報（自分の分を起動のたびに書く。ほかのアプリの分は読まない）
///     datasets.json          ⑥ 基準パスの履歴（基準パスの候補にし、開いたら自分の1件を書く）
///
/// テストでは実際の設定に触れないよう、環境変数 KOBITO_CONFIG_DIR で場所を変えられる（シリーズ共通の決まり）。
/// ほかのアプリの名前は書かない。何ができるかは、実行時に起動情報から知る。
enum Series {
    static let appID = "corkclip"
    static let appName = "CorkClip"
    static let defaultBundleID = "io.github.kobito-tools.corkclip"

    static var directory: URL {
        if let override = ProcessInfo.processInfo.environment["KOBITO_CONFIG_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("kobito-tools", isDirectory: true)
    }

    static var appsDirectory: URL { directory.appendingPathComponent("apps", isDirectory: true) }
    static var datasetsFile: URL { directory.appendingPathComponent("datasets.json") }

    // MARK: - 共通

    /// このMacの時差つきの ISO 8601（約束③・⑥・⑦の日時）。例：2026-10-15T09:00:00+09:00
    static func timestamp(_ date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// その日の YYYY-MM-DD（このMacの日付。和暦の設定でも西暦）。
    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// 一時ファイルに書いてから置き換える（途中で止まっても壊れたファイルを残さない）。権限は 600。
    static func writeAtomic(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString.lowercased()).tmp")
        guard FileManager.default.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw StoreError(status: 500, message: "\(url.path) を書き込めません。")
        }
        guard rename(temporary.path, url.path) == 0 else {
            let message = String(cString: strerror(errno))
            try? FileManager.default.removeItem(at: temporary)
            throw StoreError(status: 500, message: "\(url.path) を置き換えられません（\(message)）。")
        }
    }

    static func writeJSON(_ value: Any, to url: URL) throws {
        var data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0a)
        try writeAtomic(data, to: url)
    }

    private static func readJSON(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    // MARK: - ④ 起動情報

    /// 見せ方（④「見せ方と操作」）。色はシリーズの配色の名前から選ぶ。
    static let appNameEnglish = "CorkClip"
    static let color = "teal"
    static let glyph = "📌"
    /// .app の Resources に build.sh が入れる、アイコンの元（リポジトリの kobito/icon.svg と同じ。256 KB まで）。
    static let iconResource = "kobito/icon.svg"

    /// カードに残したクリップのカードの見せ方。日付は「残した日」なので記録として扱う。
    static let kinds: [[String: Any]] = [
        ["kind": KeptCards.kind, "label_en": "Clip", "glyph": glyph, "dates": "record"],
    ]

    /// 外から呼んでよい操作。宛先は自分（kobito://corkclip/…）だけで、id は変えない。
    static let actions: [[String: Any]] = [
        ["id": "panel", "label": "履歴を開く", "label_en": "Open history", "url": "kobito://\(appID)/panel"],
        ["id": "today", "label": "今日残したクリップを見る", "label_en": "Today's kept clips", "url": "kobito://\(appID)/day/{today}"],
        ["id": "snippet", "label": "定型文を作る", "label_en": "New snippet", "url": "kobito://\(appID)/snippet", "role": "new"],
        ["id": "latex", "label": "数式画像を作る", "label_en": "New LaTeX image", "url": "kobito://\(appID)/latex"],
        ["id": "settings", "label": "設定を開く", "label_en": "Settings", "url": "kobito://\(appID)/settings", "role": "settings"],
    ]

    /// 自分の名乗り（起動情報④の1件）。embed・receive は持たない（ほかのアプリの中には表示せず、受け渡しも受け付けない）。
    /// アイコン画像が無ければ（ハーネスなど）、代わりの1文字だけを書く。
    static func launchRecord(bundleID: String, iconFile: URL? = Bundle.main.resourceURL?.appendingPathComponent(iconResource)) -> [String: Any] {
        var icon: [String: Any] = ["glyph": glyph]
        if let iconFile, FileManager.default.fileExists(atPath: iconFile.path) { icon["file"] = iconFile.standardizedFileURL.path }
        return [
            "app": appID, "name": appName, "command": ["/usr/bin/open", "-b", bundleID],
            "name_en": appNameEnglish, "icon": icon, "color": color, "kinds": kinds, "actions": actions,
        ]
    }

    /// 自分の起動情報を書く。起動のたびに呼ぶ（入れ替えてバンドルIDや場所が変わっても追いつくように）。
    static func writeLaunchInfo(bundleID: String, iconFile: URL? = Bundle.main.resourceURL?.appendingPathComponent(iconResource)) throws {
        try writeJSON(launchRecord(bundleID: bundleID, iconFile: iconFile), to: appsDirectory.appendingPathComponent("\(appID).json"))
    }

    /// 名乗り（起動情報と同じ形の JSON）の文字列。--metadata が標準出力に出す。何も書かない（シリーズの決まり：APP_PACKAGE.md）。
    static func metadataJSON(bundleID: String, iconFile: URL? = Bundle.main.resourceURL?.appendingPathComponent(iconResource)) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: launchRecord(bundleID: bundleID, iconFile: iconFile),
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0a)
        return data
    }

    // MARK: - 受け付ける URL

    enum Route: Equatable {
        /// kobito://corkclip/day/<YYYY-MM-DD>：その日に残したクリップで絞り込む。
        case day(String)
        /// kobito://corkclip/open/<クリップID>：そのクリップを選ぶ。
        case open(Int)
        /// kobito://corkclip/snippet：新しい定型文を作る。
        case snippet
        /// kobito://corkclip/latex：数式画像を作る。
        case latex
        /// kobito://corkclip/settings：設定を開く。
        case settings
        /// kobito://corkclip/panel と、そのほか：パネルを開くだけ。
        case panel
    }

    /// 自分宛て（kobito://corkclip/…）の URL を読む。ほかのアプリ宛てなら nil。
    /// 一度受け付けた形は、作りを変えても受け付け続ける（約束②）。
    static func route(_ url: URL) -> Route? {
        guard url.scheme?.lowercased() == "kobito", url.host?.lowercased() == appID else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        switch (path.first?.lowercased(), path.dropFirst().first) {
        case ("day", let day?) where day.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil: return .day(day)
        case ("open", let id?) where Int(id) != nil: return .open(Int(id)!)
        case ("snippet", _): return .snippet
        case ("latex", _): return .latex
        case ("settings", _): return .settings
        default: return .panel
        }
    }

    // MARK: - ⑥ 基準パスの履歴

    struct DatasetEntry: Equatable {
        let path: String
        let id: String
        let app: String
        let opened: String
    }

    static let maxDatasetEntries = 50

    private static func datasetEntries() -> [DatasetEntry] {
        (readJSON(datasetsFile)?["datasets"] as? [Any] ?? []).compactMap { item in
            guard let item = item as? [String: Any], let path = item["path"] as? String, !path.isEmpty, let id = item["id"] as? String, !id.isEmpty,
                  let app = item["app"] as? String, !app.isEmpty, let opened = item["opened"] as? String, !opened.isEmpty else { return nil }
            return DatasetEntry(path: path, id: id, app: app, opened: opened)
        }
    }

    /// 基準パスを開いたときに呼ぶ。読み直して自分の1件を先頭に足し、同じ path は1件にまとめる。
    static func recordDataset(path: String, id: String, now: Date = Date()) throws {
        let entry = DatasetEntry(path: path, id: id, app: appID, opened: timestamp(now))
        let entries = ([entry] + datasetEntries().filter { $0.path != path }).prefix(maxDatasetEntries)
        let record: [String: Any] = ["v": 1, "datasets": entries.map { ["path": $0.path, "id": $0.id, "app": $0.app, "opened": $0.opened] }]
        try writeJSON(record, to: datasetsFile)
    }

    /// 今も .kobito-tools/dataset.json がある基準パスを、最後に開いた順に返す（保存先を選ぶ画面の候補）。
    static func datasetCandidates() -> [DatasetEntry] {
        datasetEntries()
            .sorted { (Dataset.parseTimestamp($0.opened) ?? .distantPast) > (Dataset.parseTimestamp($1.opened) ?? .distantPast) }
            .filter { FileManager.default.fileExists(atPath: Dataset.root($0.path).appendingPathComponent("dataset.json").path) }
    }
}
