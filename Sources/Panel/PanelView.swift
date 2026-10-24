import AppKit
import SwiftUI

/// 画面の端から出てくるパネル（3.1）。コルクボードに見立てて、上から、検索の帯、プレビューの紙（作業中はその画面）と貼り方、
/// 画びょうで留めた履歴のカード、操作の案内の帯を並べる。貼り付けの許可が無いときは、検索の帯の下に許可の案内を留める。
/// キー操作は PanelController が受け取る。
struct PanelView: View {
    @ObservedObject var model: PanelModel
    @FocusState private var focused: PanelModel.Field?

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 10) {
                header
                if model.needsAccessibility, model.mode == .list {
                    AccessibilityGuide(model: model).transition(.opacity)
                }
                if model.mode != .list {
                    Card(title: nil) { ModeView(model: model, focused: $focused) }
                        .frame(height: max(240, geometry.size.height * 0.5))
                } else {
                    PreviewSection(model: model, state: model.previewState, height: max(190, geometry.size.height * 0.38))
                }
                list
                if let message = model.message {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.accent))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                FooterHints(model: model, state: model.previewState)
            }
            .padding(.horizontal, 13).padding(.vertical, 12)
            .animation(.easeOut(duration: 0.15), value: model.message)
            .animation(.easeOut(duration: 0.15), value: model.needsAccessibility)
        }
        .foregroundStyle(Theme.ink)
        .background(CorkBackground())
        .overlay(BoardFrame())
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onChange(of: model.focusRequest) { _ in focused = model.focus }
        .onAppear { focused = model.focus }
    }

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.subtle)
                TextField("検索（#タグ type:画像 app:Word …）", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($focused, equals: .search)
                if !model.query.isEmpty {
                    Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.subtle) }
                        .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(focused == .search ? Theme.accent : Theme.cardBorder, lineWidth: focused == .search ? 1.5 : 1))
            Menu {
                Picker("並べ替え", selection: $model.sort) {
                    ForEach(SortOrder.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("並べ替え：\(model.sort.label)")
            Button { model.onCommand(.openSettings) } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help("設定（⌘,）")
        }
        .foregroundStyle(Theme.subtle)
        .padding(.leading, 5).padding(.trailing, 10).padding(.vertical, 5)
        .background(PaperStrip())
    }

    private var list: some View {
        let indexByID = Dictionary(uniqueKeysWithValues: model.rows.enumerated().map { ($1.id, $0) })
        return Group {
            if model.rows.isEmpty {
                VStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: model.query.isEmpty ? "tray" : "magnifyingglass").font(.system(size: 28)).foregroundStyle(Theme.subtle)
                        Text(model.query.isEmpty ? "まだ履歴がありません。\nコピーするとここに並びます。" : "見つかりませんでした")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.subtle)
                    }
                    .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 16)
                    .background(NotePaper(cornerRadius: 6))
                    .overlay(alignment: .top) { Pushpin(color: Theme.pinBrass, size: 12).offset(y: -4) }
                    .rotationEffect(.degrees(-1.5))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 9) {
                            if model.showsPins {
                                SectionLabel(text: "ピン・定型文", symbol: "pin.fill", count: model.pins.count)
                                ForEach(model.pins) { clip in row(clip, index: indexByID[clip.id] ?? 0) }
                                SectionLabel(text: "履歴", symbol: "clock.fill", count: model.clips.count).padding(.top, 4)
                            } else {
                                SectionLabel(text: model.query.isEmpty ? "履歴" : "見つかった履歴", symbol: "clock.fill", count: model.clips.count)
                            }
                            ForEach(model.clips) { clip in row(clip, index: indexByID[clip.id] ?? 0) }
                        }
                        .padding(.horizontal, 3)
                        .padding(.top, 2)
                        .padding(.bottom, 8)
                    }
                    .onChange(of: model.selection) { id in
                        guard let id else { return }
                        proxy.scrollTo(id)
                    }
                }
            }
        }
    }

    private func row(_ clip: ClipSummary, index: Int) -> some View {
        // 中身が変わっていないカードは描き直さない（選択が動いたときに描き直すのは、選択が外れた・付いた2枚だけ）。
        ClipCard(model: model, clip: clip, index: index, selected: model.isHighlighted(clip.id), primary: clip.id == model.selection,
                 tint: model.rowColorMode.color(for: clip))
            .equatable()
            .id(clip.id)
            .contentShape(Rectangle())
            // ダブルクリックの判定を待たずに、1回目で選ぶ（2回目で貼る）。onTapGesture(count: 2) を付けると、1回目の反応が遅れる。
            .onTapGesture {
                if clickCount >= 2 { model.selection = clip.id; model.pasteSelected() }
                else { model.click(clip.id, modifiers: NSEvent.modifierFlags) }
            }
            .onHover { inside in model.hover(clip.id, inside: inside) }
            .onDrag { model.itemProvider(for: clip.id) }
            .contextMenu { RowMenu(model: model, id: clip.id) }
    }
}

