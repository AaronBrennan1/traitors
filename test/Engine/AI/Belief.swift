import Foundation

/// Numbers that shape how evidence is weighed. Tuned with the headless simulator.
enum Tuning {
    /// Assumed chance the traitors go for the side quest on a given day.
    static var attemptRate = 0.66
    /// Assumed chance an attempted side quest comes off.
    static var questSuccess = 0.9
    /// Assumed chance a murder is blocked by the shield.
    static var shieldRate = 0.13
    /// How strongly "the victim had gone after you" counts as motive. Small, because traitors
    /// who plan their murders avoid exactly the kills that would point back at them.
    static var motive = 0.1
    static var voteBoth = 0.75, voteOnly = 1.08
    static var accuseBoth = 0.33, accuseOnly = 1.45
    static var softBoth = 0.63, softOnly = 1.15
    static var defendBoth = 0.6, defendOnly = 1.0
    static var vouchBoth = 0.3, vouchOnly = 1.1
    static var doubtBoth = 0.85, doubtOnly = 1.05
    static var mismatch = 1.4
    /// First to name someone who turned out faithful.
    static var firstNamer = 1.3
    /// Assumed chance a traitor votes for a partner who is being banished anyway.
    static var busRate = 0.4
    static var pairCap = 2.0
    /// A traitor rarely reports a partner's odd behaviour, and readily gives one an alibi.
    static var testifyBoth = 0.5, alibiBoth = 1.6
    /// How strongly a recruiter favours whoever the table suspects least.
    static var recruitBias = 6.0
    /// Two honest witnesses flatly contradicting each other.
    static var lieConflict = 0.05
    /// How much likelier each behaviour is from a player actually on the side quest, by
    /// `SightingKind.index`. Only one traitor quests on a given day, so across all traitors
    /// these come out near 1.5, 2, 2.5, 2 and 4 against a faithful.
    static var sightLift = [2.25, 3.5, 4.75, 3.5, 8.5, 0.15]

    static func sight(_ kind: SightingKind) -> Double { sightLift[kind.index] }

    /// How ready traitors are to invent things, as a multiple of their usual rate. Sim-only.
    static var lying = 1.0
    /// How far a good defence softens the listeners, as a multiple. Sim-only.
    static var persuasion = 1.0

    /// Sets a value by name, for the simulator's `--tune` switch.
    static func set(_ name: String, _ x: Double) {
        switch name {
        case "attemptRate": attemptRate = x
        case "questSuccess": questSuccess = x
        case "shieldRate": shieldRate = x
        case "motive": motive = x
        case "voteBoth": voteBoth = x
        case "voteOnly": voteOnly = x
        case "accuseBoth": accuseBoth = x
        case "accuseOnly": accuseOnly = x
        case "defendBoth": defendBoth = x
        case "vouchBoth": vouchBoth = x
        case "softOnly": softOnly = x
        case "recruitBias": recruitBias = x
        case "mismatch": mismatch = x
        case "firstNamer": firstNamer = x
        case "busRate": busRate = x
        case "pairCap": pairCap = x
        case "testifyBoth": testifyBoth = x
        case "alibiBoth": alibiBoth = x
        case "lieConflict": lieConflict = x
        case "sightScale": sightLift = sightLift.map { $0 > 1 ? 1 + ($0 - 1) * x : $0 }
        case "lying": lying = x
        case "persuasion": persuasion = x
        default: print("unknown tuning \(name)")
        }
    }
}

/// What a particular mind brings to the evidence.
struct Observer {
    /// A faithful player knows they are not a traitor. Nil for the neutral public view.
    var id: PlayerID?
    /// Private log-odds hunch about each player.
    var gut: [Double]
    /// 0...1 exponent on the evidence; below 1 the mind under-reacts.
    var temper: Double
    /// Mission slips this mind actually spotted (day * 100 + unit). Nil = spotted all.
    var noticed: Set<Int>?
    /// How much room is left for "a traitor slipped and I missed it".
    var missFloor: Double
    /// What this mind saw for itself during missions.
    var sightings: [Sighting] = []
    /// Share of soft evidence still remembered after each night.
    var decay = 1.0
    /// How far this mind over-reads a poor score ("bad at games, so a traitor").
    var slipBias = 0.0

