import Foundation

/// An honest player's odd moment, as a bot in one of these games carries it out: somewhere to go
/// and how long to stay.
struct Habit {
    var kind: SightingKind
    var start: Double
    var pos: Vec2?
    var dwell: Double
    var timer = 0.0
    var arrived = false
}

/// A stretch of the game when nobody can see far: fog, a gust, a free dance.
struct CoverWindow {
    var start: Double
    var end: Double
}

/// Something the shadow's hand can work, and that goes by itself now and then.
struct Works {
    let id: Int
    var pos: Vec2
    var reach = 34.0
    /// What the screen says when it goes.
    var text = ""
}

/// One player in the arena.
final class ArenaActor {
    let seat: ArenaSeat
    var id: PlayerID { seat.id }
    var pos = Vec2.zero
    /// Where they were a step ago, for drawing in between.
    var last = Vec2.zero
    var vel = Vec2.zero
    /// Height off the ground, for the stage.
    var z = 0.0
    var lastZ = 0.0
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
    /// The button has to be let go and pressed again after something is done.
    var latched = false
    /// Spot of the last thing finished, for a bot waiting on it.
    var finished = -1

    // Sight, refreshed five times a second.
    var seenBy: SeatMask = 0
    var newViewers: SeatMask = 0
    /// Seconds since anybody last had them in sight, and since somebody new came into view.
    var alone = 0.0
    var sinceViewer = 99.0

    // What the record wants to know.
    var sinceScore = 99.0
    /// Seconds stood by something the hand could work, and at the hand-in with nothing to hand in.
    var stood = 0.0
    var atDoor = 0.0
    var cameEmpty = false
    var inDoor = false

    // Bots.
    /// What the bot means to bring home today.
    var target = 0
    var wait = 0.0
    var plan = 0
    var goal: Vec2?
    var path: [Vec2] = []
    var pathGoal: Vec2?
    var habits: [Habit] = []

    // The shadow's hand.
    var handCool = 0.0
    /// How often a bot still means to use it today.
    var handLeft = 0
    var nextAct = Double.infinity
    var handTarget = -1
    var chase = 0.0
    var lurk = 0.0
    var tries = 0

    init(_ seat: ArenaSeat) { self.seat = seat }
}

/// The rules and the state of one mini-game, with nothing in it that draws. A stage shows it and
/// the same code plays it headless. Each game is a subclass.
///
/// Everything anyone brings home goes on one pile. A bot sets out to bring home its share of the
/// company's day, and the day is one roll for all of them, so a table left alone makes its goal
/// about as often here as the dice say it should.
class ArenaCore: ArenaGame {
    static let tick = 1.0 / 30
    /// How near a witness has to be to say for certain who was standing at something when it went.
    static var witness = 60.0
    static var handCooldown = 10.0
    /// How many times a bot on the hand uses it, before its nerve is counted.
    static var sabotageActs = 3
    /// How readily a bot shows its nerves after using the hand.
    static var nerves = 0.5
    /// How often the game's own works go by themselves.
    static var slipCount = 2

    /// What an ordinary bot brings home in this game.
    class var pace: Double { 8 }
    /// How far the bots' day swings between them, in players' shares. A game with luck of its
    /// own in it asks for less, so that the two together come to what the dice assume.
    class var swing: Double { MissionRun.spread }
    /// What one use of the hand takes off the pile, or one slip of the works by themselves.
    class var handCost: Int { 3 }

    let setup: ArenaSetup
    let spec: MissionSpec
    var rng: SeededRNG
    let totalTime: Double
    private(set) var time = 0.0
    var timeLeft: Double { max(0, totalTime - time) }
    /// 0 at the start of play, 1 when the clock runs out.
    var progress: Double { time / totalTime }
    private(set) var finished = false
    /// Whole steps taken so far.
    private(set) var steps = 0
    var stepSeconds: Double { Self.tick }

    var actors: [ArenaActor] = []
    /// The human, while they are the one playing their seat.
    private(set) var human: ArenaActor?
    var humanSeat: PlayerID? { human?.id }
    var input = ArenaInput()
    /// True for the one step in which the human's press of the button lands.
    private(set) var tapped = false
    /// A strike the human let go, for the one step it lands in.
    private(set) var shot: Vec2?
    private var pressQueued = false
    private var shotQueued: Vec2?

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
    /// What the hand can work. The first is usually where the day's work is handed in.
    var works: [Works] = []
    /// Where things are handed in, in the games that have such a place.
    var dropOff: Vec2?

