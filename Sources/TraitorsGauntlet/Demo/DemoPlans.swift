import Foundation
import TraitorsCore

/// What each game's demonstrations show. A `play` reel ends on the player scoring; a `hand` reel
/// ends on the shadow's hand going off. Every one says what it expects of the game as it goes,
/// so a reel that has stopped showing what it means to is caught by the tests and not by a player.
enum DemoPlans {
    static func plan(_ kind: MissionKind, _ reel: ArenaDemo.Reel) -> DemoPlan {
        let hand = reel == .hand
        switch kind {
        case .greatHall, .cellars, .armoury, .battlements, .crypt: return hand ? vaultDoor(kind) : gauntlet(kind)
        case .bogRelay: return hand ? bogHand : bog
        case .lanternRun: return hand ? lanternHand : lantern
        case .sheepRoundUp: return hand ? sheepHand : sheep
        case .shipwreckDive: return hand ? shipHand : ship
        case .ceiliChaos: return hand ? ceiliHand : ceili
        case .marketDay: return hand ? marketHand : market
        case .kiteRace: return hand ? kiteHand : kite
        case .hedgeMaze: return hand ? mazeHand : maze
        case .hurley: return hand ? hurleyHand : hurley
        case .banquetPrep: return hand ? banquetHand : banquet
        }
    }

    // MARK: - Writing a plan

    /// Asks something of the game as the game it is.
    private static func on<G, T>(_: G.Type, _ ask: @escaping (G) -> T) -> (any ArenaPlay) -> T {
        { ask($0 as! G) }
    }

    private static func at(_ x: Double, _ y: Double) -> Mark { { _ in Vec2(x, y) } }

    /// Settled the first time it is asked and kept, so what is being made for does not change underfoot.
    private static func fixed(_ mark: @escaping Mark) -> Mark {
        var kept: Vec2?
        return { play in
            if kept == nil { kept = mark(play) }
            return kept
        }
    }

    private static func place(_ a: ArenaActor, _ p: Vec2) {
        a.pos = p
        a.last = p
        a.path = []
    }

    /// The player in one of the games that is not the gauntlet.
    private static func me(_ g: ArenaCore) -> ArenaActor { g.human ?? g.actors[0] }
    private static var scored: Cond { on(ArenaCore.self) { $0.count(of: me($0)) >= 1 } }
    private static func scored(_ n: Int) -> Cond { on(ArenaCore.self) { $0.count(of: me($0)) >= n } }
    private static var carrying: Cond { on(ArenaCore.self) { me($0).carry > 0 } }
    /// The hand has been used, once.
    private static var sprung: Cond { { $0.acts[0] == 1 } }

    /// The end of every hand reel in the games where it is a press: stand, press, and it goes.
    private static func press(_ what: String) -> [DemoStep] {
        [.rest(0.9), .beat(what), .tap, .rest(0.3), .expect("the hand to have gone off", sprung)]
    }

    // MARK: - The gauntlet

    private static func runner(_ g: Gauntlet) -> Runner { g.runners[g.human ?? 0] }

    private static func stageCourse(_ g: Gauntlet, start: Vec2) {
        // Nothing ends the round early and the castle keeps its own hands off.
        g.seals = false
        g.misfires = []
        g.draught = -1
        let spots = [start, DemoCourses.point(3, 13), DemoCourses.point(9, 13)]
        for i in g.runners.indices where i < spots.count {
            g.runners[i].pos = spots[i]
            g.runners[i].last = spots[i]
            g.runners[i].checkpoint = spots[i]
        }
    }

    /// Whether a straight run from where the player stands to a point would get there untouched,
    /// with room to spare: it has to be safe for a runner quick off the mark and for a slow one.
    private static func clear(to point: Vec2, margin: Double = 14) -> Cond {
        on(Gauntlet.self) { g in
            let r = runner(g)
            let reach = r.pos.distance(to: point)
            let way = (point - r.pos).unit
            let stride = r.top * Feel.tick
            var traps = g.hazards
            for k in 0..<Int(reach / stride) + 30 {
                for h in traps.indices { _ = traps[h].step(act: g.act) }
                for late in [0, 14] {
                    let p = r.pos + way * min(Double(max(0, k - late)) * stride, reach)
                    for h in traps where h.deadly && h.distance(to: p) < (h.size + Feel.radius) * Feel.forgiveness + margin { return false }
                }
            }
            return true
        }
    }

