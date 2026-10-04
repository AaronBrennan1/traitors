import Foundation

/// An honest player's odd moment, or what a bot does with it: somewhere to go and something to do there.
struct Errand {
    var kind: SightingKind
    var start: Double
    var pos: Vec2?
    var spot: Int?
    var dwell: Double
    var timer = 0.0
    var arrived = false
}

/// One player in the arena.
final class ArenaActor {
    let seat: ArenaSeat
    var id: PlayerID { seat.id }
    var pos = Vec2.zero
    var vel = Vec2.zero
    /// Height off the ground, for the stage.
    var z = 0.0
    var stun = 0.0
    /// What is in their hands, in the game's own terms. 0 is nothing.
    var carry = 0
    /// A second number for the game to keep per player.
    var aux = 0.0

    // Interaction.
    var wantsInteract = false
    var hold = 0.0
    var holdNeed = 1.0
    var holdSpot = -1
    var holdSeen: SeatMask = 0
    /// Interact has to be let go and pressed again after something is done.
    var latched = false
    /// Spot of the last thing finished, for a bot waiting on it.
    var finished = -1

    // Sight, refreshed five times a second.
    var seenBy: SeatMask = 0
    var newViewers: SeatMask = 0
    /// Seconds since anybody last had them in sight.
    var alone = 0.0

    // Bots.
    var wait = 0.0
    var plan = 0
    var goal: Vec2?
    var path: [Vec2] = []
    var pathGoal: Vec2?
    var errands: [Errand] = []
    var questStart = 0.0
    var questCool = 0.0
    var questLurk = 0.0
    var questTried = false
    var spooks = 0

    init(_ seat: ArenaSeat) { self.seat = seat }
}

/// The rules and the state of one mini-game, with nothing in it that draws. A stage shows it and
/// the same code plays it headless. Each game is a subclass.
class ArenaCore {
    static let tick = 1.0 / 30

    let setup: ArenaSetup
    let spec: MissionSpec
    var rng: SeededRNG
    let totalTime: Double
    private(set) var time = 0.0
    var timeLeft: Double { max(0, totalTime - time) }
    /// 0 at the start of play, 1 when the clock runs out.
    var progress: Double { time / totalTime }
    private(set) var finished = false

    var actors: [ArenaActor] = []
    /// The human, while they are the one playing their seat.
    private(set) var human: ArenaActor?
    var input = ArenaInput()

    /// The size of the arena in points.
    var size = Vec2(390, 522)
    var grid: ArenaGrid?
    /// Goes up whenever the walls move, so a stage knows to redraw them.
    var gridVersion = 0
    /// How far anyone can see.
    var vision = 150.0
    /// Things that hide whatever is behind or inside them: fog, crowds, dust.
    var veils: [(pos: Vec2, radius: Double)] = []
    var spots: [Spot] = []
    var cover: [CoverWindow] = []
    private(set) var coverActive = false

    private(set) var counts: [PlayerID: Int] = [:]
    private(set) var bonus = 0
    /// How many pieces the side quest has.
    var questGoal = 1
    private(set) var questProgress = 0
    private(set) var questBy: PlayerID?

    var ledger: MissionLedger
    var cues: [ArenaCue] = []
    private var sightClock = 0.0

    var teamTotal: Int { counts.values.reduce(0, +) + bonus }
    var teamGoal: Int { spec.teamGoal(alive: actors.count) }

    init(_ setup: ArenaSetup) {
        self.setup = setup
        spec = setup.kind.spec
        rng = SeededRNG(seed: setup.seed)
        totalTime = spec.seconds(day: setup.day)
        ledger = MissionLedger(seats: setup.cast.map(\.id))
        actors = setup.cast.map(ArenaActor.init)
        for a in actors {
            counts[a.id] = 0
            if a.seat.isHuman, !setup.autopilot { human = a }
        }
        questGoal = setup.questSteps
    }

