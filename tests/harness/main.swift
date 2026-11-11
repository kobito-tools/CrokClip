import AppKit

// 取得 → 保存 → 書き戻しで、全ての項目・型・データが元のまま戻ることなどを、本物の NSPasteboard（名前付き）で確かめる。
// 実行は tests/run.sh から。第1引数に一時フォルダ、第2引数に schema/ を渡す。

setvbuf(stdout, nil, _IONBF, 0)
var failures = 0
func check(_ condition: @autoclosure () throws -> Bool, _ message: String) {
    if (try? condition()) == true { print("ok - \(message)") } else { print("NG - \(message)"); failures += 1 }
}

let work = URL(fileURLWithPath: CommandLine.arguments[1])
let schema = URL(fileURLWithPath: CommandLine.arguments[2])
let katex = URL(fileURLWithPath: CommandLine.arguments[3])
let store = try ClipStore(directory: work.appendingPathComponent("store"), schemaDirectory: schema)

func makePNG(width: Int, height: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.systemTeal.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func put(_ items: [[(String, Data)]], on pasteboard: NSPasteboard) {
    pasteboard.clearContents()
    pasteboard.writeObjects(items.map { representations in
        let item = NSPasteboardItem()
        for (type, data) in representations { item.setData(data, forType: NSPasteboard.PasteboardType(type)) }
        return item
    })
}

func contents(of pasteboard: NSPasteboard) -> [[Representation]] {
    (pasteboard.pasteboardItems ?? []).map { item in
        item.types.compactMap { type in item.data(forType: type).map { Representation(type: type.rawValue, data: $0) } }.filter { $0.type != Capture.ownType }
    }
}

let source = NSPasteboard(name: NSPasteboard.Name("corkclip-test-source-\(UUID().uuidString)"))
let destination = NSPasteboard(name: NSPasteboard.Name("corkclip-test-destination-\(UUID().uuidString)"))
defer { source.releaseGlobally(); destination.releaseGlobally() }

MainActor.assumeIsolated {
    // 1. パワポの図形のような独自の型を含む、2つの項目のコピー
    let slides = Data((0..<4096).map { _ in UInt8.random(in: 0...255) })
    let png = makePNG(width: 800, height: 400)
    put([[("public.utf8-plain-text", Data("図形のテキスト".utf8)), ("com.microsoft.PowerPoint-14.0-Slides-Package", slides), ("public.png", png)],
         [("public.utf8-plain-text", Data("2つ目の項目".utf8))]], on: source)
    let original = contents(of: source)
    let capture = Capture.read(from: source, sourceBundleID: "com.microsoft.Powerpoint", sourceAppName: "Microsoft PowerPoint")!
    check(capture.kind == .office, "パワポの型を含むコピーは office")
    let saved = try! store.save(capture, maxItemBytes: 100 * 1024 * 1024)
    guard case .inserted(let id) = saved else { fatalError("新しく保存されない") }
    check(FileManager.default.fileExists(atPath: store.thumbnailURL(id).path), "画像を含むコピーのサムネを作る")
    let detail = try! store.detail(id)!
    check(detail.imageData == png && detail.text == "図形のテキスト\n2つ目の項目", "プレビューに画像と文字を渡す")
    check(detail.types == ["public.utf8-plain-text", "com.microsoft.PowerPoint-14.0-Slides-Package", "public.png"], "プレビューに型の一覧を渡す（重複なし・元の並び）")
    check(try! store.detail(id, maxImageBytes: 10)!.imageData == nil, "大きすぎる画像はプレビューで読まない")

    let paster = Paster(store: store, pasteboard: destination) { Settings() }
    check(paster.write(id, mode: .original), "元の形で書き戻せる")
    check(contents(of: destination) == original, "全ての項目・型・データが元のまま戻る（\(original.count)項目・\(original.flatMap { $0 }.count)型）")
    check(destination.pasteboardItems?.allSatisfy { $0.types.contains(NSPasteboard.PasteboardType(Capture.ownType)) } == true, "書き戻した物に自分の印が付く")

    check(paster.write(id, mode: .plainText), "プレーンテキストで書き戻せる")
    check(contents(of: destination).flatMap { $0 }.map(\.type) == ["public.utf8-plain-text"], "プレーンテキストは文字の型だけ（\(destination.types?.map(\.rawValue) ?? [])）")
    check(destination.string(forType: .string) == "図形のテキスト\n2つ目の項目", "プレーンテキストは全ての項目の文字をつなぐ")

    // 2. 同じ中身をもう一度コピー
    let again = try! store.save(Capture.read(from: source)!, maxItemBytes: 100 * 1024 * 1024)
    check(again == .bumped(id), "同じ中身は新しい項目を作らない")
    check(try! store.summary(id)?.copyCount == 2, "コピーした回数が増える")

    // 3. 改行を消して貼る
    put([[("public.utf8-plain-text", Data("これは日本語の\n文章です。\nThis is an inter-\nnational\ntest.".utf8))]], on: source)
    let lines = try! store.save(Capture.read(from: source)!, maxItemBytes: 100 * 1024 * 1024).id
    paster.write(lines, mode: .joinLines)
    check(destination.string(forType: .string) == "これは日本語の文章です。This is an international test.", "改行を消して書き戻す")

    // 4. 保存しない物
    put([[("public.utf8-plain-text", Data("password".utf8)), ("org.nspasteboard.ConcealedType", Data())]], on: source)
    var captured: [Capture] = []
    let watcher = PasteboardWatcher(pasteboard: source, excludedBundleIDs: { [] }) { captured.append($0) }
    watcher.check()
    check(captured.isEmpty, "パスワード管理アプリの印が付いた物は取らない")
    for marker in ["de.petermaurer.TransientPasteboardType", "com.agilebits.onepassword", "net.antelle.keeweb"] {
        put([[("public.utf8-plain-text", Data("secret".utf8)), (marker, Data())]], on: source)
        watcher.check()
    }
    check(captured.isEmpty, "nspasteboard.org より前から使われている「保存しないで」の印でも取らない")
    put([[("public.utf8-plain-text", Data("ふつうの文字".utf8))]], on: source)
    watcher.check()
    check(captured.count == 1 && captured[0].plainText == "ふつうの文字", "ふつうのコピーは取る")
    paster.write(lines, mode: .original)
    let ownWatcher = PasteboardWatcher(pasteboard: destination, excludedBundleIDs: { [] }) { captured.append($0) }
    put([[("public.utf8-plain-text", Data("x".utf8))]], on: destination)
    paster.write(lines, mode: .original)
    ownWatcher.check()
    check(captured.count == 1, "自分で書き戻した物は取らない")
    watcher.isPaused = true
    put([[("public.utf8-plain-text", Data("停止中".utf8))]], on: source)
    watcher.check()
    check(captured.count == 1, "一時停止中は取らない")

    // 5. 大きすぎる物
    put([[("public.utf8-plain-text", Data("大きい".utf8)), ("public.png", png)]], on: source)
    let big = try! store.save(Capture.read(from: source)!, maxItemBytes: 10).id
    check(try! store.summary(big)?.oversized == true && (try! store.representations(of: big)) == nil, "上限を超えた物は生データを保存しない")
    paster.write(big, mode: .original)
    check(destination.string(forType: .string) == "大きい", "生データの無い物は文字だけ書き戻す")
}

// 6. 検索
_ = try store.save(Capture(items: [[Representation(type: "public.utf8-plain-text", data: Data("クリップボードの履歴を検索する".utf8))]], plainText: "クリップボードの履歴を検索する"), maxItemBytes: 1 << 20)
check(try store.recent(query: "履歴を検索").count == 1, "3文字以上は全文検索で見つかる")
check(try store.recent(query: "履歴").count == 1, "2文字は部分一致で見つかる")
check(try store.recent(query: "クリップ 検索").count == 1, "空白で区切った語は全て含む物")
check(try store.recent(query: "見つからない語").isEmpty, "含まない語では見つからない")
check(try store.recent(query: "PowerPoint").count >= 1, "コピー元のアプリ名でも見つかる")

// 7. 整理
let blobCount = { (try? FileManager.default.subpathsOfDirectory(atPath: store.directory.appendingPathComponent("blobs").path).filter { $0.hasSuffix(".bin") }.count) ?? 0 }
let beforeBlobs = blobCount()
var settings = Settings()
check(ClipKind.allCases.allSatisfy { settings.retention(for: $0) == 30 }, "期限の初期値は、文字も含めてどの種類も30日")
let olderSettings = try JSONDecoder().decode(Settings.self, from: Data(#"{"retentionDays": {"image": 30, "office": 30, "file": 90}}"#.utf8))
check(olderSettings.retention(for: .text) == 30 && olderSettings.retention(for: .file) == 90, "以前の設定に無い種類（文字など）は30日、選んであった日数はそのまま")
settings.retentionDays = Dictionary(uniqueKeysWithValues: ClipKind.allCases.map { ($0.rawValue, $0 == .office ? 30 : 0) })
let future = Date().addingTimeInterval(40 * 86_400)
let report = try store.cleanup(settings: settings, now: future)
check(report.removedClips == 1, "30日を過ぎた office の項目を消す（\(report.removedClips)件）")
check(try store.recent().allSatisfy { $0.kind != .office }, "消した項目は一覧から消える")
check(blobCount() < beforeBlobs, "使われなくなった生データを消す")
check(try store.recent().contains { $0.kind == .text }, "0日にした種類は無期限")
check((try? JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings)))?.retention(for: .text) == 0, "無期限（0日）を選んだことは設定のファイルに残る")
settings.maxItems = 2
try store.cleanup(settings: settings)
check(try store.usage().count == 2, "件数の上限を超えた分を古い順に消す")
try store.cleanup(settings: Settings(), now: future)
check(try store.usage().count == 0, "初期値のままなら、30日を過ぎた文字も消す")

check(try store.database.first("PRAGMA secure_delete")?["secure_delete"] as? Int == 1, "消した行は 0 で上書きする（secure_delete）")

// HTML だけのコピーは、WebKit を通さずにタグを外して文字にする（中の画像を読みに行かない）。
check(Capture.plainText(fromHTML: "<html><head><style>p{}</style></head><body><p>一行目&amp;<img src=\"https://example.com/x.png\"></p><p>二&#x884C;目<br>三行目 &lt;b&gt;</p><script>alert(1)</script></body></html>") == "一行目&\n二行目\n三行目 <b>",
      "HTML からタグ・スクリプト・CSS を外して文字にする")
check(Capture.plainText(fromHTML: "<b>太字</b>&nbsp;だけ&unknown;") == "太字 だけ&unknown;" && Capture.plainText(fromHTML: "<p></p>") == nil, "文字の参照を戻し、知らない名前は残す。文字が無ければ nil")

// 8. 改行を消す
let dictionary: (String) -> Bool = { ["international", "email"].contains($0) }
check(LineJoiner.join("inter-\nnational", isWord: dictionary) == "international", "辞書にある語はハイフンを消す")
check(LineJoiner.join("well-\nknown", isWord: dictionary) == "well-known", "辞書に無い語はハイフンを残す")
check(LineJoiner.join("first line\nsecond line") == "first line second line", "英語の行は半角スペースでつなぐ")
check(LineJoiner.join("日本語の\n文章") == "日本語の文章", "日本語の行はそのままつなぐ")
check(LineJoiner.join("英語 English\nwords") == "英語 English words", "英語で終わる行と英語で始まる行は空白を入れる")
check(LineJoiner.join("段落1の\n続き\n\n段落2") == "段落1の続き\n\n段落2", "空行（段落の区切り）は残す")
check(LineJoiner.join("段落1\n\n\n段落2", keepParagraphs: false) == "段落1段落2", "段落の区切りを残さない設定")
check(LineJoiner.join("a\r\nb") == "a b", "CRLF の改行も消す")
check(LineJoiner.isDictionaryWord("international") && !LineJoiner.isDictionaryWord("wellknown"), "macOS の辞書で語を判定できる")

// 9. 変換（F-07・F-11・F-12）と定型文の差し込み（F-09）
check(TextTransforms.apply(.toWesternPunctuation, "これは、例です。") == "これは，例です．", "句読点を「，．」に")
check(TextTransforms.apply(.toJapanesePunctuation, "これは，例です．") == "これは、例です。", "句読点を「、。」に")
check(TextTransforms.apply(.halfWidthAlphanumerics, "ＡＢＣ　１２３！カナ") == "ABC 123!カナ", "英数字・記号だけ半角に")
check(TextTransforms.apply(.fullWidthKatakana, "ｶﾞｷﾞABC") == "ガギABC", "半角カタカナだけ全角に")
check(TextTransforms.apply(.trimSpaces, "  a   b \n\n c  ") == "a b\n\nc", "余分な空白を消す")
check(TextTransforms.apply(.sentenceCase, "HELLO WORLD. NEW LINE") == "Hello world. New line", "文の先頭だけ大文字")
let tsv = "名前\t値\na_b\t50%"
check(TextTransforms.apply(.tableToLatex, tsv) == "\\begin{tabular}{ll}\n\\hline\n名前 & 値 \\\\\n\\hline\na\\_b & 50\\% \\\\\n\\hline\n\\end{tabular}", "表を LaTeX の tabular に（特殊文字を逃がす）")
check(TextTransforms.apply(.tableToMarkdown, tsv) == "| 名前 | 値 |\n| --- | --- |\n| a_b | 50% |", "表を Markdown に")
check(TextTransforms.apply(.tableToCSV, "a,b\tc\"d") == "\"a,b\",\"c\"\"d\"", "表を CSV に（引用符で囲む）")
check(TextTransforms.htmlTableRows("<table><tr><th>A</th><td>B &amp; C</td></tr><tr><td>1<br>2</td><td></td></tr></table>") == [["A", "B & C"], ["1 2", ""]], "HTML の表を読む")
check(TextTransforms.apply(.numbered, "x\n\ny") == "1. x\n\n2. y", "番号付きにする（空行は飛ばす）")
check(TextTransforms.apply([.joinLines, .toWesternPunctuation], to: TransformContext(text: "これは、\n例です。")) == "これは，例です．", "変換をつなげる")
check(TextTransforms.apply([.ocrText], to: TransformContext(text: nil, ocrText: "画像の文字")) == "画像の文字", "画像の文字をテキストで")
check(TextTransforms.apply([.tableToMarkdown], to: TransformContext(text: "A B", html: "<table><tr><td>A</td><td>B</td></tr></table>")) == "| A | B |\n| --- | --- |", "タブの無い表は HTML から読む")
let home = NSHomeDirectory()
check(TextTransforms.paths(["\(home)/Docs/a.pdf", "/tmp/b.txt"], .pathTilde, basePath: nil) == "~/Docs/a.pdf\n/tmp/b.txt", "パス（~ から）")
check(TextTransforms.paths(["/Base/Paper/a.pdf"], .pathRelative, basePath: "/Base") == "Paper/a.pdf", "パス（基準パスから）")
check(TextTransforms.paths(["/Base/a b.pdf"], .fileURL, basePath: nil) == "file:///Base/a%20b.pdf", "file:// の URL")
check(MergeSeparator.custom.separator(custom: "\\n---\\n") == "\n---\n", "任意の区切り（\\n で改行）")
let fixedDate = ISO8601DateFormatter().date(from: "2026-09-28T05:06:07Z")!
let expanded = SnippetExpander.expand("{date:yyyy}年 {clipboard}：{cursor}です", clipboard: "コピー", now: fixedDate)
check(expanded.text == "2026年 コピー：です" && expanded.cursorOffsetFromEnd == 2, "定型文の差し込み（{date:書式}・{clipboard}・{cursor}）")

// 10. 絞り込み・タグ・ピン・定型文（F-04・F-05・F-09）
let store2 = try ClipStore(directory: work.appendingPathComponent("store2"), schemaDirectory: schema)
func saveText(_ text: String, app: String, date: Date = Date()) throws -> Int {
    try store2.save(Capture(items: [[Representation(type: "public.utf8-plain-text", data: Data(text.utf8))]], sourceBundleID: "com.example.\(app)", sourceAppName: app, date: date, plainText: text), maxItemBytes: 1 << 20).id
}
let wordID = try saveText("会議の議事録", app: "Word", date: ISO8601DateFormatter().date(from: "2026-09-01T00:00:00Z")!)
let safariID = try saveText("https://arxiv.org/abs/1234", app: "Safari")
let paper = try store2.findOrCreateTag("論文")
try store2.addTag(paper, to: [safariID])
check(try store2.findOrCreateTag("論文") == paper, "同じ名前のタグは作り直さない")
check(try store2.recent(query: "#論文").map(\.id) == [safariID], "#タグ で絞り込む")
check(try store2.recent(query: "論文").map(\.id) == [safariID], "タグの名前も検索の対象")
check(try store2.recent(query: "type:link").map(\.id) == [safariID] && (try store2.recent(query: "type:リンク").map(\.id)) == [safariID], "type: で種類を絞り込む")
check(try store2.recent(query: "app:word").map(\.id) == [wordID], "app: でコピー元を絞り込む")
check(try store2.recent(query: "before:2026-09-02").map(\.id) == [wordID] && (try store2.recent(query: "after:2026-09-02").map(\.id)) == [safariID], "after:・before: で日付を絞り込む")
check(try store2.recent(sort: .copied).first?.id == safariID, "並べ替え（コピーした順）")
check(try store2.recent().first { $0.id == safariID }?.tags == ["論文"], "一覧にタグの名前を入れる")
try store2.removeTag(paper.id, from: [safariID])
check(try store2.recent(query: "#論文").isEmpty, "タグを外す")
try store2.setPinned([wordID], true)
let snippetID = try store2.createSnippet(title: "署名", body: "よろしくお願いします。\n{date:yyyy}")
check(try store2.pinned().map(\.id) == [wordID, snippetID], "ピンと定型文は並び順どおり")
check(try store2.recent(excludePinned: true).map(\.id) == [safariID], "ピンは履歴の欄から外す")
check(try store2.recent(query: "is:pinned").count == 2 && (try store2.recent(query: "type:snippet").map(\.id)) == [snippetID], "is:pinned・type:snippet")
try store2.movePin(snippetID, by: -1)
check(try store2.pinned().map(\.id) == [snippetID, wordID], "ピンを並べ替える")
try store2.updateSnippet(snippetID, title: "署名2", body: "新しい本文")
check(try store2.text(of: snippetID) == "新しい本文" && (try store2.pinned().first?.title) == "署名2" && (try store2.recent(query: "新しい本文").map(\.id)) == [snippetID], "定型文を直す")
var keepAll = Settings()
keepAll.maxItems = 0
try store2.cleanup(settings: keepAll)
check(Set(try store2.pinned().map(\.id)) == [snippetID, wordID], "整理してもピンと定型文は消さない")
MainActor.assumeIsolated {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("corkclip-test-snippet-\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }
    try! store2.updateSnippet(snippetID, title: "署名", body: "ab{cursor}cd")
    let resolved = Paster(store: store2, pasteboard: pasteboard) { Settings() }.items(for: snippetID, mode: .original)
    check(resolved.map { String(data: $0.items[0][0].data, encoding: .utf8) } == "abcd" && resolved?.cursorOffset == 2, "定型文を貼るときに差し込みを展開する")
}

// 11. 自動タグ（F-04）
var rules = Settings()
rules.autoTagRules = [AutoTagRule(kind: .app, pattern: "TeXShop", tag: "latex"), AutoTagRule(kind: .domain, pattern: "arxiv.org", tag: "論文")]
check(rules.autoTags(bundleID: "x", appName: "TeXShop", text: "a") == ["latex"], "アプリで自動タグ")
check(rules.autoTags(bundleID: "com.apple.Safari", appName: "Safari", text: "見て https://export.arxiv.org/abs/1") == ["論文"], "ドメインで自動タグ（サブドメインも）")
check(rules.autoTags(bundleID: nil, appName: nil, text: "https://example.com") == [], "当てはまらなければ付けない")

// 12. 文字認識（F-08）
func textImage(_ text: String) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 900, pixelsHigh: 160, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 900, height: 160).fill()
    NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 56), .foregroundColor: NSColor.black]).draw(at: NSPoint(x: 30, y: 50))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
