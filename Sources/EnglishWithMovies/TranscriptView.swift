import LinguaCore
import SwiftUI

struct TranscriptView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let transcript = model.transcript {
            if transcript.lines.isEmpty {
                placeholder("Nenhuma fala encontrada neste arquivo.")
            } else {
                lines(transcript)
            }
        } else {
            placeholder("A legenda aparece aqui assim que a transcrição terminar.\nVocê já pode assistir enquanto isso.")
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func lines(_ transcript: Transcript) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(transcript.lines) { line in
                        LineRow(
                            line: line,
                            isActive: line.id == model.activeLine,
                            activeWord: line.id == model.activeLine ? model.activeWord : nil
                        )
                        .id(line.id)
                    }
                }
                .padding(.vertical, 12)
            }
            .simultaneousGesture(DragGesture().onChanged { _ in model.followPlayback = false })
            .onScrollWheel { model.followPlayback = false }
            .onChange(of: model.activeLine) { _, line in
                guard model.followPlayback, let line else { return }
                withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(line, anchor: .center) }
            }
            .overlay(alignment: .bottomTrailing) {
                if !model.followPlayback {
                    Button("Voltar para a fala atual", systemImage: "text.line.first.and.arrowtriangle.forward") {
                        model.followPlayback = true
                        if let line = model.activeLine { proxy.scrollTo(line, anchor: .center) }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                }
            }
        }
    }
}

private struct LineRow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var translator: Translator
    let line: TranscriptLine
    let isActive: Bool
    let activeWord: Int?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button(timestamp(line.start)) { model.seek(to: line.start) }
                .buttonStyle(.plain)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .help("Ir para esta fala")
                .frame(width: 56, alignment: .trailing)

            VStack(alignment: .leading, spacing: 4) {
                FlowLayout(spacing: 5, lineSpacing: 4) {
                    ForEach(Array(line.words.enumerated()), id: \.offset) { index, word in
                        WordButton(
                            word: word,
                            line: line,
                            isLineActive: isActive,
                            isSpoken: isActive && (activeWord.map { index <= $0 } ?? false),
                            isCurrent: isActive && activeWord == index
                        )
                    }
                }
                if translator.showLineTranslations {
                    TranslatedText(text: line.text)
                        .font(.system(size: isActive ? 16 : 14))
                        .italic()
                        .foregroundStyle(isActive ? Color.primary.opacity(0.75) : Color.secondary.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, isActive ? 10 : 4)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Color.accentColor.opacity(0.12) : .clear)
        )
        .padding(.horizontal, 8)
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
    let word: TimedWord
    let line: TranscriptLine
    let isLineActive: Bool
    let isSpoken: Bool
    let isCurrent: Bool

    var body: some View {
        Text(word.text)
            .underline(savedWords.contains(word.text), color: .orange)
            .font(.system(size: isLineActive ? 20 : 16, weight: isLineActive ? .bold : .regular))
            .foregroundStyle(color)
            .padding(.horizontal, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isCurrent ? Color.accentColor.opacity(0.3) : .clear)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                guard !WordNormalizer.lookupKey(word.text).isEmpty else { return }
                model.pause()
                showDefinition = true
            }
            .onHover { inside in
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
        if !isLineActive { return .secondary }
        return isSpoken ? .primary : .primary.opacity(0.55)
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