    /// Call at the end of a subclass's init, once the arena is laid out.
    func ready() {
        ledger.cover = cover
        var dice = SeededRNG.derived(setup.seed, 5)
        for a in actors {
            a.questStart = totalTime * dice.range(0.12, 0.4)
            a.wait = dice.range(0, 0.6)
            guard isBot(a) else { continue }
            for kind in SightingKind.allCases where kind.suspicious {
                let rate = SightingModel.baseline(kind) * SightingModel.quirk(seed: setup.quirkSeed, player: a.id, kind: kind)
                guard dice.chance(rate), var errand = errand(kind, for: a) else { continue }
                errand.start = totalTime * dice.range(0.12, 0.8)
                a.errands.append(errand)
            }
            a.errands.sort { $0.start < $1.start }
        }
        refreshSight()
    }

    // MARK: - For the games to override

    /// One step of the game: the world, the bots and the human's movement.
    func tick(_ dt: Double) {}
    func props() -> [Prop] { [] }
    func zone(of a: ArenaActor) -> UInt8 { Zone.open }
    /// Whether a player may use something right now.
    func canUse(_ s: Spot, _ a: ArenaActor) -> Bool { true }
    func holdTime(_ s: Spot, _ a: ArenaActor) -> Double { s.hold }
    func used(_ s: Spot, _ a: ArenaActor) {}
    func aborted(_ s: Spot, _ a: ArenaActor) {}
    /// Somewhere that does nothing for the mission, for an honest wander.
    func idlePoint(for a: ArenaActor) -> Vec2? { nil }
    /// Something harmless to fiddle with that has nothing to do with the mission.
    func decoy(for a: ArenaActor) -> Spot? { nil }
    /// Somewhere well away from everyone.
    func farPoint(for a: ArenaActor) -> Vec2? { nil }

    func sees(_ w: ArenaActor, _ p: ArenaActor) -> Bool {
        let reach = coverActive ? coverVision : vision
        guard w.pos.distance(to: p.pos) <= reach else { return false }
        if let grid, !grid.clear(w.pos, p.pos) { return false }
        for v in veils where segmentNear(w.pos, p.pos, v.pos) < v.radius && w.pos.distance(to: v.pos) > v.radius * 0.6 { return false }
        return true
    }

    /// How far anyone can see while the day's cover is on.
    var coverVision: Double { vision }

    /// How far the human can see right now, in the games where the rest is hidden from them.
    var sightRadius: Double? { nil }
    /// Whether players the human cannot see are left off the screen.
    var hidesUnseen: Bool { sightRadius != nil }
    /// Whether the Interact button has anything to offer a player right now.
    func canInteract(_ a: ArenaActor) -> Bool { usable(by: a) != nil }
    /// Something of the player's own to keep an eye on: air, sliotars left.
    func meter(for a: ArenaActor) -> (label: String, value: Double)? { nil }

    // MARK: - Roles

    func isBot(_ a: ArenaActor) -> Bool { a !== human }
    func isQuester(_ a: ArenaActor) -> Bool { setup.questers.contains(a.id) }
    /// Whether to show the marks only a traitor on the side quest can see.
    var questVisible: Bool { human.map(isQuester) ?? false }
    var questOpen: Bool { questBy == nil }
    func actor(_ id: PlayerID) -> ArenaActor? { actors.first { $0.id == id } }
    func count(of a: ArenaActor) -> Int { counts[a.id] ?? 0 }

    // MARK: - Stepping

    func step(_ dt: Double) {
        guard !finished else { return }
        time += dt
        let on = cover.contains { time >= $0.start && time < $0.end }
        if on != coverActive {
            coverActive = on
            log(on ? .coverStart : .coverEnd, nil)
        }
        for a in actors {
            a.stun = max(0, a.stun - dt)
            a.wait -= dt
            a.questCool = max(0, a.questCool - dt)
        }
        tick(dt)
        interactions(dt)
        sightClock += dt
        if sightClock >= 1.0 / Double(MissionLedger.hz) {
            sightClock -= 1.0 / Double(MissionLedger.hz)
            refreshSight()
            ledger.sample(x: actors.map(\.pos.x), y: actors.map(\.pos.y), zone: actors.map(zone(of:)), seen: actors.map(\.seenBy))
        }
        if time >= totalTime { finished = true }
    }