let screenshotID = try store2.save(Capture(items: [[Representation(type: "public.png", data: textImage("CorkClip 画像の文字"))]], sourceAppName: "スクリーンショット"), maxItemBytes: 1 << 24).id
let pending = try store2.pendingOCR()
check(pending.map(\.id) == [screenshotID], "まだ文字を読んでいない画像を返す")
let recognized = OCR.recognize(pending[0].data) ?? ""
check(recognized.contains("CorkClip"), "画像の文字を読む（\(recognized.replacingOccurrences(of: "\n", with: " "))）")
try store2.setOCR(screenshotID, text: recognized)
check(try store2.pendingOCR().isEmpty && (try store2.recent(query: "CorkClip").map(\.id)) == [screenshotID], "読んだ文字で検索できる")

// 13. 数式（F-06）
let latex = LatexSource(source: "\\frac{a}{b}", options: LatexOptions())
check(LatexSource(embedded: latex.embedded) == latex && LatexSource(json: latex.json) == latex, "元の式を埋め込み・取り出せる")
check(LatexSource.renamedMarkers.allSatisfy { LatexSource(embedded: latex.embedded.replacingOccurrences(of: LatexSource.marker, with: $0)) == latex }, "以前の名前（Pastephant・InGoodPaste）で描いた画像からも元の式を取り出せる")
check(Capture.renamedLatexTypes.allSatisfy { Capture(items: [[Representation(type: $0, data: Data(latex.json.utf8))]]).kind == .formula }, "以前の名前（Pastephant・InGoodPaste）の数式の型も数式として扱う")
check(LatexSource.looksLikeLatex("$x^2$") && LatexSource.looksLikeLatex("\\frac{1}{2}") && !LatexSource.looksLikeLatex("ふつうの文章"), "LaTeX らしい文字を見分ける")
check(LatexSource.stripDelimiters("\\[ x \\]") == "x" && LatexSource.stripDelimiters("$$y$$") == "y", "囲みを外す")
let crafted = LatexSource(json: #"{"source": "x", "options": {"color": "red; background: url(https://example.com/a)", "background": "url(https://example.com/b)", "fontSize": 1e9, "padding": -5}}"#)
check(crafted?.options.color == "#000000" && crafted?.options.background == nil && crafted?.options.fontSize == 144 && crafted?.options.padding == 0,
      "クリップボードから読んだ描き方は、#RRGGBB 以外の色（url(…) など）を捨て、大きさと余白を範囲に収める")
check({ var options = LatexOptions(); options.background = "url(x)"; options.color = "#12ab3"; return options.sanitized }() == LatexOptions(), "入力途中の色も、描くときには初期値にする")
check((try? String(contentsOf: katex.appendingPathComponent("render.html"), encoding: .utf8))?.contains("default-src 'none'") == true, "描画のページは CSP で外部を読まない")
_ = NSApplication.shared
var rendered: Result<LatexImage, Error>?
Task { @MainActor in
    do { rendered = .success(try await LatexRenderer(resources: katex).render(latex, macros: "\\newcommand{\\Pset}{\\mathbb{P}}")) } catch { rendered = .failure(error) }
}
let deadline = Date().addingTimeInterval(30)
while rendered == nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
switch rendered {
case .success(let image)?:
    check(image.size.width > 5 && image.size.height > 5, "数式を描く（\(Int(image.size.width))×\(Int(image.size.height))pt）")
    check(image.png.starts(with: [0x89, 0x50, 0x4E, 0x47]) && image.pdf.starts(with: Array("%PDF".utf8)), "PNG と PDF を作る")
    if let source = CGImageSourceCreateWithData(image.png as CFData, nil), let image2 = CGImageSourceCreateImageAtIndex(source, 0, nil),
       let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
        context.draw(image2, in: CGRect(x: 0, y: 0, width: image2.width, height: image2.height))
        check(context.data!.load(fromByteOffset: 3, as: UInt8.self) == 0, "背景が透明（左下の点）")
    }
    for (label, representations) in [("PNG だけ", [image.representations[1]]), ("PDF だけ", [image.representations[0]]), ("全部", image.representations)] {
        let capture = Capture(items: [representations])
        var read = capture
        read.latex = nil
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("corkclip-test-latex-\(UUID().uuidString)"))
        put([representations.map { ($0.type, $0.data) }], on: pasteboard)
        let captured = Capture.read(from: pasteboard)
        pasteboard.releaseGlobally()
        check(captured?.kind == .formula && captured?.latex == latex && captured?.plainText == latex.source, "\(label)のコピーから元の式を読む")
    }