/// プレビューの枠と貼り方の帯。PreviewState だけを見て、中身が届いても一覧は描き直さない。
private struct PreviewSection: View {
    let model: PanelModel
    @ObservedObject var state: PreviewState
    let height: CGFloat

    var body: some View {
        if model.showPreview, state.preview != nil {
            Card(title: "プレビュー") {
                VStack(spacing: 0) {
                    PreviewView(model: model, state: state).frame(maxHeight: .infinity)
                    if state.styles.count > 1 {
                        Rectangle().fill(Theme.wellBorder).frame(height: 1)
                        StyleStrip(model: model, state: state)
                    }
                }
            }
            .frame(height: height)
        } else if state.styles.count > 1 {
            Card(title: nil) { StyleStrip(model: model, state: state) }.fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// アクセシビリティの許可が無いときの案内。赤い画びょうで留めたメモ用紙に、なぜいるかと、許可のしかたを書く。
private struct AccessibilityGuide: View {
    let model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("貼り付けの許可がまだです", systemImage: "hand.raised.fill")
                .font(.system(size: 12.5, weight: .semibold))
            Text("選んだカードを前のアプリへ貼り付けるには、アクセシビリティの許可がいります。いまは、クリップボードに戻すだけです。")
            Text("システム設定で CorkClip をオンにすると、この案内は消えます。")
                .foregroundStyle(Theme.subtle)
            // パネルは前のアプリをアクティブにしたまま出すので、ふつうのボタンだと灰色になる。貼り方の帯と同じ形で描く。
            Button { model.onCommand(.openAccessibilitySettings) } label: {
                Label("システム設定を開く", systemImage: "gearshape")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 11).padding(.vertical, 4)
                    .background(Capsule().fill(Theme.accent))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .font(.system(size: 11.5))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.top, 11).padding(.bottom, 10)
        .background(NotePaper(cornerRadius: 6))
        .overlay(alignment: .top) { Pushpin(color: Theme.pinRed, size: 12).offset(y: -5) }
    }
}

/// 右クリックのメニュー。中身（できることの一覧）は、メニューを開くときに作る。
private struct RowMenu: View {
    let model: PanelModel
    let id: Int

    var body: some View {
        ForEach(model.actionItems(for: model.multi.contains(id) ? model.multi : [id])) { action in
            Button { action.run() } label: { Label(action.label, systemImage: action.symbol) }
        }
    }
}

/// 見出しの付いた紙。プレビューと作業の画面に使い、上の両端を画びょうで留める。
private struct Card<Content: View>: View {
    let title: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.subtle)
                    .padding(.horizontal, 12).padding(.top, 7)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.well))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.wellBorder, lineWidth: 1))
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.cardShade).offset(x: 1, y: 2.5))
        .overlay(alignment: .topLeading) { Pushpin(color: Theme.pinBrass).offset(x: 9, y: -4) }
        .overlay(alignment: .topTrailing) { Pushpin(color: Theme.pinBrass).offset(x: -9, y: -4) }
    }
}

