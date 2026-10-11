import Foundation

/// The file shared between devices (e.g. in a Google Drive, Dropbox or iCloud Drive folder):
/// saved words, pronunciation history and study time. The Windows/Android version reads and
/// writes the same format (app-flutter/lib/core/sync.dart); data/sync-example.json is an example
/// both test suites read.
public struct SyncDocument: Equatable, Sendable {
    public static let fileName = "english-with-movies-sync.json"

    public var words: [SavedWord]
    public var deletedWords: [String: Date]
    public var practice: [PracticeRecord]
    public var study: StudyLog

    public init(words: WordList, practice: PracticeHistory, study: StudyLog) {
        self.words = words.words
        deletedWords = words.deleted
        self.practice = practice.recent
        self.study = study
    }

    /// Merges another device's data into the local lists:
    /// - each word keeps its most recently changed copy; a deletion newer than the word removes it;
    /// - pronunciation attempts of both sides are kept (the same attempt is not counted twice);
    /// - study time keeps the larger value of each device and day.
    public static func merge(_ remote: SyncDocument, into words: inout WordList, practice: inout PracticeHistory, study: inout StudyLog) {
        var byKey = Dictionary(words.words.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        for word in remote.words {
            if let local = byKey[word.key], local.changed >= word.changed { continue }
            var incoming = word
            // Keep this device's file path when the other device's path does not exist here.
            if let local = byKey[word.key], let path = incoming.sourcePath, !FileManager.default.fileExists(atPath: path) {
                incoming.sourcePath = local.sourcePath
            }
            byKey[word.key] = incoming
        }
        var deleted = words.deleted
        for (key, date) in remote.deletedWords where date > (deleted[key] ?? .distantPast) {
            deleted[key] = date
        }
        for (key, date) in deleted where (byKey[key]?.changed ?? .distantFuture) <= date {
            byKey.removeValue(forKey: key)
        }
        words.words = byKey.values.sorted { $0.dateAdded > $1.dateAdded }
        words.deleted = deleted

        for record in remote.practice {
            let known = Set((practice.record(sentence: record.sentence, source: record.source)?.attempts ?? []).map(Self.attemptID))
            for attempt in record.attempts where !known.contains(Self.attemptID(attempt)) {
                practice.add(attempt, sentence: record.sentence, source: record.source, lineStart: record.lineStart)
            }
        }
        practice.sortAttempts()

        let goal = study.goalMinutes
        study.merge(remote.study)
        study.goalMinutes = goal
    }

    /// The same attempt on two devices: same second and score.
    private static func attemptID(_ attempt: PracticeAttempt) -> String {
        "\(Int(attempt.date.timeIntervalSince1970))|\(attempt.score)"
    }
}

// MARK: - JSON

extension SyncDocument: Codable {
    private enum Keys: String, CodingKey {
        case app, version, words, deletedWords, practice, study
    }

    private struct Word: Codable {
        var word: String
        var phonetic, partOfSpeech, definition, translation, context, sourcePath: String?
        var sourceTime: Double?
        var added: String
        var review: Review?
    }

    private struct Review: Codable {
        var interval, ease: Double
        var repetitions, lapses: Int
        var due: String
        var lastReviewed: String?
    }

    private struct Record: Codable {
        var sentence: String
        var source: String?
        var lineStart: Double
        var attempts: [Attempt]
    }

    private struct Attempt: Codable {
        var date: String
        var score: Int
        var recognizedText: String
    }

    private struct Study: Codable {
        var devices: [String: [String: Double]]
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        words = try container.decode([Word].self, forKey: .words).map { item in
            var word = SavedWord(word: item.word, phonetic: item.phonetic, partOfSpeech: item.partOfSpeech, definition: item.definition,
                                 translation: item.translation, context: item.context, sourcePath: item.sourcePath,
                                 sourceTime: item.sourceTime, dateAdded: SyncDate.parse(item.added) ?? Date())
            word.review = item.review.map { review in
                var state = ReviewState(due: SyncDate.parse(review.due) ?? Date())
                state.interval = review.interval
                state.ease = review.ease
                state.repetitions = review.repetitions
                state.lapses = review.lapses
                state.lastReviewed = review.lastReviewed.flatMap(SyncDate.parse)
                return state
            }
            return word
        }
        deletedWords = try container.decode([String: String].self, forKey: .deletedWords).compactMapValues(SyncDate.parse)
        practice = try container.decode([Record].self, forKey: .practice).map { record in
            PracticeRecord(
                id: PracticeHistory.key(sentence: record.sentence, source: record.source),
                sentence: record.sentence, source: record.source, lineStart: record.lineStart,
                attempts: record.attempts.compactMap { attempt in
                    SyncDate.parse(attempt.date).map { PracticeAttempt(date: $0, score: attempt.score, recognizedText: attempt.recognizedText) }
                }
            )
        }
        study = StudyLog()
        study.devices = try container.decode(Study.self, forKey: .study).devices
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode("english-with-movies", forKey: .app)
        try container.encode(1, forKey: .version)
        try container.encode(words.map { word in
            Word(word: word.word, phonetic: word.phonetic, partOfSpeech: word.partOfSpeech, definition: word.definition,
                 translation: word.translation, context: word.context, sourcePath: word.sourcePath, sourceTime: word.sourceTime,
                 added: SyncDate.format(word.dateAdded),
                 review: word.review.map {
                     Review(interval: $0.interval, ease: $0.ease, repetitions: $0.repetitions, lapses: $0.lapses,
                            due: SyncDate.format($0.due), lastReviewed: $0.lastReviewed.map(SyncDate.format))
                 })
        }, forKey: .words)
        try container.encode(deletedWords.mapValues(SyncDate.format), forKey: .deletedWords)
        try container.encode(practice.map { record in
            Record(sentence: record.sentence, source: record.source, lineStart: record.lineStart,
                   attempts: record.attempts.map { Attempt(date: SyncDate.format($0.date), score: $0.score, recognizedText: $0.recognizedText) })
        }, forKey: .practice)
        try container.encode(Study(devices: study.devices), forKey: .study)
    }
}

/// ISO 8601 in UTC with milliseconds ("2026-10-12T01:23:45.678Z"), the format Dart writes.
enum SyncDate {
    nonisolated(unsafe) private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    nonisolated(unsafe) private static let plain = ISO8601DateFormatter()

    static func format(_ date: Date) -> String { withFraction.string(from: date) }

    /// Also accepts dates without milliseconds or without a time zone (taken as UTC).
    static func parse(_ text: String) -> Date? {
        if let date = withFraction.date(from: text) ?? plain.date(from: text) { return date }
        let utc = text.hasSuffix("Z") ? text : text + "Z"
        return withFraction.date(from: utc) ?? plain.date(from: utc)
    }
}

extension PracticeHistory {
    /// Oldest attempt first in every record (after merging attempts from another device).
    mutating func sortAttempts() {
        for key in records.keys {
            records[key]?.attempts.sort { $0.date < $1.date }
        }
    }
}
