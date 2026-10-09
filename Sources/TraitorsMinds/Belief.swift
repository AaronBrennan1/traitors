import Foundation
import TraitorsCore

/// What a particular mind brings to the evidence.
struct Observer {
    /// A faithful player knows they are not a traitor. Nil for the neutral public view.
    var id: PlayerID?
    /// Private log-odds hunch about each player.
    var gut: [Double]
    /// 0...1 exponent on the evidence; below 1 the mind under-reacts.
    var temper: Double
    /// What this mind saw for itself during missions.
    var sightings: [Sighting] = []
    /// Share of soft evidence still remembered after each night.
    var decay = 1.0

    static func publicView(count: Int) -> Observer {
        Observer(id: nil, gut: Array(repeating: 0, count: count), temper: 1)
    }

    /// Whether this mind knows first-hand that a claimed sighting cannot be true.
    func contradicts(subject: PlayerID, day: Int, claim: SightingKind) -> Bool {
        sightings.contains { $0.subject == subject && $0.day == day && $0.clashes(with: claim) }
    }
}

/// The kinds of evidence a belief is built from, so it can say why it thinks what it thinks.
enum EvidenceKind: Int, CaseIterable {
    case mission, testimony, vote, accuse, defend, firstNamer, pair, mismatch, lie, motive
}

struct Reason {
    /// Nil for a private hunch.
    var kind: EvidenceKind?
    /// Log-odds this pushes the player towards traitor.
    var weight: Double
}

/// A probability distribution over who the traitors currently are.
struct Belief {
    var masks: [SeatMask]
    var weights: [Double]
    /// Evidence by hypothesis and kind, `EvidenceKind.allCases.count` per hypothesis.
    var detail: [Double] = []
    var prior: [Double] = []

    func marginal(_ p: PlayerID) -> Double {
        var s = 0.0
        for i in masks.indices where masks[i].has(p) { s += weights[i] }
        return s
    }

    func marginals(count: Int) -> [Double] {
        (0..<count).map { marginal($0) }
    }

    /// Probability that every member of `team` is a traitor.
    func mass(team: SeatMask) -> Double {
        var s = 0.0
        for i in masks.indices where masks[i] & team == team { s += weights[i] }
        return s
    }

    /// Probability that no traitor is left among `alive`.
    func noneLeft(alive: SeatMask) -> Double {
        var s = 0.0
        for i in masks.indices where masks[i] & alive == 0 { s += weights[i] }
        return s
    }

    /// What counts against `p`, strongest first: how much more of each kind of evidence
    /// the worlds with `p` in them carry than the worlds without.
    func reasons(for p: PlayerID) -> [Reason] {
        let k = EvidenceKind.allCases.count
        guard detail.count == masks.count * k else { return [] }
        var with = Array(repeating: 0.0, count: k + 1), without = with
        var wIn = 0.0, wOut = 0.0
        for h in masks.indices {
            let w = weights[h]
            if masks[h].has(p) {
                wIn += w
                for j in 0..<k { with[j] += w * detail[h * k + j] }
                with[k] += w * prior[h]
            } else {
                wOut += w
                for j in 0..<k { without[j] += w * detail[h * k + j] }
                without[k] += w * prior[h]
            }
        }
        guard wIn > 0, wOut > 0 else { return [] }
        var out: [Reason] = []
        for j in 0...k {
            let d = with[j] / wIn - without[j] / wOut
            if d > 0.05 { out.append(Reason(kind: j < k ? EvidenceKind(rawValue: j) : nil, weight: d)) }
        }
        return out.sorted { $0.weight > $1.weight }
    }
}

/// Exact inference over every possible traitor team, fed the public log one event at a time.
/// It is a value: copy it and feed it something hypothetical to see what a mind would make of it.
struct Replay {
    private static let kinds = EvidenceKind.allCases.count

    /// Something said at the table today about what happened in today's mission.
    private struct Told {
        var speaker: PlayerID
        var subject: PlayerID
        var kind: SightingKind
    }

