import Foundation
import Testing
@testable import TraitorsCore
@testable import TraitorsMinds
@testable import TraitorsEngine
@testable import TraitorsLab
@testable import TraitorsGauntlet

/// Whole runs compared against a recording, so a change that keeps every rule but moves a random
/// draw is caught. The recordings are in `Golden/`. A difference here after a change that was not
/// meant to alter play is a bug to find. After one that was, record again with
/// `GOLDEN_RECORD=1 swift test -c release -Xswiftc -enable-testing --filter Golden` and review the diff.
@Suite(.tags(.golden)) struct GoldenTests {
    /// Every line of the game file, in order. A quick run checks the first few of each sort.
    static func gameLines(full: Bool) -> [String] {
        var out: [String] = []
        for seed in 1...(full ? 200 : 12) {
            out.append(line("bots", seed, play(seed: UInt64(seed), name: nil)))
        }
        for seed in 1...(full ? 50 : 4) {
            for pref in RolePreference.allCases {
                out.append(line("human-\(pref.rawValue)", seed, play(seed: UInt64(seed), name: "Tester", preference: pref)))
            }
        }
        for seed in 1...(full ? 20 : 1) {
            var game = Game(seed: UInt64(seed), humanName: nil, options: GameOptions(arena: true))
            game.runToEnd()
            out.append(line("arena", seed, game))
        }
        return out
    }

    static func line(_ sort: String, _ seed: Int, _ game: Game) -> String {
        let winner = game.winner?.rawValue ?? "none"
        return "\(sort) \(seed) \(winner) pot=\(game.pot) day=\(game.day) events=\(game.log.count) \(digest(game.log))"
    }

    /// One mini-game of each kind, played out by bots with the hand against the company.
    static func arenaLines(full: Bool) -> [String] {
        (full ? MissionKind.allCases : Array(MissionKind.allCases.prefix(2))).map { kind in
            let r = ArenaSession.play(ArenaSession.sample(kind, seed: 12, sabotage: true))
            let sunk = r.sunkBy.map(String.init) ?? "none"
            return "\(kind.rawValue) total=\(r.teamTotal ?? -1) sunkBy=\(sunk) \(digest(r.ledger))"
        }
    }

    @Test func gamesPlayOutAsRecorded() throws {
        try check(Self.gameLines(full: fullRun), against: "games.txt")
    }

    @Test func miniGamesPlayOutAsRecorded() throws {
        try check(Self.arenaLines(full: fullRun), against: "arena.txt")
    }

    // MARK: - Support

    static func digest<T: Encodable>(_ value: T) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = .sortedKeys
        let data = (try? enc.encode(value)) ?? Data()
        // FNV-1a, 64 bit.
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data { h = (h ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
        return String(h, radix: 16)
    }

    static func file(_ name: String, _ here: String = #filePath) -> URL {
        URL(fileURLWithPath: here).deletingLastPathComponent().appendingPathComponent("Golden").appendingPathComponent(name)
    }

    func check(_ lines: [String], against name: String) throws {
        let url = Self.file(name)
        if ProcessInfo.processInfo.environment["GOLDEN_RECORD"] != nil {
            #expect(fullRun, "record with FULL=1, or the file will be short")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
            return
        }
        let recorded = Set(try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init))
        for line in lines where !recorded.contains(line) {
            Issue.record("not as recorded in \(name): \(line)")
            // One is enough to say it moved; the rest would only repeat it.
            break
        }
    }
}
