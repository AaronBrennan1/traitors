import Foundation

/// What any player can see of another across the table.
package struct Seat {
    var id: PlayerID
    var name: String
    package var alive: Bool
    /// Role shown at banishment, or `.faithful` for a murder victim. Nil while unknown.
    var revealed: Role?
    package var charisma: Double

    package init(id: PlayerID, name: String, alive: Bool, revealed: Role? = nil, charisma: Double) {
        self.id = id
        self.name = name
        self.alive = alive
        self.revealed = revealed
        self.charisma = charisma
    }
}

/// The public state of the game. Bots reason from this (plus their own private notes) and
/// are never handed the hidden roles, which is what keeps them honest.
public struct TableView {
    package var day: Int
    package var seats: [Seat]
    /// Everything said and done in front of the table, with its index kept up to date.
    package var record: PublicRecord
    /// Today's mood of the table towards each player (accusations raise it, defences lower it).
    package var heat: [Double]
    /// How evidence is weighed at this table.
    package var tuning: BeliefTuning

    package init(day: Int, seats: [Seat], record: PublicRecord, heat: [Double], tuning: BeliefTuning = BeliefTuning()) {
        self.day = day
        self.seats = seats
        self.record = record
        self.heat = heat
        self.tuning = tuning
    }

    init(day: Int, seats: [Seat], log: [PublicEvent], heat: [Double], tuning: BeliefTuning = BeliefTuning()) {
        self.init(day: day, seats: seats, record: PublicRecord(log, seats: seats.count), heat: heat, tuning: tuning)
    }

    package var log: [PublicEvent] { record.events }
    package var index: LogIndex { record.index }

    package var count: Int { seats.count }
    package var alive: [PlayerID] { seats.filter(\.alive).map(\.id) }
    package var aliveMask: SeatMask { alive.reduce(0) { $0 | SeatMask.seat($1) } }
    package func name(_ id: PlayerID) -> String { seats[id].name }

    /// How much weight the table gives a player's word, from their public record.
    func standing(_ p: PlayerID) -> Double {
        var s = 1.0
        for b in index.banishments {
            guard let role = b.role, let target = index.firstVote(day: b.day, voter: p) else { continue }
            if target == b.player { s += role == .traitor ? 0.25 : -0.12 }
        }
        s -= 0.2 * Double(index.mismatches.filter { $0.player == p }.count)
        return clamp(s, 0.4, 1.6)
    }

    /// Weight of one player's voice when they speak.
    package func voice(_ p: PlayerID) -> Double {
        (0.6 + 0.8 * seats[p].charisma) * standing(p)
    }
}

/// Everything every player at the table gets to see, in order, and the answers to the questions
/// that keep being asked of it. Appending an event is the only way it changes.
package struct PublicRecord: Codable {
    package private(set) var events: [PublicEvent] = []
    package private(set) var index: LogIndex
    /// One mark per event, each made from the event and the mark before it, so two records that
    /// agree on a mark agree on everything up to it. Only good within one run of the program.
    private var marks: [Int] = []

    package init(_ events: [PublicEvent] = [], seats: Int = Rules.seats) {
        index = LogIndex(count: seats)
        for event in events { append(event) }
    }

    package mutating func append(_ event: PublicEvent) {
        var hasher = Hasher()
        hasher.combine(marks.last ?? 0)
        hasher.combine(event)
        marks.append(hasher.finalize())
        events.append(event)
        index.add(event)
    }

    /// A mark of the first `n` events. Whoever has worked through that much of a record can tell
    /// by it, later, that this record carries on from the same beginning.
    package func mark(after n: Int) -> Int {
        n > 0 && n <= marks.count ? marks[n - 1] : 0
    }

    package var count: Int { events.count }

    // Only the events are saved. The index is worked out again from them.
    private enum CodingKeys: String, CodingKey { case events, seats }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(try c.decode([PublicEvent].self, forKey: .events), seats: try c.decode(Int.self, forKey: .seats))
    }

    package func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(events, forKey: .events)
        try c.encode(index.attacks.count, forKey: .seats)
    }
}