    private(set) var counts: [PlayerID: Int] = [:]
    private(set) var bonus = 0
    /// Private: what each seat's hand has cost the company, and how often each used it, in cast order.
    private(set) var loss: [Double]
    private(set) var acts: [Int]
    private var slips: [Double] = []

    var ledger: MissionLedger
    var cues: [ArenaCue] = []
    private var sightClock = 0.0

    var teamTotal: Int { max(0, counts.values.reduce(0, +) + bonus) }
    var goal: Int { spec.teamGoal(alive: actors.count) }
    var won: Bool { teamTotal >= goal }
    var tally: [Int] { actors.map { counts[$0.id] ?? 0 } }

    init(_ setup: ArenaSetup) {
        self.setup = setup
        spec = setup.kind.spec
        rng = SeededRNG(seed: setup.seed)
        totalTime = spec.seconds(day: setup.day)
        ledger = MissionLedger(seats: setup.cast.map(\.id))
        actors = setup.cast.map(ArenaActor.init)
        loss = Array(repeating: 0, count: setup.cast.count)
        acts = loss.map { _ in 0 }
        for a in actors {
            counts[a.id] = 0
            if a.seat.isHuman, !setup.autopilot { human = a }
        }
    }

    /// Call at the end of a subclass's init, once the arena is laid out.
    func ready() {
        var dice = SeededRNG.derived(setup.seed, 5)
        shareOut()
        for a in actors {
            a.last = a.pos
            a.lastZ = a.z
            a.wait = dice.range(0, 0.6)
            guard isBot(a) else { continue }
            for kind in SightingKind.allCases where kind.suspicious {
                let rate = SightingModel.baseline(kind) * SightingModel.quirk(seed: setup.quirkSeed, player: a.id, kind: kind)
                guard dice.chance(rate), var habit = habit(kind, for: a) else { continue }
                habit.start = totalTime * dice.range(0.12, 0.8)
                a.habits.append(habit)
            }
            a.habits.sort { $0.start < $1.start }
            if isSaboteur(a) {
                a.handLeft = Self.sabotageActs + Int(a.seat.deceit.rounded())
                a.nextAct = totalTime * dice.range(0.18, 0.3)
            }
        }
        slips = (0..<Self.slipCount).map { _ in totalTime * dice.range(0.3, 0.88) }.sorted()
        refreshSight()
    }

    /// Settles what each bot sets out to bring home. The company's day is one roll for all of
    /// them, shared out by how handy each is.
    private func shareOut() {
        let bots = actors.filter(isBot)
        guard !bots.isEmpty else { return }
        let weights = bots.map { 0.61 + 0.6 * $0.seat.skill }
        let whole = max(0, weights.reduce(0, +) * Self.pace + Self.swing * setup.form * spec.head(alive: actors.count))
        let sum = weights.reduce(0, +)
        var owed = Int(whole.rounded())
        var shares = weights.map { whole * $0 / sum }
        for (i, a) in bots.enumerated() {
            a.target = Int(shares[i])
            shares[i] -= Double(a.target)
            owed -= a.target
        }
        // What is left over goes to whoever was nearest to another one.
        for i in shares.indices.sorted(by: { shares[$0] > shares[$1] }).prefix(max(0, owed)) { bots[i].target += 1 }
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
    /// Whether the hand has anything to take from this right now.
    func worksUsable(_ w: Works) -> Bool { teamTotal >= Self.handCost }
    /// What the world does when something is worked, besides what it costs.
    func sprung(_ w: Works) {}

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
    /// Whether the button has anything to offer a player right now.
    func canInteract(_ a: ArenaActor) -> Bool { usable(by: a) != nil }
    /// Something of the player's own to keep an eye on: air, sliotars left.
    func meter(for a: ArenaActor) -> (label: String, value: Double)? { nil }

    // MARK: - Roles

    func isBot(_ a: ArenaActor) -> Bool { a !== human }
    func isSaboteur(_ a: ArenaActor) -> Bool { setup.saboteurs.contains(a.id) }
    func actor(_ id: PlayerID) -> ArenaActor? { actors.first { $0.id == id } }
    func index(of a: ArenaActor) -> Int { actors.firstIndex { $0 === a } ?? 0 }
    func count(of a: ArenaActor) -> Int { counts[a.id] ?? 0 }

    // MARK: - Stepping

    func press() { pressQueued = true }
    func shoot(_ shot: Vec2) { shotQueued = shot }

    func step() {
        guard !finished else { return }
        let dt = Self.tick
        time += dt
        steps += 1
        tapped = pressQueued
        pressQueued = false
        shot = shotQueued
        shotQueued = nil
        let on = cover.contains { time >= $0.start && time < $0.end }
        if on != coverActive {
            coverActive = on
            log(on ? .darkStart : .darkEnd, nil)
        }
        for a in actors {
            a.last = a.pos
            a.lastZ = a.z
            a.stun = max(0, a.stun - dt)
            a.wait -= dt
            a.handCool = max(0, a.handCool - dt)
            a.sinceViewer += dt
            a.sinceScore += dt
        }
        // A traitor standing still by something they could work: the press is the hand.
        if tapped, let me = human, let w = canSabotage(me) {
            sabotage(me, w)
            tapped = false
            me.latched = true
        }
        slip()
        tick(dt)
        interactions(dt)
        for a in actors { watch(a, dt) }
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
            if p.newViewers != 0 { p.sinceViewer = 0 }
            p.seenBy = mask
            p.alone = mask == 0 ? p.alone + 1.0 / Double(MissionLedger.hz) : 0
        }
    }

