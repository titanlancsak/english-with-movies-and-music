import Foundation

/// Sound-by-sound (phoneme) comparison between the expected sentence and what was said.
public struct SoundAnalysis: Codable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable {
        /// The expected sound.
        case correct
        /// A close sound (e.g. a slightly different vowel).
        case close
        /// A different sound.
        case wrong
        /// Not pronounced.
        case missing
    }

    public struct Sound: Codable, Hashable, Sendable {
        public var expected: String
        public var heard: String?
        public var status: Status
    }

    public struct Word: Codable, Hashable, Sendable {
        public var text: String
        public var sounds: [Sound]
        /// Sounds added inside or right after the word (e.g. an "i" after a final consonant).
        public var extra: [String]
        /// 0...1
        public var score: Double
    }

    public var words: [Word]
    /// Everything the phoneme recognizer heard.
    public var heard: [String]
    /// 0...1
    public var score: Double

    /// Advice in Portuguese for the most important sound problems (at most 3).
    public var tips: [String] {
        var tips: [String] = []
        var seen = Set<String>()
        func add(_ key: String, _ tip: String) {
            guard tips.count < 3, seen.insert(key).inserted else { return }
            tips.append(tip)
        }

        for word in words {
            let name = word.text.trimmingCharacters(in: CharacterSet.letters.union(CharacterSet(charactersIn: "'’")).inverted)
            for sound in word.sounds where sound.status == .wrong || sound.status == .missing {
                if let tip = PhonemeTips.tip(for: sound.expected) {
                    add(sound.expected, "“\(name)”: \(tip)")
                } else if sound.status == .missing {
                    add("missing-\(name)", "“\(name)”: faltou o som \(PhonemeTips.describe(sound.expected)).")
                } else if let heard = sound.heard {
                    add("\(sound.expected)>\(heard)",
                        "“\(name)”: você disse \(PhonemeTips.describe(heard)) no lugar de \(PhonemeTips.describe(sound.expected)).")
                }
            }
            if let last = word.sounds.last, !PhonemeTips.isVowel(last.expected),
               word.extra.contains(where: PhonemeTips.isVowel) {
                add("epenthesis", "“\(name)”: não acrescente um “i” no final. Termine a palavra na consoante.")
            }
        }
        return tips
    }
}

public enum PhonemeAnalyzer {
    /// Splits espeak-ng output made with `--ipa --sep=_` (e.g. "θ_ˈɪ_ŋ_k") into phonemes,
    /// dropping stress marks. Unknown symbols are broken into known ones when possible.
    public static func phonemes(fromEspeak text: String, vocabulary: Set<String> = []) -> [String] {
        text.replacingOccurrences(of: "ˈ", with: "")
            .replacingOccurrences(of: "ˌ", with: "")
            .split(whereSeparator: { $0 == "_" || $0 == " " || $0 == "\n" })
            .map(String.init)
            .filter { !$0.isEmpty }
            .flatMap { split($0, vocabulary: vocabulary) }
    }

    private static func split(_ symbol: String, vocabulary: Set<String>) -> [String] {
        guard !vocabulary.isEmpty, !vocabulary.contains(symbol) else { return [symbol] }
        var result: [String] = []
        var rest = Substring(symbol)
        while !rest.isEmpty {
            var length = rest.count
            while length > 1, !vocabulary.contains(String(rest.prefix(length))) { length -= 1 }
            result.append(String(rest.prefix(length)))
            rest = rest.dropFirst(length)
        }
        return result
    }

