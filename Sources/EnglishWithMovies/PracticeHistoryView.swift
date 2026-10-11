import LinguaCore
import SwiftUI

/// Every practiced sentence and its scores.
struct PracticeHistoryView: View {
    @EnvironmentObject private var practice: PracticeStore

    var body: some View {
        let history = practice.history
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pronúncia")
                    .font(.system(size: 30, weight: .heavy))
                    .gradientForeground()
                Text("Clique no 🎤 ao lado de uma fala, ou use ⌘R para praticar a fala atual.")
                    .foregroundStyle(Theme.textDim)
            }
            .padding(.horizontal, 28)

            HStack(spacing: 14) {
                SummaryCard(title: "Frases praticadas", value: "\(history.records.count)", icon: "text.bubble.fill", tint: Theme.indigo)
                SummaryCard(title: "Tentativas", value: "\(history.attemptCount)", icon: "mic.fill", tint: Theme.violet)
                SummaryCard(title: "Média atual", value: history.averageScore.map(String.init) ?? "–", icon: "chart.line.uptrend.xyaxis",
                            tint: history.averageScore.map(scoreColor) ?? Theme.orange)
            }
            .padding(.horizontal, 28)

            if history.records.isEmpty {
                EmptyState(icon: "mic.badge.plus", title: "Nenhuma fala praticada ainda",
                           text: "Abra um filme, escolha uma fala e repita no microfone para receber uma nota.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(history.recent) { record in
                            RecordRow(record: record)
                                .contextMenu {
                                    Button("Apagar histórico desta frase", role: .destructive) { practice.remove(record.id) }
                                }
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.never)
            }
        }
        .padding(.top, 24)
    }
}

private struct SummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.gradient))
                .shadow(color: tint.opacity(0.5), radius: 10)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.system(size: 26, weight: .heavy).monospacedDigit())
                Text(title).font(.caption).foregroundStyle(Theme.textDim)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .glassCard()
    }
}

private struct RecordRow: View {
    let record: PracticeRecord

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ScoreRing(score: record.last?.score ?? 0, size: 46)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.sentence).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                HStack(spacing: 6) {
                    if let source = record.source {
                        Text("\(source) · \(formatTime(record.lineStart))").lineLimit(1)
                    }
                    if let date = record.last?.date {
                        Text("· ") + Text(date, format: .relative(presentation: .named))
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.textDim)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Chip(text: "melhor \(record.best)", systemImage: "trophy.fill", color: scoreColor(record.best))
                Sparkline(scores: record.attempts.suffix(10).map(\.score))
                Text("\(record.attempts.count) tentativa\(record.attempts.count == 1 ? "" : "s")").font(.caption2).foregroundStyle(Theme.textDim)
            }
        }
        .padding(14)
        .glassCard()
    }
}

/// Tiny bars showing the latest scores, oldest on the left.
private struct Sparkline: View {
    let scores: [Int]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(scores.enumerated()), id: \.offset) { _, score in
                RoundedRectangle(cornerRadius: 2)
                    .fill(scoreColor(score).gradient)
                    .frame(width: 5, height: max(2, CGFloat(score) / 100 * 22))
            }
        }
        .frame(height: 22, alignment: .bottom)
        .help("Últimas notas: " + scores.map(String.init).joined(separator: ", "))
    }
}
