import Foundation

/// What any player can see of another across the table.
struct Seat {
    var id: PlayerID
    var name: String
    var alive: Bool
    /// Role shown at banishment, or `.faithful` for a murder victim. Nil while unknown.
    var revealed: Role?
    var charisma: Double
}

/// The public state of the game. Bots reason from this (plus their own private notes) and
/// are never handed the hidden roles, which is what keeps them honest.
struct TableView {
    var day: Int
    var seats: [Seat]
    var log: [PublicEvent]
    /// Today's mood of the table towards each player (accusations raise it, defences lower it).
    var heat: [Double]
    var index: LogIndex

    init(day: Int, seats: [Seat], log: [PublicEvent], heat: [Double]) {
        self.day = day
        self.seats = seats
        self.log = log
        self.heat = heat
        self.index = LogIndex(log: log, count: seats.count)
    }

    var count: Int { seats.count }
    var alive: [PlayerID] { seats.filter(\.alive).map(\.id) }
    var aliveMask: SeatMask { alive.reduce(0) { $0 | SeatMask.seat($1) } }
    func name(_ id: PlayerID) -> String { seats[id].name }

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
    func voice(_ p: PlayerID) -> Double {
        (0.6 + 0.8 * seats[p].charisma) * standing(p)
    }
}

/// The public log, pre-sorted for the questions bots keep asking of it.
struct LogIndex {
    struct Banishment { var day: Int; var player: PlayerID; var role: Role? }
    struct Mismatch { var day: Int; var player: PlayerID; var said: PlayerID; var voted: PlayerID }
    /// Who answers for a banishment: who named them first, who pushed hardest, how many agreed.
    struct Blame {
        var day: Int
        var player: PlayerID
        var role: Role?
        var firstNamer: PlayerID?
        var pusher: PlayerID?
        var votes: Int
        var voters: Int
    }
    struct Remark { var day: Int; var by: PlayerID; var about: PlayerID }
    struct Told { var day: Int; var by: PlayerID; var about: PlayerID; var kind: SightingKind }
    struct Challenge { var day: Int; var by: PlayerID; var liar: PlayerID; var about: PlayerID? }

    var reports: [MissionReport] = []
    var statements: [Statement] = []
    var banishments: [Banishment] = []
    /// Murder victims with the night (day number) they died.
    var victims: [(day: Int, player: PlayerID)] = []
    /// votes[day][round] = voter -> target
    var votes: [Int: [Int: [PlayerID: PlayerID]]] = [:]
    var mismatches: [Mismatch] = []
    /// attacks[a][b]: how hard a has publicly gone after b (accusations and votes).
    var attacks: [[Double]]
    var blame: [Blame] = []
    /// Every time somebody staked their name on somebody else.
    var vouches: [Remark] = []
    /// Every accusation, callout and doubt, in order.
    var flags: [Remark] = []
    /// What people have said they saw in missions.
    var told: [Told] = []
    var challenges: [Challenge] = []

    init(log: [PublicEvent], count: Int) {
        attacks = Array(repeating: Array(repeating: 0, count: count), count: count)
        var declared: [Int: [PlayerID: PlayerID]] = [:]
        // The table currently sitting: who named whom first, how hard, and the first ballots.
        var named: [PlayerID?] = Array(repeating: nil, count: count)
        var push = Array(repeating: Array(repeating: 0.0, count: count), count: count)
        var ballots: [(voter: PlayerID, target: PlayerID)] = []
        var today = 0
        func turn(_ day: Int) {
            guard day != today else { return }
            today = day
            named = Array(repeating: nil, count: count)
            push = Array(repeating: Array(repeating: 0.0, count: count), count: count)
            ballots = []
        }
        for event in log {
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
                if s.kind.names, named[t] == nil { named[t] = s.speaker }
                switch s.kind {
                case .accuse, .callout, .challenge:
                    attacks[s.speaker][t] += 1
                    push[s.speaker][t] += 1
                    flags.append(Remark(day: s.day, by: s.speaker, about: t))
                case .selfDefend:
                    attacks[s.speaker][t] += 0.5
                    push[s.speaker][t] += 0.5
                case .answer, .declare:
                    attacks[s.speaker][t] += 0.5
                    push[s.speaker][t] += 0.5
                    declared[s.day, default: [:]][s.speaker] = t
                case .doubt:
                    attacks[s.speaker][t] += 0.25
                    flags.append(Remark(day: s.day, by: s.speaker, about: t))
                case .vouch:
                    vouches.append(Remark(day: s.day, by: s.speaker, about: t))
                default: break
                }
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
                named = Array(repeating: nil, count: count)
                push = Array(repeating: Array(repeating: 0.0, count: count), count: count)
                ballots = []
            case .night(let day, let victim, _):
                if let victim { victims.append((day, victim)) }
            case .finaleVote:
                break
            }
        }
    }

    func firstVote(day: Int, voter: PlayerID) -> PlayerID? {
        votes[day]?[1]?[voter]
    }

    func statements(day: Int) -> [Statement] {
        statements.filter { $0.day == day }
    }

    /// Who a player has said today that they intend to vote for.
    func declared(day: Int, by p: PlayerID) -> PlayerID? {
        statements.last { $0.day == day && $0.speaker == p && ($0.kind == .declare || $0.kind == .answer) }?.target
    }

    /// The last person to point at `p` today whom `p` has not yet answered.
    func accuser(of p: PlayerID, day: Int) -> PlayerID? {
        var open: PlayerID?
        for s in statements where s.day == day {
            if s.speaker == p, s.kind == .selfDefend { open = nil }
            if s.target == p, s.kind == .accuse || s.kind == .callout || s.kind == .challenge { open = s.speaker }
        }
        return open
    }
}

enum Chips {
    /// Citable evidence about `x`. `noticed` limits mission slips to those the observer spotted
    /// (nil = saw everything); `sightings` is what the observer saw for themselves. Strongest first.
    static func about(_ x: PlayerID, view: TableView, noticed: Set<Int>?, suspicious: Bool,
                      sightings: [Sighting] = []) -> [Chip] {
        let ix = view.index
        var chips: [Chip] = []
        if suspicious {
            for s in sightings where s.subject == x && s.kind.suspicious {
                chips.append(Chip(kind: .sighting, subject: x, day: s.day, sight: s.kind, strength: Tuning.sight(s.kind) / 5))
            }
            for r in ix.reports {
                guard let u = r.unitIndex(of: x), r.units[u].anomalous else { continue }
                if let noticed, !noticed.contains(r.day * 100 + u) { continue }
                // A poor score is thin evidence: plenty of faithful are simply bad at games.
                chips.append(Chip(kind: .missionSlip, subject: x, day: r.day, unit: u,
                                  strength: clamp(0.15 / r.units[u].innocentRate, 0.3, 0.7)))
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
            let played = ix.reports.filter { $0.unitIndex(of: x) != nil }
            if !played.isEmpty, played.allSatisfy({ !$0.units[$0.unitIndex(of: x)!].anomalous }) {
                chips.append(Chip(kind: .cleanMissions, subject: x, day: view.day, strength: 0.4))
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
        return about(chip.subject, view: view, noticed: nil, suspicious: chip.kind.isSuspicious)
            .contains { $0.kind == chip.kind && $0.day == chip.day && $0.other == chip.other }
    }
}
