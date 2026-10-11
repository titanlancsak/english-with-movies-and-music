import AppKit
import SwiftUI

@main
struct EnglishWithMoviesApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @StateObject private var model: AppModel
    @StateObject private var savedWords: SavedWordsStore
    @StateObject private var translator = Translator()
    @StateObject private var practice: PracticeStore
    @StateObject private var phonemes = PhonemeEngine()
    @StateObject private var sync: SyncService
    @StateObject private var updates = UpdateChecker()

    init() {
        // The sync service works with the stores, so they are created together.
        let model = AppModel(), savedWords = SavedWordsStore(), practice = PracticeStore()
        _model = StateObject(wrappedValue: model)
        _savedWords = StateObject(wrappedValue: savedWords)
        _practice = StateObject(wrappedValue: practice)
        _sync = StateObject(wrappedValue: SyncService(savedWords: savedWords, practice: practice, study: model.study))
    }

    var body: some Scene {
        WindowGroup("English with Movies & Music") {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.library)
                .environmentObject(savedWords)
                .environmentObject(translator)
                .environmentObject(practice)
                .environmentObject(phonemes)
                .environmentObject(model.study)
                .environmentObject(sync)
                .environmentObject(updates)
                .modifier(TranslationHost(translator: translator))
                .frame(minWidth: 960, minHeight: 640)
                .onAppear { delegate.model = model }
                .task { await updates.check() }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Abrir filme ou música…") { FilePicker.openMedia(model) }
                    .keyboardShortcut("o")
                Button("Importar legenda (.srt)…") { FilePicker.openSubtitles(model) }
                    .keyboardShortcut("i")
            }
            CommandMenu("Reprodução") {
                Button("Play / Pause") { model.togglePlay() }
                    .keyboardShortcut("p")
                Button(model.loopLine ? "Parar de repetir a fala" : "Repetir a fala atual") { model.loopLine.toggle() }
                    .keyboardShortcut("l")
                    .disabled(model.transcript == nil)
                Button("Mais devagar") { model.speed = max(0.5, model.speed - 0.25) }
                    .keyboardShortcut("[")
                Button("Mais rápido") { model.speed = min(1.25, model.speed + 0.25) }
                    .keyboardShortcut("]")
                Divider()
                Button("Buscar na legenda") { model.showSearch = true }
                    .keyboardShortcut("f")
                    .disabled(model.transcript == nil)
                Button("Shadowing (ouvir e repetir)") { model.startShadowing() }
                    .keyboardShortcut("r", modifiers: [.command, .option])
                    .disabled(model.transcript == nil)
                Button(model.hideSubtitles ? "Mostrar a legenda" : "Desafio de escuta (esconder a legenda)") { model.hideSubtitles.toggle() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Praticar a fala atual") { model.practiceCurrentLine() }
                    .keyboardShortcut("r")
                    .disabled(model.transcript == nil)
            }
            CommandMenu("Ir") {
                Button("Biblioteca") { model.section = .library }
                    .keyboardShortcut("1")
                Button("Assistindo agora") { model.section = .player }
                    .keyboardShortcut("2")
                    .disabled(model.mediaURL == nil)
                Divider()
                Button("Palavras salvas") { model.section = .savedWords }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Revisar palavras") { model.section = .review }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Histórico de pronúncia") { model.section = .practice }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
            }
        }
        .defaultSize(width: 1280, height: 820)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Files or links received before the window (and model) exist, e.g. "Open With" from Finder.
    private var pending: [URL] = []

    @MainActor var model: AppModel? {
        didSet { pending.forEach(handle); pending = [] }
    }

    @MainActor
    private func handle(_ url: URL) {
        // `--at=SECONDS` on the command line starts there.
        let start = CommandLine.arguments.first { $0.hasPrefix("--at=") }.flatMap { Double($0.dropFirst(5)) }
        if url.isFileURL { model?.open(url, at: start) } else { model?.download(from: url.absoluteString) }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Needed when launched as a plain executable (swift run) instead of a .app bundle.
        NSApplication.shared.setActivationPolicy(.regular)
        // `swift run EnglishWithMovies movie.mp4` opens the file directly;
        // `swift run EnglishWithMovies https://youtube.com/...` downloads it first.
        pending = CommandLine.arguments.dropFirst().compactMap { argument in
            if argument.hasPrefix("http") { return URL(string: argument) }
            return FileManager.default.fileExists(atPath: argument) ? URL(fileURLWithPath: argument) : nil
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A plain executable (swift run) does not come to the front by itself; a .app does
        // (and `open -g` keeps it in the background).
        if Bundle.main.bundleURL.pathExtension != "app" {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    /// Saves where playback stopped and removes pieces of unfinished downloads.
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            model?.savePosition()
            model?.study.persist()
            MediaFiles.cleanDownloadLeftovers()
        }
    }

    @MainActor
    func application(_ application: NSApplication, open urls: [URL]) {
        if model != nil {
            urls.forEach(handle)
        } else {
            pending += urls
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

enum FilePicker {
    @MainActor
    static func openMedia(_ model: AppModel) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .audio, .audiovisualContent]
        panel.allowsOtherFileTypes = true
        if panel.runModal() == .OK, let url = panel.url { model.open(url) }
    }

    @MainActor
    static func openSubtitles(_ model: AppModel) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "srt") ?? .plainText]
        if panel.runModal() == .OK, let url = panel.url { model.importSubtitles(url) }
    }
}