    private func refreshSight() {
        for p in actors {
            var mask: SeatMask = 0
            for w in actors where w !== p && sees(w, p) { mask |= SeatMask.seat(w.id) }
            p.newViewers = mask & ~p.seenBy
            p.seenBy = mask
            p.alone = mask == 0 ? p.alone + 1.0 / Double(MissionLedger.hz) : 0
        }
    }

    private func interactions(_ dt: Double) {
        for a in actors {
            let pressing = (isBot(a) ? a.wantsInteract : input.interact) && a.stun <= 0
            if !pressing { a.latched = false }
            var spot: Spot?
            if pressing, !a.latched {
                if a.holdSpot >= 0, let s = spots.first(where: { $0.id == a.holdSpot }), inReach(s, a), canUse(s, a) {
                    spot = s
                } else {
                    spot = usable(by: a)
                }
            }
            if let s = spot {
                if a.holdSpot != s.id {
                    drop(a)
                    a.holdSpot = s.id
                    a.holdNeed = holdTime(s, a)
                    a.holdSeen = 0
                    log(.interactStart, a, a: s.id, b: s.offMission ? SightingDeriver.offMission : 0)
                }
                a.hold += dt
                a.holdSeen |= a.seenBy
                if a.hold >= a.holdNeed {
                    log(.interactDone, a, a: s.id, b: s.offMission ? SightingDeriver.offMission : 0, seen: a.holdSeen)
                    let seen = a.holdSeen
                    a.hold = 0
                    a.holdSpot = -1
                    a.latched = !isBot(a)
                    a.finished = s.id
                    a.holdSeen = seen
                    used(s, a)
                }
            } else {
                drop(a)
            }
        }
    }

    /// Lets go of whatever was being held, half done.
    private func drop(_ a: ArenaActor) {
        guard a.holdSpot >= 0 else { return }
        if let s = spots.first(where: { $0.id == a.holdSpot }) {
            if a.hold > 0.25 { log(.interactAbort, a, a: s.id, b: s.offMission ? SightingDeriver.offMission : 0, seen: a.holdSeen | a.seenBy) }
            aborted(s, a)
        }
        a.hold = 0
        a.holdSpot = -1
    }

    func inReach(_ s: Spot, _ a: ArenaActor) -> Bool { a.pos.distance(to: s.pos) <= s.reach }

    /// The nearest thing in reach a player could use, which is what the Interact button is offering.
    func usable(by a: ArenaActor) -> Spot? {
        spots.filter { inReach($0, a) && canUse($0, a) }.min { $0.pos.distance(to: a.pos) < $1.pos.distance(to: a.pos) }
    }

    // MARK: - Scoring and the side quest

    func addCount(_ n: Int, for a: ArenaActor, at p: Vec2? = nil) {
        let before = count(of: a)
        let after = min(spec.steps, max(0, before + n))
        guard after != before else { return }
        counts[a.id] = after
        log(.scored, a, a: after - before)
        cues.append(.popup(after > before ? "+\(after - before)" : "\(after - before)", p ?? a.pos, seat: a.id, bad: after < before))
    }

    /// Something for the team that is nobody's in particular.
    func addBonus(_ n: Int, at p: Vec2, _ text: String? = nil) {
        bonus = max(0, bonus + n)
        cues.append(.popup(text ?? (n > 0 ? "TEAM +\(n)" : "TEAM \(n)"), p, seat: nil, bad: n < 0))
    }

    /// One more piece of the side quest done, by anyone on it. Whoever does the last piece earns the murder.
    func questStep(_ a: ArenaActor, seen: SeatMask? = nil) {
        guard isQuester(a), questBy == nil else { return }
        questProgress += 1
        log(.questStep, a, seen: seen ?? a.seenBy)
        if questProgress >= questGoal {
            questBy = a.id
            log(.questDone, a)
        }
    }

    func questUndo() {
        guard questBy == nil, questProgress > 0 else { return }
        questProgress -= 1
    }

    // MARK: - The record

