import AVFoundation
import CoreServices
import LinguaCore
import SwiftUI

/// Definition card shown when a word is clicked.
struct WordPopover: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var savedWords: SavedWordsStore
    @EnvironmentObject private var translator: Translator
    let word: String
    /// The subtitle line where the word was clicked (saved as context).
    let line: TranscriptLine

    @ViewState private var entry: DictionaryEntry?
    @ViewState private var isLoading = true
    @ViewState private var wordTranslation: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if isLoading {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            } else if let entry {
                senses(entry)
            } else {
                Text("Não encontrei esta palavra no dicionário.")
                    .foregroundStyle(Theme.textDim)
            }
            portuguese
            examples
        }
        .padding(20)
        .frame(width: 400)
        .background(
            ZStack(alignment: .topLeading) {
                Theme.background.opacity(0.6)
                Circle().fill(Theme.violet.opacity(0.35)).frame(width: 220).blur(radius: 70).offset(x: -60, y: -90)
            }
        )
        .environment(\.colorScheme, .dark)
        .task { await load() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry?.word ?? WordNormalizer.lookupKey(word))
                    .font(.system(size: 30, weight: .heavy))
                    .gradientForeground()
                if let phonetic = entry?.phonetic {
                    Text(phonetic).font(.callout).foregroundStyle(Theme.textDim)
                }
            }
            Spacer()
            Button {
                Pronouncer.shared.say(entry?.word ?? WordNormalizer.lookupKey(word))
            } label: {
                Image(systemName: "speaker.wave.2.fill")
            }
            .buttonStyle(IconButtonStyle(size: 34))
            .help("Ouvir a pronúncia")

            let isSaved = savedWords.contains(word)
            Button(action: toggleSaved) {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
            }
            .buttonStyle(IconButtonStyle(size: 34, tint: isSaved ? Theme.orange : .white))
            .disabled(isLoading)
            .help(isSaved ? "Remover das palavras salvas" : "Salvar palavra")
        }
    }

    private func toggleSaved() {
        if savedWords.contains(word) {
            savedWords.remove(word)
            return
        }
        let sense = entry?.senses.first
        savedWords.add(SavedWord(
            word: entry?.word ?? WordNormalizer.lookupKey(word),
            phonetic: entry?.phonetic,
            partOfSpeech: sense?.partOfSpeech,
            definition: sense?.definition,
            translation: wordTranslation,
            context: line.text,
            sourcePath: model.mediaURL?.path,
            sourceTime: line.start
        ))
    }

    private func senses(_ entry: DictionaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(entry.senses.enumerated()), id: \.offset) { _, sense in
                VStack(alignment: .leading, spacing: 4) {
                    Chip(text: sense.partOfSpeech, color: Theme.violet)
                    Text(sense.definition)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .textSelection(.enabled)
    }

    /// Up to 3 examples: dictionary examples first, then lines from this movie/song.
    @ViewBuilder
    private var examples: some View {
        let fromDictionary = Array((entry?.examples ?? []).prefix(DictionaryService.maxExamples))
        let remaining = DictionaryService.maxExamples - fromDictionary.count
        let fromMedia = remaining > 0
            ? (model.transcript?.lines(containing: word, limit: remaining) ?? [])
            : []

        if !isLoading, !fromDictionary.isEmpty || !fromMedia.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Exemplos")
                ForEach(fromDictionary, id: \.self) { example in
                    HStack(alignment: .top, spacing: 8) {
                        Capsule().fill(Theme.brand).frame(width: 3)
                        Text(example).fixedSize(horizontal: false, vertical: true)
                    }
                }
                ForEach(fromMedia) { line in
                    Button {
                        model.seek(to: line.start)
                        model.player?.play()
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: model.hasVideo ? "play.rectangle.fill" : "music.note")
                                .foregroundStyle(Theme.orange)
                            Text(line.text)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Ouvir este trecho")
                }
            }
            .font(.callout)
        }
    }

    @ViewBuilder
    private var portuguese: some View {
        if translator.isSupportedOS {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Em português")
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(WordNormalizer.lookupKey(word)).foregroundStyle(Theme.textDim)
                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(Theme.textDim)
                    Text(wordTranslation ?? "traduzindo…")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.orange)
                }
                TranslatedText(text: line.text)
                    .italic()
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.callout)
                if let problem = translator.problem {
                    Text(problem).font(.caption).foregroundStyle(.orange)
                }
            }
            .textSelection(.enabled)
            .task { wordTranslation = await translator.translate(WordNormalizer.lookupKey(word)) }
        }
    }

    private func load() async {
        defer { isLoading = false }
        entry = try? await model.dictionary.lookup(word)
    }
}

/// The dictionary built into macOS (works offline).
enum SystemDictionary {
    static func define(_ word: String) -> String? {
        guard !word.isEmpty else { return nil }
        let range = CFRange(location: 0, length: (word as NSString).length)
        return DCSCopyTextDefinition(nil, word as CFString, range)?.takeRetainedValue() as String?
    }
}

@MainActor
final class Pronouncer {
    static let shared = Pronouncer()
    private let synthesizer = AVSpeechSynthesizer()

    func say(_ text: String) {
        guard !AppModel.isPreview else { return }   // screenshots stay silent
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.42
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)
    }
}