/// The public log, pre-sorted for the questions bots keep asking of it.
package struct LogIndex {
    package struct Banishment { package var day: Int; package var player: PlayerID; package var role: Role? }
    package struct Mismatch { package var day: Int; package var player: PlayerID; package var said: PlayerID; package var voted: PlayerID }
    /// Who answers for a banishment: who named them first, who pushed hardest, how many agreed.
    package struct Blame {
        package var day: Int
        package var player: PlayerID
        package var role: Role?
        package var firstNamer: PlayerID?
        package var pusher: PlayerID?
        package var votes: Int
        package var voters: Int
    }
    package struct Remark { package var day: Int; package var by: PlayerID; package var about: PlayerID }
    package struct Told { package var day: Int; package var by: PlayerID; package var about: PlayerID; package var kind: SightingKind }
    package struct Challenge { package var day: Int; package var by: PlayerID; package var liar: PlayerID; package var about: PlayerID? }

    package var reports: [MissionReport] = []
    package var statements: [Statement] = []
    package var banishments: [Banishment] = []
    /// Murder victims with the night (day number) they died.
    package var victims: [(day: Int, player: PlayerID)] = []
    /// votes[day][round] = voter -> target
    package var votes: [Int: [Int: [PlayerID: PlayerID]]] = [:]
    package var mismatches: [Mismatch] = []
    /// attacks[a][b]: how hard a has publicly gone after b (accusations and votes).
    package var attacks: [[Double]]
    package var blame: [Blame] = []
    /// Every time somebody staked their name on somebody else.
    package var vouches: [Remark] = []
    /// Every accusation, callout and doubt, in order.
    package var flags: [Remark] = []
    /// What people have said they saw in missions.
    package var told: [Told] = []
    package var challenges: [Challenge] = []

    // The table currently sitting: what each has said they will do, who named whom first, how
    // hard, and the first ballots.
    private var declared: [Int: [PlayerID: PlayerID]] = [:]
    private var named: [PlayerID?]
    private var push: [[Double]]
    private var ballots: [(voter: PlayerID, target: PlayerID)] = []
    private var today = 0
    private let count: Int

    init(count: Int) {
        self.count = count
        attacks = Array(repeating: Array(repeating: 0, count: count), count: count)
        named = Array(repeating: nil, count: count)
        push = Array(repeating: Array(repeating: 0.0, count: count), count: count)
    }

    init(log: [PublicEvent], count: Int) {
        self.init(count: count)
        for event in log { add(event) }
    }

    private mutating func clearTable() {
        named = Array(repeating: nil, count: count)
        push = Array(repeating: Array(repeating: 0.0, count: count), count: count)
        ballots = []
    }

    private mutating func turn(_ day: Int) {
        guard day != today else { return }
        today = day
        clearTable()
    }

    /// Takes in the next event of the log.
    mutating func add(_ event: PublicEvent) {
        switch event {
        case .mission(let r):
            turn(r.day)
            reports.append(r)
        case .statement(let s):
            turn(s.day)
            statements.append(s)
            if let chip = s.chip, let seen = chip.sight {
                if chip.isTestimony {
                    told.append(Told(day: chip.day, by: s.speaker, about: chip.subject, kind: seen))
                } else if s.kind == .challenge, let liar = s.target {
                    challenges.append(Challenge(day: s.day, by: s.speaker, liar: liar, about: chip.other))
                }
            }
            guard let t = s.target else { break }
            let effect = s.kind.effect
            if effect.names, named[t] == nil { named[t] = s.speaker }
            attacks[s.speaker][t] += effect.attack
            push[s.speaker][t] += effect.push
            if effect.declares { declared[s.day, default: [:]][s.speaker] = t }
            if effect.flags { flags.append(Remark(day: s.day, by: s.speaker, about: t)) }
            if effect.vouches { vouches.append(Remark(day: s.day, by: s.speaker, about: t)) }
        case .vote(let day, let round, let voter, let target):
            turn(day)
            votes[day, default: [:]][round, default: [:]][voter] = target
            attacks[voter][target] += 1
            if round == 1 {
                ballots.append((voter, target))
                if let said = declared[day]?[voter], said != target {
                    mismatches.append(Mismatch(day: day, player: voter, said: said, voted: target))
                }
            }
        case .banished(let day, let player, let role):
            banishments.append(Banishment(day: day, player: player, role: role))
            var pusher: PlayerID?
            var hardest = 0.0
            for a in 0..<count where a != named[player] && push[a][player] > hardest {
                hardest = push[a][player]
                pusher = a
            }
            blame.append(Blame(day: day, player: player, role: role, firstNamer: named[player], pusher: pusher,
                               votes: ballots.filter { $0.target == player }.count, voters: ballots.count))
            clearTable()
        case .night(let day, let victim, _):
            if let victim { victims.append((day, victim)) }
        case .finaleVote:
            break
        }
    }

    package func firstVote(day: Int, voter: PlayerID) -> PlayerID? {
        votes[day]?[1]?[voter]
    }

    package func statements(day: Int) -> [Statement] {
        statements.filter { $0.day == day }
    }

    /// Who a player has said today that they intend to vote for.
    package func declared(day: Int, by p: PlayerID) -> PlayerID? {
        statements.last { $0.day == day && $0.speaker == p && ($0.kind == .declare || $0.kind == .answer) }?.target
    }

    /// The last person to point at `p` today whom `p` has not yet answered.
    package func accuser(of p: PlayerID, day: Int) -> PlayerID? {
        var open: PlayerID?
        for s in statements where s.day == day {
            if s.speaker == p, s.kind == .selfDefend { open = nil }
            if s.target == p, s.kind == .accuse || s.kind == .callout || s.kind == .challenge { open = s.speaker }
        }
        return open
    }
}

