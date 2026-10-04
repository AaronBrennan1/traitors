import Foundation

/// What the human's mini-game hands back to the engine.
struct MissionResult: Codable, Equatable {
    /// Share of the mission's steps completed, 0...1.
    var score: Double
    /// Whether the traitor's secret objective was completed along the way.
    var questDone: Bool
    /// The count each bot finished on in the same game, by seat. Nil when the game was not played out.
    var rivals: [PlayerID: Int]? = nil
    /// What the team brought home between them, bonuses included. Nil when the game was not played out.
    var teamTotal: Int? = nil
    /// The traitor who finished the side quest in the game, if anyone did.
    var questBy: PlayerID? = nil
    /// The record of the game as it was played. With one, what people saw is worked out from it
    /// and not from the dice.
    var ledger: MissionLedger? = nil
}

/// One day's mission. Everyone plays the same game together and comes back with a count that is
/// read out against par. A traitor may also complete the side quest hidden inside the game; it
/// eats time, so it tends to show up as a poor score, the same as an honest bad day.
struct MissionRun: Codable {
    /// Spread of a player's showing from one day to the next, as a share of the steps.
    static let sigma = 0.16
    /// What going after the side quest costs a bot, as a share of the steps.
    static let questPenalty = 0.05

    var kind: MissionKind
    var day: Int
    var order: [PlayerID]
    var human: PlayerID?
    /// Private: living traitors. Never copied into the public report.
    var traitors: [PlayerID]
    /// Private: the bot traitor who means to do the side quest today, if any.
    var runner: PlayerID?
    /// Private: how readily the runner backs out when nobody else has slipped.
    var caution: Double
    /// Private: chance the runner pulls the side quest off once they go for it.
    var questOdds: Double
    /// False on a recruit night, when there is no murder to earn.
    var questOpen: Bool
    var skill: [Double]
    var perception: [Double]
    var deceit: [Double]
    /// Seeds each player's own habits, which stay the same all game.
    var quirkSeed: UInt64
    var rng: SeededRNG
    /// Seeds the layout of the mini-game, so a resumed game deals the same board.
    var layoutSeed: UInt64

    var done = false
    var planned = false
    /// Private: the count each bot is headed for, settled before play.
    var targets: [PlayerID: Int] = [:]
    /// Private: the runner goes for the side quest today and pulls it off.
    var runnerQuest = false
    /// Private: the runner went for the side quest, whether or not it came off.
    var runnerAttempt = false
    /// Private: who had eyes on each player from start to finish, by seat.
    var coverage: [SeatMask] = []
    /// Private: what was seen during the mission and by whom.
    var sightings: [Sighting] = []
    var counts: [PlayerID: Int] = [:]
    /// Private: the traitor whose side quest earned tonight's murder, if any.
    var questCompletedBy: PlayerID?
    /// How many pieces the side quest has today. It grows late in the game.
    var questSteps = 1
    var teamTotal = 0
    /// Private: who was in somebody's sight nearly all mission.
    var neverAlone: [PlayerID] = []

    init(kind: MissionKind, day: Int, alive: [PlayerID], human: PlayerID?, traitors: [PlayerID],
         runner: PlayerID?, caution: Double, questOdds: Double, questOpen: Bool, traits: [Personality],
         quirkSeed: UInt64, rng: SeededRNG, questSteps: Int = 1) {
        self.kind = kind
        self.day = day
        self.human = human
        self.traitors = traitors
        self.runner = runner
        self.caution = caution
        self.questOdds = questOdds
        self.questOpen = questOpen
        self.skill = traits.map(\.skill)
        self.perception = traits.map(\.perception)
        self.deceit = traits.map(\.deceit)
        self.quirkSeed = quirkSeed
        self.questSteps = questSteps
        self.rng = rng
        self.order = self.rng.shuffled(alive)
        self.layoutSeed = self.rng.next()
    }

    // MARK: - Running

    /// Settles the bots before anyone plays: the count each is headed for, and whether the
    /// runner goes after the side quest. The mini-game plays the bots towards these.
    mutating func plan() {
        guard !planned else { return }
        planned = true
        let spec = kind.spec
        // Who happens to be watching whom all the way through.
        var eyes = SeededRNG.derived(layoutSeed, 1)
        coverage = Array(repeating: 0, count: skill.count)
        for p in order {
            for w in order where w != p && eyes.chance(SightingModel.cover(perception[w])) {
                coverage[p] |= SeatMask.seat(w)
            }
        }
        for p in order where p != human && p != runner {
            targets[p] = Self.sample(kind, skill: skill[p], questing: false, rng: &rng)
        }
        if let r = runner, r != human {
            // The runner reads the room first: an honest player headed under par is cover.
            let cover = order.filter { !traitors.contains($0) && $0 != human && (targets[$0] ?? spec.steps) < spec.par }.count
            var attempt = questOpen
            if attempt, cover == 0, rng.chance(caution) { attempt = false }
            // Somebody has not taken their eyes off the runner: only the brazen go ahead.
            if attempt, coverage[r] != 0, rng.chance(1 - 0.6 * deceit[r]) { attempt = false }
            targets[r] = Self.sample(kind, skill: skill[r], questing: attempt, rng: &rng)
            runnerAttempt = attempt
            runnerQuest = attempt && rng.chance(questOdds)
        }
    }

