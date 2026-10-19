import AppKit
import SwiftUI

/// パネルの色。コルクボードに見立てる（コルクの地、木の枠、画びょうで留めたメモ用紙）。文字は kobito-tools シリーズの小人と同じ墨色。明るい画面と暗い画面の両方を持つ。
enum Theme {
    private static func dynamic(_ light: String, _ dark: String, alpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(hex: hex, alpha: alpha)
        })
    }

    /// アクセント（シリーズの青みがかった灰色）。コルクの茶色の上でも、選んでいる物がはっきり分かる。
    static let accent = dynamic("#4F6C84", "#9DB4C6")
    /// コルクの地（粒の模様は CorkBackground が描く）。
    static let cork = dynamic("#C9A06F", "#5A4533")
    /// ボードの木の枠。
    static let frame = dynamic("#8B5E3A", "#33251A")
    static let frameHighlight = dynamic("#B07E52", "#4E3A2A")
    /// 帯の紙（検索欄・見出し・キーの案内を書く細長い紙）。
    static let paper = dynamic("#F7F1E3", "#2E2A25")
    /// メモ用紙（履歴のカード）。
    static let card = dynamic("#FFFDF7", "#37332D")
    static let cardBorder = dynamic("#E3D7BF", "#4C463D")
    /// 紙の下に落ちる影（影の効果は重いので、ずらした形で描く）。
    static let cardShade = dynamic("#5B3E22", "#000000", alpha: 0.28)
    /// プレビューの紙。
    static let well = dynamic("#FCF9F1", "#312D28")
    static let wellBorder = dynamic("#DCCFB5", "#554E44")
    /// 文字（小人の墨色）。
    static let ink = dynamic("#3B4441", "#E6E3D9")
    static let subtle = dynamic("#76716A", "#A9A49B")
    /// キーの印の地。
    static let keycap = dynamic("#EDE5D3", "#45403A")
    /// 画びょう。ピン留めは赤、定型文は緑、ほかは真鍮。
    static let pinRed = Color(nsColor: NSColor(hex: "#D2443A"))
    static let pinGreen = Color(nsColor: NSColor(hex: "#3F8A6E"))
    static let pinBrass = Color(nsColor: NSColor(hex: "#C9A24D"))

    /// 色分けに使う色（シリーズ共通のタグの色と同じ並び）。
    static let palette = ["#477B70", "#C75543", "#9B7432", "#5C668F", "#7B587D", "#416B7C", "#8A6A4F", "#6D7A45"]

    /// シリーズ共通のタグの色と同じハッシュ（hash = hash * 31 + 文字のコード）で、同じ名前にはいつも同じ色を返す。
    static func paletteIndex(for key: String) -> Int {
        var hash: UInt32 = 0
        for scalar in key.unicodeScalars { hash = hash &* 31 &+ scalar.value }
        return Int(hash % UInt32(palette.count))
    }

    static func color(for key: String) -> Color { Color(nsColor: NSColor(hex: palette[paletteIndex(for: key)])) }
}

/// 一覧のカードの色分け（設定で選ぶ）。
enum RowColorMode: String, Codable, CaseIterable {
    case app, kind, tag, none

    var label: String {
        switch self {
        case .app: "コピー元のアプリごと"
        case .kind: "種類ごと"
        case .tag: "最初のタグごと"
        case .none: "色分けしない"
        }
    }

    /// 色を決める名前。nil なら色を付けない。
    func key(for clip: ClipSummary) -> String? {
        switch self {
        case .app: clip.isSnippet ? "定型文" : (clip.sourceBundleID ?? clip.sourceAppName)
        case .kind: clip.isSnippet ? "snippet" : clip.kind.rawValue
        case .tag: clip.tags.first
        case .none: nil
        }
    }

    func color(for clip: ClipSummary) -> Color? {
        guard let key = key(for: clip) else { return nil }
        if self == .kind {
            // 種類は数が決まっているので、重ならないよう順に色を割り当てる。
            let order = ClipKind.allCases.map(\.rawValue) + ["snippet"]
            return Color(nsColor: NSColor(hex: Theme.palette[(order.firstIndex(of: key) ?? 0) % Theme.palette.count]))
        }
        return Theme.color(for: key)
    }
}

extension NSColor {
    /// #RRGGBB から作る。
    convenience init(hex: String, alpha: CGFloat = 1) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
    }
}