private struct SectionLabel: View {
    let text: String
    let symbol: String
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 9))
            Text(text).font(.system(size: 11, weight: .semibold))
            Text("\(count)").font(.system(size: 10, weight: .medium)).monospacedDigit()
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Capsule().fill(Theme.keycap))
        }
        .foregroundStyle(Theme.subtle)
        // コルクに留めた小さな名札。
        .padding(.leading, 8).padding(.trailing, 5).padding(.vertical, 3)
        .background(PaperStrip(cornerRadius: 4))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }
}

/// 一覧の1件。画びょうで留めたメモ用紙に、左の色の帯（色分け）、サムネかアイコン、見出し、コピー元と時刻、タグを書く。
/// 選んでいる紙は少し持ち上がる。画びょうは、ピン留めは赤、定型文は緑、ほかは真鍮。
private struct ClipCard: View, Equatable {
    let model: PanelModel
    let clip: ClipSummary
    let index: Int
    let selected: Bool
    let primary: Bool
    let tint: Color?

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.unitsStyle = .short
        return formatter
    }()

    private var color: Color { tint ?? Theme.subtle }

    private var pinColor: Color { clip.isSnippet ? Theme.pinGreen : clip.pinned ? Theme.pinRed : Theme.pinBrass }

    /// model は見た目に関わらないので比べない。
    static func == (lhs: ClipCard, rhs: ClipCard) -> Bool {
        lhs.clip == rhs.clip && lhs.index == rhs.index && lhs.selected == rhs.selected && lhs.primary == rhs.primary && lhs.tint == rhs.tint
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            leading
                .frame(width: 42, height: 42)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color.opacity(0.14)))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(clip.displayText)
                        .font(.system(size: 13, weight: clip.title == nil ? .regular : .semibold))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 5) {
                    if let icon = model.appIcon(for: clip.sourceBundleID), !clip.isSnippet {
                        Image(nsImage: icon).resizable().frame(width: 13, height: 13)
                    }
                    Text(caption).lineLimit(1)
                    ForEach(clip.tags.prefix(3), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.color(for: tag))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Theme.color(for: tag).opacity(0.13)))
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.subtle)
            }
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.subtle.opacity(0.8))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Theme.keycap.opacity(0.7)))
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 9)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(alignment: .leading) {
            // 色分けの帯。
            Rectangle().fill(tint ?? Color.clear).frame(width: 4)
        }
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(selected ? Theme.accent.opacity(primary ? 0.16 : 0.09) : Color.clear))
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.card))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(selected ? Theme.accent : Theme.cardBorder, lineWidth: selected && primary ? 2 : 1))
        // 影の効果はメインスレッドで描かれて重いので、ふだんの紙はずらした形で影を描き、本物の影は選んでいる紙だけに付ける。
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.cardShade).offset(x: 1, y: selected ? 3 : 1.5))
        .overlay(alignment: .top) { Pushpin(color: pinColor, size: clip.pinned || clip.isSnippet ? 13 : 10).offset(y: clip.pinned || clip.isSnippet ? -5.5 : -4) }
        .lifted(selected)
    }

    @ViewBuilder private var leading: some View {
        if let thumbnail = model.thumbnail(for: clip) {
            Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
        } else {
            Image(systemName: clip.isSnippet ? "text.badge.star" : clip.kind.symbolName).font(.system(size: 17)).foregroundStyle(color)
        }
    }

    private var caption: String {
        if clip.isSnippet { return "定型文" + (clip.title == nil ? "" : "・" + clip.preview) }
        var parts = [clip.sourceAppName, Self.relativeFormatter.localizedString(for: clip.lastUsedAt, relativeTo: Date())].compactMap { $0 }
        if clip.copyCount > 1 { parts.append("×\(clip.copyCount)") }
        if clip.oversized { parts.append("文字だけ保存") }
        return parts.joined(separator: " · ")
    }
}

