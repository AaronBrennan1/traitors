import SwiftUI

struct Stats: Codable {
    var played = 0
    var asFaithful = 0
    var asTraitor = 0
    var wonAsFaithful = 0
    var wonAsTraitor = 0
    var lastRecordedSeed: UInt64?
}

/// Owns the current game and everything that outlives it.
@Observable
final class GameStore {
    var game: Game?
    var stats = Stats()
    var settings = Settings() {
        didSet {
            Feedback.settings = settings
            Persistence.save(settings, to: "settings.json")
        }
    }

    init() {
        stats = Persistence.load(Stats.self, from: "stats.json") ?? Stats()
        settings = Persistence.load(Settings.self, from: "settings.json") ?? Settings()
        Feedback.settings = settings
        // Saves from before the missions changed shape cannot be read any more.
        Persistence.delete("save.json")
        Persistence.delete("save-v2.json")
        Persistence.delete("save-v3.json")
        Persistence.delete("save-v4.json")
        Persistence.delete("save-v5.json")
        Persistence.delete("save-v6.json")
        Persistence.delete("save-v7.json")
        game = Persistence.load(Game.self, from: Persistence.saveFile)
        #if DEBUG
        Feedback.muted = UserDefaults.standard.bool(forKey: "mute")
        Autoplay.applyLaunchArguments(to: self)
        #endif
    }

    var hasSave: Bool { game != nil && game?.phase != .gameOver }

    func newGame(name: String, preference: RolePreference, seed: UInt64? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        game = Game(seed: seed ?? UInt64.random(in: 1...UInt64.max / 2),
                    humanName: trimmed.isEmpty ? "You" : trimmed, preference: preference)
        save()
    }

    func send(_ input: HumanInput) {
        guard var g = game else { return }
        g.advance(input)
        game = g
        if g.phase == .gameOver { record(g) }
        save()
    }

    func leaveGame() {
        if game?.phase == .gameOver {
            game = nil
            Persistence.delete(Persistence.saveFile)
        }
    }

    func abandon() {
        game = nil
        Persistence.delete(Persistence.saveFile)
    }

    /// Scenes whose outcome has been told on screen. Never saved: a scene left half-way plays again.
    var told: Set<String> = []

    private func sceneID(_ g: Game) -> String { "\(g.seed)-\(g.phase.rawValue)-\(g.day)-\(g.alive.count)" }

    /// The scene on screen has said who is gone, so the rest of the screen may show it.
    func tell() {
        if let g = game { told.insert(sceneID(g)) }
    }

    /// Whoever the engine has already sent out but the scene has not yet said so. Until it does,
    /// they are drawn in their seat and nothing about their going is given away.
    var concealed: Set<PlayerID> {
        guard let g = game, g.phase == .voteReveal || g.phase == .breakfast, !told.contains(sceneID(g)) else { return [] }
        return Set(g.feed.filter { $0.kind == .banish || $0.kind == .murder }.compactMap(\.target))
    }

    /// A player as the screen may show them right now.
    func shown(_ p: Player) -> Player { concealed.contains(p.id) ? seated(p) : p }

    /// The human is out and has been told so.
    var spectating: Bool {
        guard let g = game, let me = g.human else { return false }
        return !g.players[me].alive && !concealed.contains(me)
    }

    /// The role the human is entitled to see for a player right now.
    func roleShown(_ p: PlayerID) -> Role? {
        guard let g = game else { return nil }
        let hidden = concealed
        let humanOut = !g.humanAlive && !(g.human.map(hidden.contains) ?? false)
        if g.phase == .gameOver || humanOut { return g.players[p].role }
        if p == g.human { return g.players[p].role }
        if g.humanIsTraitor, g.players[p].role == .traitor { return .traitor }
        return hidden.contains(p) ? nil : g.revealedRole(p)
    }

    func humanWon(_ g: Game) -> Bool {
        guard let me = g.human, let winner = g.winner else { return false }
        return g.players[me].role == winner
    }

    private func record(_ g: Game) {
        guard stats.lastRecordedSeed != g.seed, let me = g.human else { return }
        stats.lastRecordedSeed = g.seed
        stats.played += 1
        let won = humanWon(g)
        if g.players[me].role == .traitor {
            stats.asTraitor += 1
            if won { stats.wonAsTraitor += 1 }
        } else {
            stats.asFaithful += 1
            if won { stats.wonAsFaithful += 1 }
        }
        Persistence.save(stats, to: "stats.json")
    }

    private func save() {
        if let game { Persistence.save(game, to: Persistence.saveFile) }
    }
}

enum Persistence {
    static let saveFile = "save-v8.json"

    private static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Traitors", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func save<T: Encodable>(_ value: T, to file: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: folder.appendingPathComponent(file), options: .atomic)
    }

    static func load<T: Decodable>(_ type: T.Type, from file: String) -> T? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(file)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func delete(_ file: String) {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
    }
}

#if DEBUG
/// Launch arguments that jump straight to a given point in a seeded game, for screenshots:
/// `-autoplay 1 -seed 7 -role traitor -stopPhase voting -stopDay 2 -mission cellars`
/// Add `-arenaBots 1` to have a bot play your seat in the gauntlet, and `-arenaSpeed 4` to hurry it.
/// `-stopVoteRound 2` and `-stopNight offer` narrow the stop; `swift run traitors-sim --scenes` finds seeds
/// for the rarer scenes. `-ceremony settled` opens a staged scene on its last frame. `-mute 1` keeps it silent.
enum Autoplay {
    static func applyLaunchArguments(to store: GameStore) {
        let d = UserDefaults.standard
        guard d.bool(forKey: "autoplay") else { return }
        let seed = UInt64(max(1, d.integer(forKey: "seed")))
        let role = RolePreference(rawValue: d.string(forKey: "role") ?? "") ?? .random
        var stop = Autopilot.Stop()
        stop.phase = Phase(rawValue: d.string(forKey: "stopPhase") ?? "") ?? .gameOver
        stop.day = max(1, d.integer(forKey: "stopDay"))
        stop.voteRound = d.integer(forKey: "stopVoteRound") > 0 ? d.integer(forKey: "stopVoteRound") : nil
        stop.night = NightChoice(rawValue: d.string(forKey: "stopNight") ?? "")
        store.game = Autopilot.play(seed: seed, name: d.string(forKey: "name") ?? "Aaron", preference: role, stop: stop,
                                    mission: MissionKind(rawValue: d.string(forKey: "mission") ?? ""))
    }
}
#endif
