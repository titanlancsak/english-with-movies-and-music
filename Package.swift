// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EnglishWithMovies",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .executable(name: "EnglishWithMovies", targets: ["EnglishWithMovies"]),
        .library(name: "LinguaCore", targets: ["LinguaCore"]),
    ],
    targets: [
        // Platform-independent logic (transcript model, parsers, dictionary).
        // Reusable later by an iPhone/iPad app.
        .target(name: "LinguaCore"),
        // macOS app (SwiftUI).
        .executableTarget(name: "EnglishWithMovies", dependencies: ["LinguaCore"]),
        // Self-checks for LinguaCore. Run with: swift run LinguaCoreChecks
        // (A plain executable, because XCTest/Swift Testing need a full Xcode install.)
        .executableTarget(name: "LinguaCoreChecks", dependencies: ["LinguaCore"]),
    ],
    swiftLanguageModes: [.v5]
)
