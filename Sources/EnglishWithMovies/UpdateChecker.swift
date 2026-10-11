import AppKit
import Foundation
import LinguaCore

/// Looks for a newer version on GitHub when the app opens and offers the download.
@MainActor
final class UpdateChecker: ObservableObject {
    struct Release: Equatable {
        let tag: String
        let page: URL
        var version: String { tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV")) }
    }

    @Published private(set) var available: Release?

    static let releasesAPI = URL(string: "https://api.github.com/repos/titanlancsak/english-with-movies-and-music/releases/latest")!
    /// The running version (nil when run with `swift run`, which has no Info.plist).
    static var current: String? { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String }

    func check() async {
        guard let current = Self.current, !AppModel.isPreview else { return }
        var request = URLRequest(url: Self.releasesAPI, timeoutInterval: 15)
        request.setValue("EnglishWithMovies/\(current)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
              AppVersion.isNewer(tag, than: current),
              UserDefaults.standard.string(forKey: "dismissedUpdate") != tag else { return }
        available = Release(tag: tag, page: page)
    }

    func download() {
        if let available { NSWorkspace.shared.open(available.page) }
    }

    /// "Depois": not shown again for this version.
    func dismiss() {
        if let available { UserDefaults.standard.set(available.tag, forKey: "dismissedUpdate") }
        available = nil
    }
}
