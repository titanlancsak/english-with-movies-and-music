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
            VStack(alignment: .leading, spacing: 4) {
                Text("Revisão")
                    .font(.system(size: 30, weight: .heavy))
                    .gradientForeground()
                Text("Cartões com repetição espaçada: quem você erra volta logo, quem você sabe volta depois.")
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ModePicker(mode: $mode)
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
        .frame(maxWidth: 680)
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
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
        model.study.add(StudyLog.secondsPerReview)
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
        return HStack(spacing: 12) {
            GradientProgress(value: Double(done) / Double(max(sessionSize, 1)))
            Text("\(done)/\(sessionSize)").font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.textDim)
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
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [Theme.indigo.opacity(0.28), Theme.violet.opacity(0.14), Color.white.opacity(0.03)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Theme.violet.opacity(0.7), Theme.stroke, Theme.orange.opacity(0.4)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2)
        )
        .shadow(color: Theme.violet.opacity(0.3), radius: 30, y: 12)
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
                Text(word.word).font(.system(size: 52, weight: .heavy)).gradientForeground()
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
                    Image(systemName: "speaker.wave.3.fill").font(.system(size: 56)).gradientForeground(Theme.brand)
                }
                .buttonStyle(.plain)
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
            .font(.title2.weight(.bold))
            .foregroundStyle(Theme.orange)

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
                    }
                    .buttonStyle(GlassButtonStyle())
                }
            }
        }
    }

    private func speakButton(_ word: SavedWord) -> some View {
        Button { Pronouncer.shared.say(word.word) } label: {
            Image(systemName: "speaker.wave.2.fill")
        }
        .buttonStyle(IconButtonStyle(size: 32))
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
                            Text(grade.title).font(.system(size: 14, weight: .bold))
                            Text(ReviewScheduler.describeNext(word.review, grade: grade)).font(.caption).opacity(0.8)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GradeButtonStyle(color: color(grade), key: grade.rawValue))
                    .keyboardShortcut(KeyEquivalent(Character(String(grade.rawValue))), modifiers: [])
                    .help("Tecla \(grade.rawValue)")
                }
            }
        } else {
            Button { isFlipped = true } label: {
                Label("Mostrar resposta", systemImage: "arrow.2.squarepath")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut(.space, modifiers: [])
            .help("Barra de espaço")
        }
    }

    private func color(_ grade: ReviewGrade) -> Color {
        switch grade {
        case .again: scoreColor(0)
        case .hard: scoreColor(70)
        case .good: scoreColor(100)
        case .easy: Color(red: 0.376, green: 0.647, blue: 0.980)   // #60A5FA
        }
    }

    private var finished: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 54)).gradientForeground(Theme.brand)
            Text("Revisão concluída!").font(.system(size: 28, weight: .heavy))
            Text("Você revisou \(reviewed) cartões e lembrou de \(remembered) (\(reviewed > 0 ? remembered * 100 / reviewed : 0)%).")
            stats
            HStack {
                if !store.list.due().isEmpty {
                    Button("Continuar revisando (\(store.list.due().count))") { startSession(all: false) }
                        .buttonStyle(PrimaryButtonStyle())
                }
                Button("Voltar para a biblioteca") { model.section = .library }
                    .buttonStyle(GlassButtonStyle())
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
                Image(systemName: "checkmark.circle.fill").font(.system(size: 54)).gradientForeground(Theme.brand)
                Text("Tudo em dia!").font(.system(size: 28, weight: .heavy))
                stats
                Button("Revisar todas mesmo assim") { startSession(all: true) }
                    .buttonStyle(GlassButtonStyle())
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

/// The review modes as glass capsules; the selected one is filled with the brand gradient.
private struct ModePicker: View {
    @Binding var mode: ReviewView.Mode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ReviewView.Mode.allCases) { option in
                Button { mode = option } label: {
                    Text(option.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(mode == option ? .white : Theme.textDim)
                        .background(Capsule().fill(mode == option ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Color.clear)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(Theme.surface))
        .overlay(Capsule().strokeBorder(Theme.stroke))
    }
}

/// An answer button tinted by how well the word was remembered, with its keyboard key.
private struct GradeButtonStyle: ButtonStyle {
    let color: Color
    let key: Int

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color.opacity(configuration.isPressed ? 0.45 : 0.25)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(color.opacity(0.6)))
            .overlay(alignment: .topTrailing) {
                Text("\(key)").font(.system(size: 9, weight: .bold)).foregroundStyle(color).padding(6)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