    private func interactions(_ dt: Double) {
        for a in actors {
            let pressing = (isBot(a) ? a.wantsInteract : input.hold) && a.stun <= 0
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
                }
                a.hold += dt
                if a.hold >= a.holdNeed {
                    a.hold = 0
                    a.holdSpot = -1
                    a.latched = !isBot(a)
                    a.finished = s.id
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
        if let s = spots.first(where: { $0.id == a.holdSpot }) { aborted(s, a) }
        a.hold = 0
        a.holdSpot = -1
    }

    func inReach(_ s: Spot, _ a: ArenaActor) -> Bool { a.pos.distance(to: s.pos) <= s.reach }

    /// The nearest thing in reach a player could use, which is what the button is offering.
    func usable(by a: ArenaActor) -> Spot? {
        spots.filter { inReach($0, a) && canUse($0, a) }.min { $0.pos.distance(to: a.pos) < $1.pos.distance(to: a.pos) }
    }

    /// The things the record notes about how somebody is carrying themselves, whoever they are.
    private func watch(_ a: ArenaActor, _ dt: Double) {
        let slow = a.vel.length < 60
        // Standing by something the hand could work, and leaving it the moment somebody looks.
        if slow, a.stun <= 0, works.contains(where: { $0.pos.distance(to: a.pos) <= $0.reach }) {
            a.stood += dt
        } else {
            if a.stood >= 0.5, a.sinceViewer <= 0.5, !slow { log(.balked, a) }
            a.stood = 0
        }
        // Walking up to where things are handed in with nothing to hand in.
        guard let door = dropOff else { return }
        let inside = door.distance(to: a.pos) <= 34
        if inside, !a.inDoor { a.cameEmpty = a.carry == 0 && a.sinceScore > 3 }
        a.inDoor = inside
        if inside, a.cameEmpty, a.carry == 0, slow {
            a.atDoor += dt
            if a.atDoor >= 0.7 {
                tell(.emptyHanded, a)
                a.cameEmpty = false
            }
        } else {
            a.atDoor = 0
        }
    }

    // MARK: - Scoring

    func addCount(_ n: Int, for a: ArenaActor, at p: Vec2? = nil) {
        let before = count(of: a)
        let after = max(0, before + n)
        guard after != before else { return }
        counts[a.id] = after
        a.sinceScore = 0
        log(.banked, a, a: after - before)
        cues.append(.popup(after > before ? "+\(after - before)" : "\(after - before)", p ?? a.pos, seat: a.id, bad: after < before))
    }

    /// Something for the team that is nobody's in particular.
    func addBonus(_ n: Int, at p: Vec2, _ text: String? = nil) {
        bonus += n
        cues.append(.popup(text ?? (n > 0 ? "TEAM +\(n)" : "TEAM \(n)"), p, seat: nil, bad: n < 0))
    }

    // MARK: - The record

    func log(_ code: EventCode, _ a: ArenaActor?, a x: Int = 0, b y: Int = 0, seen: SeatMask? = nil) {
        ledger.events.append(MissionEvent(tick: ledger.ticks, actor: a?.id ?? -1, code: code, a: x, b: y, seen: seen ?? a?.seenBy ?? 0))
    }

    /// Behaviour the game itself knows to be odd.
    func tell(_ kind: SightingKind, _ a: ArenaActor) {
        log(.tell, a, a: kind.index)
    }

    // MARK: - The shadow's hand

    /// What a press right now would work, if it would be the hand at all: a traitor, standing still, with something in reach.
    func canSabotage(_ a: ArenaActor) -> Works? {
        guard isSaboteur(a), a.handCool <= 0, a.stun <= 0 else { return nil }
        guard a === human ? input.move.length < 0.2 : a.vel.length < 25 else { return nil }
        return works.filter { $0.pos.distance(to: a.pos) <= $0.reach && worksUsable($0) }
            .min { $0.pos.distance(to: a.pos) < $1.pos.distance(to: a.pos) }
    }

    func sabotage(_ a: ArenaActor, _ w: Works) {
        a.handCool = Self.handCooldown
        acts[index(of: a)] += 1
        log(.sabotage, a, a: w.id)
        cues.append(.hand(a.id))
        spring(w, by: a)
    }

    /// Works something, whoever or whatever did it, and writes down everyone standing by it.
    /// The record of who was standing there is the same whether or not one of them did it.
    func spring(_ w: Works, by a: ArenaActor?) {
        let n = min(Self.handCost, teamTotal)
        guard n > 0 else { return }
        bonus -= n
        if let a { loss[index(of: a)] += Double(n) }
        log(.spilled, nil, a: n)
        cues.append(.popup("-\(n)", w.pos, seat: nil, bad: true))
        if !w.text.isEmpty { cues.append(.banner(w.text)) }
        cues.append(.shake)
        sprung(w)
        for j in actors where j === a || standingBy(j, w) { noteSprung(j, w) }
    }

    /// Writes down that somebody was standing by something when it went. Only somebody close can say for certain who.
    func noteSprung(_ j: ArenaActor, _ w: Works) {
        var near: SeatMask = 0
        for o in actors where o !== j && j.seenBy.has(o.id) && o.pos.distance(to: j.pos) <= Self.witness { near |= SeatMask.seat(o.id) }
        log(.sprung, j, a: w.id, seen: near)
        j.stood = 0
    }

    /// Stopped beside it for a moment, not just passing.
    func standingBy(_ a: ArenaActor, _ w: Works) -> Bool {
        a.stun <= 0 && a.stood >= 0.4 && a.pos.distance(to: w.pos) <= w.reach
    }

    /// Private: the traitor whose hand made the difference between making the goal and not.
    var sunkBy: PlayerID? {
        guard teamTotal < goal else { return nil }
        let total = loss.reduce(0, +)
        guard total > 0, Double(teamTotal) + total >= Double(goal) else { return nil }
        var best = 0
        for i in loss.indices where loss[i] > loss[best] { best = i }
        return actors[best].id
    }

    /// Lets the game's own works slip when their time comes. It waits a little for somebody to be
    /// standing by one, so that being there when it goes is something that happens to the honest too.
    private func slip() {
        guard let due = slips.first, time >= due else { return }
        let pool = works.filter(worksUsable)
        let attended = pool.first { w in actors.contains { standingBy($0, w) } }
        if let w = attended ?? (time - due > 4 && !pool.isEmpty ? pool[rng.int(pool.count)] : nil) {
            spring(w, by: nil)
            slips.removeFirst()
        } else if time - due > 8 {
            slips.removeFirst()
        }
    }

    /// Takes a bot traitor to something it can work and has it work it when the coast is clear.
    /// True while it has the bot.
    func runHand(_ a: ArenaActor, speed: Double, _ dt: Double) -> Bool {
        guard isSaboteur(a), a.handLeft > 0, time >= a.nextAct, a.handCool <= 0 else { return false }
        var target = works.first { $0.id == a.handTarget && worksUsable($0) }
        if target == nil {
            target = works.filter(worksUsable).min { $0.pos.distance(to: a.pos) < $1.pos.distance(to: a.pos) }
            a.handTarget = target?.id ?? -1
            a.chase = 0
            a.lurk = 0
        }
        guard let w = target else {
            a.nextAct = time + 2
            return false
        }
        func leave(_ lo: Double, _ hi: Double) {
            a.handTarget = -1
            a.tries += 1
            a.nextAct = time + rng.range(lo, hi)
        }
        a.wantsInteract = false
        if a.pos.distance(to: w.pos) > w.reach * 0.7 {
            a.chase += dt
            if a.chase > 12 {
                leave(3, 6)
                return false
            }
            travel(a, to: w.pos, speed: speed, dt, within: w.reach * 0.5)
            return true
        }
        stand(a)
        a.lurk += dt
        let deceit = a.seat.deceit
        // Late in the day, or after being put off twice, there is no more waiting for a quiet moment.
        let desperate = progress > 0.72 || a.tries >= 2
        // Someone has just come into view, and the bot loses its nerve.
        if a.sinceViewer < 0.25, !desperate, rng.chance(1 - 0.6 * deceit) {
            leave(4, 8)
            return false
        }
        let tolerance = deceit < 0.4 ? 0 : deceit < 0.65 ? 1 : 2
        if a.seenBy.nonzeroBitCount <= tolerance || desperate {
            guard a.lurk > 0.4 else { return true }
            sabotage(a, w)
            a.handLeft -= 1
            a.handTarget = -1
            a.tries = 0
            a.nextAct = time + Self.handCooldown + rng.range(0.5, 3)
            // A nervous hand hangs back afterwards, or ducks out of the way.
            if rng.chance(Self.nerves * (1.3 - deceit)), let h = habit(rng.chance(0.5) ? .offTask : .loiter, for: a) {
                var h = h
                h.start = time + 0.5
                a.habits.insert(h, at: 0)
            }
        } else if a.lurk > 3 {
            // Hanging about waiting for a moment looks worse the longer it goes on.
            leave(4, 8)
            return false
        }
        return true
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
            a.pos = Vec2(clamp(next.x, 4, size.x - 4), clamp(next.y, 4, size.y - 4))
            a.vel = .zero
            return a.pos.distance(to: target) <= max(within, 6)
        }
        a.vel = (next - a.pos) * (speed / d)
        a.pos += a.vel * dt
        // Wherever a bot is making for, it stays on the floor.
        a.pos = Vec2(clamp(a.pos.x, 4, size.x - 4), clamp(a.pos.y, 4, size.y - 4))
        return false
    }