    /// Compares expected phonemes (one list per word) with the heard phonemes.
    public static func analyze(words: [String], expected: [[String]], heard: [String]) -> SoundAnalysis {
        let flat = expected.enumerated().flatMap { index, phonemes in phonemes.map { (word: index, symbol: $0) } }
        var results = expected.map { _ in [SoundAnalysis.Sound]() }
        var extras = expected.map { _ in [String]() }
        var lastWord = 0
        var extraCount = 0

        for step in align(flat.map(\.symbol), heard) {
            switch step {
            case let .pair(e, h):
                let similarity = similarity(flat[e].symbol, heard[h])
                let status: SoundAnalysis.Status = similarity == 1 ? .correct : similarity >= 0.6 ? .close : .wrong
                results[flat[e].word].append(.init(expected: flat[e].symbol, heard: status == .correct ? nil : heard[h], status: status))
                lastWord = flat[e].word
            case let .missing(e):
                results[flat[e].word].append(.init(expected: flat[e].symbol, heard: nil, status: .missing))
                lastWord = flat[e].word
            case let .extra(h):
                if !flat.isEmpty { extras[lastWord].append(heard[h]) }
                extraCount += 1
            }
        }

        var credit = 0.0
        let analyzed = words.indices.map { index -> SoundAnalysis.Word in
            let sounds = results[index]
            let wordCredit = sounds.reduce(0.0) { $0 + score($1.status) }
            credit += wordCredit
            let score = sounds.isEmpty ? 1 : max(0, wordCredit / Double(sounds.count) - 0.1 * Double(extras[index].count))
            return .init(text: words[index], sounds: sounds, extra: extras[index], score: score)
        }
        let total = max(1, flat.count)
        let overall = max(0, credit / Double(total) - 0.03 * Double(extraCount))
        return SoundAnalysis(words: analyzed, heard: heard, score: min(1, overall))
    }

    private static func score(_ status: SoundAnalysis.Status) -> Double {
        switch status {
        case .correct: 1
        case .close: 0.6
        case .wrong, .missing: 0
        }
    }

    // MARK: - Phoneme similarity

    /// Sounds that are the same for scoring (length marks, reduced vowels, flap T).
    private static let equivalent: [Set<String>] = [
        ["i", "iː"], ["u", "uː"], ["ɑ", "ɑː"], ["ɔ", "ɔː"], ["ɜ", "ɜː"],
        ["ᵻ", "ɪ", "ə"], ["ɚ", "ɜː", "əɹ"], ["ɾ", "t", "d"], ["ɑːɹ", "ɑɹ"], ["ɔːɹ", "ɔɹ", "oːɹ"],
        ["r", "ɹ"], ["ɐ", "ə"], ["əl", "l"],
    ]

    /// Sounds a learner can easily swap; close but not the same.
    private static let close: [Set<String>] = [
        ["ɪ", "i", "iː", "e"], ["ʊ", "u", "uː"], ["ʌ", "ə", "ɐ", "a"], ["æ", "ɛ", "a", "e"],
        ["ɑː", "ɑ", "a", "ɒ", "ʌ"], ["ɔː", "ɔ", "o", "oʊ", "ɒ"], ["eɪ", "e", "ɛ"], ["oʊ", "o", "ɔ"],
        ["aɪ", "a"], ["aʊ", "a"], ["ɚ", "ɹ", "ər"], ["ɑːɹ", "ɑː"], ["ɔːɹ", "ɔː"],
        ["s", "z"], ["f", "v"], ["tʃ", "ʃ"], ["dʒ", "ʒ"], ["n", "ŋ"], ["m", "n"],
    ]

