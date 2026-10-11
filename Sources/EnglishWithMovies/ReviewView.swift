import LinguaCore
import SwiftUI

/// Flashcard review of the saved words, with spaced repetition.
struct ReviewView: View {
    @EnvironmentObject private var store: SavedWordsStore
    @EnvironmentObject private var model: AppModel

    enum Mode: String, CaseIterable, Identifiable {
        case englishToPortuguese = "Inglês → Português"
        case portugueseToEnglish = "Português → Inglês"
        case listening = "Ouvir"
        var id: String { rawValue }
    }

    @ViewState private var mode: Mode = Mode(rawValue: UserDefaults.standard.string(forKey: "reviewMode") ?? "") ?? .englishToPortuguese
    @ViewState private var queue: [String] = []
    @ViewState private var sessionSize = 0
    @ViewState private var isFlipped = false
    @ViewState private var reviewed = 0
    @ViewState private var remembered = 0
    @ViewState private var isRunning = false

    private static let sessionLimit = 20

    var body: some View {
        VStack(spacing: 18) {
            Picker("Modo", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: mode) { _, mode in
                UserDefaults.standard.set(mode.rawValue, forKey: "reviewMode")
                isFlipped = false
                speakIfListening()
            }

            if isRunning, let word = currentWord {
                progress
                card(word)
                answerButtons(word)
            } else if isRunning {
                finished
            } else {
                startScreen
            }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 560)
        .onAppear { if !isRunning { startSession(all: false) } }
    }

    private var currentWord: SavedWord? {
        queue.first.flatMap { key in store.list.words.first { $0.key == key } }
    }

    // MARK: - Session

    private func startSession(all: Bool) {
        let words = all ? store.list.words.shuffled() : store.list.due().shuffled()
        queue = Array(words.prefix(Self.sessionLimit)).map(\.key)
        sessionSize = queue.count
        reviewed = 0
        remembered = 0
        isFlipped = false
        isRunning = !queue.isEmpty
        speakIfListening()
    }

    private func answer(_ grade: ReviewGrade) {
        guard let key = queue.first else { return }
        store.grade(key, grade)
        reviewed += 1
        if grade != .again { remembered += 1 }
        queue.removeFirst()
        // A forgotten word comes back at the end of this session.
        if grade == .again { queue.append(key) }
        isFlipped = false
        speakIfListening()
    }

    private func speakIfListening() {
        guard mode == .listening, let word = currentWord else { return }
        Pronouncer.shared.say(word.word)
    }

    // MARK: - Screens