    /// Settles the whole mission from what the mini-game hands back: the human's result and the
    /// count each bot actually finished on. A bot the game did not report keeps its planned count.
    mutating func resolve(human result: MissionResult?) {
        guard !done else { return }
        plan()
        let spec = kind.spec
        if let me = human {
            let r = result ?? MissionResult(score: 0, questDone: false)
            counts[me] = Int((clamp(r.score, 0, 1) * Double(spec.steps)).rounded())
            if r.questDone, questOpen, traitors.contains(me) { questCompletedBy = me }
        }
        for p in order where p != human {
            counts[p] = min(spec.steps, max(0, result?.rivals?[p] ?? targets[p] ?? 0))
        }
        if let ledger = result?.ledger {
            // The game was played out: who did the side quest and what was seen come from the record.
            if let by = result?.questBy, questOpen, traitors.contains(by) { questCompletedBy = by }
            if let r = runner, r != human {
                runnerAttempt = ledger.events.contains { $0.actor == r && $0.code == .questTry }
                runnerQuest = questCompletedBy == r
            }
            let seen = SightingDeriver.derive(ledger, day: day, perception: perception, human: human, seed: layoutSeed)
            sightings = seen.sightings
            neverAlone = seen.neverAlone
        } else {
            if let r = runner, r != human, runnerQuest, questCompletedBy == nil { questCompletedBy = r }
            observe()
            neverAlone = order.filter { coverage[$0] != 0 }
        }
        teamTotal = max(result?.teamTotal ?? 0, order.reduce(0) { $0 + (counts[$1] ?? 0) })
        done = true
    }

    /// Works out what everybody saw of everybody else. Honest players have their own odd
    /// habits, so nothing here is proof; the side quest only makes the same things likelier.
    private mutating func observe() {
        var eyes = SeededRNG.derived(layoutSeed, 2)
        for p in order {
            let questing = p == human ? questCompletedBy == p : (p == runner && runnerAttempt)
            var odd = false
            for kind in SightingKind.allCases where kind.suspicious {
                var rate = SightingModel.baseline(kind) * SightingModel.quirk(seed: quirkSeed, player: p, kind: kind)
                if questing {
                    // The player's own sleight of hand is not measured, so they get the benefit of the doubt.
                    rate *= SightingModel.lift(kind, deceit: p == human ? 1 : deceit[p])
                } else if p == human {
                    // The player is not held to a bot's habits they never chose.
                    rate = kind == .atQuestObject ? 0 : rate * 0.8
                }
                var happened = eyes.chance(min(rate, 0.9))
                var seenBy: SeatMask = 0
                for w in order where w != p && eyes.chance(SightingModel.watch(perception[w])) {
                    seenBy |= SeatMask.seat(w)
                }
                // The side quest cannot be done unseen under somebody's nose.
                if questing, kind == .atQuestObject, coverage[p] != 0 { happened = true }
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

    // MARK: - Skill curves

    /// The share of steps below which a player is under par.
    static func threshold(_ kind: MissionKind) -> Double {
        (Double(kind.spec.par) - 0.5) / Double(kind.spec.steps)
    }

    /// How far above the par line a player of this skill sits on an average day.
    static func margin(_ s: Double) -> Double { 0.08 + 0.18 * (s - 0.5) }

    /// Chance an honest player of this skill finishes under par.
    static func slipRate(skill s: Double) -> Double {
        0.5 * erfc(margin(s) / sigma / 2.0.squareRoot())
    }

    /// Chance a player of this skill finishes under par with the side quest to do as well.
    static func questRate(skill s: Double) -> Double {
        0.5 * erfc((margin(s) - questPenalty) / sigma / 2.0.squareRoot())
    }

    static func sample(_ kind: MissionKind, skill s: Double, questing: Bool, rng: inout SeededRNG) -> Int {
        let steps = Double(kind.spec.steps)
        var x = threshold(kind) + margin(s) + sigma * rng.gaussian()
        if questing { x -= questPenalty }
        return Int(clamp((x * steps).rounded(), 0, steps))
    }

    // MARK: - Public report

    func report(names: [String]) -> MissionReport {
        let spec = kind.spec
        var units: [MissionUnit] = []
        var lines: [String] = []
        var scores: [PlayerID: Double] = [:]
        for p in order {
            let c = counts[p] ?? 0
            let under = c < spec.par
            let detail = "\(names[p]) came back with \(c) of \(spec.steps) \(spec.unit)" + (under ? ", under par." : ".")
            units.append(MissionUnit(players: [p], count: c, anomalous: under,
                                     innocentRate: Self.slipRate(skill: skill[p]),
                                     questRate: Self.questRate(skill: skill[p]), detail: detail))
            if under { lines.append(detail) }
            scores[p] = Double(c) / Double(spec.steps)
        }
        if lines.isEmpty { lines = ["A clean run. Everybody made par."] }
        // The pot is the team's: everyone's haul against what was asked of them together.
        let goal = spec.teamGoal(alive: order.count)
        let share = min(1, Double(teamTotal) / Double(goal))
        let pot = Int((Double(spec.potPerHead * order.count) * share / 10).rounded()) * 10
        return MissionReport(kind: kind, day: day, steps: spec.steps, par: spec.par, units: units,
                             scores: scores, potEarned: pot, lines: lines, teamTotal: teamTotal, teamGoal: goal)
    }
}
