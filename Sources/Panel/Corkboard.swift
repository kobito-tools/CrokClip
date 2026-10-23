import AppKit
import SwiftUI

// パネルをコルクボードに見立てる部品（コルクの地、木の枠、画びょう）。画像は同梱せず、ここで描く。

/// コルクの地。粒の模様を小さな絵に一度だけ描いておき、敷き詰める（パネルの大きさが変わっても描き直さない）。
struct CorkBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Image(nsImage: scheme == .dark ? Self.darkTile : Self.lightTile)
                .resizable(resizingMode: .tile)
            // 縁を少し暗くして、ボードの奥行きを出す。
            RadialGradient(colors: [.clear, .black.opacity(scheme == .dark ? 0.25 : 0.12)], center: .center, startRadius: 120, endRadius: 520)
        }
    }

    static let lightTile = tile(base: "#C9A06F", grains: ["#9E7243", "#B58653", "#DDB887", "#E8C899", "#87603A"])
    static let darkTile = tile(base: "#5A4533", grains: ["#3F2F22", "#4A3829", "#715841", "#7E6449", "#33261B"])

    /// 継ぎ目が出ないよう、端からはみ出た粒は反対の端にも描く。乱数は毎回同じ並びにする。
    private static func tile(base: String, grains: [String]) -> NSImage {
        let size: CGFloat = 140
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSColor(hex: base).setFill()
            rect.fill()
            var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
            func random() -> CGFloat {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return CGFloat((seed >> 33) % 10_000) / 10_000
            }
            for _ in 0..<1100 {
                let x = random() * size, y = random() * size
                let radius = 0.4 + pow(random(), 2.2) * 2.2
                let color = NSColor(hex: grains[Int(random() * CGFloat(grains.count)) % grains.count], alpha: 0.35 + random() * 0.5)
                color.setFill()
                for dx in [-size, 0, size] where x + dx + radius > 0 && x + dx - radius < size {
                    for dy in [-size, 0, size] where y + dy + radius > 0 && y + dy - radius < size {
                        NSBezierPath(ovalIn: NSRect(x: x + dx - radius, y: y + dy - radius * 0.8, width: radius * 2, height: radius * 1.6)).fill()
                    }
                }
            }
            return true
        }
    }
}

/// ボードの木の枠。パネルの縁に重ねる。
struct BoardFrame: View {
    var cornerRadius: CGFloat = 16
    var width: CGFloat = 6

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Theme.frameHighlight, Theme.frame], startPoint: .top, endPoint: .bottom), lineWidth: width)
            // 枠の内側の小さな段（コルクとの境目）。
            RoundedRectangle(cornerRadius: cornerRadius - width, style: .continuous)
                .strokeBorder(Color.black.opacity(0.22), lineWidth: 1)
                .padding(width)
        }
        .allowsHitTesting(false)
    }
}

/// 画びょう。上から見た丸い頭に、光と小さな影を付ける。
struct Pushpin: View {
    var color: Color
    var size: CGFloat = 11

    var body: some View {
        ZStack {
            // 影（ぼかすと重いので、ずらした丸で描く）。
            Circle().fill(Color.black.opacity(0.28)).offset(x: size * 0.12, y: size * 0.16)
            Circle().fill(color)
            Circle().fill(LinearGradient(colors: [.white.opacity(0.45), .clear, .black.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().strokeBorder(Color.black.opacity(0.28), lineWidth: 0.6)
            Circle().fill(Color.white.opacity(0.75)).frame(width: size * 0.26, height: size * 0.26).offset(x: -size * 0.18, y: -size * 0.18)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }
}

/// メニューバーのアイコン：枠の付いたボードに、画びょうで留めた紙が1枚。テンプレート画像にして、メニューバーの色に合わせる。
enum CorkboardIcon {
    static let menuBar: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.set()
            // ボードの枠。
            let board = NSBezierPath(roundedRect: NSRect(x: 1.75, y: 3.25, width: 14.5, height: 11.5), xRadius: 2.2, yRadius: 2.2)
            board.lineWidth = 1.5
            board.stroke()
            // コルクの粒。
            for (x, y) in [(12.6, 7.0), (13.2, 11.6), (10.9, 12.4)] {
                NSBezierPath(ovalIn: NSRect(x: x - 0.6, y: y - 0.6, width: 1.2, height: 1.2)).fill()
            }
            // 留めた紙（少し傾ける）。
            let note = NSBezierPath(rect: NSRect(x: -3, y: -2.4, width: 6, height: 5.4))
            var transform = AffineTransform(translationByX: 7.4, byY: 9.6)
            transform.rotate(byDegrees: -7)
            note.transform(using: transform)
            note.fill()
            // 画びょう（紙との間をすかして、頭を丸く見せる）。
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: NSRect(x: 4.9, y: 4.6, width: 4.8, height: 4.8)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSBezierPath(ovalIn: NSRect(x: 5.65, y: 5.35, width: 3.3, height: 3.3)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "CorkClip"
        return image
    }()
}