    private static func trap(_ i: Int, is state: HazardState) -> Cond {
        on(Gauntlet.self) { $0.hazards[i].state == state }
    }

    private static func gauntlet(_ kind: MissionKind) -> DemoPlan {
        let p = DemoCourses.point
        let banked: Cond = on(Gauntlet.self) { runner($0).banked >= 1 }
        let lift: [DemoStep] = [
            .beat("Walk into the hoard to lift a bag"), .rest(0.4), .go(at(195, 80), within: 6),
            .expect("a bag in hand", on(Gauntlet.self) { runner($0).carry >= 1 }),
        ]
        let bank: [DemoStep] = [.go({ _ in p(6, 1.6) }, within: 8), .expect("a bag in the vault", banked)]
        var steps: [DemoStep]
        switch kind {
        case .cellars:
            steps = lift + [
                .beat("A barrel is coming: step out of its lane"), .go({ _ in p(2, 10.9) }, within: 6),
                .wait(until: { play in !trap(0, is: .rest)(play) }, timeout: 4), .go({ _ in p(3, 9.4) }, within: 6),
                .beat("Carry it up to the vault"), .go({ _ in p(3, 3.4) }, within: 8),
            ] + bank
        case .armoury:
            steps = lift + [
                .beat("A plate in the floor looses the darts"), .go({ _ in p(6, 7.1) }, within: 5),
                .wait(until: { play in !trap(0, is: .rest)(play) }, timeout: 2),
                .wait(until: clear(to: p(6, 4)), timeout: 3),
                .beat("Carry it up to the vault"),
            ] + bank
        case .battlements:
            let blown: (Gauntlet) -> Bool = { g in g.hazards[0].blows(runner(g).pos) }
            steps = lift + [
                .go({ _ in p(6, 8.3) }, within: 6),
                .wait(until: on(Gauntlet.self) { $0.hazards[0].warning > 0.55 || $0.hazards[0].state == .live }, timeout: 6),
                .beat("A gust: lean into it"),
                .drive(until: on(Gauntlet.self) { runner($0).pos.y > p(6, 4).y }, timeout: 6, on(Gauntlet.self) { g in
                    let r = runner(g)
                    // Into the wind while it blows, and back to the middle of the walk when it drops.
                    return blown(g) ? Vec2(-0.82, 0.5) : Vec2(clamp((195 - r.pos.x) / 40, -0.6, 0.6), 1)
                }),
                .beat("Carry it up to the vault"),
            ] + bank
        case .crypt:
            steps = lift + [
                .beat("Wait for the flame to drop"), .go({ _ in p(6, 9.1) }, within: 6),
                .wait(until: clear(to: p(6, 6.8)), timeout: 4), .go({ _ in p(6, 6.8) }, within: 6),
                .wait(until: clear(to: p(6, 3.8)), timeout: 4),
                .beat("Carry it up to the vault"), .go({ _ in p(6, 3.8) }, within: 8),
            ] + bank
        default:
            steps = lift + [
                .beat("Wait for the blade and walk through"), .go({ _ in p(6, 9.1) }, within: 6),
                .wait(until: clear(to: p(6, 6.9)), timeout: 4), .go({ _ in p(6, 5.95) }, within: 3),
                .beat("Tap Dash for a burst"), .tap, .steer(Vec2(0, 1), seconds: 0.3),
            ] + bank
        }
        return DemoPlan(stage: { stageCourse($0 as! Gauntlet, start: p(6, 12)) },
                        make: { Gauntlet($0, course: DemoCourses.course(kind)) }, steps: steps)
    }

    /// The hand on any course: the vault door, which spills what is in it back down the floor.
    private static func vaultDoor(_ kind: MissionKind) -> DemoPlan {
        let p = DemoCourses.point
        return DemoPlan(stage: {
            let g = $0 as! Gauntlet
            stageCourse(g, start: p(3.5, 3.9))
            g.teamTotal = 6
        }, make: { Gauntlet($0, course: DemoCourses.course(kind)) }, steps: [
            .beat("Stand still by the vault door"), .rest(0.4), .go({ _ in p(6, 3.3) }, within: 6),
        ] + press("Tap Dash, and the vault spills"), tail: 1.8)
    }