    let count: Int
    let tuning: BeliefTuning
    private(set) var observer: Observer
    /// True while every hunch in `prior` is still just the observer's gut about that team, so it
    /// can be worked out again from a gut that has changed.
    private var plainPrior = true
    private var masks: [SeatMask] = []
    private var prior: [Double] = []
    private var ev: [Double] = []

    private var aliveMask: SeatMask
    private var aliveAtMission: SeatMask
    private var pending: MissionReport?
    private var attacks: [Double]
    private var today = 0
    private var declared: [PlayerID?]
    /// Who first named each player at today's table.
    private var named: [PlayerID?]
    private var ballots: [(voter: PlayerID, target: PlayerID)] = []
    private var told: [Told] = []

    init(count n: Int, observer: Observer, teamSize: Int = Rules.traitors, tuning: BeliefTuning = BeliefTuning()) {
        count = n
        self.tuning = tuning
        self.observer = observer
        aliveMask = (1 << SeatMask(n)) - 1
        aliveAtMission = aliveMask
        attacks = Array(repeating: 0, count: n * n)
        declared = Array(repeating: nil, count: n)
        named = Array(repeating: nil, count: n)

        let pool = (0..<n).filter { $0 != observer.id }
        var teams: [SeatMask] = []
        var hunch: [Double] = []
        func build(_ start: Int, _ left: Int, _ mask: SeatMask, _ gut: Double) {
            if left == 0 { teams.append(mask); hunch.append(gut); return }
            guard pool.count - start >= left else { return }
            for i in start..<pool.count {
                build(i + 1, left - 1, mask | SeatMask.seat(pool[i]), gut + observer.gut[pool[i]])
            }
        }
        build(0, teamSize, 0, 0)
        masks = teams
        prior = hunch
        ev = Array(repeating: 0, count: teams.count * Self.kinds)
    }

    // MARK: - Feeding

    mutating func feed(_ events: [PublicEvent]) {
        for e in events { feed(e) }
    }

    mutating func feed(_ event: PublicEvent) {
        switch event {
        case .mission(let r):
            turn(to: r.day)
            pending = r
            aliveAtMission = aliveMask
            told = []

        case .statement(let s):
            turn(to: s.day)
            hear(s)

        case .vote(let day, let round, let voter, let target):
            turn(to: day)
            affinity(.vote, voter, target, both: tuning.voteBoth, only: tuning.voteOnly)
            attacks[voter * count + target] += 1
            if round == 1 {
                ballots.append((voter, target))
                if let said = declared[voter], said != target {
                    let l = log(tuning.mismatch)
                    for h in masks.indices where masks[h].has(voter) { add(.mismatch, h, l) }
                }
            }

        case .banished(_, let player, let role):
            aliveMask &= ~SeatMask.seat(player)
            if role == .traitor { keep { $0.has(player) } }
            if role == .faithful {
                keep { !$0.has(player) }
                if let first = named[player] {
                    let l = log(tuning.firstNamer)
                    for h in masks.indices where masks[h].has(first) { add(.firstNamer, h, l) }
                }
            } else {
                // Who kept their name off a partner while the table was writing it?
                let others = Double(max(ballots.count - 1, 1))
                for b in ballots where b.target != player && b.voter != player {
                    let share = Double(ballots.filter { $0.target == player }.count) / others
                    let f = clamp((1 - tuning.busRate) / max(1 - share, 0.05), 1 / tuning.pairCap, tuning.pairCap)
                    let l = log(f)
                    for h in masks.indices where masks[h].has(b.voter) && masks[h].has(player) { add(.pair, h, l) }
                }
            }
            ballots = []
            named = Array(repeating: nil, count: count)

        case .night(let day, let victim, let recruitNight):
            // The traitors only get their night by the shadow's task or by the company falling
            // short, so what happened says something about the day whichever kind of night it was.
            if let r = pending, r.day == day {
                let term = missionTerm(report: r, acted: victim != nil || recruitNight)
                for h in masks.indices { add(.mission, h, term[h]) }
            }
            if recruitNight {
                if let victim {
                    // The offer was refused and the refuser was killed: they were faithful.
                    keep { !$0.has(victim) }
                    aliveMask &= ~SeatMask.seat(victim)
                } else {
                    recruit()
                }
            } else if let victim {
                keep { !$0.has(victim) }
                motive(victim)
                aliveMask &= ~SeatMask.seat(victim)
            }
            pending = nil
            told = []
            // Hard facts stay; impressions fade.
            if observer.decay < 1 { for i in ev.indices { ev[i] *= observer.decay } }

        case .finaleVote:
            break
        }
    }

