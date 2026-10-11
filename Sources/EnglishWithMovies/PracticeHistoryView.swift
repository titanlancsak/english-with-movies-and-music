import LinguaCore
import SwiftUI

/// Window with every practiced sentence and its scores.
struct PracticeHistoryView: View {
    @EnvironmentObject private var practice: PracticeStore

    var body: some View {
        let history = practice.history
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SummaryCard(title: "Frases praticadas", value: "\(history.records.count)")
                SummaryCard(title: "Tentativas", value: "\(history.attemptCount)")
                SummaryCard(title: "Média atual", value: history.averageScore.map(String.init) ?? "–",
                            color: history.averageScore.map(scoreColor) ?? .secondary)
            }
            .padding()

            if history.records.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "mic.badge.plus")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Nenhuma fala praticada ainda").font(.title3.bold())
                    Text("Clique no 🎤 ao lado de uma fala, ou use ⌘R para praticar a fala atual.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(history.recent) { record in
                    RecordRow(record: record)
                        .contextMenu {
                            Button("Apagar histórico desta frase", role: .destructive) { practice.remove(record.id) }
                        }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}

private struct SummaryCard: View {
    let title: String
    let value: String
    var color: Color = .primary

    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title.bold()).foregroundStyle(color).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }
}

private struct RecordRow: View {
    let record: PracticeRecord

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ScoreRing(score: record.last?.score ?? 0, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.sentence).lineLimit(2)
                HStack(spacing: 6) {
                    if let source = record.source {
                        Text("\(source) · \(formatTime(record.lineStart))").lineLimit(1)
                    }
                    if let date = record.last?.date {
                        Text(date, format: .relative(presentation: .named))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("melhor \(record.best)").font(.caption.bold()).foregroundStyle(scoreColor(record.best))
                Sparkline(scores: record.attempts.suffix(10).map(\.score))
                Text("\(record.attempts.count)× ").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Tiny bars showing the latest scores, oldest on the left.
private struct Sparkline: View {
    let scores: [Int]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(scores.enumerated()), id: \.offset) { _, score in
                RoundedRectangle(cornerRadius: 1)
                    .fill(scoreColor(score))
                    .frame(width: 5, height: max(2, CGFloat(score) / 100 * 22))
            }
        }
        .frame(height: 22, alignment: .bottom)
        .help("Últimas notas: " + scores.map(String.init).joined(separator: ", "))
    }
}
