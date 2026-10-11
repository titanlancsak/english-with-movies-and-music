import Foundation

/// How well the user remembered a word in a review.
public enum ReviewGrade: Int, CaseIterable, Codable, Sendable {
    case again = 1, hard, good, easy

    public var title: String {
        switch self {
        case .again: "Errei"
        case .hard: "Difícil"
        case .good: "Bom"
        case .easy: "Fácil"
        }
    }
}

/// Spaced-repetition state of a saved word (a simplified SM-2, the method used by Anki).
public struct ReviewState: Codable, Hashable, Sendable {
    /// Days until the next review.
    public var interval: Double = 0
    /// How fast the interval grows (starts at 2.5, never below 1.3).
    public var ease: Double = 2.5
    /// Correct answers in a row.
    public var repetitions = 0
    /// Times the word was forgotten after being learned.
    public var lapses = 0
    public var due: Date
    public var lastReviewed: Date?

    public init(due: Date = Date()) {
        self.due = due
    }

    /// Learned well: reviewed correctly with an interval of three weeks or more.
    public var isMastered: Bool { interval >= 21 }
}

public enum ReviewScheduler {
    /// A word answered "Errei" comes back in the same session, after a few minutes.
    public static let relearnDelay: TimeInterval = 10 * 60

    public static func next(_ state: ReviewState?, grade: ReviewGrade, now: Date = Date()) -> ReviewState {
        var state = state ?? ReviewState(due: now)
        state.lastReviewed = now

        switch grade {
        case .again:
            if state.repetitions > 0 { state.lapses += 1 }
            state.repetitions = 0
            state.interval = 0
            state.ease = max(1.3, state.ease - 0.2)
            state.due = now.addingTimeInterval(relearnDelay)
            return state
        case .hard:
            state.interval = state.repetitions == 0 ? 1 : max(1, state.interval * 1.2)
            state.ease = max(1.3, state.ease - 0.15)
        case .good:
            switch state.repetitions {
            case 0: state.interval = 1
            case 1: state.interval = 3
            default: state.interval = (state.interval * state.ease).rounded()
            }
        case .easy:
            state.interval = state.repetitions == 0 ? 4 : (state.interval * state.ease * 1.3).rounded()
            state.ease += 0.15
        }
        state.repetitions += 1
        state.due = now.addingTimeInterval(state.interval * 86_400)
        return state
    }

    /// "10 min", "1 dia", "3 dias", "2 meses": shown on the answer buttons.
    public static func describeNext(_ state: ReviewState?, grade: ReviewGrade, now: Date = Date()) -> String {
        let next = next(state, grade: grade, now: now)
        let seconds = next.due.timeIntervalSince(now)
        if seconds < 3600 { return "\(Int((seconds / 60).rounded())) min" }
        let days = Int((seconds / 86_400).rounded())
        if days < 31 { return days == 1 ? "1 dia" : "\(days) dias" }
        let months = Int((Double(days) / 30).rounded())
        return months == 1 ? "1 mês" : "\(months) meses"
    }
}

extension WordList {
    /// Words to review now (never-reviewed words count as due), most overdue first.
    public func due(now: Date = Date()) -> [SavedWord] {
        words.filter { ($0.review?.due ?? .distantPast) <= now }
            .sorted { ($0.review?.due ?? .distantPast) < ($1.review?.due ?? .distantPast) }
    }

    public func masteredCount() -> Int {
        words.filter { $0.review?.isMastered == true }.count
    }

    /// When the next word becomes due, if none is due now.
    public func nextDueDate(after now: Date = Date()) -> Date? {
        words.compactMap(\.review?.due).filter { $0 > now }.min()
    }

    public mutating func grade(_ word: String, _ grade: ReviewGrade, now: Date = Date()) {
        let key = WordNormalizer.lookupKey(word)
        guard let index = words.firstIndex(where: { $0.key == key }) else { return }
        words[index].review = ReviewScheduler.next(words[index].review, grade: grade, now: now)
    }
}
