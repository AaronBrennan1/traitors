// swift-tools-version: 6.2
import PackageDescription

// The game with no UI in it. The iOS app (test.xcodeproj) links `TraitorsEngine` from here.
// `TraitorsLab` is the simulator and the measuring tools: the command line and the tests use
// it, and the app does not.
let settings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .swiftLanguageMode(.v5),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
    name: "TraitorsEngine",
    platforms: [.macOS(.v15), .iOS(.v17)],
    products: [
        .library(name: "TraitorsEngine", targets: ["TraitorsEngine"]),
        .library(name: "TraitorsGauntlet", targets: ["TraitorsGauntlet"]),
    ],
    targets: [
        // The vocabulary: players, the public record and what each statement means, randomness, the mission ledger.
        .target(name: "TraitorsCore", swiftSettings: settings),
        // How a seat decides: inference, planning, defences. Depends on nothing but the vocabulary.
        .target(name: "TraitorsMinds", dependencies: ["TraitorsCore"], swiftSettings: settings),
        // The mini-games: the gauntlet and the ten others, each a real-time simulation played through an ArenaSession.
        .target(name: "TraitorsGauntlet", dependencies: ["TraitorsCore"], swiftSettings: settings),
        // The rules and the telling: Game, its prompts and scenes, the day's mission, dialogue and staging.
        .target(name: "TraitorsEngine", dependencies: ["TraitorsCore", "TraitorsMinds", "TraitorsGauntlet"], swiftSettings: settings),
        .target(name: "TraitorsLab", dependencies: ["TraitorsCore", "TraitorsMinds", "TraitorsGauntlet", "TraitorsEngine"], swiftSettings: settings),
        .executableTarget(name: "traitors-sim", dependencies: ["TraitorsLab"], path: "Tools/Sim", swiftSettings: settings),
        .testTarget(name: "CoreTests", dependencies: ["TraitorsCore"], path: "Tests/CoreTests", swiftSettings: settings),
        .testTarget(name: "MindsTests", dependencies: ["TraitorsCore", "TraitorsMinds"], path: "Tests/MindsTests", swiftSettings: settings),
        .testTarget(name: "GauntletTests", dependencies: ["TraitorsCore", "TraitorsGauntlet", "TraitorsLab"], path: "Tests/GauntletTests", swiftSettings: settings),
        .testTarget(name: "EngineTests", dependencies: ["TraitorsCore", "TraitorsMinds", "TraitorsGauntlet", "TraitorsEngine", "TraitorsLab"], path: "Tests/EngineTests", exclude: ["Golden"], swiftSettings: settings),
    ]
)
