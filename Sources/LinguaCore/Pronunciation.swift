import Foundation

/// The result of comparing what the user said with a subtitle line.
public struct PronunciationResult: Codable, Hashable, Sendable {
    public enum WordStatus: String, Codable, Sendable {
        /// Recognized clearly.
        case correct
        /// Recognized, but unclear or slightly different.
        case unsure
        /// Recognized as a different word.
        case wrong
        /// Not said.
        case missing
    }

    public struct WordResult: Codable, Hashable, Sendable {
        public var text: String
        public var status: WordStatus
        /// What the recognizer heard instead, when different.
        public var heard: String?
    }

    public var words: [WordResult]
    /// Words said that are not in the sentence.
    public var extraWords: [String]
    public var recognizedText: String
    /// 0...1
    public var accuracy: Double
    /// 0...1
    public var fluency: Double
    /// 0...1
    public var completeness: Double
    /// 0...100
    public var score: Int
    /// The user's duration divided by the character's (1 = same speed).
    public var speedRatio: Double?
    public var longPauses: Int
    /// Sound-by-sound analysis, when the phoneme recognizer is installed.
    public var sounds: SoundAnalysis?

    /// Short advice in Portuguese.
    public var tips: [String] {
        var tips: [String] = []
        let wrong = words.filter { $0.status == .wrong }
        let missing = words.filter { $0.status == .missing }
        let unsure = words.filter { $0.status == .unsure }

        if words.allSatisfy({ $0.status == .missing }) {
            return ["Não consegui entender a frase. Fale mais perto do microfone e um pouco mais alto."]
        }
        if !wrong.isEmpty {
            let list = wrong.prefix(3).map { "“\(Self.clean($0.text))” (entendi “\($0.heard ?? "?")”)" }
            tips.append("Treine: " + list.joined(separator: ", ") + ".")
        }
        if !missing.isEmpty {
            tips.append("Faltou: " + missing.prefix(4).map { "“\(Self.clean($0.text))”" }.joined(separator: ", ") + ".")
        }
        if !unsure.isEmpty {
            tips.append("Quase lá: " + unsure.prefix(3).map { "“\(Self.clean($0.text))”" }.joined(separator: ", ")
                + " saiu pouco claro.")
        }
        if let ratio = speedRatio {
            if ratio > 1.4 {
                tips.append("Você falou mais devagar que o personagem. Tente um ritmo mais natural.")
            } else if ratio < 0.6 {
                tips.append("Você falou mais rápido que o personagem. Fale com calma, articulando cada palavra.")
            }
        }
        if longPauses > 0 {
            tips.append("Evite pausas longas no meio da frase.")
        }
        if tips.isEmpty {
            tips.append(score >= 90 ? "Excelente! Pronúncia clara e ritmo natural." : "Muito bem! Continue praticando.")
        }
        return tips
    }

    private static func clean(_ word: String) -> String {
        word.trimmingCharacters(in: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'’-")).inverted)
    }
}

/// Scores a spoken attempt against a subtitle line, word by word.
///
/// - Accuracy (60%): words recognized correctly, weighted by the recognizer's confidence;
///   with a sound analysis, half of it comes from the sounds.
/// - Fluency (25%): speed compared with the character, and long pauses, weighted by accuracy.
/// - Completeness (15%): how much of the sentence was said.
public enum PronunciationScorer {
    public static func score(target: TranscriptLine, spoken: [TimedWord], sounds: SoundAnalysis? = nil) -> PronunciationResult {
        let expected = target.words.filter { !comparable($0.text).isEmpty }
        let heard = spoken.filter { !comparable($0.text).isEmpty }
        let recognizedText = spoken.map(\.text).joined(separator: " ")

        guard !expected.isEmpty else {
            return PronunciationResult(words: [], extraWords: [], recognizedText: recognizedText,
                                       accuracy: 0, fluency: 0, completeness: 0, score: 0, speedRatio: nil, longPauses: 0,
                                       sounds: sounds)
        }

        var results: [PronunciationResult.WordResult] = []
        var extras: [String] = []
        var credit = 0.0

        for step in align(expected.map { comparable($0.text) }, heard.map { comparable($0.text) }) {
            switch step {
            case let .match(e, h, similarity):
                let word = expected[e].text
                let spokenWord = heard[h]
                if similarity == 1 {
                    let confident = (spokenWord.confidence ?? 1) >= 0.5
                    results.append(.init(text: word, status: confident ? .correct : .unsure, heard: nil))
                    credit += confident ? 1 : 0.7
                } else if similarity >= 0.75 {
                    results.append(.init(text: word, status: .unsure, heard: spokenWord.text))
                    credit += 0.5
                } else {
                    results.append(.init(text: word, status: .wrong, heard: spokenWord.text))
                }
            case let .missing(e):
                results.append(.init(text: expected[e].text, status: .missing, heard: nil))
            case let .extra(h):
                extras.append(heard[h].text)
            }
        }

        let count = Double(expected.count)
        let wordAccuracy = max(0, credit / count - 0.05 * Double(extras.count))
        // Nothing recognized means nothing to credit, whatever the sounds say.
        let accuracy = sounds.map { heard.isEmpty ? 0 : 0.5 * wordAccuracy + 0.5 * $0.score } ?? wordAccuracy
        let missing = results.filter { $0.status == .missing }.count
        let completeness = 1 - Double(missing) / count

        // Fluency: speed and pauses, only counting what matches the sentence.
        var speedRatio: Double?
        var longPauses = 0
        var fluency = 0.0
        if let first = heard.first, let last = heard.last, completeness > 0 {
            // Compare with the time the character takes for the part that was said,
            // so saying half the sentence does not look like speaking too fast.
            let actorDuration = max((target.end - target.start) * completeness, 0.3)
            let ratio = max(last.end - first.start, 0.1) / actorDuration
            speedRatio = ratio
            let speedScore: Double
            switch ratio {
            // Being a bit faster than the character is fine; much slower is the usual problem.
            case 0.6...1.4: speedScore = 1
            case ..<0.6: speedScore = max(0, (ratio - 0.3) / 0.3)
            default: speedScore = max(0, 1 - (ratio - 1.4) / 1.2)
            }
            longPauses = zip(heard, heard.dropFirst()).filter { $1.start - $0.end > 0.8 }.count
            let pauseScore = max(0, 1 - 0.2 * Double(longPauses))
            // Speaking fluently only counts for words that were said correctly.
            fluency = (0.7 * speedScore + 0.3 * pauseScore) * accuracy
        }

        let score = Int((100 * (0.6 * accuracy + 0.25 * fluency + 0.15 * completeness)).rounded())
        return PronunciationResult(
            words: results, extraWords: extras, recognizedText: recognizedText,
            accuracy: accuracy, fluency: fluency, completeness: completeness,
            score: min(100, max(0, score)), speedRatio: speedRatio, longPauses: longPauses,
            sounds: sounds
        )
    }

