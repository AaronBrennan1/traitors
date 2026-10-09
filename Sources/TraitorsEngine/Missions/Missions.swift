import Foundation
import TraitorsCore
import TraitorsMinds

/// One day's mission. Everyone runs the same course together and what they bring home goes on one
/// pile, which either reaches the goal or does not. Nobody's own share is kept. A traitor may
/// use the shadow's hand to see that it does not.
public struct MissionRun: Codable {

    public package(set) var kind: MissionKind
    var day: Int
    package var order: [PlayerID]
    package var human: PlayerID?
    /// Private: living traitors. Never copied into the public report.
    var traitors: [PlayerID]
    /// Private: the bot traitor who means to use the shadow's hand today, if any.
    package var runner: PlayerID?
    /// How quick and tidy each player is about the work.
    var skill: [Double]
    var perception: [Double]
    var deceit: [Double]
    /// Seeds each player's own habits, which stay the same all game.
    var quirkSeed: UInt64
    var rng: SeededRNG
    /// The numbers the day is played by.
    package var tuning = Tuning()
    /// Seeds the course and everything on it, so a resumed game deals the same run.
    var layoutSeed: UInt64

    var done = false
    var planned = false
    /// Private: how good a day the bots are having between them. It is one number for all of them.
    var form = 0.0
    /// Private: the runner used the hand, whether or not it sank the day.
    package var runnerAttempt = false
    /// Private: the human used the hand.
    var humanAttempt = false
    /// Private: who had eyes on each player from start to finish, by seat.
    var coverage: [SeatMask] = []
    /// Private: what was seen during the mission and by whom.
    package var sightings: [Sighting] = []
    /// Private: the traitor whose hand cost the company its day, if one did.
    var sunkBy: PlayerID?
    var teamTotal = 0
    package var groupWon = false
    /// Private: who was in somebody's sight nearly all mission.
    var neverAlone: [PlayerID] = []

    package init(kind: MissionKind, day: Int, alive: [PlayerID], human: PlayerID?, traitors: [PlayerID],
         runner: PlayerID?, traits: [Personality], quirkSeed: UInt64, rng: SeededRNG, tuning: Tuning = Tuning()) {
        self.tuning = tuning
        self.kind = kind
        self.day = day
        self.human = human
        self.traitors = traitors
        self.runner = runner
        self.skill = traits.map(\.skill)
        self.perception = traits.map(\.perception)
        self.deceit = traits.map(\.deceit)
        self.quirkSeed = quirkSeed
        self.rng = rng
        self.order = self.rng.shuffled(alive)
        self.layoutSeed = self.rng.next()
    }

    public var teamGoal: Int { kind.spec.teamGoal(alive: order.count, handicap: tuning.mission.handicap) }

    // MARK: - Running

    /// Settles the bots before anyone plays: how good a day the company is going to have, and
    /// whether the runner uses the hand.
    package mutating func plan() {
        guard !planned else { return }
        planned = true
        // Who happens to be watching whom all the way through.
        var eyes = SeededRNG.derived(layoutSeed, 1)
        coverage = Array(repeating: 0, count: perception.count)
        for p in order {
            for w in order where w != p && eyes.chance(SightingModel.cover(perception[w])) {
                coverage[p] |= SeatMask.seat(w)
            }
        }
        if let r = runner, r != human {
            // Somebody has not taken their eyes off the runner: only the brazen go ahead.
            runnerAttempt = !(coverage[r] != 0 && rng.chance(1 - 0.6 * deceit[r]))
        }
        form = rng.gaussian()
    }

    /// Settles the whole mission from what the game hands back: what the company brought home and
    /// what was seen. With no game played, the bots bring what their day was good for.
    package mutating func resolve(human result: MissionResult?) {
        guard !done else { return }
        plan()
        let me = human.flatMap { traitors.contains($0) ? $0 : nil }
        if let ledger = result?.ledger {
            // The game was played out: who used the hand and what was seen come from the record.
            if let r = runner, r != human { runnerAttempt = ledger.events.contains { $0.actor == r && $0.code == .sabotage } }
            humanAttempt = me != nil && ledger.events.contains { $0.actor == me && $0.code == .sabotage }
            let seen = SightingDeriver.derive(ledger, day: day, perception: perception, human: human, seed: layoutSeed, tuning: tuning.sightings)
            sightings = seen.sightings
            neverAlone = seen.neverAlone
            teamTotal = result?.teamTotal ?? 0
            groupWon = teamTotal >= teamGoal
            if !groupWon, let by = result?.sunkBy, traitors.contains(by) { sunkBy = by }
        } else {
            let head = kind.spec.head(alive: order.count)
            let bots = Double(order.filter { $0 != human }.count)
            let theirs = runnerAttempt ? tuning.mission.sabotageCost : 0
            let mine = me == nil ? 0 : clamp(result?.sabotage ?? 0, 0, 3)
            humanAttempt = mine > 0
            let effort = human == nil ? 0 : clamp(result?.effort ?? 0, 0, 2)
            teamTotal = result?.teamTotal ?? max(0, Int(((bots + tuning.mission.spread * form - theirs + effort - mine) * head).rounded()))
            groupWon = teamTotal >= teamGoal
            if !groupWon, Double(teamTotal) + (theirs + mine) * head >= Double(teamGoal) { sunkBy = mine > theirs ? me : runner }
            observe()
            neverAlone = order.filter { coverage[$0] != 0 }
        }
        done = true
    }

    /// Works out what everybody saw of everybody else. Honest players have their own odd
    /// habits, so nothing here is proof; the hand only makes the same things likelier.
    private mutating func observe() {
        var eyes = SeededRNG.derived(layoutSeed, 2)
        for p in order {
            let acting = p == human ? humanAttempt : (p == runner && runnerAttempt)
            var odd = false
            for kind in SightingKind.allCases where kind.suspicious {
                var rate = SightingModel.baseline(kind) * SightingModel.quirk(seed: quirkSeed, player: p, kind: kind)
                if acting {
                    // The player's own sleight of hand is not measured, so they get the benefit of the doubt.
                    rate *= SightingModel.lift(kind, deceit: p == human ? 1 : deceit[p], tuning: tuning.belief)
                } else if p == human {
                    // The player is not held to a bot's habits they never chose.
                    rate = kind == .atTheWorks ? 0 : rate * 0.8
                }
                var happened = eyes.chance(min(rate, 0.9))
                var seenBy: SeatMask = 0
                for w in order where w != p && eyes.chance(SightingModel.watch(perception[w])) {
                    seenBy |= SeatMask.seat(w)
                }
                // The hand cannot be used unseen under somebody's nose.
                if acting, kind == .atTheWorks, coverage[p] != 0 { happened = true }
                guard happened else { continue }
                odd = true
                seenBy |= coverage[p]
                if seenBy != 0 { sightings.append(Sighting(day: day, subject: p, kind: kind, witnesses: seenBy)) }
            }
            if !odd, coverage[p] != 0 {
                sightings.append(Sighting(day: day, subject: p, kind: .inView, witnesses: coverage[p]))
            }
        }
    }

    // MARK: - Public report

    func report() -> MissionReport {
        let spec = kind.spec
        let share = min(1, Double(teamTotal) / Double(teamGoal))
        let pot = Int((Double(spec.potPerHead * order.count) * share / 10).rounded()) * 10
        return MissionReport(kind: kind, day: day, teamTotal: teamTotal, teamGoal: teamGoal, groupWon: groupWon, potEarned: pot)
    }
}