    private var progress: some View {
        let done = sessionSize - Set(queue).count
        return VStack(spacing: 4) {
            ProgressView(value: Double(done), total: Double(max(sessionSize, 1)))
            Text("\(done) de \(sessionSize) palavras").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func card(_ word: SavedWord) -> some View {
        ZStack {
            front(word)
                .opacity(isFlipped ? 0 : 1)
            back(word)
                .opacity(isFlipped ? 1 : 0)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.accentColor.opacity(0.08))
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        )
        .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .animation(.easeInOut(duration: 0.35), value: isFlipped)
        .contentShape(Rectangle())
        .onTapGesture { isFlipped.toggle() }
    }

    @ViewBuilder
    private func front(_ word: SavedWord) -> some View {
        VStack(spacing: 16) {
            switch mode {
            case .englishToPortuguese:
                Text(word.word).font(.system(size: 44, weight: .bold))
                if let phonetic = word.phonetic { Text(phonetic).foregroundStyle(.secondary) }
                speakButton(word)
                if let context = word.context {
                    highlighted(context, word: word)
                        .font(.title3)
                        .italic()
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                Text("O que significa?").font(.headline).foregroundStyle(.secondary)
            case .portugueseToEnglish:
                if let translation = word.translation {
                    Text(translation).font(.system(size: 40, weight: .bold)).multilineTextAlignment(.center)
                } else {
                    TranslatedText(text: word.word).font(.system(size: 40, weight: .bold))
                }
                if let definition = word.definition {
                    Text(definition).multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
                Text("Como se diz em inglês?").font(.headline).foregroundStyle(.secondary)
            case .listening:
                Button { Pronouncer.shared.say(word.word) } label: {
                    Image(systemName: "speaker.wave.3.fill").font(.system(size: 56))
                }
                .buttonStyle(.borderless)
                .help("Ouvir de novo")
                Text("Que palavra é essa? O que significa?").font(.headline).foregroundStyle(.secondary)
            }
        }
    }

    private func back(_ word: SavedWord) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(word.word).font(.system(size: 36, weight: .bold))
                if let phonetic = word.phonetic { Text(phonetic).foregroundStyle(.secondary) }
                speakButton(word)
            }
            Group {
                if let translation = word.translation {
                    Text(translation)
                } else {
                    TranslatedText(text: word.word)
                }
            }
            .font(.title2.weight(.semibold))
            .foregroundStyle(.orange)

            if let definition = word.definition {
                VStack(spacing: 2) {
                    if let partOfSpeech = word.partOfSpeech {
                        Text(partOfSpeech).font(.caption.italic()).foregroundStyle(.secondary)
                    }
                    Text(definition).multilineTextAlignment(.center)
                }
            }
            if let context = word.context {
                Divider()
                highlighted(context, word: word).italic().multilineTextAlignment(.center)
                TranslatedText(text: context)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let path = word.sourcePath, FileManager.default.fileExists(atPath: path) {
                    Button("Ver no \(word.sourceName ?? "filme")", systemImage: "film") {
                        model.open(URL(fileURLWithPath: path), at: word.sourceTime ?? 0)
                        NSApp.windows.first { $0.identifier?.rawValue != "review" && $0.canBecomeMain }?
                            .makeKeyAndOrderFront(nil)
                    }
                    .controlSize(.small)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func speakButton(_ word: SavedWord) -> some View {
        Button { Pronouncer.shared.say(word.word) } label: {
            Image(systemName: "speaker.wave.2.fill")
        }
        .buttonStyle(.borderless)
        .help("Ouvir a pronúncia")
    }

    /// The sentence with the word in bold.
    private func highlighted(_ sentence: String, word: SavedWord) -> Text {
        sentence.split(separator: " ").enumerated().reduce(Text("")) { text, element in
            let (index, token) = element
            let part = Text((index > 0 ? " " : "") + token)
            return text + (WordNormalizer.lookupKey(String(token)) == word.key ? part.bold().foregroundColor(.primary) : part)
        }
    }

    @ViewBuilder
    private func answerButtons(_ word: SavedWord) -> some View {
        if isFlipped {
            HStack(spacing: 10) {
                ForEach(ReviewGrade.allCases, id: \.self) { grade in
                    Button { answer(grade) } label: {
                        VStack(spacing: 2) {
                            Text(grade.title).font(.headline)
                            Text(ReviewScheduler.describeNext(word.review, grade: grade)).font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(color(grade))
                    .keyboardShortcut(KeyEquivalent(Character(String(grade.rawValue))), modifiers: [])
                    .help("Tecla \(grade.rawValue)")
                }
            }
            .controlSize(.large)
        } else {
            Button { isFlipped = true } label: {
                Text("Mostrar resposta").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.space, modifiers: [])
            .help("Barra de espaço")
        }
    }

    private func color(_ grade: ReviewGrade) -> Color {
        switch grade {
        case .again: .red
        case .hard: .orange
        case .good: .green
        case .easy: .blue
        }
    }

    private var finished: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 54)).foregroundStyle(.green)
            Text("Revisão concluída!").font(.title.bold())
            Text("Você revisou \(reviewed) cartões e lembrou de \(remembered) (\(reviewed > 0 ? remembered * 100 / reviewed : 0)%).")
            stats
            HStack {
                if !store.list.due().isEmpty {
                    Button("Continuar revisando (\(store.list.due().count))") { startSession(all: false) }
                        .buttonStyle(.borderedProminent)
                }
                Button("Fechar") { NSApp.keyWindow?.close() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var startScreen: some View {
        VStack(spacing: 14) {
            if store.list.words.isEmpty {
                Image(systemName: "rectangle.on.rectangle.angled").font(.system(size: 48)).foregroundStyle(.secondary)
                Text("Nenhuma palavra salva ainda").font(.title2.bold())
                Text("Clique numa palavra da legenda e toque em 🔖 para salvar. Ela aparece aqui para revisar.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 54)).foregroundStyle(.green)
                Text("Tudo em dia!").font(.title.bold())
                stats
                Button("Revisar todas mesmo assim") { startSession(all: true) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var stats: some View {
        VStack(spacing: 4) {
            Text("\(store.list.words.count) palavras salvas · \(store.list.masteredCount()) dominadas")
                .foregroundStyle(.secondary)
            if let next = store.list.nextDueDate() {
                Text("Próxima revisão \(next.formatted(.relative(presentation: .named)))")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