case .failure(let error)?: check(false, "数式を描く（\(error)）")
case nil: check(false, "数式を描く（時間切れ）")
}
var broken: Result<LatexImage, Error>?
Task { @MainActor in
    do { broken = .success(try await LatexRenderer(resources: katex).render(LatexSource(source: "\\frac{a", options: LatexOptions()), macros: "")) } catch { broken = .failure(error) }
}
while broken == nil, Date() < deadline.addingTimeInterval(10) { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
if case .failure(let error)? = broken { check(error is LatexError, "書き方の誤りを知らせる（\(error)）") } else { check(false, "書き方の誤りを知らせる") }

// 14. 共有タグとカードに残す（F-04・F-17）
func decodeSettings(_ json: String) -> Settings? { try? JSONDecoder().decode(Settings.self, from: Data(json.utf8)) }
check(decodeSettings(#"{"workspaceKeep": false}"#)?.keepCards == false && decodeSettings(#"{"workspaceKeep": false, "keepCards": true}"#)?.keepCards == true && decodeSettings("{}")?.keepCards == true, "「カードに残す」の設定は以前の名前（workspaceKeep）から引き継ぐ")
let base = work.appendingPathComponent("base").path
try FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
_ = try Dataset.create(base, datasetId: "テスト")
let exportTag = try store2.findOrCreateTag("書き出し")
try store2.addTag(exportTag, to: [wordID])
try store2.syncTags(basePath: base)
let tagsJSON = (try? JSONSerialization.jsonObject(with: Data(contentsOf: Dataset.tagsFile(base)))) as? [String: Any]
check((tagsJSON?["tags"] as? [[String: Any]])?.contains { $0["name"] as? String == "書き出し" } == true, "共有タグ（tags.json）に書き出す")
// 以前の書き出し先（日ごとのメモの DB）に、9月28日の分が残っている。
let legacy = try SQLiteDatabase(path: Dataset.legacyDatabasePath(base), journal: .delete)
try legacy.exec("""
CREATE TABLE memos (id TEXT PRIMARY KEY, title TEXT, body_html TEXT, body_text TEXT, created_at TEXT, updated_at TEXT, deleted_at TEXT);
CREATE TABLE memo_tags (memo_id TEXT, tag_id TEXT);
INSERT INTO memos VALUES ('memo-old', '09月28日のクリップ', '<div>x</div>', '10:00・Safari\n以前に残した文字', '2026-09-28T01:00:00.000Z', '2026-09-28T03:00:00.000Z', NULL);
INSERT INTO memos VALUES ('memo-gone', '09月29日のクリップ', '', '消したメモ', '2026-09-29T01:00:00.000Z', '2026-09-29T01:00:00.000Z', '2026-09-30T00:00:00.000Z');
INSERT INTO memo_tags VALUES ('memo-old', 'tag-old');
""")
let keptSchema = schema.appendingPathComponent("kept")
let keepTime = Date()
let today = Series.day(keepTime)
func entry(_ id: Int, text: String, tags: [Tag], image: Data? = nil) -> KeptCards.Entry {
    KeptCards.Entry(clipID: id, copiedAt: keepTime, appName: "Safari", tagNames: tags.map(\.name), tagIDs: tags.map(\.id), text: text, latex: nil, filePaths: [], ocrText: nil, image: image)
}
try KeptCards.keep([entry(safariID, text: "https://arxiv.org/abs/1234", tags: [exportTag], image: makePNG(width: 10, height: 10))], basePath: base, schemaDirectory: keptSchema, now: keepTime)
try KeptCards.keep([entry(wordID, text: "2件目", tags: [exportTag]), entry(safariID, text: "https://arxiv.org/abs/1234 直した", tags: [exportTag], image: makePNG(width: 12, height: 12))], basePath: base, schemaDirectory: keptSchema, now: keepTime.addingTimeInterval(1))
try store2.markExported([wordID], at: keepTime)
let cardLines = (try? String(contentsOf: KeptCards.cardsFile(base), encoding: .utf8))?.split(separator: "\n").map(String.init) ?? []
let cardList = cardLines.compactMap { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any] }
check(cardList.map { $0["id"] as? String } == ["clips-2026-09-28", "clips-\(today)"], "日ごとに1枚のカードを書く（以前の書き出し先から移した日と、今日。消したメモは移さない）")
let todayCard = cardList.last ?? [:]
check(todayCard["v"] as? Int == 1 && todayCard["app"] as? String == "corkclip" && todayCard["kind"] as? String == "クリップ" && todayCard["date"] as? String == today, "カードは約束③の形（v・app・kind・date）")
check(todayCard["title"] as? String == KeptCards.title(day: today) && KeptCards.title(day: "2026-10-05") == "10月5日のクリップ", "見出しは「10月5日のクリップ」")
check(todayCard["url"] as? String == "kobito://corkclip/day/\(today)" && Series.route(URL(string: todayCard["url"] as! String)!) == .day(today), "カードの URL で、その日に残した物を開ける")
check(todayCard["tags"] as? [String] == [exportTag.id], "タグは tags.json のタグID（重複を除く）")
check((todayCard["text"] as? String).map { $0.contains("直した") && $0.contains("2件目") && !$0.contains("abs/1234\n") } == true, "同じ項目をもう一度残したら中身を新しくする")
check((todayCard["updated"] as? String).map { Dataset.parseTimestamp($0) != nil && $0.range(of: "(Z|[+-]\\d{2}:\\d{2})$", options: .regularExpression) != nil } == true, "更新日時は時差付き")
check(cardList.first?["tags"] as? [String] == ["tag-old"] && (cardList.first?["text"] as? String)?.contains("以前に残した文字") == true, "以前の書き出し先のメモを、文字とタグごと移す")
let uploads = (try? FileManager.default.contentsOfDirectory(atPath: Dataset.uploadsDirectory(base).path)) ?? []
check(uploads.count == 1 && uploads[0].hasSuffix(".png"), "画像は PNG で uploads/ に保存する（カードには入れない。残し直したら前の画像は消す）")
check(cardLines.allSatisfy { !$0.contains("base64") && !$0.contains("\\/") }, "カードは1行1件の JSON")
let longText = String(repeating: "あ", count: 2500)
try KeptCards.keep([entry(snippetID, text: longText, tags: [])], basePath: base, schemaDirectory: keptSchema, now: keepTime.addingTimeInterval(2))
let longCard = ((try? String(contentsOf: KeptCards.cardsFile(base), encoding: .utf8))?.split(separator: "\n").last).flatMap { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any] }
check((longCard?["text"] as? String)?.unicodeScalars.count == 2000, "本文は2000文字まで")
try KeptCards.refresh(basePath: base, schemaDirectory: keptSchema)
check(((try? String(contentsOf: KeptCards.cardsFile(base), encoding: .utf8))?.split(separator: "\n").count) == 2, "書き直しても移し替えは一度だけ")
check(try store2.recent(query: "kept:\(today)").map(\.id) == [wordID] && (try store2.recent(query: "exported:\(today)").map(\.id)) == [wordID] && (try store2.recent(query: "kept:2000-01-01")).isEmpty, "kept: でその日に残した物を絞り込む（カードから開くとき）")
check(!FileManager.default.fileExists(atPath: Dataset.directory(base).appendingPathComponent("lock.json").path), "残し終えたら使用中の印を外す")
// カードから外す：このMacで残した物を消し、画像も消してカードを書き直す。
try KeptCards.remove(clipIDs: [safariID], basePath: base, schemaDirectory: keptSchema)
let afterRemove = (try? String(contentsOf: KeptCards.cardsFile(base), encoding: .utf8)) ?? ""
check(!afterRemove.contains("直した") && afterRemove.contains("2件目"), "カードから外した物はカードに出さない（ほかの物は残す）")
check(((try? FileManager.default.contentsOfDirectory(atPath: Dataset.uploadsDirectory(base).path)) ?? ["?"]).isEmpty, "カードから外したら、残した画像も消す")
try store2.clearExported([wordID])
check(try store2.exportedAt(wordID) == nil, "外したら、残した印も消す")
try store2.markExported([wordID], at: keepTime)
// 使用中の印にはホスト名を書かず、どのMacかは machineId で見分ける。
let lockFile = Dataset.directory(base).appendingPathComponent("lock.json")
let heldLock = DatasetLock(basePath: base)
try heldLock.acquire()
let lockJSON = (try? JSONSerialization.jsonObject(with: Data(contentsOf: lockFile))) as? [String: Any]
check(lockJSON?["machineId"] as? String == DatasetLock.machineId && lockJSON?["hostname"] == nil, "使用中の印にホスト名を書かない")
heldLock.release()
try Dataset.writeJSON(["app": "corkclip", "machineId": "corkclip-other", "pid": 1, "heartbeatAt": Dataset.timestamp()], to: lockFile)
do { try DatasetLock(basePath: base).acquire(); check(false, "別のMacの印があれば使わない") }
catch { check((error as? StoreError)?.message.contains("別のMac") == true, "別のMacの印があれば使わない（machineId で見分ける）") }
try FileManager.default.removeItem(at: lockFile)
// 以前の名前（Pastephant・InGoodPaste）で書き出したフォルダとDBは、新しい名前へ移す。
for (oldName, oldDatabase) in [("Pastephant", "pastephant.sqlite3"), ("InGoodPaste", "ingoodpaste.sqlite3")] {
    let oldBase = work.appendingPathComponent("renamed-base-\(oldName)").path
    let oldPath = URL(fileURLWithPath: oldBase).appendingPathComponent(".kobito-tools/\(oldName)/database/\(oldDatabase)")
    try FileManager.default.createDirectory(at: oldPath.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("db".utf8).write(to: oldPath)
    try Data("cards".utf8).write(to: oldPath.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("cards.jsonl"))
    try Dataset.ensureDirectories(oldBase)
    check((try? Data(contentsOf: URL(fileURLWithPath: Dataset.legacyDatabasePath(oldBase)))) == Data("db".utf8) && FileManager.default.fileExists(atPath: KeptCards.cardsFile(oldBase).path) && !FileManager.default.fileExists(atPath: oldPath.deletingLastPathComponent().deletingLastPathComponent().path), "以前の名前（\(oldName)）の書き出し先を CorkClip/ へ移す")
}
// 両方あるときは、いま使われている Pastephant のほうを移し、もう片方には触れない。
let bothBase = work.appendingPathComponent("renamed-base-both").path
for oldName in ["Pastephant", "InGoodPaste"] {
    try FileManager.default.createDirectory(atPath: bothBase + "/.kobito-tools/\(oldName)/database", withIntermediateDirectories: true)
    try Data(oldName.utf8).write(to: URL(fileURLWithPath: bothBase + "/.kobito-tools/\(oldName)/mark"))
}
try Dataset.ensureDirectories(bothBase)
check((try? String(contentsOf: Dataset.directory(bothBase).appendingPathComponent("mark"), encoding: .utf8)) == "Pastephant" && FileManager.default.fileExists(atPath: bothBase + "/.kobito-tools/InGoodPaste/mark"), "両方の古い名前があれば Pastephant を移し、もう片方は残す")
// すでに CorkClip/ があれば、古い名前のフォルダは移さない。
try FileManager.default.createDirectory(atPath: bothBase + "/.kobito-tools/Pastephant", withIntermediateDirectories: true)
try Dataset.ensureDirectories(bothBase)
check(FileManager.default.fileExists(atPath: bothBase + "/.kobito-tools/Pastephant") && (try? String(contentsOf: Dataset.directory(bothBase).appendingPathComponent("mark"), encoding: .utf8)) == "Pastephant", "CorkClip/ があれば古い名前のフォルダには触れない")
// このMacの履歴と設定（~/Library/Application Support/<名前>/）も、一時フォルダで同じように確かめる。
for oldName in ["Pastephant", "InGoodPaste"] {
    let support = work.appendingPathComponent("support-\(oldName)", isDirectory: true)
    try FileManager.default.createDirectory(at: support.appendingPathComponent(oldName).appendingPathComponent("database"), withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: support.appendingPathComponent(oldName).appendingPathComponent("settings.json"))
    ClipStore.moveRenamedDirectory(in: support, to: support.appendingPathComponent("CorkClip"))
    check(FileManager.default.fileExists(atPath: support.appendingPathComponent("CorkClip/settings.json").path) && !FileManager.default.fileExists(atPath: support.appendingPathComponent(oldName).path), "このMacの履歴と設定（\(oldName)/）を CorkClip/ へ移す")
}
let supportBoth = work.appendingPathComponent("support-both", isDirectory: true)
for oldName in ["InGoodPaste", "Pastephant", "CorkClip"] {
    try FileManager.default.createDirectory(at: supportBoth.appendingPathComponent(oldName), withIntermediateDirectories: true)
}
ClipStore.moveRenamedDirectory(in: supportBoth, to: supportBoth.appendingPathComponent("CorkClip"))
check(["InGoodPaste", "Pastephant"].allSatisfy { FileManager.default.fileExists(atPath: supportBoth.appendingPathComponent($0).path) }, "このMacに CorkClip/ があれば古い名前のフォルダには触れない")
let renamedBase = work.appendingPathComponent("renamed-base-Pastephant").path
try FileManager.default.createDirectory(atPath: renamedBase + "/.kobito-tools/Pastephant", withIntermediateDirectories: true)
check(Dataset.basePath(for: URL(fileURLWithPath: renamedBase).appendingPathComponent(".kobito-tools/Pastephant")) == Dataset.basePath(for: URL(fileURLWithPath: renamedBase)), "以前の名前のフォルダを選んでも基準パスに読み替える")
print("KEPT_DB=\(Dataset.keptDatabasePath(base))")
print("CARDS=\(KeptCards.cardsFile(base).path)")

// 15. 貼り方（⇥）：項目の中身に合う物だけを並べる
func styleIDs(_ kind: ClipKind, _ context: TransformContext?, combos: [TransformCombo] = [], multiple: Bool = false) -> [String] {
    PasteStyle.styles(kind: kind, context: context, combos: combos, multiple: multiple).map(\.id)
}
check(styleIDs(.text, TransformContext(text: "ひとこと")) == ["original", "more"], "短い文字は「そのまま」と「ほかの変換」だけ")
check(styleIDs(.text, TransformContext(text: "これは、\n例です。")) == ["original", "joinLines", "toWesternPunctuation", "more"], "改行と句読点のある文章")
check(styleIDs(.richText, TransformContext(text: "名前\t値\na\t1")).starts(with: ["original", "plain", "joinLines", "tableToLatex", "tableToMarkdown", "tableToCSV"]), "表（タブ区切り）には表の変換を出す")
check(styleIDs(.file, TransformContext(filePaths: ["/Base/a.pdf"], basePath: "/Base")) == ["original", "pathAbsolute", "pathTilde", "pathRelative", "fileName", "fileURL", "more"], "ファイルにはパスの貼り方")
check(styleIDs(.image, TransformContext(ocrText: "文字")) == ["original", "ocrText"], "画像には画像の文字")
check(styleIDs(.formula, TransformContext(text: "\\frac{a}{b}")) == ["original", "plain"], "数式には LaTeX の式")
check(styleIDs(.text, TransformContext(text: "$x^2$")).contains("latexImage"), "LaTeX らしい文字には数式画像")
check(styleIDs(.text, TransformContext(text: "abc"), combos: [TransformCombo(name: "組", steps: [.uppercase])]).contains { $0.hasPrefix("combo-") }, "保存した組み合わせも並べる")
check(styleIDs(.text, TransformContext(text: "a"), multiple: true) == ["original", "plain", "joinLines"], "複数選んでいるときは文字をつなぐ貼り方だけ")

// 16. カードの色分け：シリーズ共通のタグの色と同じハッシュで、同じ名前にはいつも同じ色
check(Theme.paletteIndex(for: "com.apple.Safari") == 1, "シリーズ共通のハッシュで色を選ぶ")
check(Theme.paletteIndex(for: "論文") == Theme.paletteIndex(for: "論文") && (0..<Theme.palette.count).contains(Theme.paletteIndex(for: "🐘長い名前のアプリ")), "日本語・絵文字でも色が決まる")
let kindColors = Set(ClipKind.allCases.map { kind in ClipKind.allCases.firstIndex(of: kind)! % Theme.palette.count })
check(kindColors.count == ClipKind.allCases.count, "種類ごとの色は重ならない")

// 17. 重い項目を選んでも、選択はすぐに動く（プレビューと貼り方は裏で読む）
MainActor.assumeIsolated {
    let heavyStore = try! ClipStore(directory: work.appendingPathComponent("store3"), schemaDirectory: schema)
    let side = 2400
    let noise = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    arc4random_buf(noise.bitmapData!, noise.bytesPerRow * side)
    let heavyPNG = noise.representation(using: .png, properties: [:])!
    let heavyID = try! heavyStore.save(Capture(items: [[Representation(type: "public.png", data: heavyPNG)]], sourceAppName: "重い画像"), maxItemBytes: .max).id
    let textID = try! heavyStore.save(Capture(items: [[Representation(type: "public.utf8-plain-text", data: Data("一行目\n二行目".utf8))]], sourceAppName: "文章", plainText: "一行目\n二行目"), maxItemBytes: .max).id
    let model = PanelModel(store: heavyStore)
    var commands: [PanelCommand] = []
    model.onCommand = { commands.append($0) }
    model.reload(keepSelection: false)
    func wait(until condition: () -> Bool, seconds: Double = 10) {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }
    let started = Date()
    model.selection = heavyID
    let elapsed = Date().timeIntervalSince(started)
    check(elapsed < 0.02, "重い画像（\(heavyPNG.count / 1_048_576)MB）を選んでも、選択はすぐに動く（\(Int(elapsed * 1000))ms）")
    wait { model.preview?.summary.id == heavyID && model.previewImage != nil }
    check(model.preview?.summary.id == heavyID, "プレビューは少し遅れて出る")
    check(max(model.previewImage?.width ?? .max, model.previewImage?.height ?? .max) <= 900, "プレビューの画像は画面の大きさに縮めて読む")
    check(model.previewImage.map { $0.bitsPerComponent == 8 && $0.alphaInfo == .premultipliedFirst } == true, "プレビューの画像は、画面に出すときに変換がいらない形で用意する")
    // 移った直後（貼り方を読み終える前）に ⏎ を押しても、いまの項目の貼り方で貼る。
    model.selection = textID
    model.pasteSelected()
    if case .paste(let ids, let mode)? = commands.last { check(ids == [textID] && mode == .original, "移った直後の ⏎ は、いまの項目を貼る") } else { check(false, "移った直後の ⏎ は、いまの項目を貼る") }
    wait { model.styles.contains { $0.id == "joinLines" } }
    check(model.styles.map(\.id).contains("joinLines"), "貼り方も裏で読んで出る")
    model.selectStyle(model.styles.firstIndex { $0.id == "joinLines" }!)
    model.pasteSelected()
    if case .paste(let ids, let mode)? = commands.last { check(ids == [textID] && mode == .joinLines, "⇥ で選んだ貼り方で貼る") } else { check(false, "⇥ で選んだ貼り方で貼る") }
    // アクセシビリティの許可の案内は、許可が無いときだけ出し、許可したら消える。
    var granted = false
    model.accessibilityGranted = { granted }
    model.prepareForShow()
    check(model.needsAccessibility, "許可が無ければ、開いたときに案内を出す")
    granted = true
    model.refreshAccessibility()
    check(!model.needsAccessibility, "許可したら、開いている間に案内が消える")
    granted = false
    model.prepareForShow()
    granted = true
    model.prepareForShow()
    check(!model.needsAccessibility, "許可していれば、開いても案内は出ない")
    // ⌃⏎：最後に使った「そのまま」以外の貼り方で貼る（覚えた物は設定に残す）。
    var remembered: [PasteMethod] = []
    model.onPasteMethodChange = { remembered.append($0) }
    model.settings = { var settings = Settings(); settings.lastPasteMethod = .joinLines; return settings }
    model.prepareForShow()
    model.selection = textID
    check(model.lastPasteMethod == .joinLines, "開いたときに、前回の貼り方を設定から読む")
    model.pasteSelected()
    check(model.lastPasteMethod == .joinLines && remembered.isEmpty, "「そのまま」で貼っても、前回の貼り方は変えない")
    model.pasteWithLastMethod()
    if case .paste(let ids, let mode)? = commands.last { check(ids == [textID] && mode == .joinLines, "⌃⏎ は前回の貼り方で貼る") } else { check(false, "⌃⏎ は前回の貼り方で貼る") }
    model.paste(.plainText)
    check(model.lastPasteMethod == .plainText && remembered == [.plainText], "⇧⏎ で貼ると、書式なしを前回の貼り方として覚える")
    model.settings = { var settings = Settings(); settings.lastPasteMethod = .transform([.quote]); return settings }
    model.prepareForShow()
    model.selection = textID
    model.pasteWithLastMethod()
    if case .pasteText(let text, let copyOnly)? = commands.last {
        check(!copyOnly && text == TextTransforms.apply([.quote], to: TransformContext(text: "一行目\n二行目")), "前回の貼り方が変換なら、変換してから貼る")
    } else { check(false, "前回の貼り方が変換なら、変換してから貼る") }
    model.settings = { var settings = Settings(); settings.lastPasteMethod = .transform([.pathAbsolute]); return settings }
    model.prepareForShow()
    model.selection = textID
    let before = commands.count
    model.pasteWithLastMethod()
    check(commands.count == before && model.message != nil, "前回の貼り方がこの項目に使えなければ、貼らずに知らせる")
    model.settings = { Settings() }
    model.prepareForShow()
    model.selection = textID
    model.pasteWithLastMethod()
    check(commands.count == before && model.message != nil, "前回の貼り方がまだ無ければ、貼らずに知らせる")
    // 文字の無い画像では、書式なし・改行を消すは貼らずに知らせ、前回の貼り方も変えない。
    for method in [PasteMethod.plainText, .joinLines] {
        model.settings = { var settings = Settings(); settings.lastPasteMethod = method; return settings }
        model.prepareForShow()
        model.selection = heavyID
        model.message = nil
        model.pasteWithLastMethod()
        check(commands.count == before && model.message != nil, "前回の貼り方が「\(method.label)」でも、文字の無い画像には貼らずに知らせる")
    }
    remembered = []
    model.message = nil
    model.paste(.plainText)
    check(commands.count == before && model.message != nil && remembered.isEmpty && model.lastPasteMethod == .joinLines, "文字の無い画像で ⇧⏎ を押しても、貼らず、前回の貼り方も変えない")
    model.settings = { Settings() }
    model.prepareForShow()
    check(PasteMethod(.transform([.joinLines, .latexImage])) == nil && PasteMethod(.mode(.original)) == nil && PasteMethod(.moreTransforms) == nil, "そのまま・数式画像・ほかの変換は覚えない")
    var savedSettings = Settings()
    savedSettings.lastPasteMethod = .transform([.joinLines, .quote])
    check((try? JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(savedSettings)))?.lastPasteMethod == .transform([.joinLines, .quote]), "前回の貼り方は設定のファイルに残る")
    // →：上にほかの変換、下にこの項目にできること。
    model.beginActions()
    check(model.mode == .transform && !model.transformEntries.isEmpty && model.moreFocus == .transforms, "→ で、ほかの変換の一覧を開き、↑↓ は変換に効く")
    let actionIDs = Set(model.actions.map(\.id))
    check(!actionIDs.isEmpty && actionIDs.isDisjoint(with: ["copy", "transform", "share", "quicklook", "snippet", "help"]), "できることには、コピーだけ・変換を選ぶ・Quick Look・新しい定型文・キーの一覧を並べない（送るは無い）")
    check(actionIDs.isSuperset(of: ["tags", "pin", "edit", "latex", "stack", "delete"]), "できることには、タグ・ピン・編集・数式・スタック・削除を並べる")
    model.toggleMoreFocus()
    check(model.moreFocus == .actions, "⇥ で、できることの一覧に移る")
    model.endMode()
    model.multi = [textID, heavyID]
    model.selection = textID
    model.beginActions()
    check(model.mode == .transform && model.transformEntries.isEmpty && model.moreFocus == .actions && model.actions.contains { $0.id == "merge" }, "複数選んで → を押すと、変換は出さず、できることに効く")
    model.endMode()
    model.multi = []
}

// 18. kobito シリーズの約束：④ 起動情報と、受け付ける URL
check(Series.directory.path == ProcessInfo.processInfo.environment["KOBITO_CONFIG_DIR"], "PC 固有領域は KOBITO_CONFIG_DIR で変えられる")
try Series.writeLaunchInfo(bundleID: "io.github.kobito-tools.corkclip")
let launchJSON = (try? JSONSerialization.jsonObject(with: Data(contentsOf: Series.appsDirectory.appendingPathComponent("corkclip.json")))) as? [String: Any]
check(launchJSON?["app"] as? String == "corkclip" && launchJSON?["name"] as? String == "CorkClip" && launchJSON?["command"] as? [String] == ["/usr/bin/open", "-b", "io.github.kobito-tools.corkclip"], "起動情報を書き出す（open -b <バンドルID>）")
check(launchJSON?["embed"] == nil && launchJSON?["receive"] == nil, "起動情報に embed・receive は持たない")
// --metadata（シリーズの決まり：APP_PACKAGE.md）は、起動情報と同じものを出すだけで、何も書かない。
let metadataJSON = (try? JSONSerialization.jsonObject(with: Series.metadataJSON(bundleID: "io.github.kobito-tools.corkclip"))) as? NSDictionary
check(metadataJSON != nil && metadataJSON == launchJSON.map { $0 as NSDictionary }, "--metadata の名乗りは、書き出す起動情報と同じ")
let marker = (try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "kobito-app.json")))) as? [String: Any]
check(marker?["app"] as? String == Series.appID && marker?["name"] as? String == Series.appName && marker?["bundle_id"] as? String == Series.defaultBundleID,
      "目印（kobito-app.json）のアプリID・表示名・バンドルIDが、名乗りとそろっている")