    // MARK: - The Bog Relay

    /// The stick that crosses the bog: from one stone of the front lane to the next, and off the
    /// last of them onto the far bank.
    private static let stones: (any ArenaPlay) -> Vec2 = on(BogCore.self) { g in
        let a = me(g)
        let next = g.stones.filter { $0.pos.x > a.pos.x + 14 && abs($0.pos.y - BogCore.lanes[0]) < 12 }
            .min { $0.pos.x < $1.pos.x }?.pos ?? Vec2(730, 26)
        return (next - a.pos).unit
    }

    private static let bog = DemoPlan(stage: {
        let g = $0 as! BogCore
        place(me(g), Vec2(84, 24))
        // The others are on their way back for another, so the three are not all in one knot.
        if g.actors.count > 2 {
            place(g.actors[1], Vec2(430, 62))
            place(g.actors[2], Vec2(230, 62))
        }
    }, steps: [
        .beat("Lift a sod at the bank"), .rest(0.5), .go(at(34, 28), within: 6), .expect("a sod in hand", carrying),
        .beat("Keep to the stones"), .drive(until: on(BogCore.self) { me($0).pos.x > 560 }, timeout: 8, stones),
        .beat("Stack it on the far side"), .drive(until: scored, timeout: 4, stones),
    ], tail: 1.2)

    private static let bogHand = DemoPlan(stage: {
        let g = $0 as! BogCore
        place(me(g), Vec2(640, 40))
        g.prime(4)
    }, steps: [.beat("Stand still at the stack"), .rest(0.4), .go(at(722, 56), within: 6)] + press("Tap Pass, and it slumps"), tail: 1.6)

    // MARK: - Castle Lantern Run

    private static func lamp(_ wanted: @escaping (LanternCore.Lantern) -> Bool) -> Mark {
        fixed(on(LanternCore.self) { g in
            let a = me(g)
            return g.lanterns.filter { !$0.tower && wanted($0) }.map(\.pos).min { $0.distance(to: a.pos) < $1.distance(to: a.pos) }
        })
    }

    private static var lantern: DemoPlan {
        DemoPlan(stage: {
            // The others come to the fire from the walls, so the player is first to it.
            let g = $0 as! LanternCore
            if g.actors.count > 2 {
                place(g.actors[1], Vec2(48, 240))
                place(g.actors[2], Vec2(432, 240))
            }
        }, steps: [
            .beat("Take a flame from the brazier"), .rest(0.5), .go(on(LanternCore.self) { $0.brazier }, within: 22),
            .expect("a flame in hand", carrying),
            .beat("Walk into a dark lantern to light it"), .go(lamp { $0.burn < LanternCore.dim }, within: 16),
            .expect("a lantern lit", scored),
            .beat("Hold Trim to keep one burning"), .go(lamp { $0.burn > 0.32 && $0.burn < 0.7 }, within: 10),
            .hold(until: on(LanternCore.self) { me($0).finished >= 0 }, timeout: 4),
        ])
    }

    private static let lanternHand = DemoPlan(stage: { ($0 as! LanternCore).prime(5) }, steps: [
        .beat("Stand still at the brazier"), .rest(0.5), .go(on(LanternCore.self) { $0.brazier }, within: 12),
    ] + press("Tap Trim, and the fire is smothered"), tail: 1.6)

    // MARK: - Sheep Round-Up

    /// The sheep the demonstration is about: the first one laid out.
    private static func ewe(_ g: SheepCore) -> SheepCore.Sheep? { g.sheep.first }

    private static func behind(_ g: SheepCore) -> Vec2? {
        ewe(g).map { $0.pos + ($0.pos - g.pens[$0.colour].centre).unit * 34 }
    }

