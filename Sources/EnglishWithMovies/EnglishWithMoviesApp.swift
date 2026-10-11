import AppKit
import SwiftUI

@main
struct EnglishWithMoviesApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("English with Movies & Music") {
            ContentView()
                .environmentObject(model)
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
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Files received before the window (and model) exist, e.g. "Open With" from Finder.
    private var pending: [URL] = []

    @MainActor var model: AppModel? {
        didSet { pending.forEach { model?.open($0) }; pending = [] }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Needed when launched as a plain executable (swift run) instead of a .app bundle.
        NSApplication.shared.setActivationPolicy(.regular)
        // `swift run EnglishWithMovies movie.mp4` opens the file directly.
        pending = CommandLine.arguments.dropFirst()
            .filter { !$0.hasPrefix("-") && FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @MainActor
    func application(_ application: NSApplication, open urls: [URL]) {
        if let model {
            urls.forEach { model.open($0) }
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
