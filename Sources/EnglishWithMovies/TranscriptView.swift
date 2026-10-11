import LinguaCore
import SwiftUI

struct TranscriptView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let transcript = model.transcript {
            if transcript.lines.isEmpty {
                placeholder("Nenhuma fala encontrada neste arquivo.")
            } else {
                VStack(spacing: 0) {
                    if model.showSearch || model.subtitleSource != nil || model.hideSubtitles {
                        TranscriptHeader()
                    }
                    lines(transcript)
                }
            }
        } else {
            placeholder("A legenda aparece aqui assim que a transcrição terminar.\nVocê já pode assistir enquanto isso.")
        }
    }

    private func placeholder(_ text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "captions.bubble.fill")
                .font(.system(size: 34))
                .gradientForeground(Theme.brand)
            Text(text)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textDim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func lines(_ transcript: Transcript) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    let matches = Set(model.searchMatches)
                    ForEach(transcript.lines) { line in
                        LineRow(
                            line: line,
                            isActive: line.id == model.activeLine,
                            activeWord: line.id == model.activeLine ? model.activeWord : nil,
                            searchMatch: matches.contains(line.id) ? (line.id == model.currentSearchLine ? .current : .other) : nil
                        )
                        .id(line.id)
                    }
                }
                .padding(.vertical, 14)
            }
            .scrollIndicators(.never)
            .simultaneousGesture(DragGesture().onChanged { _ in model.followPlayback = false })
            .onScrollWheel { model.followPlayback = false }
            .onChange(of: model.activeLine) { _, line in
                guard model.followPlayback, let line else { return }
                withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(line, anchor: .center) }
            }
            .onChange(of: model.scrollRequest) { _, _ in
                guard let line = model.scrollLine else { return }
                // Far rows of a lazy list are only estimated, so scroll again once they exist.
                proxy.scrollTo(line, anchor: .center)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { proxy.scrollTo(line, anchor: .center) }
            }
            .overlay(alignment: .bottomTrailing) {
                if !model.followPlayback {
                    Button("Voltar para a fala atual", systemImage: "text.line.first.and.arrowtriangle.forward") {
                        model.followPlayback = true
                        if let line = model.activeLine { proxy.scrollTo(line, anchor: .center) }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(16)
                }
            }
        }
    }
}