    private static let sheep = DemoPlan(stage: {
        let g = $0 as! SheepCore
        // One for the top pen in the middle of the field, and the rest well out of the way of it.
        g.stage(flock: [(Vec2(220, 205), 2), (Vec2(90, 400), 0), (Vec2(350, 410), 1), (Vec2(120, 330), 1),
                        (Vec2(345, 335), 0), (Vec2(66, 160), 2), (Vec2(384, 150), 0)], dog: Vec2(330, 300))
        place(me(g), Vec2(306, 268))
        if g.actors.count > 2 {
            place(g.actors[1], Vec2(110, 446))
            place(g.actors[2], Vec2(350, 462))
        }
    }, steps: [
        .beat("Sheep run from you: get behind one"), .rest(0.5), .go(on(SheepCore.self, behind), within: 10, timeout: 4),
        .beat("Walk it into the pen of its colour"),
        .drive(until: scored, timeout: 8, on(SheepCore.self) { g in
            guard let spot = behind(g) else { return .zero }
            return ((spot - me(g).pos) * (1 / 18)).capped(1)
        }),
        .beat("Tap Whistle to send the dog"), .rest(0.3), .steer(Vec2(1, 0), seconds: 0.45), .tap, .steer(Vec2(1, 0), seconds: 0.15),
        .rest(1.1),
    ], tail: 0.8)

    private static let sheepHand = DemoPlan(stage: {
        let g = $0 as! SheepCore
        g.stage(flock: [(Vec2(250, 200), 2), (Vec2(330, 380), 1), (Vec2(180, 420), 0), (Vec2(360, 160), 0), (Vec2(240, 330), 1)],
                dog: Vec2(330, 300))
        place(me(g), Vec2(176, 318))
        if g.actors.count > 2 {
            place(g.actors[1], Vec2(300, 446))
            place(g.actors[2], Vec2(360, 250))
        }
        g.prime(4)
    }, steps: [
        .beat("Stand still at the mouth of a pen"), .rest(0.4), .go(on(SheepCore.self) { $0.pens[0].mouth }, within: 8),
    ] + press("Tap Whistle, and the gate bursts"), tail: 1.8)

    // MARK: - The Shipwreck Dive

    /// The chest the demonstration brings up. It is the player's from the start, so no bot makes for it.
    private static func prize(_ g: ShipCore) -> ShipCore.Chest? { g.chests.first { $0.id == me(g).plan - 100 } }

    private static let ship = DemoPlan(stage: {
        let g = $0 as! ShipCore
        guard let grid = g.grid else { return }
        let a = me(g)
        let near = g.chests.filter { $0.kind == 0 }
            .min { grid.path(from: a.pos, to: $0.pos).count < grid.path(from: a.pos, to: $1.pos).count }
        a.plan = (near?.id ?? 0) + 100
    }, steps: [
        .beat("Dive to the wreck"), .rest(0.5), .go(on(ShipCore.self) { prize($0)?.home }, within: 10, timeout: 8),
        .beat("Hold Lift at a chest"), .hold(until: carrying, timeout: 3),
        .beat("Swim it up to the boat"), .go(on(ShipCore.self) { $0.boat }, within: 30, timeout: 9),
        .expect("a chest in the boat", scored),
        .expect("no meeting with an eel", on(ShipCore.self) { me($0).stun <= 0 }),
    ])

    private static let shipHand = DemoPlan(stage: {
        let g = $0 as! ShipCore
        place(me(g), Vec2(168, g.surface + 6))
        g.prime(3)
    }, steps: [.beat("Hold still at the boat"), .rest(0.4), .go(on(ShipCore.self) { $0.boat }, within: 10)] + press("Tap Lift, and the net slips"),
       tail: 1.6)

    // MARK: - Céilí Chaos

    private static let ceili = DemoPlan(stage: {
        let g = $0 as! CeiliCore
        place(me(g), g.centre(g.index(0, 0)))
    }, steps: [
        .beat("A tile lights up in your colour"), .rest(0.9),
        .beat("Get onto it"), .go(on(CeiliCore.self) { g in g.places[me(g).id].map(g.centre) }, within: 4),
        .beat("Be there when the ring closes"), .wait(until: scored, timeout: 6),
    ], tail: 1.2)

    private static let ceiliHand = DemoPlan(stage: {
        let g = $0 as! CeiliCore
        place(me(g), g.centre(g.index(0, 0)))
        g.prime(5)
    }, steps: [
        .beat("Step onto a cracked board"), .rest(0.6),
        .go(fixed(on(CeiliCore.self) { g in
            let a = me(g)
            return g.cracks.map(g.centre).min { $0.distance(to: a.pos) < $1.distance(to: a.pos) }
        }), within: 4),
        .beat("Be standing still on it as the beat lands"), .wait(until: sprung, timeout: 6),
    ], tail: 1.8)