    private mutating func hear(_ s: Statement) {
        if let t = s.target, s.kind.effect.names, named[t] == nil { named[t] = s.speaker }

        if let chip = s.chip, let seen = chip.sight {
            if chip.isTestimony {
                testify(speaker: s.speaker, subject: chip.subject, day: chip.day, kind: seen)
            } else if s.kind == .challenge, chip.kind == .caughtLie, let liar = s.target, let about = chip.other {
                // Two people cannot both be telling the truth here.
                let l = log(tuning.lieConflict)
                for h in masks.indices where !masks[h].has(s.speaker) && !masks[h].has(liar) { add(.lie, h, l) }
                testify(speaker: s.speaker, subject: about, day: chip.day, kind: seen)
            }
        }

        guard let t = s.target else { return }
        let effect = s.kind.effect
        if let reading = effect.reading {
            let read = weigh(reading)
            affinity(read.as, s.speaker, t, both: read.both, only: read.only)
        }
        attacks[s.speaker * count + t] += effect.attack
        if effect.declares { declared[s.speaker] = t }
    }

    /// What each reading of a statement is worth: how much likelier it is said of a partner than
    /// of anyone (`both`), and by a traitor of a faithful than by a faithful (`only`).
    private func weigh(_ reading: StatementEffect.Reading) -> (as: EvidenceKind, both: Double, only: Double) {
        switch reading {
        case .accuse: return (.accuse, tuning.accuseBoth, tuning.accuseOnly)
        case .rebuttal: return (.accuse, tuning.softBoth, 1)
        case .soft: return (.accuse, tuning.softBoth, tuning.softOnly)
        case .doubt: return (.accuse, tuning.doubtBoth, tuning.doubtOnly)
        case .defend: return (.defend, tuning.defendBoth, tuning.defendOnly)
        case .vouch: return (.defend, tuning.vouchBoth, tuning.vouchOnly)
        }
    }

    /// Somebody's word about today's mission. It counts in full in the worlds where the
    /// speaker is faithful and for nothing in the worlds where they are not.
    private mutating func testify(speaker: PlayerID, subject: PlayerID, day: Int, kind: SightingKind) {
        if let r = pending, r.day == day, !told.contains(where: { $0.speaker == speaker && $0.subject == subject && $0.kind == kind }) {
            told.append(Told(speaker: speaker, subject: subject, kind: kind))
        }
        let l = log(kind.suspicious ? tuning.testifyBoth : tuning.alibiBoth)
        for h in masks.indices where masks[h].has(speaker) && masks[h].has(subject) { add(.testimony, h, l) }
        if speaker != observer.id, observer.contradicts(subject: subject, day: day, claim: kind) {
            // This mind was there and knows better.
            let lie = log(tuning.lieConflict)
            for h in masks.indices where !masks[h].has(speaker) { add(.lie, h, lie) }
        }
    }

    /// Shifts this mind's private hunch about one player.
    mutating func nudge(_ p: PlayerID, by x: Double) {
        plainPrior = false
        for h in masks.indices where masks[h].has(p) { prior[h] += x }
    }

    /// The day of the last event taken in.
    var day: Int { today }

    /// Carries on as the same mind a little later: more may have been seen, and its hunches may
    /// have moved. Returns false, and changes nothing, when what has been worked out so far
    /// would not be what `later` would have worked out from the start.
    mutating func carryOn(as later: Observer) -> Bool {
        guard later.id == observer.id, later.decay == observer.decay, later.gut.count == observer.gut.count else { return false }
        if later.gut != observer.gut {
            guard plainPrior else { return false }
            for h in masks.indices {
                // In seat order, as the hypotheses were first built.
                var hunch = 0.0
                for p in 0..<count where masks[h].has(p) { hunch += later.gut[p] }
                prior[h] = hunch
            }
        }
        observer = later
        return true
    }

