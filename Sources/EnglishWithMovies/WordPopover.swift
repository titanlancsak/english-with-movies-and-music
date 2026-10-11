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
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            if isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else if let entry {
                senses(entry)
            } else {
                Text("Não encontrei esta palavra no dicionário.")
                    .foregroundStyle(.secondary)
            }
            portuguese
            examples
        }
        .padding(16)
        .frame(width: 380)
        .task { await load() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(entry?.word ?? WordNormalizer.lookupKey(word))
                .font(.title2.bold())
            if let phonetic = entry?.phonetic {
                Text(phonetic).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Pronouncer.shared.say(entry?.word ?? WordNormalizer.lookupKey(word))
            } label: {
                Image(systemName: "speaker.wave.2.fill")
            }
            .buttonStyle(.borderless)
            .help("Ouvir a pronúncia")

            let isSaved = savedWords.contains(word)
            Button(action: toggleSaved) {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(isSaved ? Color.orange : Color.primary)
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
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(entry.senses.enumerated()), id: \.offset) { _, sense in
                VStack(alignment: .leading, spacing: 2) {
                    Text(sense.partOfSpeech)
                        .font(.caption.italic())
                        .foregroundStyle(.secondary)
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
            VStack(alignment: .leading, spacing: 6) {
                Text("Exemplos").font(.headline)
                ForEach(fromDictionary, id: \.self) { example in
                    Label(example, systemImage: "text.quote")
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(fromMedia) { line in
                    Button {
                        model.seek(to: line.start)
                        model.player?.play()
                    } label: {
                        Label(line.text, systemImage: model.hasVideo ? "film" : "music.note")
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
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
            VStack(alignment: .leading, spacing: 6) {
                Text("Em português").font(.headline)
                HStack(alignment: .firstTextBaseline) {
                    Text(WordNormalizer.lookupKey(word)).foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                    Text(wordTranslation ?? "traduzindo…").bold()
                }
                Label {
                    TranslatedText(text: line.text).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "character.bubble")
                }
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
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.42
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)
    }
}