    // MARK: - Market Day Scramble

    private static func stageMarket(_ g: MarketCore) {
        // The others shop further up the square, so the stall by the cart is not sold out from under the player.
        if g.actors.count > 2 {
            place(g.actors[1], Vec2(330, 236))
            place(g.actors[2], Vec2(150, 356))
        }
    }

    private static var market: DemoPlan {
        let carry: (Int) -> Cond = { n in on(MarketCore.self) { me($0).carry >= n } }
        return DemoPlan(stage: { stageMarket($0 as! MarketCore) }, steps: [
            .beat("Find a stall with a gold tag"), .rest(0.6),
            .go(fixed(on(MarketCore.self) { g in
                let a = me(g)
                return g.stalls.indices.filter { g.needs(a, $0) && g.stalls[$0].stock > 0 }.map { g.stalls[$0].pos }
                    .min { $0.distance(to: a.pos) < $1.distance(to: a.pos) }
            }), within: 9),
            .beat("Hold Buy"), .hold(until: carry(1)), .rest(0.2), .hold(until: carry(2)), .rest(0.2), .hold(until: carry(3)),
            .beat("Carry it back to the cart"), .go(on(MarketCore.self) { $0.cart }, within: 26),
            .expect("three things on the cart", scored(3)),
        ])
    }

    private static let marketHand = DemoPlan(stage: {
        let g = $0 as! MarketCore
        stageMarket(g)
        g.prime(4)
    }, steps: [.beat("Stand still at the cart"), .rest(0.5), .go(on(MarketCore.self) { $0.cart }, within: 14)] + press("Tap Buy, and the cart tips"),
       tail: 1.6)

    // MARK: - Cliffside Kite Race

    private static func stageKite(_ g: KiteCore, x: Double, height: Double) {
        let a = me(g)
        place(a, Vec2(x, 6))
        a.z = height
        a.lastZ = height
    }

    /// The stick that runs the path and flies the kite to a height.
    private static func fly(_ g: KiteCore, to height: Double) -> Vec2 {
        Vec2(1, clamp((height - me(g).z) / 20, -1, 1))
    }

    private static let caught: Cond = on(KiteCore.self) { $0.canInteract(me($0)) }

    private static let kite = DemoPlan(stage: { stageKite($0 as! KiteCore, x: 70, height: 140) }, steps: [
        .beat("Push right to run the cliff path"), .steer(Vec2(1, 0), seconds: 0.6),
        .beat("Up and down flies the kite through a ring"),
        .drive(until: scored, timeout: 5, on(KiteCore.self) { g in fly(g, to: g.rings[0].height) }),
        .beat("Caught on a sea stack? Hold Tug"),
        .drive(until: caught, timeout: 5, on(KiteCore.self) { g in fly(g, to: g.spires[0].height) }),
        .rest(0.6), .hold(until: { !caught($0) }, timeout: 2), .steer(Vec2(1, 0.6), seconds: 0.7),
    ], tail: 0.8)

    private static let kiteHand = DemoPlan(stage: {
        let g = $0 as! KiteCore
        stageKite(g, x: 196, height: 84)
        g.prime(8)
    }, steps: [
        .beat("Fly your kite onto a sea stack"),
        .drive(until: caught, timeout: 5, on(KiteCore.self) { g in fly(g, to: g.spires[0].height) }),
        .beat("Leave it caught, with never a tug"), .wait(until: sprung, timeout: 4),
    ], tail: 1.8)

    // MARK: - The Hedge Maze

    /// The sigil the demonstration walks to: the one with the shortest way on to the bell.
    private static func sigil(_ g: MazeCore) -> Int? {
        guard let grid = g.grid else { return nil }
        return g.finds.indices.filter { g.finds[$0].kind == 0 }
            .min { grid.path(from: g.bell, to: g.finds[$0].pos).count < grid.path(from: g.bell, to: g.finds[$1].pos).count }
    }

