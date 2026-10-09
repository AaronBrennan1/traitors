import Foundation
import TraitorsCore

/// The rules and the state of one run of the gauntlet, with nothing in it that draws. Everyone
/// carries gold from the hoard up to the vault through the traps, and what reaches the vault
/// goes on one pile. The screen shows it and the same code plays it headless.
public final class Gauntlet {
    /// Steps a crumbling tile holds after the first foot on it, and steps it stays gone.
    static let crackTicks = Feel.ticks(0.6)
    static let goneTicks = Feel.ticks(4)

    public let setup: ArenaSetup
    /// The numbers the bots and the works go by.
    var tuning: ArenaTuning { setup.tuning.arena }
    public let course: Course
    var rng: SeededRNG
    /// Steps on the clock.
    let totalTicks: Int
    /// What the company has to get into the vault between them.
    public let goal: Int
    private(set) var tick = 0
    public private(set) var finished = false
    /// 0, 1 or 2: the traps quicken and more of them wake as the round goes on.
    private(set) var act = 0

    public package(set) var runners: [Runner] = []
    public package(set) var hazards: [Hazard]
    public package(set) var bags = Array(repeating: Bag(), count: 48)
    /// Crumbling tiles by tile index: 0 sound, above 0 steps until it goes, below 0 steps until it is back.
    public package(set) var floor: [Int16]
    /// Steps of darkness left in each sconce's stretch, and whose hand put it out, or -1.
    public package(set) var dark: [Int]
    var darkBy: [Int]
    /// Everything in the vault, on one pile. Nobody's own share is part of the result.
    public package(set) var teamTotal = 0
    /// Where the last bags went in, for a screen with nobody of its own to follow.
    var lead: Vec2?
    /// Steps the vault has been sealing for.
    private(set) var seal = 0
    private(set) var overtime = false
    /// Whether a full pile seals the vault and ends the round early. Off for measuring a course.
    package var seals = true

    /// The stick of whoever is playing the human's seat.
    public package(set) var input = ArenaInput()
    public package(set) var ledger: MissionLedger
    public package(set) var cues: [ArenaCue] = []
    var bots: [Bot] = []
    /// The human's place in `runners`, while they are the one playing their seat.
    public let human: Int?
    /// Private: bags each seat's hand has cost the company, in the order of `runners`.
    public package(set) var loss: [Double]
    /// Private: how often each seat used the hand.
    public package(set) var acts: [Int]
    /// Steps at which the castle's own mechanisms slip, soonest first.
    var misfires: [Int] = []
    var draught = -1
    var vaultSlips = false

    /// `course` is only ever given by a test that wants a floor of its own.
    init(_ setup: ArenaSetup, course laid: Course? = nil) {
        self.setup = setup
        course = laid ?? Course(setup.kind)
        rng = SeededRNG(seed: setup.seed)
        let spec = setup.kind.spec
        totalTicks = Feel.ticks(spec.seconds(day: setup.day))
        goal = spec.teamGoal(alive: setup.cast.count, handicap: setup.tuning.mission.handicap)
        hazards = course.hazards
        for i in hazards.indices { hazards[i].sticks = setup.tuning.arena.sticks }
        floor = Array(repeating: 0, count: course.tiles.count)
        dark = Array(repeating: 0, count: course.bands.count)
        darkBy = Array(repeating: -1, count: course.bands.count)
        ledger = MissionLedger(seats: setup.cast.map(\.id))
        loss = Array(repeating: 0, count: setup.cast.count)
        acts = Array(repeating: 0, count: setup.cast.count)
        human = setup.autopilot ? nil : setup.cast.firstIndex { $0.isHuman }

        // Everyone starts in a row just above the hoard.
        let n = setup.cast.count
        let y = course.hoard.y + Course.cell * 1.5
        for (i, seat) in setup.cast.enumerated() {
            let x = n > 1 ? 50 + Double(i) * (course.size.x - 100) / Double(n - 1) : course.size.x / 2
            runners.append(Runner(seat, at: Vec2(x, y)))
        }
        for h in hazards.indices { _ = hazards[h].step(act: 0) }
        seatBots()
        scheduleCastle()
        refreshSight()
    }

    // MARK: - The clock

