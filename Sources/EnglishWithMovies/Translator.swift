import SwiftUI
import Translation

/// English → Portuguese translation using Apple's on-device Translation framework (free, offline
/// after macOS downloads the language pack once).
///
/// Translation sessions only exist inside a view's `translationTask`, so `TranslationHost` keeps
/// one session open and serves the requests queued here, in batches.
@MainActor
final class Translator: ObservableObject {
    static let source = Locale.Language(identifier: "en")
    static let target = Locale.Language(identifier: "pt-BR")

    @Published var showLineTranslations: Bool {
        didSet { UserDefaults.standard.set(showLineTranslations, forKey: "showLineTranslations") }
    }
    /// Becomes true on the first request, so the language download is only offered when needed.
    @Published fileprivate(set) var isActive = false
    @Published fileprivate(set) var problem: String?

    let isSupportedOS: Bool

    private var cache: [String: String] = [:]
    private var order: [String] = []
    private var waiting: [String: [CheckedContinuation<String?, Never>]] = [:]
    private var wakeUp: CheckedContinuation<Void, Never>?

    init() {
        showLineTranslations = UserDefaults.standard.bool(forKey: "showLineTranslations")
        if #available(macOS 15, *) { isSupportedOS = true } else { isSupportedOS = false }
    }

    func cached(_ text: String) -> String? { cache[text] }

    func translate(_ text: String) async -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, isSupportedOS else { return nil }
        if let cached = cache[text] { return cached }
        if !isActive { isActive = true }
        return await withCheckedContinuation { continuation in
            if waiting[text] == nil { order.append(text) }
            waiting[text, default: []].append(continuation)
            wakeUp?.resume()
            wakeUp = nil
        }
    }

    fileprivate func nextBatch() async -> [String] {
        while order.isEmpty {
            await withCheckedContinuation { continuation in
                wakeUp?.resume()
                wakeUp = continuation
            }
            if Task.isCancelled { return [] }
        }
        let batch = Array(order.prefix(25))
        order.removeFirst(batch.count)
        return batch
    }

    fileprivate func deliver(_ text: String, _ translation: String?) {
        if let translation { cache[text] = translation }
        waiting.removeValue(forKey: text)?.forEach { $0.resume(returning: translation) }
    }

    fileprivate func stopWaiting() {
        wakeUp?.resume()
        wakeUp = nil
    }
}

/// Hosts the translation session. Attach once to the main window.
struct TranslationHost: ViewModifier {
    @ObservedObject var translator: Translator

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.translationTask(configuration) { session in
                await serve(session)
            }
        } else {
            content
        }
    }

    @available(macOS 15, *)
    private var configuration: TranslationSession.Configuration? {
        translator.isActive ? TranslationSession.Configuration(source: Translator.source, target: Translator.target) : nil
    }

    @available(macOS 15, *)
    @MainActor
    private func serve(_ session: TranslationSession) async {
        do {
            // Shows the system prompt to download the Portuguese pack if it is missing.
            try await session.prepareTranslation()
            translator.problem = nil
        } catch {
            translator.problem = "Para traduzir, baixe o português em Ajustes do Sistema › Geral › Idioma e Região › Idiomas de Tradução."
        }
        defer { translator.stopWaiting() }

        while !Task.isCancelled {
            let batch = await translator.nextBatch()
            guard !batch.isEmpty else { continue }
            let requests = batch.enumerated().map {
                TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset))
            }
            do {
                let responses = try await session.translations(from: requests)
                var delivered = Set<String>()
                for response in responses {
                    guard let index = response.clientIdentifier.flatMap(Int.init), batch.indices.contains(index) else { continue }
                    translator.deliver(batch[index], response.targetText)
                    delivered.insert(batch[index])
                }
                batch.filter { !delivered.contains($0) }.forEach { translator.deliver($0, nil) }
                translator.problem = nil
            } catch {
                batch.forEach { translator.deliver($0, nil) }
                translator.problem = "Não foi possível traduzir: \(error.localizedDescription)"
            }
        }
    }
}

/// Shows the Portuguese translation of `text`, translating it the first time it appears.
struct TranslatedText: View {
    @EnvironmentObject private var translator: Translator
    let text: String
    @ViewState private var translation: String?

    var body: some View {
        Group {
            if let translation = translation ?? translator.cached(text) {
                Text(translation)
            } else {
                Text("traduzindo…").foregroundStyle(.tertiary)
            }
        }
        .task(id: text) { translation = await translator.translate(text) }
    }
}