    // MARK: - Reading

    func belief() -> Belief {
        var m = masks
        var e = ev
        var p = prior
        if let r = pending {
            // Mission done, night still to come: weigh what was seen on its own.
            let term = missionTerm(report: r, acted: nil)
            for h in m.indices { e[h * Self.kinds + EvidenceKind.mission.rawValue] += term[h] }
        }
        if m.isEmpty {
            // Contradictory evidence should be impossible; fall back to "anyone alive".
            for i in 0..<count where aliveMask.has(i) && i != observer.id { m.append(SeatMask.seat(i)) }
            e = Array(repeating: 0, count: m.count * Self.kinds)
            p = Array(repeating: 0, count: m.count)
        }
        var logw = m.indices.map { h -> Double in
            var total = 0.0
            for j in 0..<Self.kinds { total += e[h * Self.kinds + j] }
            return observer.temper * total + p[h]
        }
        let top = logw.max() ?? 0
        logw = logw.map { exp($0 - top) }
        let z = logw.reduce(0, +)
        return Belief(masks: m, weights: logw.map { $0 / z }, detail: e, prior: p)
    }

    // MARK: - Terms

    private mutating func turn(to day: Int) {
        guard day != today else { return }
        today = day
        declared = Array(repeating: nil, count: count)
        named = Array(repeating: nil, count: count)
        ballots = []
    }

    private mutating func add(_ kind: EvidenceKind, _ h: Int, _ x: Double) {
        ev[h * Self.kinds + kind.rawValue] += x
    }

    private mutating func affinity(_ kind: EvidenceKind, _ from: PlayerID, _ to: PlayerID, both: Double, only: Double) {
        let lb = log(both), lo = log(only)
        for h in masks.indices where masks[h].has(from) {
            add(kind, h, masks[h].has(to) ? lb : lo)
        }
    }

    private mutating func keep(_ test: (SeatMask) -> Bool) {
        var m: [SeatMask] = [], e: [Double] = [], p: [Double] = []
        for h in masks.indices where test(masks[h]) {
            m.append(masks[h])
            p.append(prior[h])
            e.append(contentsOf: ev[(h * Self.kinds)..<((h + 1) * Self.kinds)])
        }
        masks = m; ev = e; prior = p
    }

    /// Somebody alive has just joined the traitors. A lone traitor picks the cover they
    /// need most, so the less suspected a player was, the likelier they are the recruit.
    private mutating func recruit() {
        plainPrior = false
        let before = belief()
        var m: [SeatMask] = [], e: [Double] = [], p: [Double] = []
        for h in masks.indices {
            for r in 0..<count where aliveMask.has(r) && !masks[h].has(r) && r != observer.id {
                m.append(masks[h] | SeatMask.seat(r))
                p.append(prior[h] + observer.gut[r] - tuning.recruitBias * before.marginal(r))
                e.append(contentsOf: ev[(h * Self.kinds)..<((h + 1) * Self.kinds)])
            }
        }
        if !m.isEmpty { masks = m; ev = e; prior = p }
    }

    private mutating func motive(_ victim: PlayerID) {
        for h in masks.indices {
            let team = masks[h]
            var total = 0.0
            var mine = 0.0
            for c in 0..<count where aliveMask.has(c) && !team.has(c) {
                var a = 0.0
                for t in 0..<count where team.has(t) && aliveMask.has(t) { a += attacks[c * count + t] }
                let w = exp(tuning.motive * min(a, 3))
                total += w
                if c == victim { mine = w }
            }
            if total > 0, mine > 0 { add(.motive, h, log(mine / total)) }
        }
    }