// 見せ方と操作（④）。
let launchIcon = launchJSON?["icon"] as? [String: Any]
check(launchJSON?["name_en"] as? String == "CorkClip" && launchJSON?["color"] as? String == "teal", "起動情報に英語名と色（シリーズの配色の名前）を書く")
check(launchIcon?["glyph"] as? String == "📌" && launchIcon?["file"] == nil, "アイコン画像が無ければ、代わりの1文字だけを書く")
let launchKinds = launchJSON?["kinds"] as? [[String: Any]] ?? []
check(launchKinds.count == 1 && launchKinds[0]["kind"] as? String == KeptCards.kind && launchKinds[0]["dates"] as? String == "record", "カードの種類は1つで、日付は記録として扱う")
let launchActions = launchJSON?["actions"] as? [[String: Any]] ?? []
let actionIDs = launchActions.compactMap { $0["id"] as? String }
check(actionIDs == ["panel", "today", "snippet", "latex", "settings"] && Set(actionIDs).count == actionIDs.count, "操作の id は決まった名前で重ならない")
check(launchActions.allSatisfy { ($0["label"] as? String)?.isEmpty == false && ($0["url"] as? String)?.hasPrefix("kobito://corkclip/") == true }, "操作は名前を持ち、宛先は自分だけ")
check(launchActions.allSatisfy { action in
    let url = action["url"] as! String
    return url.replacingOccurrences(of: "{today}", with: "").range(of: "[{}]", options: .regularExpression) == nil
        && Series.route(URL(string: url.replacingOccurrences(of: "{today}", with: "2026-10-20"))!) != nil
}, "操作の URL の置き換えは {today} だけで、どれも自分で受け付ける")
let launchRoutes = launchActions.map { Series.route(URL(string: ($0["url"] as! String).replacingOccurrences(of: "{today}", with: "2026-10-20"))!) }
check(launchRoutes == [.panel, .day("2026-10-20"), .snippet, .latex, .settings], "操作の URL が、それぞれの画面に届く")
check(launchActions.first { $0["role"] as? String == "settings" }?["id"] as? String == "settings" && launchActions.first { $0["role"] as? String == "new" }?["id"] as? String == "snippet", "設定と新しく作る操作に role を付ける")
let iconSVG = work.appendingPathComponent("kobito/icon.svg")
try FileManager.default.createDirectory(at: iconSVG.deletingLastPathComponent(), withIntermediateDirectories: true)
try Data("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1 1\"/>".utf8).write(to: iconSVG)
try Series.writeLaunchInfo(bundleID: "io.github.kobito-tools.corkclip", iconFile: iconSVG)
let launchWithIcon = (try? JSONSerialization.jsonObject(with: Data(contentsOf: Series.appsDirectory.appendingPathComponent("corkclip.json")))) as? [String: Any]
check(((launchWithIcon?["icon"] as? [String: Any])?["file"] as? String) == iconSVG.standardizedFileURL.path && (iconSVG.path as NSString).isAbsolutePath, "アイコン画像があれば、その絶対パスを書く")
check(Series.route(URL(string: "kobito://corkclip/day/2026-10-15")!) == .day("2026-10-15"), "kobito://corkclip/day/<日付> を受け付ける")
check(Series.route(URL(string: "kobito://corkclip/open/42?dataset=abc")!) == .open(42), "kobito://corkclip/open/<ID> を受け付ける")
check(Series.route(URL(string: "kobito://corkclip/day/昨日")!) == .panel && Series.route(URL(string: "kobito://corkclip")!) == .panel, "知らない形はパネルを開くだけ")
check(Series.route(URL(string: "kobito://another/open/1")!) == nil && Series.route(URL(string: "corkclip://open")!) == nil, "ほかのアプリ宛ての URL は受け取らない")
check(try store2.recent(query: "id:\(wordID)").map(\.id) == [wordID], "id: でその項目だけにする")
check(Series.timestamp(Date(timeIntervalSince1970: 0)).range(of: "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(Z|[+-]\\d{2}:\\d{2})$", options: .regularExpression) != nil, "日時は時差付きの ISO 8601")