    public static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        if equivalent.contains(where: { $0.contains(a) && $0.contains(b) }) { return 1 }
        if close.contains(where: { $0.contains(a) && $0.contains(b) }) { return 0.6 }
        let aVowel = PhonemeTips.isVowel(a), bVowel = PhonemeTips.isVowel(b)
        if aVowel && bVowel { return 0.3 }
        if !aVowel && !bVowel { return 0.2 }
        return 0
    }

    enum Step: Equatable {
        case pair(Int, Int)
        case missing(Int)
        case extra(Int)
    }

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
            if i > 0, j > 0, cost[i][j] == cost[i - 1][j - 1] + 1 - similarity(expected[i - 1], heard[j - 1]) {
                steps.append(.pair(i - 1, j - 1))
                i -= 1; j -= 1
            } else if i > 0, cost[i][j] == cost[i - 1][j] + 1 {
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

/// Names and advice (in Portuguese) for English sounds that are hard for Brazilians.
public enum PhonemeTips {
    public static func isVowel(_ symbol: String) -> Bool {
        guard let first = symbol.first else { return false }
        return "aeiouæɑɒɔəɚɛɜɪʊʌᵻɐøœyɨɯ".contains(first)
    }

    /// A friendly name, e.g. "th (think)".
    public static func name(for symbol: String) -> String? {
        names[symbol]
    }

    public static func tip(for symbol: String) -> String? {
        tips[symbol]
    }

    /// "“é” (bed) /ɛ/" when the sound has a friendly name, otherwise "/ɛ/".
    public static func describe(_ symbol: String) -> String {
        guard let name = names[symbol] else { return "/\(symbol)/" }
        return "o som “\(name)” /\(symbol)/"
    }

    private static let names: [String: String] = [
        "θ": "th (think)", "ð": "th (the)", "ɹ": "r (red)", "h": "h (house)", "æ": "a (cat)",
        "ɪ": "i curto (ship)", "iː": "i longo (sheep)", "i": "i (happy)", "ʊ": "u curto (book)",
        "uː": "u longo (food)", "ʌ": "a fechado (cup)", "ə": "vogal neutra (about)", "ɑː": "a aberto (father)",
        "ɑːɹ": "ar (car)", "ɔː": "ó (thought)", "ɔːɹ": "or (more)", "ɚ": "er (teacher)", "ɜː": "er (bird)",
        "eɪ": "ei (say)", "oʊ": "ou (go)", "aɪ": "ai (my)", "aʊ": "au (now)", "ɔɪ": "ói (boy)",
        "ŋ": "ng (sing)", "w": "w (we)", "v": "v (very)", "dʒ": "dj (job)", "tʃ": "tch (chair)",
        "ʃ": "sh (she)", "ʒ": "j (vision)", "z": "z (zoo)", "s": "s (see)", "t": "t (top)", "d": "d (dog)",
        "ɾ": "t/d rápido (water)", "l": "l (love)", "ɛ": "é (bed)", "ᵻ": "i fraco (wanted)",
    ]

    private static let tips: [String: String] = [
        "θ": "o “th” de think: ponha a ponta da língua entre os dentes e sopre, sem vibrar. Não é /t/, /f/ nem /s/.",
        "ð": "o “th” de the: língua entre os dentes, vibrando a garganta. Não é /d/ nem /z/.",
        "ɹ": "o R americano (red): curve a língua para trás sem encostar no céu da boca. Não é o R de “carro” nem o de “caro”.",
        "ɚ": "o “er” de teacher: vogal com a língua curvada para trás, como o R americano.",
        "ɜː": "o “er” de bird: vogal longa com a língua curvada para trás.",
        "æ": "o “a” de cat: abra bem a boca, um som entre “é” e “á”.",
        "ɪ": "o “i” curto de ship: mais curto e relaxado que o “i” de sheep.",
        "iː": "o “i” longo de sheep: sorria e prolongue o “i”.",
        "ʊ": "o “u” curto de book: mais curto e relaxado que o “u” de food.",
        "uː": "o “u” longo de food: lábios arredondados, prolongue o “u”.",
        "ʌ": "o “a” de cup: um “a” curto, com a boca pouco aberta.",
        "ɑː": "o “a” de father: “a” bem aberto e longo, no fundo da boca.",
        "ɑːɹ": "o “ar” de car: “a” aberto seguido do R americano.",
        "ɔːɹ": "o “or” de more: “ó” seguido do R americano.",
        "ŋ": "o “ng” de sing: som nasal no fundo da boca, sem pronunciar um “g” no final.",
        "w": "o “w” de we: lábios arredondados como um “u” rápido. Não é /v/.",
        "v": "o “v” de very: dentes de cima no lábio de baixo, vibrando. Não é /w/ nem /b/.",
        "h": "o “h” de house: solte o ar suavemente, como um “r” de “rato” bem leve. Não deixe mudo.",
        "eɪ": "o “ei” de say: deslize do “e” para o “i”.",
        "oʊ": "o “ou” de go: deslize do “o” para o “u”, com os lábios arredondando.",
        "z": "o “z” de zoo: vibre a garganta, como um zumbido.",
    ]
}
