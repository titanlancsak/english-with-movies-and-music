import Foundation
import LinguaCore

/// Keeps the pronunciation history on disk (~/Library/Application Support/EnglishWithMovies/practice-history.json).
@MainActor
final class PracticeStore: ObservableObject {
    @Published private(set) var history: PracticeHistory

    private let fileURL = AppFolders.root.appendingPathComponent("practice-history.json")

    init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        history = (try? Data(contentsOf: fileURL)).flatMap { try? decoder.decode(PracticeHistory.self, from: $0) }
            ?? PracticeHistory()
    }

    func record(for line: TranscriptLine, source: String?) -> PracticeRecord? {
        history.record(sentence: line.text, source: source)
    }

    func add(_ result: PronunciationResult, for line: TranscriptLine, source: String?) {
        history.add(PracticeAttempt(result: result), sentence: line.text, source: source, lineStart: line.start)
        persist()
    }

    func remove(_ id: String) {
        history.remove(id)
        persist()
    }

    /// After merging another device's data (see SyncService).
    func replace(with history: PracticeHistory) {
        guard history != self.history else { return }
        self.history = history
        persist()
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(history) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