// 19. ⑥ 基準パスの履歴
let otherBase = work.appendingPathComponent("other-base").path
try FileManager.default.createDirectory(atPath: otherBase, withIntermediateDirectories: true)
_ = try Dataset.create(otherBase, datasetId: "別の")
let goneBase = work.appendingPathComponent("gone-base").path
// ほかのアプリが書いた1件と、壊れた1件・もう無い基準パスの1件。
try Series.writeJSON(["v": 1, "datasets": [["path": otherBase, "id": "別の", "app": "another", "opened": "2026-10-01T09:00:00+09:00"],
                                         ["path": goneBase, "id": "消えた", "app": "another", "opened": "2026-10-02T09:00:00+09:00"],
                                         ["path": base, "id": 3]]], to: Series.datasetsFile)
check(Series.datasetCandidates().map(\.path) == [otherBase], "履歴から、dataset.json が今もある基準パスだけを候補にする")
try Series.recordDataset(path: base, id: "テスト", now: Date(timeIntervalSince1970: 1_800_000_000))
try Series.recordDataset(path: base, id: "テスト", now: Date(timeIntervalSince1970: 1_800_000_100))
let history = (try? JSONSerialization.jsonObject(with: Data(contentsOf: Series.datasetsFile))) as? [String: Any]
let historyItems = history?["datasets"] as? [[String: Any]] ?? []
check(history?["v"] as? Int == 1 && historyItems.filter { $0["path"] as? String == base }.count == 1, "同じ基準パスは1件にまとめる")
check(historyItems.first?["app"] as? String == "corkclip" && historyItems.first?["id"] as? String == "テスト" && historyItems.contains { $0["app"] as? String == "another" }, "自分の1件を先頭に足し、ほかのアプリの分は残す")
check(Series.datasetCandidates().map(\.path) == [base, otherBase], "最後に開いた順に並べる")