private struct LineRow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var translator: Translator
    @EnvironmentObject private var practice: PracticeStore
    let line: TranscriptLine
    let isActive: Bool
    let activeWord: Int?
    var searchMatch: SearchMatch?

    enum SearchMatch { case current, other }

    @ViewState private var isHovered = false

    /// Listening challenge: hidden until clicked.
    private var isHidden: Bool { model.hideSubtitles && !model.revealedLines.contains(line.id) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .trailing, spacing: 6) {
                Button(timestamp(line.start)) { model.seek(to: line.start) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(isActive ? Theme.violet : Theme.textDim)
                    .help("Ir para esta fala")
                HStack(spacing: 5) {
                    if let best = practice.record(for: line, source: model.sourceName)?.best {
                        Chip(text: "\(best)", color: scoreColor(best))
                            .help("Sua melhor nota nesta fala")
                    }
                    if isActive || isHovered {
                        Button {
                            model.pause()
                            model.practiceLine = line
                        } label: {
                            Image(systemName: "mic.fill")
                        }
                        .buttonStyle(IconButtonStyle(size: 26, tint: isActive ? Theme.violet : .white))
                        .help("Praticar a pronúncia desta fala (⌘R na fala atual)")
                    }
                }
                .frame(height: 26)
            }
            .frame(width: 70, alignment: .trailing)

            VStack(alignment: .leading, spacing: 6) {
                FlowLayout(spacing: 4, lineSpacing: 6) {
                    ForEach(Array(line.words.enumerated()), id: \.offset) { index, word in
                        WordButton(
                            word: word,
                            line: line,
                            isLineActive: isActive,
                            isSpoken: isActive && (activeWord.map { index <= $0 } ?? false),
                            isCurrent: isActive && activeWord == index,
                            isSentenceStart: index == 0 || line.words[index - 1].text.last.map { ".?!".contains($0) } == true
                        )
                    }
                }
                .blur(radius: isHidden ? 7 : 0)
                .allowsHitTesting(!isHidden)
                .overlay {
                    if isHidden {
                        Text(isActive ? "Ouça… e clique para conferir" : "Clique para ver")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(isHovered || isActive ? 0.85 : 0))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture { model.revealedLines.insert(line.id) }
                    }
                }
                if translator.showLineTranslations, !isHidden {
                    TranslatedText(text: line.text)
                        .font(.system(size: isActive ? 16 : 14))
                        .italic()
                        .foregroundStyle(isActive ? Theme.orange.opacity(0.95) : Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, isActive ? 14 : 6)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isActive
                      ? AnyShapeStyle(LinearGradient(colors: [Theme.indigo.opacity(0.22), Theme.violet.opacity(0.12)],
                                                     startPoint: .leading, endPoint: .trailing))
                      : AnyShapeStyle(isHovered ? Theme.surface : Color.clear))
        )
        .overlay(alignment: .leading) {
            if isActive {
                Capsule().fill(Theme.warm).frame(width: 3).padding(.vertical, 12)
            }
        }
        .overlay {
            if let searchMatch {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.orange.opacity(searchMatch == .current ? 0.9 : 0.35), lineWidth: searchMatch == .current ? 2 : 1)
            }
        }
        .padding(.horizontal, 10)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.2), value: isActive)
    }

    private func timestamp(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

private struct WordButton: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var savedWords: SavedWordsStore
    @EnvironmentObject private var translator: Translator
    @ViewState private var showDefinition = false
    @ViewState private var isHovered = false
    let word: TimedWord
    let line: TranscriptLine
    let isLineActive: Bool
    let isSpoken: Bool
    let isCurrent: Bool
    var isSentenceStart = false

    var body: some View {
        let saved = savedWords.contains(word.text)
        let uncommon = !saved && model.highlightUncommon && CommonWords.isUncommon(word.text, atSentenceStart: isSentenceStart)
        Text(word.text)
            .underline(saved || uncommon, pattern: saved ? .solid : .dot, color: saved ? Theme.orange : Theme.violet)
            .font(.system(size: isLineActive ? 22 : 16, weight: isLineActive ? .bold : .regular))
            .foregroundStyle(color)
            .padding(.horizontal, isCurrent ? 6 : 2)
            .padding(.vertical, isCurrent ? 1 : 0)
            .background(
                Capsule()
                    .fill(Theme.brand)
                    .shadow(color: Theme.violet.opacity(0.6), radius: 8)
                    .opacity(isCurrent ? 1 : 0)
            )
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovered && !isCurrent ? Color.white.opacity(0.1) : .clear)
            )
            .animation(.easeOut(duration: 0.12), value: isCurrent)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !WordNormalizer.lookupKey(word.text).isEmpty else { return }
                model.pause()
                showDefinition = true
            }
            .onHover { inside in
                isHovered = inside
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .popover(isPresented: $showDefinition, arrowEdge: .top) {
                WordPopover(word: word.text, line: line)
                    .environmentObject(model)
                    .environmentObject(savedWords)
                    .environmentObject(translator)
            }
    }

    private var color: Color {
        if !isLineActive { return .white.opacity(0.6) }
        return isSpoken ? .white : .white.opacity(0.42)
    }
}

/// Lays out children left to right, wrapping to new rows like text.
struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + row.height - size.height), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += row.indices.isEmpty ? size.width : size.width + spacing
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

private extension View {
    /// Detects mouse wheel / trackpad scrolling so auto-follow can pause while the user reads.
    func onScrollWheel(_ action: @escaping () -> Void) -> some View {
        background(ScrollWheelMonitor(action: action))
    }
}

private struct ScrollWheelMonitor: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak view] event in
            if let view, let window = view.window, event.window == window,
               view.bounds.contains(view.convert(event.locationInWindow, from: nil)) {
                action()
            }
            return event
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var monitor: Any?
    }
}

/// Above the subtitles: where they came from, the listening challenge and the search box.
private struct TranscriptHeader: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            if model.showSearch {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.textDim)
                    TextField("Buscar na legenda", text: $model.searchQuery)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                        .onSubmit { model.showSearchResult(1) }
                        .onExitCommand { close() }
                    if !model.searchQuery.isEmpty {
                        let count = model.searchMatches.count
                        Text(count == 0 ? "nada" : "\(model.searchIndex + 1) de \(count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(count == 0 ? Theme.orange : Theme.textDim)
                        Button { model.showSearchResult(-1) } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.plain).disabled(count == 0)
                        Button { model.showSearchResult(1) } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.plain).disabled(count == 0)
                    }
                    Button { close() } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.textDim)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .glassCard(cornerRadius: 10)
                .frame(maxWidth: 380)
                .onAppear { searchFocused = true }
            }
            Spacer(minLength: 0)
            if model.hideSubtitles {
                Chip(text: "Desafio de escuta: clique numa fala para ver", systemImage: "eye.slash.fill", color: Theme.orange)
            }
            if let source = model.subtitleSource {
                Chip(text: source, systemImage: "captions.bubble.fill", color: Theme.violet)
                    .help("Estas legendas vieram junto com o vídeo. Para usar a transcrição automática, clique em Transcrever de novo.")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
    }

    private func close() {
        model.searchQuery = ""
        model.showSearch = false
    }
}
