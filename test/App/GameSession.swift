import SwiftUI
import TraitorsEngine

struct Stats: Codable, Equatable {
    var played = 0
    var asFaithful = 0
    var asTraitor = 0
    var wonAsFaithful = 0
    var wonAsTraitor = 0
    var lastRecordedSeed: UInt64?
}

/// The game in play: holds it, passes answers to it, and keeps what the screen needs from it
/// (`prompt`, `scene`) up to date. Everything that outlives a game goes through `saves`.
@Observable
final class GameSession {
    private(set) var game: Game?
    /// What the game is waiting for. Worked out once per answer, not once per view.
    private(set) var prompt: Prompt?
    /// What the human may see right now.
    private(set) var scene: GameScene?
    private(set) var stats = Stats()
    var settings = Settings() {
        didSet {
            effects.settings = settings
            saves.save(settings, to: "settings.json")
        }
    }

    /// Why the last answer sent was turned away, if it was.
    @ObservationIgnored private(set) var refused: GameError?
    @ObservationIgnored private let saves: SaveStore
    @ObservationIgnored let effects: Effects
    /// Scenes whose outcome has been told on screen. Never saved: a scene left half-way plays again.
    @ObservationIgnored private var told: Set<String> = []

    init(saves: SaveStore = FileSaveStore(), effects: Effects = Feedback.effects) {
        self.saves = saves
        self.effects = effects
        stats = saves.load(Stats.self, from: "stats.json") ?? Stats()
        settings = saves.load(Settings.self, from: "settings.json") ?? Settings()
        effects.settings = settings
        // Saves from before the format carried its own version cannot be read any more.
        SavedGame.legacy.forEach(saves.delete)
        game = SavedGame.read(from: saves)
        refresh()
    }

    var hasSave: Bool { game != nil && game?.phase != .gameOver }

    func newGame(name: String, preference: RolePreference, seed: UInt64? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        open(Game(seed: seed ?? UInt64.random(in: 1...UInt64.max / 2),
                  humanName: trimmed.isEmpty ? "You" : trimmed, preference: preference))
    }

    /// Takes up a game that is already under way. One opened only to look at is not written over the save.
    func open(_ game: Game, saving: Bool = true) {
        self.game = game
        refresh()
        if saving { save() }
    }

    /// Answers the current prompt. An answer the game refuses changes nothing.
    func send(_ answer: Answer) {
        guard step(answer) else { return }
        refresh()
        save()
    }

    /// For a human who is out: plays on to the end of the game in one go.
    func skipToEnd() {
        var steps = 0
        while let g = game, g.phase != .gameOver, steps < 400, step(.proceed) { steps += 1 }
        refresh()
        save()
    }

    private func step(_ answer: Answer) -> Bool {
        guard var g = game else { return false }
        do { try g.advance(answer) } catch {
            // A view offered something the game does not take. Nothing has moved; say so and carry on.
            refused = error as? GameError
            print("the game refused \(answer): \(error)")
            return false
        }
        refused = nil
        game = g
        if g.phase == .gameOver { record(g) }
        return true
    }

    func leaveGame() {
        if game?.phase == .gameOver { abandon() }
    }

    func abandon() {
        game = nil
        refresh()
        saves.delete(SavedGame.file)
    }

    // MARK: - What may be shown

    private func sceneID(_ g: Game) -> String { "\(g.seed)-\(g.phase.rawValue)-\(g.day)-\(g.alive.count)" }

    /// The scene on screen has said who is gone, so the rest of the screen may show it.
    func tell() {
        guard let g = game, told.insert(sceneID(g)).inserted else { return }
        refresh()
    }

    private func refresh() {
        prompt = game?.prompt
        scene = game.map { $0.scene(told: told.contains(sceneID($0))) }
    }

    /// A player as the screen may show them right now.
    func shown(_ p: Player) -> Player { scene?.shown(p.id) ?? p }

    /// The human is out and has been told so.
    var spectating: Bool { scene?.spectating ?? false }

    /// The role the human is entitled to see for a player right now.
    func roleShown(_ p: PlayerID) -> Role? { scene?.role(p) }

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
        saves.save(stats, to: "stats.json")
    }

    private func save() {
        if let game { SavedGame.write(game, to: saves) }
    }
}

#if DEBUG
/// Launch arguments that jump straight to a given point in a seeded game, for screenshots:
/// `-autoplay 1 -seed 7 -role traitor -stopPhase voting -stopDay 2 -mission cellars`
/// Add `-arenaBots 1` to have a bot play your seat in the gauntlet, and `-arenaSpeed 4` to hurry it.
/// `-stopVoteRound 2` and `-stopNight offer` narrow the stop; `swift run traitors-sim --scenes` finds seeds
/// for the rarer scenes. `-ceremony settled` opens a staged scene on its last frame. `-mute 1` keeps it silent.
enum Autoplay {
    static func applyLaunchArguments(to session: GameSession, defaults d: UserDefaults = .standard) {
        session.effects.muted = d.bool(forKey: "mute")
        guard d.bool(forKey: "autoplay") else { return }
        let seed = UInt64(max(1, d.integer(forKey: "seed")))
        let role = RolePreference(rawValue: d.string(forKey: "role") ?? "") ?? .random
        var stop = Autopilot.Stop()
        stop.phase = Phase(rawValue: d.string(forKey: "stopPhase") ?? "") ?? .gameOver
        stop.day = max(1, d.integer(forKey: "stopDay"))
        stop.voteRound = d.integer(forKey: "stopVoteRound") > 0 ? d.integer(forKey: "stopVoteRound") : nil
        stop.night = NightChoice(rawValue: d.string(forKey: "stopNight") ?? "")
        session.open(Autopilot.play(seed: seed, name: d.string(forKey: "name") ?? "Aaron", preference: role, stop: stop,
                                    mission: MissionKind(rawValue: d.string(forKey: "mission") ?? "")), saving: false)
    }
}
#endif
