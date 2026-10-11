import AppKit
import SwiftUI

@main
struct EnglishWithMoviesApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @StateObject private var model = AppModel()
    @StateObject private var savedWords = SavedWordsStore()
    @StateObject private var translator = Translator()
    @StateObject private var practice = PracticeStore()
    @StateObject private var phonemes = PhonemeEngine()

    var body: some Scene {
        WindowGroup("English with Movies & Music") {
            ContentView()
                .environmentObject(model)
                .environmentObject(savedWords)
                .environmentObject(translator)
                .environmentObject(practice)
                .environmentObject(phonemes)
                .modifier(TranslationHost(translator: translator))
                .frame(minWidth: 820, minHeight: 620)
                .onAppear { delegate.model = model }
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
                Button("Praticar a fala atual") { model.practiceCurrentLine() }
                    .keyboardShortcut("r")
                    .disabled(model.transcript == nil)
            }
            CommandGroup(after: .windowArrangement) {
                OpenSavedWordsButton()
                OpenPracticeHistoryButton()
            }
        }

        Window("Palavras salvas", id: "saved-words") {
            SavedWordsView()
                .environmentObject(model)
                .environmentObject(savedWords)
                .environmentObject(translator)
        }
        .defaultSize(width: 560, height: 640)

        Window("Histórico de pronúncia", id: "practice-history") {
            PracticeHistoryView()
                .environmentObject(practice)
        }
        .defaultSize(width: 600, height: 620)
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
        if url.isFileURL { model?.open(url) } else { model?.download(from: url.absoluteString) }
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
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// Deletes downloaded videos. Downloads left behind by a crash are still on the
    /// list, so they go too. (Not done at launch: files opened from Finder arrive later.)
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            if let model {
                model.deleteDownloads()
            } else {
                DownloadedFiles.deleteAll()
            }
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

/// Menu item (⇧⌘S) that opens the saved words window.
private struct OpenSavedWordsButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Palavras salvas") { openWindow(id: "saved-words") }
            .keyboardShortcut("s", modifiers: [.command, .shift])
    }
}

/// Menu item (⇧⌘H) that opens the pronunciation history window.
private struct OpenPracticeHistoryButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Histórico de pronúncia") { openWindow(id: "practice-history") }
            .keyboardShortcut("h", modifiers: [.command, .shift])
    }
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
