import Foundation
import Testing
@testable import TraitorsCore
@testable import TraitorsMinds
@testable import TraitorsEngine
@testable import TraitorsLab
@testable import TraitorsGauntlet

@Suite struct TableTests {
    @Test(.tags(.sweep), .enabled(if: fullRun)) func whatBotsCiteFromTheRecordIsTrue() {
        for seed in 1...30 {
            var game = Game(seed: UInt64(seed), humanName: nil)
            var checked = 0
            var cap = StepCap()
            while game.phase != .gameOver, cap.allows(game) {
                game.go()
                let v = game.view()
                for s in v.index.statements.dropFirst(checked) {
                    guard let chip = s.chip else { continue }
                    #expect(Chips.holds(chip, view: v), "seed \(seed) day \(s.day): \(s.speaker) cited \(chip.kind) falsely")
                }
                checked = v.index.statements.count
            }
        }
    }

    @Test func aMadeUpClaimFromTheRecordDoesNotHold() {
        var game = Game(seed: 6, humanName: nil)
        run(&game, to: .gameOver)
        let v = game.view()
        guard let b = v.index.banishments.first(where: { $0.role == .faithful }) else { return }
        let voters = v.index.votes[b.day]?[1] ?? [:]
        let innocent = (0..<Rules.seats).first { voters[$0] != nil && voters[$0] != b.player }
        if let innocent {
            #expect(!Chips.holds(Chip(kind: .votedOutFaithful, subject: innocent, day: b.day, other: b.player), view: v))
        }
        if let guilty = (0..<Rules.seats).first(where: { voters[$0] == b.player }) {
            #expect(Chips.holds(Chip(kind: .votedOutFaithful, subject: guilty, day: b.day, other: b.player), view: v))
        }
    }

    @Test(.tags(.sweep), .enabled(if: fullRun)) func onlyTraitorsEverInventASighting() {
        var lies = 0
        for seed in 1...100 {
            var game = Game(seed: UInt64(seed), humanName: nil)
            run(&game, to: .gameOver)
            var role = Array(repeating: Role.faithful, count: game.players.count)
            for p in game.players where p.role == .traitor && !p.wasRecruited { role[p.id] = .traitor }
            for event in game.log {
                if case .night(_, nil, true) = event { for p in game.players where p.wasRecruited { role[p.id] = .traitor } }
                guard case .statement(let s) = event, let chip = s.chip, chip.isTestimony else { continue }
                let real = game.sightings.contains { $0.day == chip.day && $0.subject == chip.subject && $0.kind == chip.sight && $0.witnesses.has(s.speaker) }
                if !real {
                    lies += 1
                    #expect(role[s.speaker] == .traitor, "seed \(seed): faithful \(s.speaker) invented a sighting")
                }
            }
            #expect(game.tally.liesCaught <= game.tally.liesTold)
        }
        #expect(lies > 0)
    }

    @Test(.tags(.sweep), .enabled(if: fullRun)) func theHumanCanAnswerAChargeButNeverHasTo() {
        var answered = 0
        for seed in 1...80 {
            var game = Game(seed: UInt64(seed), humanName: "Tester", preference: seed % 2 == 0 ? .traitor : .faithful)
            var steps = 0
            while game.phase != .gameOver, steps < 600 {
                if case .speak(let step, _, let options) = game.prompt {
                    if !options.isEmpty, seed % 3 == 0 {
                        game.go(.rebut(options.count - 1))
                        answered += 1
                        #expect(game.log.contains { if case .statement(let s) = $0 { return s.speaker == 0 && s.defence != nil } else { return false } })
                    } else {
                        game.go(.say(.pass, target: nil, chip: nil))
                    }
                    // Either way the turn is spent.
                    if case .speak(step, _, _) = game.prompt { Issue.record("seed \(seed): the turn was not spent") }
                } else {
                    game.auto()
                }
                steps += 1
            }
            #expect(game.phase == .gameOver)
        }
        #expect(answered > 0)
    }

    @Test func theHumanIsToldWhatTheySawAndCanCiteIt() {
        var cited = 0
        for seed in 1...40 {
            var game = Game(seed: UInt64(seed), humanName: "Tester", preference: .faithful)
            while game.phase != .roundTable, game.phase != .gameOver { game.auto() }
            guard game.phase == .roundTable else { continue }
            let mine = game.minds[0].seen.filter { $0.day == game.day && $0.kind.suspicious }
            for s in mine {
                let chips = game.notebook(about: s.subject, suspicious: true)
                #expect(chips.contains { $0.kind == .sighting && $0.sight == s.kind })
            }
            if let s = mine.first(where: { game.players[$0.subject].alive }),
               let chip = game.notebook(about: s.subject, suspicious: true).first(where: { $0.kind == .sighting }) {
                game.go(.say(.accuse, target: s.subject, chip: chip))
                #expect(game.view().index.told.contains { $0.by == 0 && $0.about == s.subject })
                cited += 1
            }
        }
        #expect(cited > 0)
    }
}