    static func publicView(count: Int) -> Observer {
        Observer(id: nil, gut: Array(repeating: 0, count: count), temper: 1, noticed: nil, missFloor: 0.08)
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
    let observer: Observer
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

    init(count n: Int, observer: Observer, teamSize: Int = Rules.traitors) {
        count = n
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
            affinity(.vote, voter, target, both: Tuning.voteBoth, only: Tuning.voteOnly)
            attacks[voter * count + target] += 1
            if round == 1 {
                ballots.append((voter, target))
                if let said = declared[voter], said != target {
                    let l = log(Tuning.mismatch)
                    for h in masks.indices where masks[h].has(voter) { add(.mismatch, h, l) }
                }
            }

        case .banished(_, let player, let role):
            aliveMask &= ~SeatMask.seat(player)
            if role == .traitor { keep { $0.has(player) } }
            if role == .faithful {
                keep { !$0.has(player) }
                if let first = named[player] {
                    let l = log(Tuning.firstNamer)
                    for h in masks.indices where masks[h].has(first) { add(.firstNamer, h, l) }
                }
            } else {
                // Who kept their name off a partner while the table was writing it?
                let others = Double(max(ballots.count - 1, 1))
                for b in ballots where b.target != player && b.voter != player {
                    let share = Double(ballots.filter { $0.target == player }.count) / others
                    let f = clamp((1 - Tuning.busRate) / max(1 - share, 0.05), 1 / Tuning.pairCap, Tuning.pairCap)
                    let l = log(f)
                    for h in masks.indices where masks[h].has(b.voter) && masks[h].has(player) { add(.pair, h, l) }
                }
            }
            ballots = []
            named = Array(repeating: nil, count: count)

        case .night(let day, let victim, let recruitNight):
            if recruitNight {
                if let victim {
                    // The offer was refused and the refuser was killed: they were faithful.
                    keep { !$0.has(victim) }
                    aliveMask &= ~SeatMask.seat(victim)
                } else {
                    recruit()
                }
            } else {
                if let r = pending, r.day == day {
                    let term = missionTerm(report: r, murdered: victim != nil)
                    for h in masks.indices { add(.mission, h, term[h]) }
                }
                if let victim {
                    keep { !$0.has(victim) }
                    motive(victim)
                    aliveMask &= ~SeatMask.seat(victim)
                }
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
        if let t = s.target, s.kind.names, named[t] == nil { named[t] = s.speaker }

        if let chip = s.chip, let seen = chip.sight {
            if chip.isTestimony {
                testify(speaker: s.speaker, subject: chip.subject, day: chip.day, kind: seen)
            } else if s.kind == .challenge, chip.kind == .caughtLie, let liar = s.target, let about = chip.other {
                // Two people cannot both be telling the truth here.
                let l = log(Tuning.lieConflict)
                for h in masks.indices where !masks[h].has(s.speaker) && !masks[h].has(liar) { add(.lie, h, l) }
                testify(speaker: s.speaker, subject: about, day: chip.day, kind: seen)
            }
        }

        guard let t = s.target else { return }
        switch s.kind {
        case .accuse, .callout, .challenge:
            affinity(.accuse, s.speaker, t, both: Tuning.accuseBoth, only: Tuning.accuseOnly)
            attacks[s.speaker * count + t] += 1
        case .selfDefend:
            affinity(.accuse, s.speaker, t, both: Tuning.softBoth, only: 1)
            attacks[s.speaker * count + t] += 0.5
        case .answer, .declare:
            affinity(.accuse, s.speaker, t, both: Tuning.softBoth, only: Tuning.softOnly)
            attacks[s.speaker * count + t] += 0.5
            declared[s.speaker] = t
        case .doubt:
            affinity(.accuse, s.speaker, t, both: Tuning.doubtBoth, only: Tuning.doubtOnly)
            attacks[s.speaker * count + t] += 0.25
        case .defend:
            affinity(.defend, s.speaker, t, both: Tuning.defendBoth, only: Tuning.defendOnly)
        case .vouch:
            affinity(.defend, s.speaker, t, both: Tuning.vouchBoth, only: Tuning.vouchOnly)
        default:
            break
        }
    }

    /// Somebody's word about today's mission. It counts in full in the worlds where the
    /// speaker is faithful and for nothing in the worlds where they are not.
    private mutating func testify(speaker: PlayerID, subject: PlayerID, day: Int, kind: SightingKind) {
        if let r = pending, r.day == day, !told.contains(where: { $0.speaker == speaker && $0.subject == subject && $0.kind == kind }) {
            told.append(Told(speaker: speaker, subject: subject, kind: kind))
        }
        let l = log(kind.suspicious ? Tuning.testifyBoth : Tuning.alibiBoth)
        for h in masks.indices where masks[h].has(speaker) && masks[h].has(subject) { add(.testimony, h, l) }
        if speaker != observer.id, observer.contradicts(subject: subject, day: day, claim: kind) {
            // This mind was there and knows better.
            let lie = log(Tuning.lieConflict)
            for h in masks.indices where !masks[h].has(speaker) { add(.lie, h, lie) }
        }
    }

    /// Shifts this mind's private hunch about one player.
    mutating func nudge(_ p: PlayerID, by x: Double) {
        for h in masks.indices where masks[h].has(p) { prior[h] += x }
    }

    // MARK: - Reading

    func belief() -> Belief {
        var m = masks
        var e = ev
        var p = prior
        if let r = pending {
            // Mission done, night still to come: weigh what was seen on its own.
            let term = missionTerm(report: r, murdered: nil)
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
        let before = belief()
        var m: [SeatMask] = [], e: [Double] = [], p: [Double] = []
        for h in masks.indices {
            for r in 0..<count where aliveMask.has(r) && !masks[h].has(r) && r != observer.id {
                m.append(masks[h] | SeatMask.seat(r))
                p.append(prior[h] + observer.gut[r] - Tuning.recruitBias * before.marginal(r))
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
                let w = exp(Tuning.motive * min(a, 3))
                total += w
                if c == victim { mine = w }
            }
            if total > 0, mine > 0 { add(.motive, h, log(mine / total)) }
        }
    }

    /// Joint likelihood, per team, of everything known about the day's mission (scores, what
    /// was seen, who was watched throughout) and whether a murder followed.
    private func missionTerm(report: MissionReport, murdered: Bool?) -> [Double] {
        // What this mind knows for itself about each player, as a ratio of "was on the side
        // quest" to "was not".
        var own = Array(repeating: 1.0, count: count)
        var ownSeen = Array(repeating: 0, count: count)
        for t in 0..<count where aliveAtMission.has(t) {
            guard let u = report.unitIndex(of: t) else { continue }
            let unit = report.units[u]
            let seen = unit.anomalous && (observer.noticed?.contains(report.day * 100 + u) ?? true)
            let r = clamp(unit.innocentRate, 0.05, 0.95), q = clamp(unit.questRate, 0.05, 0.95)
            if seen {
                own[t] = pow(q / r, 1 + observer.slipBias)
            } else {
                own[t] = max(observer.missFloor / r, (1 - q) / (1 - r))
            }
        }
        for s in observer.sightings where s.day == report.day && ownSeen[s.subject] & (1 << s.kind.index) == 0 {
            ownSeen[s.subject] |= 1 << s.kind.index
            own[s.subject] *= Tuning.sight(s.kind)
        }

        let a = Tuning.attemptRate, shield = Tuning.shieldRate, k = Tuning.questSuccess
        return masks.map { mask in
            let team = mask & aliveAtMission
            guard team != 0 else { return murdered == true ? -6 : 0 }
            var sum = 0.0
            var members = 0
            for t in 0..<count where team.has(t) {
                members += 1
                var f = own[t]
                var seen = ownSeen[t]
                // Take the word of anyone this world has down as faithful.
                for w in told where w.subject == t && !mask.has(w.speaker) && seen & (1 << w.kind.index) == 0 {
                    seen |= 1 << w.kind.index
                    f *= Tuning.sight(w.kind)
                }
                sum += f
            }
            let mean = sum / Double(members)
            switch murdered {
            case .some(true): return log(mean)
            case .some(false): return log((1 - a) + a * mean * ((1 - k) + k * shield))
            case .none: return log((1 - a) + a * mean)
            }
        }
    }
}

enum Inference {
    static func compute(view: TableView, observer: Observer) -> Belief {
        compute(log: view.log, count: view.count, observer: observer)
    }

    static func compute(log: [PublicEvent], count n: Int, observer: Observer) -> Belief {
        var replay = Replay(count: n, observer: observer)
        replay.feed(log)
        return replay.belief()
    }
}
