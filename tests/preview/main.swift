import AppKit
import SwiftUI

// パネル・設定の画面・メニューバーのアイコンを、アプリを起動せずに PNG に書き出す（見た目を確かめる用）。
// 実行は tests/preview.sh から。第1引数に一時フォルダ、第2引数に schema/、第3引数に書き出す先のフォルダを渡す。
// 履歴は一時フォルダに作った見本で、実際の履歴と設定には触れない。

let work = URL(fileURLWithPath: CommandLine.arguments[1])
let schema = URL(fileURLWithPath: CommandLine.arguments[2])
let output = URL(fileURLWithPath: CommandLine.arguments[3])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func makePNG(width: Int, height: Int, draw: (NSRect) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(NSRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

/// 見えないウィンドウに置いて描かせ、2倍の解像度で書き出す。
@MainActor func render<V: View>(_ view: V, size: NSSize, dark: Bool, name: String) {
    let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
    host.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.backgroundColor = dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.93, alpha: 1)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.6))
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    host.cacheDisplay(in: host.bounds, to: rep)
    let url = output.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png")
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print(url.path)
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    let store = try! ClipStore(directory: work.appendingPathComponent("store"), schemaDirectory: schema)
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("corkclip-preview-\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }

    @discardableResult func add(_ text: String? = nil, png: Data? = nil, app: (String, String)) -> Int {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        if let text { item.setString(text, forType: .string) }
        if let png { item.setData(png, forType: .png) }
        pasteboard.writeObjects([item])
        let capture = Capture.read(from: pasteboard, sourceBundleID: app.0, sourceAppName: app.1)!
        return try! store.save(capture, maxItemBytes: .max).id
    }
    let safari = ("com.apple.Safari", "Safari"), notes = ("com.apple.Notes", "メモ"), finder = ("com.apple.finder", "Finder"), terminal = ("com.apple.Terminal", "ターミナル")

    let address = add("〒100-0001 東京都千代田区千代田1-1", app: notes)
    try! store.setPinned([address], true)
    let snippet = try! store.createSnippet(title: "お礼のあいさつ", body: "いつもお世話になっております。\nご確認いただき、ありがとうございました。")
    _ = snippet
    add("https://github.com/kobito-tools", app: safari)
    let picture = makePNG(width: 320, height: 200) { rect in
        NSGradient(starting: NSColor(hex: "#8FB4D0"), ending: NSColor(hex: "#F2D49B"))!.draw(in: rect, angle: 90)
        NSColor(hex: "#5E8C5A").setFill()
        NSBezierPath(ovalIn: NSRect(x: -40, y: -120, width: 400, height: 200)).fill()
    }
    add(png: picture, app: finder)
    let meeting = add("来週の打ち合わせは、火曜の 14 時から会議室 B で行います。資料は前日までに共有フォルダへお願いします。", app: notes)
    try! store.addTag(try! store.findOrCreateTag("仕事"), to: [meeting])
    add("swift build -c release", app: terminal)
    let latest = add("コルクボードに留めるように、コピーした物を取っておけます。", app: notes)
    try! store.addTag(try! store.findOrCreateTag("メモ"), to: [latest])

    let model = PanelModel(store: store)
    model.prepareForShow()
    for dark in [false, true] {
        render(PanelView(model: model), size: NSSize(width: 380, height: 760), dark: dark, name: "panel")
    }

    // 何も無いときの案内。
    let emptyStore = try! ClipStore(directory: work.appendingPathComponent("empty"), schemaDirectory: schema)
    let empty = PanelModel(store: emptyStore)
    empty.prepareForShow()
    render(PanelView(model: empty), size: NSSize(width: 380, height: 520), dark: false, name: "panel-empty")

    let settings = SettingsModel(settings: Settings())
    for dark in [false, true] {
        render(SettingsView(model: settings), size: NSSize(width: 680, height: 640), dark: dark, name: "settings")
    }

    // メニューバーのアイコン（明るい・暗いメニューバーの色で、大きくして描く）。
    for dark in [false, true] {
        let png = makePNG(width: 144, height: 72) { rect in
            (dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.92, alpha: 1)).setFill()
            rect.fill()
            let icon = CorkboardIcon.menuBar.copy() as! NSImage
            icon.isTemplate = false
            let tinted = NSImage(size: icon.size, flipped: false) { r in
                icon.draw(in: r)
                (dark ? NSColor.white : NSColor.black).set()
                r.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: 0, y: 0, width: 72, height: 72))
            tinted.draw(in: NSRect(x: 90, y: 27, width: 18, height: 18))
        }
        let url = output.appendingPathComponent("menubar-\(dark ? "dark" : "light").png")
        try! png.write(to: url)
        print(url.path)
    }
}