// 20. 起動のしかた（手で開いたときだけ設定画面を出す）
func openAppEvent(launchedAsLoginItem: Bool) -> NSAppleEventDescriptor {
    let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenApplication),
                                       targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
    if launchedAsLoginItem { event.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)), forKeyword: AEKeyword(keyAEPropData)) }
    return event
}
check(LaunchKind.isLoginItemLaunch(openAppEvent(launchedAsLoginItem: true)), "ログイン項目としての起動を見分ける")
check(!LaunchKind.isLoginItemLaunch(openAppEvent(launchedAsLoginItem: false)), "ふつうの起動はログイン時の起動としない")
check(!LaunchKind.isLoginItemLaunch(nil), "起動の Apple Event が無いときは、ログイン時の起動としない")
check(LaunchKind.shouldOpenSettingsOnLaunch(launchedAsLoginItem: false, hasPendingURL: false), "手で開いたときは設定画面を出す")
check(!LaunchKind.shouldOpenSettingsOnLaunch(launchedAsLoginItem: true, hasPendingURL: false), "ログイン時の起動では設定画面を出さない")
check(!LaunchKind.shouldOpenSettingsOnLaunch(launchedAsLoginItem: false, hasPendingURL: true), "URL で起動されたときは、その操作を優先して設定画面を出さない")

print(failures == 0 ? "すべて成功" : "\(failures) 件失敗")
exit(failures == 0 ? 0 : 1)
