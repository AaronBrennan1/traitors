// swift-tools-version: 6.2
import PackageDescription

// Command-line harness for the game engine. The same sources under test/Engine
// are compiled into the iOS app by the Xcode project; this package exists so the
// engine can be unit-tested and simulated headlessly with `swift test` / `swift run`.
let settings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .swiftLanguageMode(.v5),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
    name: "TraitorsEngine",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "TraitorsEngine", targets: ["TraitorsEngine"]),
    ],
    targets: [
        .target(name: "TraitorsEngine", path: "test/Engine", swiftSettings: settings),
        .executableTarget(name: "traitors-sim", dependencies: ["TraitorsEngine"], path: "Tools/Sim", swiftSettings: settings),
        .testTarget(name: "EngineTests", dependencies: ["TraitorsEngine"], path: "Tests/EngineTests", swiftSettings: settings),
    ]
)
