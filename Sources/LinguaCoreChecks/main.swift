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
check(transcript.nearestLineIndex(at: 7) == 0 && transcript.nearestLineIndex(at: 0) == 0 && transcript.nearestLineIndex(at: 50) == 1, "transcript: nearest line for jumps into silence")
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

// MARK: Saved words

var list = WordList()
list.add(SavedWord(word: "Harbor", definition: "a place for ships", context: "We need to leave the harbor."))
list.add(SavedWord(word: "storm", definition: "strong wind, \"rain\", and thunder"))
list.add(SavedWord(word: "harbor!", definition: "updated"))
check(list.words.map(\.key) == ["harbor", "storm"], "saved words: newest first, no duplicates")
check(list.words.first?.definition == "updated", "saved words: saving again replaces the entry")
check(list.contains("STORM.") && !list.contains("rain"), "saved words: contains ignores case and punctuation")
check(list.filtered(by: "thunder").map(\.key) == ["storm"], "saved words: search in definitions")
list.remove("Storm")
check(list.words.count == 1, "saved words: remove")
check(SavedWord(word: "x", sourcePath: "/Movies/Tears of Steel.mp4").sourceName == "Tears of Steel", "saved words: source name")
let csv = WordList(words: [SavedWord(word: "storm", definition: "wind, \"rain\"", translation: "tempestade")]).csv()
check(csv == "word,portuguese,phonetic,part of speech,definition,sentence,source\nstorm,tempestade,,,\"wind, \"\"rain\"\"\",,\n", "saved words: CSV quoting and translation")
check(WordList(words: [SavedWord(word: "storm", translation: "tempestade")]).filtered(by: "tempest").count == 1, "saved words: search in translation")
let oldFormat = #"{"words":[{"key":"robot","word":"robot","dateAdded":0}]}"#
check((try? JSONDecoder().decode(WordList.self, from: Data(oldFormat.utf8)))?.words.first?.translation == nil, "saved words: lists saved before translations still load")

// MARK: Sound annotations

func words(_ text: String) -> [TimedWord] {
    text.split(separator: " ").enumerated().map { TimedWord(text: String($1), start: Double($0), end: Double($0) + 0.5) }
}
check(SoundAnnotationFilter.clean(words("(background music playing) Hello there.")).map(\.text) == ["Hello", "there."], "sound: multi-word description")
check(SoundAnnotationFilter.clean(words("[Music]. I can't [BLANK_AUDIO] go *sighs* now")).map(\.text) == ["I", "can't", "go", "now"], "sound: single-word tags and trailing punctuation")
check(SoundAnnotationFilter.clean(words("♪ We sing along ♪")).map(\.text) == ["We", "sing", "along"], "sound: music symbols")
check(SoundAnnotationFilter.clean(words("♪Hey♪ you")).map(\.text) == ["Hey", "you"], "sound: music symbols glued to words")

check(SoundAnnotationFilter.clean(words("(well I think we should leave now before the storm hits the harbor and the boats sink")).count == 17, "sound: unclosed bracket keeps the speech")
check(SoundAnnotationFilter.clean(words("We're out.[MUSIC PLAYING][MUSIC PLAYING] No.(dramatic music)(dramatic music) Go")).map(\.text) == ["We're", "out.", "No.", "Go"], "sound: annotations glued to words")
check(SoundAnnotationFilter.clean(words("What the f*ck is that")).count == 5, "sound: asterisk inside a word is kept")

let noisy = Transcript(lines: [
    TranscriptLine(id: 0, start: 0, end: 2, words: words("[Music]")),
    TranscriptLine(id: 1, start: 3, end: 6, words: [
        TimedWord(text: "(door", start: 3, end: 3.5), TimedWord(text: "slams)", start: 3.5, end: 4),
        TimedWord(text: "Who's", start: 4.5, end: 5), TimedWord(text: "there?", start: 5, end: 6),
    ]),
])
let quiet = noisy.removingSoundAnnotations()
check(quiet.lines.map(\.text) == ["Who's there?"], "sound: empty lines removed")
check(quiet.lines.first?.id == 0 && quiet.lines.first?.start == 4.5, "sound: line ids and timing updated")
check(SRTParser.parse("1\n00:00:01,000 --> 00:00:02,000\n[THUNDER RUMBLES]\n\n2\n00:00:03,000 --> 00:00:04,000\nRun!\n").lines.map(\.text) == ["Run!"], "sound: SRT annotations removed")

// MARK: Pronunciation

func spoken(_ text: String, start: Double = 0, step: Double = 0.4, confidence: Double = 0.9) -> [TimedWord] {
    text.split(separator: " ").enumerated().map {
        TimedWord(text: String($1), start: start + Double($0) * step, end: start + Double($0) * step + 0.3, confidence: confidence)
    }
}
let line = TranscriptLine(id: 0, start: 10, end: 12.8, words: spoken("We need to leave the harbor before sunset.", start: 10))

let perfect = PronunciationScorer.score(target: line, spoken: spoken("We need to leave the harbor before sunset."))
check(perfect.score >= 95 && perfect.words.allSatisfy { $0.status == .correct }, "pronunciation: perfect attempt scores high (\(perfect.score))")

let oneWrong = PronunciationScorer.score(target: line, spoken: spoken("We need to leave the harvard before sunset"))
check(oneWrong.words.map(\.status) == [.correct, .correct, .correct, .correct, .correct, .wrong, .correct, .correct], "pronunciation: one wrong word, rest aligned")
check(oneWrong.words[5].heard == "harvard" && oneWrong.score < 90, "pronunciation: a wrong word is not 'excellent' (\(oneWrong.score))")