    private static let maze = DemoPlan(stage: {
        let g = $0 as! MazeCore
        guard let grid = g.grid, let pick = sigil(g) else { return }
        let a = me(g)
        // Three finds already in hand, so the one in the picture is the fourth and the bell can be rung.
        let rest = g.finds.indices.filter { $0 != pick }
            .sorted { g.finds[$0].pos.distance(to: g.finds[pick].pos) > g.finds[$1].pos.distance(to: g.finds[pick].pos) }
        g.stage(found: Array(rest.prefix(3)), for: a)
        // A few steps short of the sigil, on the side away from the bell.
        let out = grid.path(from: g.finds[pick].pos, to: a.pos)
        if !out.isEmpty { place(a, out[min(4, out.count - 1)]) }
    }, steps: [
        .beat("Walk into a sigil to claim it"), .rest(0.5),
        .go(on(MazeCore.self) { g in sigil(g).map { g.finds[$0].pos } }, within: 8, timeout: 6), .expect("a sigil claimed", scored),
        .beat("With four finds, ring the bell"), .go(on(MazeCore.self) { $0.bell }, within: 10, timeout: 9),
        .expect("the bell rung", scored(2)),
    ])

    private static let mazeHand = DemoPlan(stage: {
        let g = $0 as! MazeCore
        guard let grid = g.grid else { return }
        let a = me(g)
        let out = grid.path(from: g.bell, to: a.pos)
        if !out.isEmpty { place(a, out[min(3, out.count - 1)]) }
        g.prime(4)
    }, steps: [.beat("Stand still at the bell"), .rest(0.4), .go(on(MazeCore.self) { $0.bell }, within: 6)] + press("Tap Search, and the rope snaps"),
       tail: 1.6)

    // MARK: - Hurley Target Practice

    private static func stageHurley(_ g: HurleyCore) {
        // The player takes the middle of the line, where the whole lawn is in front of them.
        guard g.actors.count > 2 else { return }
        let middle = g.actors[1].pos
        place(g.actors[1], g.actors[0].pos)
        place(g.actors[0], middle)
    }

    private static let hurley = DemoPlan(stage: { stageHurley($0 as! HurleyCore) }, steps: [
        .beat("Pull back and let go"), .rest(0.5),
        .pull(to: on(HurleyCore.self) { g in g.targets.first { $0.kind == 0 && $0.pos.x < 100 }?.pos }, draw: 0.9),
        .wait(until: scored, timeout: 3), .wait(until: on(HurleyCore.self) { me($0).stun <= 0 }, timeout: 4),
        .beat("Pull further for the far targets"),
        .pull(to: on(HurleyCore.self) { g in
            // The one on the far wall, where it will have rolled to by the time the ball comes down.
            guard let t = g.targets.first(where: { $0.kind == 2 }) else { return nil }
            return t.pos + Vec2(t.speed * (0.45 + me(g).pos.distance(to: t.pos) / 700), 0)
        }, draw: 1.1),
        .wait(until: scored(2), timeout: 3),
    ])

    private static let hurleyHand = DemoPlan(stage: {
        let g = $0 as! HurleyCore
        stageHurley(g)
        g.prime(6)
    }, steps: [
        .beat("Aim at the old bell on the far wall"), .rest(0.6), .pull(to: on(HurleyCore.self) { $0.bell }, draw: 1.2),
        .beat("Every target drops"), .wait(until: sprung, timeout: 3),
    ], tail: 1.8)

    // MARK: - The Banquet Prep

    private static let banquet = DemoPlan(steps: [
        .beat("A station that glows has a job waiting"), .rest(0.5),
        .go(on(BanquetCore.self) { $0.stations[1].stand }, within: 8),
        .beat("Hold Work to do it"), .hold(until: scored, timeout: 3),
        .beat("Every job feeds the next"), .go(on(BanquetCore.self) { $0.stations[3].stand }, within: 8, timeout: 7),
        .hold(until: scored(2), timeout: 3),
    ])

    private static let banquetHand = DemoPlan(stage: {
        let g = $0 as! BanquetCore
        place(me(g), Vec2(112, 84))
        g.prime(4)
    }, steps: [.beat("Stand still at the pass"), .rest(0.4), .go(at(176, 60), within: 8)] + press("Tap Work, and a tray goes over"),
       tail: 1.6)
}