    func log(_ code: EventCode, _ a: ArenaActor?, a x: Int = 0, b y: Int = 0, seen: SeatMask? = nil, heardWithin: Double? = nil) {
        var heard: SeatMask = 0
        if let a, let r = heardWithin {
            for o in actors where o !== a && o.pos.distance(to: a.pos) <= r { heard |= SeatMask.seat(o.id) }
        }
        ledger.events.append(MissionEvent(tick: ledger.ticks, actor: a?.id ?? -1, code: code, a: x, b: y,
                                          seen: seen ?? a?.seenBy ?? 0, heard: heard))
    }

    /// Behaviour the game itself knows to be odd.
    func tell(_ kind: SightingKind, _ a: ArenaActor, heardWithin: Double? = nil) {
        log(.tell, a, a: kind.index, heardWithin: heardWithin)
    }

    func noteTry(_ a: ArenaActor) {
        guard !a.questTried else { return }
        a.questTried = true
        log(.questTry, a)
    }

    // MARK: - Moving

    /// Moves by a velocity, sliding along any wall in the way, and keeps inside the arena.
    func slide(_ a: ArenaActor, _ v: Vec2, _ dt: Double, radius: Double = 8) {
        a.vel = v
        var p = a.pos
        let nx = Vec2(p.x + v.x * dt, p.y)
        if !blocked(nx, radius) { p = nx }
        let ny = Vec2(p.x, p.y + v.y * dt)
        if !blocked(ny, radius) { p = ny }
        a.pos = Vec2(clamp(p.x, radius, size.x - radius), clamp(p.y, radius, size.y - radius))
    }

    private func blocked(_ p: Vec2, _ r: Double) -> Bool {
        guard let grid else { return false }
        return grid.isSolid(Vec2(p.x - r, p.y - r)) || grid.isSolid(Vec2(p.x + r, p.y - r))
            || grid.isSolid(Vec2(p.x - r, p.y + r)) || grid.isSolid(Vec2(p.x + r, p.y + r))
    }

    /// Walks a bot towards a point, round the walls where there are any. True on arrival.
    @discardableResult
    func travel(_ a: ArenaActor, to target: Vec2, speed: Double, _ dt: Double, within: Double = 3) -> Bool {
        if a.pos.distance(to: target) <= within {
            a.vel = .zero
            return true
        }
        var next = target
        if let grid, !grid.walkable(a.pos, target) {
            if a.pathGoal == nil || a.pathGoal!.distance(to: target) > 4 || a.path.isEmpty {
                a.path = grid.path(from: a.pos, to: target)
                a.pathGoal = target
            }
            // Cut every corner that can be cut.
            while a.path.count > 1, a.pos.distance(to: a.path[0]) < 5 || grid.walkable(a.pos, a.path[1]) { a.path.removeFirst() }
            guard let first = a.path.first else { a.vel = .zero; return true }
            next = first
            if a.path.count == 1, a.pos.distance(to: first) <= max(within, grid.cell * 0.75), grid.isSolid(target) {
                a.vel = .zero
                return true
            }
        }
        let d = a.pos.distance(to: next)
        let stepLength = speed * dt
        if d <= stepLength {
            a.pos = next
            a.vel = .zero
            return next == target
        }
        a.vel = (next - a.pos) * (speed / d)
        a.pos += a.vel * dt
        return false
    }

    func stand(_ a: ArenaActor) { a.vel = .zero }

    // MARK: - Bot pacing

    /// True while a bot still has scoring to do today.
    func wants(_ a: ArenaActor) -> Bool { count(of: a) < a.seat.target }

    /// 0...1: how hard a bot should be trying right now to land on its target by the end.
    func drive(_ a: ArenaActor) -> Double {
        let have = Double(count(of: a))
        guard have < Double(a.seat.target) else { return 0 }
        let due = Double(a.seat.target) * min(1, progress / 0.82)
        return clamp(0.6 + 0.4 * (due - have + 0.5), 0.2, 1)
    }

    /// True when a bot has got so far in front of its day that it should hang back for a while.
    func ahead(_ a: ArenaActor) -> Bool {
        Double(count(of: a)) >= Double(a.seat.target) * min(1, progress / 0.82) + 1
    }

    // MARK: - Honest habits