    func stand(_ a: ArenaActor) { a.vel = .zero }

    // MARK: - Bot pacing

    /// True while a bot still has scoring to do today.
    func wants(_ a: ArenaActor) -> Bool { count(of: a) < a.target }

    /// 0...1: how hard a bot should be trying right now to land on its target by the end.
    func drive(_ a: ArenaActor) -> Double {
        let have = Double(count(of: a))
        guard have < Double(a.target) else { return 0 }
        let due = Double(a.target) * min(1, progress / 0.82)
        return clamp(0.6 + 0.4 * (due - have + 0.5), 0.2, 1)
    }

    /// True when a bot has got so far in front of its day that it should hang back for a while.
    func ahead(_ a: ArenaActor) -> Bool {
        Double(count(of: a)) >= Double(a.target) * min(1, progress / 0.82) + 1
    }

    // MARK: - Honest habits

    private func habit(_ kind: SightingKind, for a: ArenaActor) -> Habit? {
        switch kind {
        case .offTask:
            return idlePoint(for: a).map { Habit(kind: kind, start: 0, pos: $0, dwell: SightingDeriver.offTaskSeconds + 1) }
        case .loiter:
            return Habit(kind: kind, start: 0, pos: nil, dwell: SightingDeriver.loiterSeconds + 1)
        case .emptyHanded:
            return dropOff.map { Habit(kind: kind, start: 0, pos: $0, dwell: 1.4) }
        case .startled, .atTheWorks:
            // Whatever is furthest from where everyone hands things in is the one to be caught hanging about.
            let far = works.max { ($0.pos.distance(to: dropOff ?? a.pos)) < ($1.pos.distance(to: dropOff ?? a.pos)) }
            return far.map { Habit(kind: kind, start: 0, pos: $0.pos, dwell: kind == .startled ? 3 : 7) }
        case .inView:
            return nil
        }
    }

    /// Runs a bot's odd moment if one is due. True while it has the bot's attention.
    func runHabit(_ a: ArenaActor, speed: Double, _ dt: Double) -> Bool {
        guard var h = a.habits.first, time >= h.start else { return false }
        // Nobody walks up empty-handed with their arms full.
        if h.kind == .emptyHanded, !h.arrived, a.carry != 0 || a.sinceScore < 3 { return false }
        a.wantsInteract = false
        if !h.arrived {
            if let p = h.pos, !travel(a, to: p, speed: speed, dt, within: 12) {
                // Give up on anywhere that cannot be reached in good time.
                h.timer += dt
                if h.timer > 14 { a.habits.removeFirst() } else { a.habits[0] = h }
                return true
            }
            h.arrived = true
            h.timer = 0
        }
        stand(a)
        h.timer += dt
        if h.timer >= h.dwell || (h.kind == .startled && h.timer > 0.6 && a.sinceViewer < 0.2) {
            a.habits.removeFirst()
        } else {
            a.habits[0] = h
        }
        return true
    }
}
