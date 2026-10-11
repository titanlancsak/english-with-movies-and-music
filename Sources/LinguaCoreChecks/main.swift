import Foundation
import LinguaCore

var failures = 0

func check(_ condition: @autoclosure () throws -> Bool, _ name: String, line: Int = #line) {
    let passed = (try? condition()) ?? false
    if !passed { failures += 1 }
    print(passed ? "✓ \(name)" : "✗ \(name) (line \(line))")
}

func token(_ text: String, _ from: Int, _ to: Int) -> String {
    #"{"text": "\#(text)", "offsets": {"from": \#(from), "to": \#(to)}}"#
}

// MARK: Whisper JSON

do {
    let tokens = [
        token("[_BEG_]", 0, 0), token(" I", 0, 200), token(" can", 200, 400),
        token("'t", 400, 450), token(" go", 500, 700), token(".", 700, 750),
        token(" See", 2500, 2700), token(" you", 2700, 2900), token("!", 2900, 3000),
    ].joined(separator: ",")
    let json = #"{"transcription": [{"tokens": [\#(tokens)]}]}"#
    let transcript = try WhisperJSONParser.parse(Data(json.utf8))
    check(transcript.lines.map(\.text) == ["I can't go.", "See you!"], "whisper: merges sub-word tokens into sentences")
    let cant = transcript.lines[0].words[1]
    check(cant.start == 0.2 && cant.end == 0.45, "whisper: word timing spans its tokens")
} catch {
    check(false, "whisper: parse failed \(error)")
}

do {
    var data = Data(#"{"transcription": [{"tokens": [{"text": " hi"#.utf8)
    data.append(0xE2)  // first byte of a multi-byte character, cut off
    data.append(Data(#"", "offsets": {"from": 0, "to": 100}}]}]}"#.utf8))
    let transcript = try WhisperJSONParser.parse(data)
    check(transcript.lines.first?.words.first?.text == "hi", "whisper: tolerates invalid UTF-8")
} catch {
    check(false, "whisper: invalid UTF-8 parse failed \(error)")
}

// MARK: Transcript lookup

let transcript = Transcript(lines: [
    TranscriptLine(id: 0, start: 1, end: 3, words: [
        TimedWord(text: "Good", start: 1, end: 1.5), TimedWord(text: "morning.", start: 1.6, end: 3),
    ]),
    TranscriptLine(id: 1, start: 10, end: 12, words: [
        TimedWord(text: "Morning,", start: 10, end: 11), TimedWord(text: "friend", start: 11, end: 12),
    ]),
])
check(transcript.lineIndex(at: 0.5) == nil, "transcript: nothing before first line")
check(transcript.lineIndex(at: 1.7) == 0 && transcript.lines[0].wordIndex(at: 1.7) == 1, "transcript: active line and word")
check(transcript.lineIndex(at: 4) == 0, "transcript: line stays briefly after it ends")
check(transcript.lineIndex(at: 7) == nil, "transcript: clears during long silence")
check(transcript.lineIndex(at: 11) == 1, "transcript: later line")
check(transcript.lines(containing: "MORNING!", limit: 3).map(\.id) == [0, 1], "transcript: finds lines with a word")
check(transcript.lines(containing: "morning", limit: 1).map(\.id) == [0], "transcript: respects limit")

// MARK: SRT

let srt = "1\r\n00:00:01,000 --> 00:00:03,000\r\n<i>Hello there</i>\r\n\r\n2\r\n00:01:00,500 --> 00:01:02,000\r\nHow are\r\nyou?\r\n"
let subtitles = SRTParser.parse(srt)
check(subtitles.lines.map(\.text) == ["Hello there", "How are you?"], "srt: text and tags")
check(subtitles.lines.count == 2 && subtitles.lines[1].start == 60.5, "srt: timestamps")
check(abs((subtitles.lines.first?.words.last?.end ?? 0) - 3) < 0.001, "srt: words fill the line duration")

// MARK: Word normalizing

check(WordNormalizer.lookupKey("“Don’t!”") == "don't", "normalizer: punctuation and curly apostrophes")
check(WordNormalizer.lookupKey("...") == "", "normalizer: punctuation only")
check(WordNormalizer.candidates(for: "Let's").contains("let"), "normalizer: contraction")
check(WordNormalizer.candidates(for: "running").contains("run"), "normalizer: doubled consonant + ing")
check(WordNormalizer.candidates(for: "making").contains("make"), "normalizer: silent e + ing")
check(WordNormalizer.candidates(for: "studied").contains("study"), "normalizer: ied")
check(WordNormalizer.candidates(for: "movies").contains("movie"), "normalizer: plural")

// MARK: Dictionary parsing

do {
    let definitions = (1...5).map { #"{"definition": "def \#($0)", "example": "example \#($0)"}"# }
        .joined(separator: ",")
    let json = #"[{"word": "run", "phonetic": "/ɹʌn/", "meanings": [{"partOfSpeech": "verb", "definitions": [\#(definitions)]}]}]"#
    let entry = try DictionaryService.parse(Data(json.utf8))
    check(entry?.examples == ["example 1", "example 2", "example 3"], "dictionary: at most 3 examples")
    check(entry?.senses.count == 2 && entry?.phonetic == "/ɹʌn/", "dictionary: senses and phonetic")
} catch {
    check(false, "dictionary: parse failed \(error)")
}

// MARK: macOS dictionary text (sample written for these checks)

let sample = "lan·tern | ˈlantərn | noun a lamp with a cover that protects the flame: she held a lantern | the lantern lit the path. • a glass structure on top of a dome. verb [with object] 1 light up with a lantern: they lanterned the yard. 2 put in a lantern. ORIGIN invented for testing."
let parsed = SystemDictionaryParser.parse(sample)
check(parsed?.word == "lantern" && parsed?.phonetic == "/ˈlantərn/", "system dictionary: headword and phonetic")
check(parsed?.senses.map(\.partOfSpeech) == ["noun", "noun", "verb", "verb"], "system dictionary: parts of speech")
check(parsed?.senses.first?.definition == "a lamp with a cover that protects the flame", "system dictionary: definition without examples")
check(parsed?.senses[2].definition == "light up with a lantern", "system dictionary: strips grammar notes and numbers")
check(parsed?.examples == ["She held a lantern", "The lantern lit the path", "They lanterned the yard"], "system dictionary: at most 3 examples")
let unnamed = SystemDictionaryParser.parse("| stôrm | noun a strong wind: a storm hit the coast. • a sudden outburst: [as noun] : a storm of protest. 3 Sports a quick attack", fallbackWord: "storm")
check(unnamed?.word == "storm", "system dictionary: falls back to the looked-up word")
check(unnamed?.examples == ["A storm hit the coast", "A storm of protest"], "system dictionary: cleans stray colons")
check(unnamed?.senses.count == 2, "system dictionary: splits capitalized numbered senses")
check(SystemDictionaryParser.parse("nonsense without structure") == nil, "system dictionary: rejects unknown format")

print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
