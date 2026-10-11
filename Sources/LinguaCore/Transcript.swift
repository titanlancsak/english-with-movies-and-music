import Foundation

/// A single spoken word with its timing (in seconds).
public struct TimedWord: Codable, Hashable, Sendable {
    public var text: String
    public var start: Double
    public var end: Double

    public init(text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// One subtitle line (usually a sentence).
public struct TranscriptLine: Codable, Hashable, Identifiable, Sendable {
    public var id: Int
    public var start: Double
    public var end: Double
    public var words: [TimedWord]

    public init(id: Int, start: Double, end: Double, words: [TimedWord]) {
        self.id = id
        self.start = start
        self.end = end
        self.words = words
    }

    public var text: String { words.map(\.text).joined(separator: " ") }

    /// Index of the word being spoken at `time`, or the last word already spoken.
    public func wordIndex(at time: Double) -> Int? {
        guard time >= start else { return nil }
        var result: Int?
        for (i, word) in words.enumerated() {
            if word.start <= time { result = i } else { break }
        }
        return result
    }
}

public struct Transcript: Codable, Hashable, Sendable {
    public var lines: [TranscriptLine]

    public init(lines: [TranscriptLine]) {
        self.lines = lines
    }

    /// Index of the line being spoken at `time` (binary search).
    /// Between two lines, the previous line stays active until the next one starts.
    public func lineIndex(at time: Double) -> Int? {
        var low = 0
        var high = lines.count - 1
        var found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].start <= time {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        guard let index = found else { return nil }
        // Do not keep a line highlighted long after it ended.
        return time <= lines[index].end + 2 ? index : nil
    }

    /// Lines that contain the given word (case and punctuation insensitive).
    public func lines(containing word: String, limit: Int) -> [TranscriptLine] {
        let key = WordNormalizer.lookupKey(word)
        guard !key.isEmpty else { return [] }
        var result: [TranscriptLine] = []
        for line in lines where line.words.contains(where: { WordNormalizer.lookupKey($0.text) == key }) {
            result.append(line)
            if result.count == limit { break }
        }
        return result
    }
}

/// Groups timed words into readable subtitle lines.
public enum LineBuilder {
    /// - Parameter words: words in chronological order. `segmentBreaks` marks words that
    ///   ended a segment in the source (e.g. a Whisper segment or a song line).
    public static func build(words: [TimedWord], segmentBreaks: Set<Int> = []) -> [TranscriptLine] {
        var lines: [TranscriptLine] = []
        var current: [TimedWord] = []

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            lines.append(TranscriptLine(id: lines.count, start: first.start, end: last.end, words: current))
            current = []
        }

        for (i, word) in words.enumerated() {
            current.append(word)
            let next = i + 1 < words.count ? words[i + 1] : nil
            let endsSentence = word.text.last.map { ".?!".contains($0) } ?? false
            let longPause = next.map { $0.start - word.end > 1.0 } ?? true
            let segmentEnd = segmentBreaks.contains(i) && current.count >= 6
            if endsSentence || longPause || segmentEnd || current.count >= 20 {
                flush()
            }
        }
        flush()
        return lines
    }
}
