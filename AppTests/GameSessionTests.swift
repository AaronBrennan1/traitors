import Foundation
import Testing
import TraitorsEngine
@testable import test

/// A session with nothing behind it but memory: no files, no sound.
@MainActor
func session(_ saves: MemorySaveStore = MemorySaveStore(), effects: RecordingEffects = RecordingEffects()) -> GameSession {
    GameSession(saves: saves, effects: effects)
}

/// A game written out with its keys in order, so two can be compared whole.
func written(_ game: Game?) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return try encoder.encode(game)
}

/// What the screens' own buttons would send for each prompt.
struct Tapper: SeatPolicy {
    func answer(_ prompt: Prompt, in game: Game) -> Answer {
        switch prompt {
        case .proceed, .over: return .proceed
        case .playMission: return .mission(MissionResult())
        case .speak: return .say(.pass, target: nil, chip: nil)
        case .vote(_, let candidates): return .vote(candidates[0])
        case .murder(let candidates, let advice): return .murder(advice ?? candidates[0])
        case .recruit(let candidates): return .recruit(candidates[0])
        case .answerOffer: return .offer(accept: true)
        case .endOrBanish: return .finale(end: false)
        }
    }
}

@MainActor
extension GameSession {
    /// Answers prompts as `Tapper` would until `stop` says so or the game is over.
    func play(until stop: (Game) -> Bool = { _ in false }) {
        var steps = 0
        while let g = game, let prompt, g.phase != .gameOver, !stop(g), steps < 600 {
            send(Tapper().answer(prompt, in: g))
            steps += 1
        }
    }
}

@MainActor
@Suite struct GameSessionTests {
    @Test func aSessionStartsEmptyAndKeepsNothingItWasNotAskedTo() {
        let saves = MemorySaveStore()
        let s = session(saves)
        #expect(s.game == nil && s.prompt == nil && s.scene == nil && !s.hasSave)
        #expect(saves.data(named: SavedGame.file) == nil)
    }

    @Test func everyAnswerMovesTheGameAndSavesItOnce() throws {
        let saves = MemorySaveStore()
        let s = session(saves)
        s.newGame(name: "  Aoife  ", preference: .faithful, seed: 7)
        #expect(s.game?.players[0].name == "Aoife" && s.game?.phase == .roleReveal && s.hasSave)
        #expect(saves.writes[SavedGame.file] == 1)
        guard case .proceed(.breakfast) = s.prompt else { Issue.record("a new game waits at the role reveal"); return }

        s.send(.proceed)
        #expect(s.game?.phase == .breakfast && saves.writes[SavedGame.file] == 2)
        #expect(s.scene?.phase == .breakfast && s.scene?.day == 1)

        // An answer the game does not take changes nothing and is not saved.
        let before = try written(s.game)
        s.send(.vote(3))
        #expect(s.refused == .notAskedFor)
        #expect(try written(s.game) == before && saves.writes[SavedGame.file] == 2)
        s.send(.proceed)
        #expect(s.refused == nil && s.game?.phase == .missionBrief)
    }

    @Test func aSavedGameIsPickedUpWhereItWasLeft() throws {
        let saves = MemorySaveStore()
        let first = session(saves)
        first.newGame(name: "Aoife", preference: .traitor, seed: 11)
        first.play { $0.phase == .roundTable }
        #expect(first.game?.phase == .roundTable)

        let second = session(saves)
        #expect(second.hasSave && second.game?.phase == .roundTable && second.game?.day == first.game?.day)
        #expect(try written(second.game) == written(first.game))
        // And it carries on exactly as the first would have.
        first.play { $0.phase == .voteReveal }
        second.play { $0.phase == .voteReveal }
        #expect(first.game?.outcome?.vote == second.game?.outcome?.vote)
    }

    @Test func aSaveFromAnotherVersionIsNotRead() throws {
        let saves = MemorySaveStore()
        let s = session(saves)
        s.newGame(name: "Aoife", preference: .faithful, seed: 3)
        // The same file, claiming to be from an older build.
        var raw = try #require(try JSONSerialization.jsonObject(with: saves.data(named: SavedGame.file)!) as? [String: Any])
        #expect(raw["version"] as? Int == SavedGame.current)
        raw["version"] = SavedGame.current - 1
        saves.write(try JSONSerialization.data(withJSONObject: raw), named: SavedGame.file)
        #expect(session(saves).game == nil)
        // Files from before the version moved inside the file are cleared away.
        saves.write(Data("{}".utf8), named: "save-v8.json")
        saves.write(Data("{}".utf8), named: "save.json")
        _ = session(saves)
        #expect(saves.data(named: "save-v8.json") == nil && saves.data(named: "save.json") == nil)
    }

    @Test func whoHasJustLeftIsHeldBackUntilTheSceneHasSaidSo() {
        let s = session()
        s.newGame(name: "Aoife", preference: .faithful, seed: 2)
        s.play { $0.phase == .voteReveal }
        let out = s.game?.outcome?.vote?.banished
        guard let game = s.game, let out, out != 0 else { return }
        #expect(!game.players[out].alive)
        // Still in their seat on screen, and what they were is not showing.
        #expect(s.shown(game.players[out]).alive && s.roleShown(out) == nil && s.scene?.concealed == [out])
        s.tell()
        #expect(!s.shown(game.players[out]).alive && s.roleShown(out) == game.players[out].role && s.scene?.concealed.isEmpty == true)
        // Telling it twice is telling it once.
        s.tell()
        #expect(s.roleShown(out) == game.players[out].role)
    }

    @Test func skippingToTheEndIsOneSaveAndTheGameIsCountedOnce() {
        let saves = MemorySaveStore()
        let s = session(saves)
        s.newGame(name: "Aoife", preference: .faithful, seed: 1)
        // Seed 1, faithful: the human is banished on day two and watches from there.
        s.play { !$0.humanAlive }
        guard let game = s.game, !game.humanAlive, game.phase != .gameOver else { Issue.record("expected to be watching by now"); return }
        s.tell()
        #expect(s.spectating)
        let writes = saves.writes[SavedGame.file] ?? 0
        s.skipToEnd()
        #expect(s.game?.phase == .gameOver && s.game?.winner != nil)
        #expect(saves.writes[SavedGame.file] == writes + 1)
        #expect(s.stats.played == 1 && s.stats.asFaithful == 1 && saves.load(Stats.self, from: "stats.json") == s.stats)
        // Going round again does not count it twice.
        s.skipToEnd()
        #expect(s.stats.played == 1)
        s.leaveGame()
        #expect(s.game == nil && saves.data(named: SavedGame.file) == nil)
        #expect(session(saves).stats.played == 1)
    }

    @Test func settingsReachTheEffectsAndTheStore() {
        let saves = MemorySaveStore()
        let effects = RecordingEffects()
        let s = session(saves, effects: effects)
        #expect(effects.settings.sound && effects.settings.haptics)
        s.settings.sound = false
        #expect(!effects.settings.sound && effects.settings.haptics)
        #expect(saves.load(Settings.self, from: "settings.json")?.sound == false)
        #expect(!session(saves, effects: RecordingEffects()).settings.sound)
    }
}
