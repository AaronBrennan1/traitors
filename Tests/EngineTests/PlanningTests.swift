import Foundation
import Testing
@testable import TraitorsCore
@testable import TraitorsMinds
@testable import TraitorsEngine
@testable import TraitorsLab
@testable import TraitorsGauntlet

@Suite struct PlanningTests {
    @Test func lookingAheadNeverMovesTheGame() throws {
        var game = Game(seed: 12, humanName: nil)
        run(&game, to: .voteReveal)
        let enc = JSONEncoder()
        enc.outputFormatting = .sortedKeys
        let before = try enc.encode(game)
        let v = game.view()
        let known = game.team.flatMap { game.minds[$0].exposed }
        let listeners = Listeners.build(view: v, team: game.team, known: known)
        let a = VoteSim.pBanish(view: v, listeners: listeners, fixed: [], rng: .derived(game.seed, 1))
        let b = VoteSim.pBanish(view: v, listeners: listeners, fixed: [], rng: .derived(game.seed, 1))
        #expect(a == b)
        #expect(abs(a.reduce(0, +) - 1) < 1e-9)
        let plan = TeamPlanner.plan(view: v, team: game.team, known: known, seed: game.seed)
        let again = TeamPlanner.plan(view: v, team: game.team, known: known, seed: game.seed)
        #expect(try enc.encode(plan) == enc.encode(again))
        #expect(try enc.encode(game) == before)
    }

    @Test func theTeamPlanSurvivesASave() throws {
        var game = Game(seed: 21, humanName: "Tester", preference: .traitor)
        run(&game, to: .roundTable, answering: true)
        #expect(game.teamPlan != nil)
        let restored = try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(game))
        #expect(restored.teamPlan?.scapegoat == game.teamPlan?.scapegoat)
        #expect(restored.teamPlan?.stances == game.teamPlan?.stances)
        #expect(restored.sightings == game.sightings)
    }

    @Test(.tags(.sweep), .enabled(if: fullRun)) func aTraitorVouchesForAPartnerAtMostOnceATable() {
        for seed in 1...80 {
            var game = Game(seed: UInt64(seed), humanName: nil)
            run(&game, to: .gameOver)
            var role = Array(repeating: Role.faithful, count: game.players.count)
            for p in game.players where p.role == .traitor && !p.wasRecruited { role[p.id] = .traitor }
            var count: [PlayerID: Int] = [:]
            for event in game.log {
                switch event {
                case .statement(let s):
                    if let t = s.target, s.kind == .vouch || s.kind == .defend, role[s.speaker] == .traitor, role[t] == .traitor {
                        count[s.speaker, default: 0] += 1
                        #expect(count[s.speaker]! <= 1, "seed \(seed): \(s.speaker) spoke up for a partner twice at one table")
                    }
                case .banished:
                    count = [:]
                case .night(_, nil, true):
                    for p in game.players where p.wasRecruited { role[p.id] = .traitor }
                default: break
                }
            }
        }
    }

    @Test(.tags(.sweep), .enabled(if: fullRun)) func aTraitorIsNeverTheFirstToNameAPartner() {
        for seed in 201...280 {
            var game = Game(seed: UInt64(seed), humanName: nil)
            run(&game, to: .gameOver)
            var role = Array(repeating: Role.faithful, count: game.players.count)
            for p in game.players where p.role == .traitor && !p.wasRecruited { role[p.id] = .traitor }
            var named: Set<PlayerID> = []
            var day = 0
            for event in game.log {
                switch event {
                case .statement(let s):
                    // "Named" is anything said today that points the finger, by someone outside the team.
                    if s.day != day { day = s.day; named = [] }
                    guard let t = s.target, s.kind.effect.names else { break }
                    if role[s.speaker] == .traitor, role[t] == .traitor, s.kind == .accuse || s.kind == .callout {
                        #expect(named.contains(t), "seed \(seed): \(s.speaker) opened on partner \(t)")
                    }
                    if role[s.speaker] == .faithful { named.insert(t) }
                case .night(_, nil, true):
                    for p in game.players where p.wasRecruited { role[p.id] = .traitor }
                default: break
                }
            }
        }
    }
}
