import Foundation
import TraitorsCore

/// The Bog Relay. Turf goes from the bank on the left to the stack on the right across stones
/// that sink. `y` is depth: the front lane, the middle lane, and the back lane where nobody needs to go.
public final class BogCore: ArenaCore {
    struct Stone {
        var pos: Vec2
        var sunk = 0.0
    }

    static let lanes = [22.0, 62.0]
    static let backLane = 104.0
    public static let light = 1, heavy = 2
    /// Added to what is carried once it has changed hands.
    public static let passed = 10

    override class var pace: Double { 7 }
    override class var handCost: Int { 2 }

    private(set) var stones: [Stone] = []
    /// The three pools in the back lane.
    private var pools: [Spot] = []
    let stack = Vec2(738, 60)
    private var oakAt = -1
    private var oakTimer = 6.0
    /// Seconds every stone stays under after a bank gives way.
    private(set) var flood = 0.0

    override init(_ setup: ArenaSetup) {
        super.init(setup)
        size = Vec2(760, 130)
        vision = 150
        var dice = SeededRNG.derived(setup.seed, 7)
        for lane in Self.lanes {
            for i in 0..<11 where dice.chance(0.88) {
                stones.append(Stone(pos: Vec2(96 + Double(i) * 57 + dice.range(-8, 8), lane + dice.range(-5, 5))))
            }
        }
        for (i, x) in [220.0, 380.0, 540.0].enumerated() {
            pools.append(Spot(id: i, pos: Vec2(x + dice.range(-25, 25), Self.backLane), reach: 26, hold: 2, tag: i, offMission: true))
        }
        spots = pools
        works = [Works(id: 0, pos: stack, reach: 36, text: "THE STACK SLUMPS")]
        for p in pools { works.append(Works(id: 1 + p.id, pos: p.pos, reach: 26, text: "THE BANK GIVES WAY")) }
        dropOff = stack
        let fog = totalTime * dice.range(0.38, 0.5)
        cover = [CoverWindow(start: fog, end: fog + 8)]
        for (i, a) in actors.enumerated() {
            a.pos = Vec2(30 + Double(i % 2) * 22, 14 + Double(i) * 13)
        }
        ready()
    }

    override var coverVision: Double { 46 }
    public override var sightRadius: Double? { coverActive ? coverVision : nil }

    package override func canInteract(_ a: ArenaActor) -> Bool {
        usable(by: a) != nil || (a.carry > 0 && actors.contains { $0 !== a && $0.carry == 0 && $0.pos.distance(to: a.pos) < 34 })
    }

    override func zone(of a: ArenaActor) -> UInt8 {
        if a.pos.x < 70 || a.pos.x > 690 { return Zone.task }
        return a.pos.y > 84 ? Zone.off : Zone.open
    }

    override func idlePoint(for a: ArenaActor) -> Vec2? { Vec2(rng.range(140, 620), Self.backLane - 6) }

    override func canUse(_ s: Spot, _ a: ArenaActor) -> Bool { s.id == oakAt }

    override func used(_ s: Spot, _ a: ArenaActor) {
        guard s.id == oakAt else { return }
        oakAt = -1
        oakTimer = 14
        addBonus(1, at: s.pos, "BOG OAK +1")
    }

    override func sprung(_ w: Works) {
        // A bank giving way swamps the stones for a while as well.
        if w.id != 0 { flood = 5 }
    }

    private func pace(_ a: ArenaActor) -> Double {
        var speed = 140.0
        if a.carry % Self.passed == Self.heavy { speed *= 0.7 }
        let ground = a.pos.x < 70 || a.pos.x > 690
        let dry = ground || stones.contains { $0.sunk < 1 && $0.pos.distance(to: a.pos) < 21 }
        return dry ? speed : speed * 0.55
    }