    // MARK: - Word comparison

    private static let spellOut: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()

    /// Lowercase letters only; numbers are spelled out ("4" -> "four").
    static func comparable(_ word: String) -> String {
        let lowered = word.lowercased().replacingOccurrences(of: "’", with: "'")
        let digits = lowered.filter(\.isNumber)
        if !digits.isEmpty, digits.count == lowered.filter({ $0.isLetter || $0.isNumber }).count,
           let number = Int(digits), let words = spellOut.string(from: NSNumber(value: number)) {
            return words.filter(\.isLetter)
        }
        return lowered.filter { $0.isLetter }
    }

    /// 1 for identical words, down to 0 for completely different ones.
    public static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        let a = Array(a), b = Array(b)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return 1 - Double(previous[b.count]) / Double(max(a.count, b.count))
    }

    enum Step: Equatable {
        case match(Int, Int, similarity: Double)
        case missing(Int)
        case extra(Int)
    }

    /// Aligns expected and heard words (edit distance), so one wrong word does not shift the rest.
    static func align(_ expected: [String], _ heard: [String]) -> [Step] {
        let n = expected.count, m = heard.count
        var cost = Array(repeating: Array(repeating: 0.0, count: m + 1), count: n + 1)
        for i in 0...n { cost[i][0] = Double(i) }
        for j in 0...m { cost[0][j] = Double(j) }
        if n > 0, m > 0 {
            for i in 1...n {
                for j in 1...m {
                    let substitution = 1 - similarity(expected[i - 1], heard[j - 1])
                    cost[i][j] = min(cost[i - 1][j] + 1, cost[i][j - 1] + 1, cost[i - 1][j - 1] + substitution)
                }
            }
        }

        var steps: [Step] = []
        var i = n, j = m
        while i > 0 || j > 0 {
            if i > 0, j > 0 {
                let similar = similarity(expected[i - 1], heard[j - 1])
                if cost[i][j] == cost[i - 1][j - 1] + (1 - similar) {
                    steps.append(.match(i - 1, j - 1, similarity: similar))
                    i -= 1; j -= 1
                    continue
                }
            }
            if i > 0, cost[i][j] == cost[i - 1][j] + 1 {
                steps.append(.missing(i - 1))
                i -= 1
            } else {
                steps.append(.extra(j - 1))
                j -= 1
            }
        }
        return steps.reversed()
    }
}

// MARK: - History

public struct PracticeAttempt: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var date: Date
    public var score: Int
    public var accuracy: Double
    public var fluency: Double
    public var completeness: Double
    public var recognizedText: String

    public init(result: PronunciationResult, date: Date = Date()) {
        self.date = date
        score = result.score
        accuracy = result.accuracy
        fluency = result.fluency
        completeness = result.completeness
        recognizedText = result.recognizedText
    }
}

/// All attempts for one sentence of one movie or song.
public struct PracticeRecord: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var sentence: String
    public var source: String?
    public var lineStart: Double
    /// Oldest first.
    public var attempts: [PracticeAttempt]

    public var best: Int { attempts.map(\.score).max() ?? 0 }
    public var last: PracticeAttempt? { attempts.last }
}

public struct PracticeHistory: Codable, Hashable, Sendable {
    public private(set) var records: [String: PracticeRecord] = [:]

    public init() {}

    public static func key(sentence: String, source: String?) -> String {
        "\(source ?? "")|\(sentence.lowercased())"
    }

    public func record(sentence: String, source: String?) -> PracticeRecord? {
        records[Self.key(sentence: sentence, source: source)]
    }

    public mutating func add(_ attempt: PracticeAttempt, sentence: String, source: String?, lineStart: Double) {
        let key = Self.key(sentence: sentence, source: source)
        var record = records[key] ?? PracticeRecord(id: key, sentence: sentence, source: source, lineStart: lineStart, attempts: [])
        record.attempts.append(attempt)
        records[key] = record
    }

    public mutating func remove(_ id: String) {
        records.removeValue(forKey: id)
    }

    /// Most recently practiced first.
    public var recent: [PracticeRecord] {
        records.values.sorted { ($0.last?.date ?? .distantPast) > ($1.last?.date ?? .distantPast) }
    }

    public var attemptCount: Int { records.values.reduce(0) { $0 + $1.attempts.count } }

    /// Average of the latest score of each sentence.
    public var averageScore: Int? {
        let latest = records.values.compactMap(\.last?.score)
        guard !latest.isEmpty else { return nil }
        return Int((Double(latest.reduce(0, +)) / Double(latest.count)).rounded())
    }
}