    public var time: Double { Double(tick) * Feel.tick }
    public var timeLeft: Double { Double(max(0, totalTicks - tick)) * Feel.tick }
    /// 0 at the start of play, 1 when the clock runs out.
    var progress: Double { min(1, Double(tick) / Double(totalTicks)) }
    var hoardOpen: Bool { tick < totalTicks }
    /// 0...1 while the vault is sealing.
    package var sealing: Double { Double(seal) / Double(Feel.seal) }
    public var won: Bool { teamTotal >= goal }

    public func index(of seat: PlayerID) -> Int? { runners.firstIndex { $0.id == seat } }

    /// The human pressed Dash.
    public func press() {
        if let h = human { runners[h].buffer = Feel.buffer }
    }

    func press(_ i: Int) { runners[i].buffer = Feel.buffer }

    // MARK: - Stepping

    public func step() {
        guard !finished else { return }
        tick += 1
        let now = progress < Feel.acts[0] ? 0 : progress < Feel.acts[1] ? 1 : 2
        if now != act {
            act = now
            cues.append(.act(act))
        }
        for h in hazards.indices {
            switch hazards[h].step(act: act) {
            case .warned: cues.append(.warned(h))
            case .fired: cues.append(.fired(h))
            default: break
            }
        }
        castle()
        for t in course.crumbles where floor[t] != 0 {
            if floor[t] == 1 {
                floor[t] = -Int16(Gauntlet.goneTicks)
                cues.append(.gave(course.centre(of: t)))
            } else {
                floor[t] += floor[t] > 0 ? -1 : 1
            }
        }
        for i in runners.indices {
            if i == human { runners[i].move = input.move } else { think(i) }
        }
        for i in runners.indices { move(i) }
        separate()
        for i in runners.indices { settle(i) }
        ageBags()
        if tick % Feel.sampleEvery == 0 {
            refreshSight()
            ledger.sample(x: runners.map(\.pos.x), y: runners.map(\.pos.y), zone: runners.map { course.zone(at: $0.pos) },
                          seen: runners.map(\.seenBy))
        }
        flow()
    }

    /// The end of the round: the vault sealing on a full pile, or the clock, with a little grace
    /// for anyone still on their way up with gold.
    private func flow() {
        if seals, teamTotal >= goal {
            if seal == 0 { cues.append(.sealing) }
            seal += 1
            if seal >= Feel.seal {
                cues.append(.sealed)
                finished = true
                return
            }
        } else if seal > 0 {
            seal = 0
            cues.append(.unsealed)
        }
        guard tick >= totalTicks else { return }
        let stillComing = seal > 0 || runners.contains { $0.up && $0.carry > 0 }
        if stillComing, tick < totalTicks + Feel.overtime {
            if !overtime {
                overtime = true
                cues.append(.overtime)
            }
        } else {
            finished = true
        }
    }

    // MARK: - Sight

    /// How far anyone can see between two places right now.
    public func vision(_ a: Vec2, _ b: Vec2) -> Double {
        var v = course.vision
        for i in dark.indices where dark[i] > 0 && (course.band(i, holds: a) || course.band(i, holds: b)) {
            v = min(v, Feel.douseVision)
        }
        return v
    }

    func sees(_ w: Runner, _ p: Runner) -> Bool {
        guard w.up, p.up, w.pos.distance(to: p.pos) <= vision(w.pos, p.pos) else { return false }
        return course.grid.clear(w.pos, p.pos)
    }

    private func refreshSight() {
        for p in runners.indices {
            var mask: SeatMask = 0
            for w in runners.indices where w != p && sees(runners[w], runners[p]) { mask |= SeatMask.seat(runners[w].id) }
            runners[p].newViewers = mask & ~runners[p].seenBy
            if runners[p].newViewers != 0 { runners[p].sinceViewer = 0 }
            runners[p].seenBy = mask
        }
    }

    // MARK: - The record

    func log(_ code: EventCode, _ i: Int?, a: Int = 0, b: Int = 0) {
        ledger.events.append(MissionEvent(tick: ledger.ticks, actor: i.map { runners[$0].id } ?? -1, code: code, a: a, b: b,
                                          seen: i.map { runners[$0].seenBy } ?? 0))
    }
}

/// Shortest distance from a point to the line between two others.
func segmentNear(_ a: Vec2, _ b: Vec2, _ p: Vec2) -> Double {
    let ab = b - a
    let l2 = ab.dot(ab)
    guard l2 > 1e-9 else { return a.distance(to: p) }
    let t = clamp((p - a).dot(ab) / l2, 0, 1)
    return (a + ab * t).distance(to: p)
}