    /// Joint likelihood, per team, of what was seen during the day's mission and of the night
    /// that followed. `acted` is whether the traitors murdered or recruited, nil while the night
    /// is still to come.
    private func missionTerm(report: MissionReport, acted: Bool?) -> [Double] {
        // What this mind saw for itself of each player, as a ratio of "used the shadow's hand"
        // to "did not".
        var own = Array(repeating: 1.0, count: count)
        var ownSeen = Array(repeating: 0, count: count)
        for s in observer.sightings where s.day == report.day && ownSeen[s.subject] & (1 << s.kind.index) == 0 {
            ownSeen[s.subject] |= 1 << s.kind.index
            own[s.subject] *= tuning.sight(s.kind)
        }

        // How likely the day's result is with the hand in play and without, and how much of that
        // the hand accounts for. Whether the traitors then had their night adds nothing: it
        // follows from the result.
        let a = tuning.attemptRate
        let with = report.groupWon ? 1 - tuning.sinkRate : tuning.sinkRate
        let without = report.groupWon ? 1 - tuning.baseLoss : tuning.baseLoss
        let quiet = (1 - a) * without
        return masks.map { mask in
            let team = mask & aliveAtMission
            guard team != 0 else { return acted == true ? -6 : 0 }
            var sum = 0.0
            var members = 0
            for t in 0..<count where team.has(t) {
                members += 1
                var f = own[t]
                var seen = ownSeen[t]
                // Take the word of anyone this world has down as faithful.
                for w in told where w.subject == t && !mask.has(w.speaker) && seen & (1 << w.kind.index) == 0 {
                    seen |= 1 << w.kind.index
                    f *= tuning.sight(w.kind)
                }
                sum += f
            }
            let mean = sum / Double(members)
            // Scaled so that a day on which nothing was seen of anyone says nothing.
            return log((quiet + a * with * mean) / (quiet + a * with))
        }
    }
}

enum Inference {
    static func compute(view: TableView, observer: Observer) -> Belief {
        compute(log: view.log, count: view.count, observer: observer, tuning: view.tuning)
    }

    static func compute(log: [PublicEvent], count n: Int, observer: Observer, tuning: BeliefTuning = BeliefTuning()) -> Belief {
        var replay = Replay(count: n, observer: observer, tuning: tuning)
        replay.feed(log)
        return replay.belief()
    }
}

/// What a mind has already worked through of the public record, kept so the next question
/// starts from there and not from the first day. It only ever saves work: whatever it hands
/// back is exactly what replaying the whole record would give, or it starts again.
struct Recall {
    enum Whose: Hashable {
        /// The mind's own reading, as an honest player in its seat.
        case own
        /// A neutral onlooker's.
        case anyone
        /// This mind's model of another seat's.
        case listener(PlayerID)
    }

    private struct Kept {
        var replay: Replay
        /// How many events of the record it has taken in, and the record's mark of them.
        var fed: Int
        var mark: Int
        /// What the observer had seen up to the last day taken in, which is all that has been used.
        var seen: [Sighting]
    }

    private var kept: [Whose: Kept] = [:]

    /// The replay `observer` would have after everything in `record`.
    mutating func replay(_ whose: Whose, of record: PublicRecord, seats: Int, observer: Observer,
                         tuning: BeliefTuning = BeliefTuning()) -> Replay {
        var k: Kept
        if var old = kept[whose], old.fed <= record.count, record.mark(after: old.fed) == old.mark,
           old.replay.tuning == tuning, observer.sightings.filter({ $0.day <= old.replay.day }) == old.seen,
           old.replay.carryOn(as: observer) {
            k = old
        } else {
            k = Kept(replay: Replay(count: seats, observer: observer, tuning: tuning), fed: 0, mark: 0, seen: [])
        }
        if k.fed < record.count {
            for event in record.events[k.fed...] { k.replay.feed(event) }
            k.fed = record.count
            k.mark = record.mark(after: k.fed)
        }
        k.seen = observer.sightings.filter { $0.day <= k.replay.day }
        kept[whose] = k
        return k.replay
    }

    mutating func belief(_ whose: Whose, at view: TableView, observer: Observer) -> Belief {
        replay(whose, of: view.record, seats: view.count, observer: observer, tuning: view.tuning).belief()
    }
}