/// 貼り方の帯。選んだ項目に合う貼り方だけを並べる。⇥ で切り替え、クリックでも選べる。
/// 幅に収まらないときは次の行へ折り返し、どの貼り方も切れずに見えるようにする。
private struct StyleStrip: View {
    let model: PanelModel
    @ObservedObject var state: PreviewState

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("貼り方").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.subtle).padding(.top, 5)
            FlowLayout(spacing: 6, lineSpacing: 5) {
                ForEach(Array(state.styles.enumerated()), id: \.element.id) { index, style in
                    let selected = index == state.styleIndex
                    Label(style.label, systemImage: style.symbol)
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .lineLimit(1)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(selected ? Theme.accent : Theme.card))
                        .overlay(Capsule().strokeBorder(selected ? Color.clear : Theme.cardBorder))
                        .foregroundStyle(selected ? Color.white : Theme.ink)
                        .contentShape(Capsule())
                        .onTapGesture {
                            model.selectStyle(index)
                            if clickCount >= 2 { model.pasteSelected() }
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}

/// 子を左から並べ、幅に収まらなければ次の行へ送る。
private struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map { $0.height }.reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if !row.indices.isEmpty, needed > width {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

/// いまの画面で使えるキーの案内。一覧では3つだけにし、ほかは → の一覧で見つけられるようにする。
private struct FooterHints: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var state: PreviewState

    private var items: [(String, String)] {
        switch model.mode {
        case .list:
            let style = model.currentStyle.map { $0.id == "more" ? "変換を選ぶ" : "「\($0.label)」で貼る" } ?? "貼る"
            return [("⏎", style), ("⇥", "貼り方"), ("→", "できること"), ("⌘/", "キー")]
        case .actions: return [("英字", "そのキーの操作"), ("⏎", "選んだ操作"), ("esc", "戻る")]
        case .tags: return [("⏎", "付ける（無ければ作る）"), ("↑↓", "候補"), ("⌫", "最後のタグを外す"), ("esc", "戻る")]
        case .edit: return [("⌘⏎", "貼る"), ("⇧⌘⏎", "コピーだけ"), ("esc", "戻る")]
        case .transform: return [("⏎", "貼る"), ("space", "つなげる"), ("⌘S", "組み合わせを保存"), ("esc", "戻る")]
        case .merge: return [("⏎", "まとめて貼る"), ("⌘⏎", "新しい項目として保存"), ("↑↓", "区切り"), ("esc", "戻る")]
        case .latex: return [("⏎", "画像にして貼る"), ("⇧⏎", "改行"), ("⌘⏎", "コピーだけ"), ("esc", "戻る")]
        case .snippet: return [("⌘⏎", "保存"), ("⇥", "次の欄"), ("esc", "戻る")]
        case .help: return [("どのキーでも", "戻る")]
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(items, id: \.0) { key, text in
                HStack(spacing: 4) {
                    Text(key)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Theme.keycap))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.cardBorder))
                    Text(text).font(.system(size: 11)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.subtle)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(PaperStrip())
    }
}

/// いまのクリックが何回目か（ダブルクリックなら 2）。
var clickCount: Int { NSApp.currentEvent?.clickCount ?? 1 }

private extension View {
    /// 選んでいる紙を少し持ち上げる。影の効果は、持ち上げた紙にだけ付ける。
    @ViewBuilder func lifted(_ on: Bool) -> some View {
        if on { shadow(color: .black.opacity(0.22), radius: 5, y: 3).offset(y: -1.5) } else { self }
    }
}

/// コルクに留めた細長い紙（検索・見出し・キーの案内）。
private struct PaperStrip: View {
    var cornerRadius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Theme.paper)
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 0.5))
            .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Theme.cardShade).offset(x: 0.5, y: 1.5))
    }
}

/// メモ用紙（履歴が空のときの案内）。
private struct NotePaper: View {
    var cornerRadius: CGFloat = 5

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 1))
            .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Theme.cardShade).offset(x: 1, y: 2.5))
    }
}