    private func errand(_ kind: SightingKind, for a: ArenaActor) -> Errand? {
        switch kind {
        case .offTask:
            return idlePoint(for: a).map { Errand(kind: kind, start: 0, pos: $0, spot: nil, dwell: SightingDeriver.offTaskSeconds + 1) }
        case .loiter:
            return Errand(kind: kind, start: 0, pos: nil, spot: nil, dwell: SightingDeriver.loiterSeconds + 1)
        case .brokeAway:
            return farPoint(for: a).map { Errand(kind: kind, start: 0, pos: $0, spot: nil, dwell: SightingDeriver.awaySeconds + 1) }
        case .startled, .atQuestObject:
            return decoy(for: a).map { Errand(kind: kind, start: 0, pos: $0.pos, spot: $0.id, dwell: kind == .startled ? 0.6 : 8) }
        case .inView:
            return nil
        }
    }

    /// Runs a bot's odd moment if one is due. True while it has the bot's attention.
    func runErrand(_ a: ArenaActor, speed: Double, _ dt: Double) -> Bool {
        guard var e = a.errands.first, time >= e.start else { return false }
        if !e.arrived {
            if let p = e.pos, !travel(a, to: p, speed: speed, dt, within: 10) {
                // Give up on anywhere that cannot be reached in good time.
                e.timer += dt
                if e.timer > 14 { a.errands.removeFirst() } else { a.errands[0] = e }
                return true
            }
            e.arrived = true
            e.timer = 0
            a.finished = -1
        }
        stand(a)
        e.timer += dt
        a.wantsInteract = e.spot != nil
        let done = e.timer >= e.dwell || (e.kind == .atQuestObject && a.finished == e.spot)
        if done {
            a.wantsInteract = false
            a.errands.removeFirst()
        } else {
            a.errands[0] = e
        }
        return true
    }

    // MARK: - The side quest, for a bot

    /// Whether a bot on the side quest should be about it yet.
    func questDue(_ a: ArenaActor) -> Bool {
        guard isBot(a), isQuester(a), questBy == nil, a.questStart.isFinite else { return false }
        if time >= a.questStart { return true }
        // Set off early to be in place when the cover comes.
        return cover.contains { $0.start > time && $0.start - time < 6 }
    }

    /// Nobody is looking, or there is cover, or there is no time left to be careful.
    func safeNow(_ a: ArenaActor) -> Bool {
        coverActive || a.alone >= 0.4 || (timeLeft < totalTime * 0.2 && a.seat.deceit > 0.45)
    }

    /// Someone has just come into view, and the bot loses its nerve.
    func spooked(_ a: ArenaActor) -> Bool {
        guard a.newViewers != 0, !coverActive, timeLeft >= totalTime * 0.2 else { return false }
        a.newViewers = 0
        guard rng.chance(1 - 0.6 * a.seat.deceit) else { return false }
        // Caught out twice, all but the coolest heads call it off for the day.
        a.spooks += 1
        if a.spooks >= 2, a.seat.deceit < 0.55 { a.questStart = .infinity }
        return true
    }

    /// Takes a bot to a spot and has it hold Interact there when the coast is clear. True while it has the bot.
    func runQuest(_ a: ArenaActor, at spot: Spot, speed: Double, _ dt: Double) -> Bool {
        guard questDue(a) else { return false }
        noteTry(a)
        if a.pos.distance(to: spot.pos) > spot.reach * 0.6 {
            a.wantsInteract = false
            travel(a, to: spot.pos, speed: speed, dt, within: spot.reach * 0.5)
            return true
        }
        stand(a)
        if a.questCool > 0 {
            a.wantsInteract = false
            return true
        }
        if a.hold > 0, a.holdSpot == spot.id {
            a.wantsInteract = !spooked(a)
            if !a.wantsInteract { a.questCool = rng.range(1.2, 2.5) }
            return true
        }
        if safeNow(a) {
            a.wantsInteract = true
            a.questLurk = 0
        } else {
            // Hanging about waiting for a moment looks worse the longer it goes on: walk off and come back.
            a.wantsInteract = false
            a.questLurk += dt
            if a.questLurk > 5 {
                a.questLurk = 0
                a.questStart = time + rng.range(5, 9)
            }
        }
        return true
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