package enum Chips {
    /// Citable evidence about `x`. `sightings` is what the observer saw for themselves. Strongest first.
    package static func about(_ x: PlayerID, view: TableView, suspicious: Bool, sightings: [Sighting] = []) -> [Chip] {
        let ix = view.index
        var chips: [Chip] = []
        if suspicious {
            for s in sightings where s.subject == x && s.kind.suspicious {
                chips.append(Chip(kind: .sighting, subject: x, day: s.day, sight: s.kind, strength: view.tuning.sight(s.kind) / 5))
            }
            for b in ix.banishments {
                guard let role = b.role, let target = ix.firstVote(day: b.day, voter: x) else { continue }
                if role == .faithful, target == b.player {
                    chips.append(Chip(kind: .votedOutFaithful, subject: x, day: b.day, other: b.player, strength: 0.5))
                }
                if role == .traitor, target != b.player {
                    chips.append(Chip(kind: .sparedTraitor, subject: x, day: b.day, other: b.player, strength: 1.0))
                }
            }
            for b in ix.blame where b.role == .faithful {
                if b.firstNamer == x {
                    chips.append(Chip(kind: .firstNamed, subject: x, day: b.day, other: b.player, strength: 0.9))
                } else if b.pusher == x {
                    chips.append(Chip(kind: .pushedHardest, subject: x, day: b.day, other: b.player, strength: 0.7))
                }
            }
            for b in ix.banishments where b.role == .traitor {
                if let v = ix.vouches.first(where: { $0.by == x && $0.about == b.player }) {
                    chips.append(Chip(kind: .sworeBy, subject: x, day: v.day, other: b.player, strength: 1.4))
                } else if let s = ix.statements.first(where: { $0.speaker == x && $0.kind == .defend && $0.target == b.player }) {
                    chips.append(Chip(kind: .defendedTraitor, subject: x, day: s.day, other: b.player, strength: 1.2))
                }
            }
            for c in ix.challenges where c.liar == x {
                chips.append(Chip(kind: .caughtLie, subject: x, day: c.day, other: c.about, strength: 1.3))
            }
            for v in ix.victims where ix.attacks[v.player][x] >= 1 {
                chips.append(Chip(kind: .victimSuspected, subject: x, day: v.day, other: v.player, strength: 0.8))
            }
            for m in ix.mismatches where m.player == x {
                chips.append(Chip(kind: .sayVote, subject: x, day: m.day, other: m.voted, strength: 0.7))
            }
            chips.append(Chip(kind: .gut, subject: x, day: view.day, strength: 0.2))
        } else {
            for s in sightings where s.subject == x && s.kind == .inView {
                chips.append(Chip(kind: .inSight, subject: x, day: s.day, sight: .inView, strength: 1.1))
            }
            for b in ix.banishments where b.role == .traitor {
                if ix.firstVote(day: b.day, voter: x) == b.player {
                    chips.append(Chip(kind: .votedTraitor, subject: x, day: b.day, other: b.player, strength: 1.0))
                }
                if let s = ix.statements.first(where: { $0.speaker == b.player && $0.kind == .accuse && $0.target == x }) {
                    chips.append(Chip(kind: .accusedByTraitor, subject: x, day: s.day, other: b.player, strength: 0.7))
                }
                if let f = ix.flags.first(where: { $0.by == x && $0.about == b.player && $0.day < b.day }) {
                    chips.append(Chip(kind: .flaggedEarly, subject: x, day: f.day, other: b.player, strength: 0.8))
                }
            }
            for b in ix.blame where b.role == .traitor && b.firstNamer == x {
                chips.append(Chip(kind: .firstOnTraitor, subject: x, day: b.day, other: b.player, strength: 1.1))
            }
            chips.append(Chip(kind: .gut, subject: x, day: view.day, strength: 0.2))
        }
        return chips.sorted { $0.strength > $1.strength }
    }

    /// Whether a chip that rests on the public record is actually true. Anything a player
    /// claims to have seen cannot be checked this way.
    static func holds(_ chip: Chip, view: TableView) -> Bool {
        if chip.sight != nil || chip.kind == .gut { return true }
        if chip.kind == .tableAgreed {
            return view.index.blame.contains { $0.player == chip.other && $0.day == chip.day && $0.votes == chip.unit }
        }
        return about(chip.subject, view: view, suspicious: chip.kind.isSuspicious)
            .contains { $0.kind == chip.kind && $0.day == chip.day && $0.other == chip.other }
    }
}