let partial = PronunciationScorer.score(target: line, spoken: spoken("We need to leave"))
check(partial.words.filter { $0.status == .missing }.count == 4 && partial.completeness == 0.5, "pronunciation: missing words")
check(partial.score < 60, "pronunciation: half a sentence scores low (\(partial.score))")
check(!partial.tips.contains { $0.contains("rápido") }, "pronunciation: half a sentence is not 'too fast'")

let mumbled = PronunciationScorer.score(target: line, spoken: spoken("We need to leave the harbor before sunset.", confidence: 0.2))
check(mumbled.words.allSatisfy { $0.status == .unsure } && mumbled.score < perfect.score, "pronunciation: low confidence is unsure (\(mumbled.score))")

let slow = PronunciationScorer.score(target: line, spoken: spoken("We need to leave the harbor before sunset.", step: 1.2))
check(slow.speedRatio ?? 0 > 2 && slow.longPauses > 0 && slow.score < perfect.score, "pronunciation: slow speech lowers fluency (\(slow.score))")
check(slow.tips.contains { $0.contains("devagar") }, "pronunciation: tip about speed")

let silent = PronunciationScorer.score(target: line, spoken: [])
check(silent.score == 0 && silent.tips.first?.contains("microfone") == true, "pronunciation: nothing said")

let numbers = TranscriptLine(id: 1, start: 0, end: 2, words: spoken("four three two one"))
check(PronunciationScorer.score(target: numbers, spoken: spoken("4 3 2 1")).score >= 95, "pronunciation: digits match spelled numbers")
check(PronunciationScorer.similarity("harbor", "harbour") >= 0.8, "pronunciation: similar spellings are close")

var history = PracticeHistory()
history.add(PracticeAttempt(result: oneWrong), sentence: line.text, source: "Film", lineStart: line.start)
history.add(PracticeAttempt(result: perfect), sentence: line.text, source: "Film", lineStart: line.start)
history.add(PracticeAttempt(result: partial), sentence: "Another line", source: "Film", lineStart: 20)
let record = history.record(sentence: line.text, source: "Film")
check(record?.attempts.count == 2 && record?.best == perfect.score, "history: attempts and best score per sentence")
check(history.attemptCount == 3 && history.recent.first?.sentence == "Another line", "history: counts and most recent first")
check(history.averageScore == (perfect.score + partial.score + 1) / 2 || history.averageScore == (perfect.score + partial.score) / 2, "history: average of latest scores")

// MARK: Sounds (phonemes)

check(PhonemeAnalyzer.phonemes(fromEspeak: "θ_ˈɪ_ŋ_k ð_ə") == ["θ", "ɪ", "ŋ", "k", "ð", "ə"], "sounds: espeak output split, stress removed")
check(PhonemeAnalyzer.phonemes(fromEspeak: "ɑːɹx", vocabulary: ["ɑːɹ", "x"]) == ["ɑːɹ", "x"], "sounds: unknown symbols split into known ones")

let think = PhonemeAnalyzer.analyze(words: ["think", "big"], expected: [["θ", "ɪ", "ŋ", "k"], ["b", "ɪ", "ɡ"]],
                                    heard: ["t", "ɪ", "ŋ", "k", "b", "ɪ", "ɡ", "i"])
check(think.words[0].sounds.first?.status == .wrong && think.words[0].sounds.first?.heard == "t", "sounds: th said as t")
check(think.words[1].extra == ["i"], "sounds: extra vowel after final consonant")
check(think.tips.contains { $0.contains("think") && $0.contains("língua entre os dentes") }, "sounds: th tip")
check(think.tips.contains { $0.contains("big") && $0.contains("“i”") }, "sounds: extra vowel tip")
check(think.score < 0.9 && think.score > 0.5, "sounds: score reflects errors (\(think.score))")

let clean = PhonemeAnalyzer.analyze(words: ["sheep"], expected: [["ʃ", "iː", "p"]], heard: ["ʃ", "i", "p"])
check(clean.score == 1 && clean.tips.isEmpty, "sounds: length marks do not count as errors")
let ship = PhonemeAnalyzer.analyze(words: ["sheep"], expected: [["ʃ", "iː", "p"]], heard: ["ʃ", "ɪ", "p"])
check(ship.words[0].sounds[1].status == .close, "sounds: ship vs sheep is close, not correct")
let dropped = PhonemeAnalyzer.analyze(words: ["want"], expected: [["w", "ɑː", "n", "t"]], heard: ["w", "ɑː", "n"])
check(dropped.words[0].sounds.last?.status == .missing, "sounds: dropped final consonant")

let vowel = PhonemeAnalyzer.analyze(words: ["weather"], expected: [["w", "ɛ", "ð", "ɚ"]], heard: ["w", "iː", "ð", "ɚ"])
check(vowel.tips.first?.contains("i longo (sheep)") == true && vowel.tips.first?.contains("é (bed)") == true, "sounds: generic tip uses friendly names")

let withSounds = PronunciationScorer.score(target: line, spoken: spoken("We need to leave the harbor before sunset."), sounds: think)
check(withSounds.score < perfect.score && withSounds.sounds != nil, "sounds: sound errors lower the score (\(withSounds.score))")

print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