    override func tick(_ dt: Double) {
        flood = max(0, flood - dt)
        for i in stones.indices {
            let stood = flood > 0 || actors.contains { $0.pos.distance(to: stones[i].pos) < 21 }
            stones[i].sunk = clamp(stones[i].sunk + (stood ? dt / 1.6 : -dt / 3), 0, 1)
        }
        oakTimer -= dt
        if oakAt < 0, oakTimer <= 0 { oakAt = rng.int(3) }

        for a in actors {
            guard a.stun <= 0 else { stand(a); continue }
            if isBot(a) { think(a, dt) } else { slide(a, input.move * pace(a), dt) }
            exchange(a)
        }
        // A press with nothing to use hands the sod to whoever is standing beside you.
        if tapped, let me = human, usable(by: me) == nil, me.carry > 0,
           let other = actors.filter({ $0 !== me && $0.carry == 0 && $0.pos.distance(to: me.pos) < 34 })
            .min(by: { $0.pos.distance(to: me.pos) < $1.pos.distance(to: me.pos) }) {
            other.carry = me.carry % Self.passed + Self.passed
            me.carry = 0
            cues.append(.popup("PASSED", me.pos, seat: me.id, bad: false))
        }
    }

    /// Lifting at the bank and stacking at the far side both happen by walking in.
    private func exchange(_ a: ArenaActor) {
        if a.carry == 0, a.pos.x < 44 {
            a.carry = a.pos.y > 65 ? Self.heavy : Self.light
            cues.append(.burst(a.pos, seat: a.id))
        } else if a.carry > 0, a.pos.x > 716 {
            let relay = a.carry >= Self.passed
            let weight = a.carry % Self.passed
            a.carry = 0
            addCount(weight, for: a)
            if relay { addBonus(1, at: a.pos, "RELAY +1") }
        }
    }

    private func think(_ a: ArenaActor, _ dt: Double) {
        a.wantsInteract = false
        let speed = pace(a) * (0.78 + 0.22 * a.seat.skill)
        if runHand(a, speed: speed, dt) { return }
        if runHabit(a, speed: speed, dt) { return }
        if a.carry > 0 {
            if a.goal == nil || a.goal!.x < 100 { a.goal = Vec2(732, rng.pick(Self.lanes) + rng.range(-6, 6)) }
            // Out of the bank and onto a lane of stones first, then along it.
            travel(a, to: a.pos.x < 96 ? Vec2(100, a.goal!.y) : a.goal!, speed: speed, dt)
            return
        }
        // Empty-handed: back for another, unless the day's work is done or well in hand.
        if !wants(a) || ahead(a) && a.pos.x > 690 {
            stand(a)
            return
        }
        if a.goal == nil || a.goal!.x > 100 {
            let left = a.target - count(of: a)
            // The big pile when there are not enough trips left for small ones.
            let big = left >= 2 && Double(left) > timeLeft / 13
            a.goal = Vec2(30, big ? 96 : 34)
        }
        // Keep to a lane on the way back, then cut across to the pile.
        let lane = a.pos.x > 110 ? Vec2(100, a.goal!.y > 65 ? Self.lanes[1] : Self.lanes[0]) : a.goal!
        travel(a, to: lane, speed: speed, dt)
    }

    public override func props() -> [Prop] {
        var out: [Prop] = []
        for (i, s) in stones.enumerated() { out.append(Prop(id: i, kind: .stone, pos: s.pos, value: s.sunk)) }
        out.append(Prop(id: 100, kind: .turfLight, pos: Vec2(24, 34)))
        out.append(Prop(id: 101, kind: .turfHeavy, pos: Vec2(24, 96)))
        out.append(Prop(id: 102, kind: .stack, pos: stack, value: min(1, Double(teamTotal) / Double(goal))))
        for p in pools {
            out.append(Prop(id: 110 + p.id, kind: .hollow, pos: p.pos))
            if p.id == oakAt { out.append(Prop(id: 120 + p.id, kind: .bogOak, pos: p.pos, z: 6)) }
        }
        return out
    }
}
