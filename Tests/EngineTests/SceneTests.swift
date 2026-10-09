import Foundation
import Testing
@testable import TraitorsCore
@testable import TraitorsMinds
@testable import TraitorsEngine
@testable import TraitorsLab
@testable import TraitorsGauntlet

/// What the human is allowed to see, and when.
@Suite struct SceneTests {
    @Test func nobodyIsShownGoneBeforeTheSceneHasSaidSo() {
        var banishments = 0, murders = 0
        for seed in seeds(1...40, quick: 6) {
            var game = Game(seed: UInt64(seed), humanName: "Tester", preference: seed % 2 == 0 ? .traitor : .faithful)
            var cap = StepCap()
            while game.phase != .gameOver, cap.allows(game) {
                game.auto()
                var gone: PlayerID?
                if game.phase == .voteReveal { gone = game.outcome?.vote?.banished }
                if game.phase == .breakfast { gone = game.outcome?.morning?.victim }
                let before = game.scene(told: false), after = game.scene(told: true)
                #expect(after.concealed.isEmpty)
                guard let gone else {
                    // Nothing is being held back, so being told changes nothing.
                    #expect(before.concealed.isEmpty && before.spectating == after.spectating, "seed \(seed) \(game.phase)")
                    continue
                }
                if game.phase == .voteReveal { banishments += 1 } else { murders += 1 }
                #expect(before.concealed == [gone])
                #expect(before.shown(gone).alive && !after.shown(gone).alive, "seed \(seed)")
                // Everyone else is shown as they are.
                for p in game.players where p.id != gone { #expect(before.shown(p.id).alive == p.alive) }
                if gone == 0 {
                    #expect(!before.spectating && after.spectating)
                } else if !game.humanIsTraitor, game.humanAlive, game.phase == .voteReveal {
                    // What they were is the last thing told.
                    #expect(before.role(gone) == nil, "seed \(seed): the role was out before the declaration")
                    #expect(after.role(gone) == (game.finale ? nil : game.players[gone].role))
                }
            }
        }
        #expect(banishments > 0 && murders > 0)
    }

    @Test func aRoleIsOnlyShownToSomeoneEntitledToIt() {
        var spectated = 0
        for seed in seeds(1...40, quick: 6) {
            for pref in [RolePreference.faithful, .traitor] {
                var game = Game(seed: UInt64(seed), humanName: "Tester", preference: pref)
                var cap = StepCap()
                while game.phase != .gameOver, cap.allows(game) {
                    game.auto()
                    let scene = game.scene(told: true)
                    #expect(scene.role(0) == game.players[0].role)
                    if game.phase == .gameOver || scene.spectating {
                        // Out of the game, or at the end of it: everything is open.
                        if scene.spectating { spectated += 1 }
                        for p in game.players { #expect(scene.role(p.id) == p.role) }
                        continue
                    }
                    for p in game.players where p.id != 0 {
                        if game.humanIsTraitor, p.role == .traitor {
                            #expect(scene.role(p.id) == .traitor)
                        } else {
                            // Only what the table has been told: a banishment's declaration, or a murder.
                            #expect(scene.role(p.id) == game.revealedRole(p.id), "seed \(seed) day \(game.day): seat \(p.id)")
                            if p.alive { #expect(scene.role(p.id) == nil, "seed \(seed): a living player's role is showing") }
                        }
                    }
                }
            }
        }
        #expect(spectated > 0)
    }

    @Test func theSceneCarriesWhatTheHeaderShows() {
        var game = Game(seed: 5, humanName: "Tester", preference: .faithful)
        run(&game, to: .roundTable, answering: true)
        let scene = game.scene(told: true)
        #expect(scene.day == game.day && scene.pot == game.pot && scene.phase == .roundTable && !scene.finale)
        #expect(scene.seats.count == Rules.seats && scene.lines.count == game.feed.count)
    }
}
