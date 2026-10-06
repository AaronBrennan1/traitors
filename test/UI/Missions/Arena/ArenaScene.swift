import SpriteKit
import SwiftUI

/// The one button. It says what the game's one action is, and for a traitor standing by something
/// they could work it wears the faintest red rim: nothing anyone looking over a shoulder would notice.
final class ActionButton: SKNode {
    static let radius: CGFloat = 36
    private let face = SKShapeNode(circleOfRadius: ActionButton.radius)
    private let ring = SKShapeNode()
    private let rim = SKShapeNode(circleOfRadius: ActionButton.radius + 3)
    private let label: ToonLabel
    private var step = -1

    init(_ text: String) {
        label = ToonLabel(text, size: 13, color: Toon.cream)
        super.init()
        face.lineWidth = 2
        addChild(face)
        ring.strokeColor = Toon.cream
        ring.lineWidth = 4
        ring.lineCap = .round
        ring.fillColor = .clear
        addChild(ring)
        rim.strokeColor = Toon.red
        rim.lineWidth = 1.2
        rim.fillColor = .clear
        rim.alpha = 0
        addChild(rim)
        addChild(label)
        zPosition = 900
        show(ring: nil, lit: true, pressed: false, hand: false)
    }

    required init?(coder: NSCoder) { return nil }

    /// `ring` runs from 0 to 1 round the button while something is filling: a dash coming back, a
    /// job being done. `lit` is whether a press would do anything.
    func show(ring fill: Double?, lit: Bool, pressed: Bool, hand: Bool) {
        face.fillColor = (lit ? Toon.goldDark : Toon.ink).withAlphaComponent(pressed ? 0.95 : 0.72)
        face.strokeColor = lit ? Toon.gold : Toon.cream.withAlphaComponent(0.3)
        label.alpha = lit ? 1 : 0.45
        setScale(pressed ? 0.93 : 1)
        rim.alpha = hand ? 0.55 : 0
        // The ring is only redrawn when it has visibly moved on.
        let now = fill.map { Int(min(max($0, 0), 1) * 24) } ?? 24
        guard now != step else { return }
        step = now
        if fill == nil {
            ring.path = nil
        } else {
            let path = CGMutablePath()
            path.addArc(center: .zero, radius: Self.radius + 6, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi * CGFloat(now) / 24, clockwise: true)
            ring.path = path
        }
    }
}

/// Runs a mini-game and everything the thumbs touch: the stick, the one button, and the pull of a
/// strike. The game itself is an `ArenaGame`, the stage underneath draws it, and the tally along
/// the top is SwiftUI, fed through `model`.
final class ArenaScene: SKScene {
    let config: ArenaConfig
    let layout: ArenaLayout
    let runner: ArenaRunner
    let stage: any ArenaStage
    let model: ArenaHUDModel
    var game: any ArenaGame { runner.game }
    /// The game, when it is the gauntlet, and when it is one of the others.
    let gauntlet: Gauntlet?
    let arena: ArenaCore?
    var onFinish: ((MissionResult) -> Void)?
    /// How many times faster than life to run, for unattended checks.
    var pace = 1.0

    private var lastTime: TimeInterval = 0
    private var built = false
    private var finishDelay = 1.6
    private var ended = false
    private var shownNumber = ""
    private var wasPaused = false
    /// The 3, 2, 1 after a pause, in seconds still to run.
    private var resume = 0.0
    /// Seconds the game holds still for, on a hit or a delivery, so that it lands.
    private var freeze = 0.0
    private var second = Int.max
    private var lastWarn = 0.0

    private let flashNode = SKSpriteNode(color: Toon.red, size: .zero)
    private let dark = Sprites.darkness()
    private let stick = ThumbStick()
    private let button: ActionButton?
    /// Whether this game is steered with the stick, and whether it is played by pulling back a strike.
    private let steers: Bool
    private let aims: Bool
    private let aimLine = SKShapeNode()
    private var stickTouch: UITouch?
    private var buttonTouch: UITouch?
    private var aimTouch: UITouch?
    private var aimFrom = CGPoint.zero
    private var aimTo = CGPoint.zero
    private var place = 0

    /// The player's seat, and their place in the cast, while they are the one at the controls.
    private var mine: PlayerID? { game.humanSeat }
    private var me: Int? { mine.flatMap { seat in config.setup.cast.firstIndex { $0.id == seat } } }

    init(config: ArenaConfig, layout: ArenaLayout) {
        self.config = config
        self.layout = layout
        runner = ArenaRunner(config.setup)
        gauntlet = runner.game as? Gauntlet
        arena = runner.game as? ArenaCore
        stage = ArenaStages.make(config, runner.game, layout)
        model = ArenaHUDModel(config: config, game: runner.game)
        button = config.setup.kind.button.map(ActionButton.init)
        aims = config.setup.kind == .hurley
        steers = config.setup.kind != .hurley
        super.init(size: layout.size)
        scaleMode = .aspectFit
        backgroundColor = stage.backdrop
    }

    required init?(coder: NSCoder) { return nil }

    override func didMove(to view: SKView) {
        guard !built else { return }
        built = true
        view.isMultipleTouchEnabled = true
        addChild(stage)
        dark.zPosition = 600
        dark.alpha = 0.9
        dark.isHidden = true
        addChild(dark)
        let vignette = Sprites.vignette(size: layout.size, strength: 0.4)
        vignette.position = layout.centre
        vignette.zPosition = 610
        addChild(vignette)
        flashNode.size = layout.size
        flashNode.anchorPoint = .zero
        flashNode.alpha = 0
        flashNode.zPosition = 700
        addChild(flashNode)
        if let overlay = (stage as? CoreStage)?.overlay {
            overlay.zPosition = 650
            addChild(overlay)
        }
        addChild(stick)
        if let button, me != nil {
            button.position = CGPoint(x: ArenaLayout.width - 58, y: layout.safeBottom + 66)
            addChild(button)
        }
        aimLine.strokeColor = Toon.cream
        aimLine.lineWidth = 4
        aimLine.lineCap = .round
        aimLine.zPosition = 880
        addChild(aimLine)
        Feedback.prepare()
        refresh(0)
    }

    // MARK: - The loop

    override func update(_ currentTime: TimeInterval) {
        // A long frame is caught up by the game, not slowed down for.
        let real = lastTime == 0 ? 0 : min(currentTime - lastTime, 0.25)
        lastTime = currentTime

        if model.paused {
            if !wasPaused {
                wasPaused = true
                dropTouches()
            }
            return
        }
        if wasPaused {
            wasPaused = false
            if runner.stage == .playing { resume = 1.5 }
        }
        if resume > 0 {
            resume -= real
            let number = resume > 0 ? "\(Int(resume / 0.5) + 1)" : ""
            if number != shownNumber {
                shownNumber = number
                model.countdown = number.isEmpty ? nil : number
                Feedback.play(number.isEmpty ? .go : .countdown)
            }
            return
        }

        var dt = real * pace
        if freeze > 0 {
            freeze -= real
            dt = 0
        }
        var input = ArenaInput()
        if steers { input.move = stage.arenaVector(stick.vector) }
        input.hold = buttonTouch != nil
        let before = runner.stage
        runner.advance(dt, input: input)

        switch runner.stage {
        case .countdown:
            let number = "\(min(3, Int(runner.countdown / 0.9) + 1))"
            if number != shownNumber {
                shownNumber = number
                model.countdown = number
                Feedback.play(.countdown)
            }
        case .playing:
            if before == .countdown {
                shownNumber = ""
                model.countdown = nil
                Feedback.play(.go)
                Feedback.prepare()
            }
            let s = Int(game.timeLeft.rounded(.up))
            if s != second, s <= 10, s > 0, second != Int.max { Feedback.play(.lastSeconds) }
            second = s
        case .finished:
            if !ended {
                ended = true
                finish()
            }
            finishDelay -= real
            // A player reads the card and moves on when ready. An unattended run moves itself on.
            if model.autoAdvance ? finishDelay <= 0 : model.proceed, let done = onFinish {
                onFinish = nil
                done(runner.result())
            }
        }

        stage.sync(alpha: runner.alpha, dt: real)
        for cue in game.cues { play(cue) }
        game.cues.removeAll(keepingCapacity: true)
        refresh(real)
    }

    private func finish() {
        var own: ArenaHUDModel.Summary.Own?
        if let me {
            let count = game.tally[me]
            let key = "best.\(config.setup.kind.rawValue)"
            let best = UserDefaults.standard.integer(forKey: key)
            if count > best { UserDefaults.standard.set(count, forKey: key) }
            var extras: [ArenaHUDModel.Summary.Extra] = []
            if let gauntlet, let r = gauntlet.human.map({ gauntlet.runners[$0] }) {
                extras = [.init(value: "\(r.bestStreak)", label: "in a row"), .init(value: "\(r.nearMisses)", label: "near misses")]
            } else {
                let ahead = game.tally.filter { $0 > count }.count
                extras = [.init(value: "\(ahead + 1)", label: "your place of \(game.tally.count)"),
                          .init(value: "\(game.tally.max() ?? 0)", label: "the most by anyone")]
            }
            own = .init(count: count, best: max(best, count), record: count > best && count > 0, extras: extras)
        }
        var hand: ArenaHUDModel.Summary.Hand?
        if config.handVisible, let me {
            hand = .init(uses: game.acts[me], cost: Int(game.loss[me].rounded()), sank: game.sunkBy == mine)
        }
        model.endTitle = gauntlet != nil && game.won ? "Sealed" : "Time"
        model.summary = ArenaHUDModel.Summary(teamTotal: game.teamTotal, own: own, hand: hand)
        model.ended = true
        Feedback.play(game.won ? .teamGoal : .time)
        dropTouches()
        if game.won, !Tokens.Motion.reduced {
            FX.confetti(in: self, size: layout.size, colors: config.cast.map(\.color) + [Toon.gold])
        }
    }

    private func dropTouches() {
        stick.end()
        stickTouch = nil
        buttonTouch = nil
        aimTouch = nil
        aimLine.path = nil
    }

    // MARK: - What the game says back

    private func play(_ cue: ArenaCue) {
        switch cue {
        case .pickup(let seat):
            if seat == mine {
                Feedback.play(.pickup)
                stage.figure(seat)?.squash()
            }
        case .banked(let seat, let bags, let bonus, let at):
            let own = seat == mine
            popup("+\(bags)", at: stage.screenPoint(at), color: own ? Toon.gold : config.color(seat), size: own ? 22 : 13)
            if own {
                // The note climbs as the company closes on its goal.
                Feedback.play(.score(note))
                freeze = max(freeze, 0.034)
                if bonus > 0 { popup("STREAK", at: stage.screenPoint(at + Vec2(0, 26)), color: Toon.cream, size: 12) }
            } else {
                Feedback.play(.otherScore)
            }
        case .downed(let seat, let at, _):
            guard stage.inEarshot(at) else { break }
            FX.burst(in: self, at: stage.screenPoint(at), color: config.color(seat), count: 9, reach: 30)
            if seat == mine {
                freeze = max(freeze, 0.085)
                stage.shake(0.75)
                flash(Toon.danger, 0.32)
                Feedback.play(.hit)
                Feedback.prepare()
            } else {
                stage.shake(0.18)
                Feedback.play(.bump)
            }
        case .woke(let seat):
            stage.figure(seat)?.squash()
        case .dash(let seat):
            stage.figure(seat)?.squash()
            if seat == mine { Feedback.play(.dash) }
        case .bump(let at):
            if let r = gauntlet?.human.flatMap({ gauntlet?.runners[$0] }), r.pos.distance(to: at) < 40 { Feedback.play(.bump) }
        case .nearMiss(let seat, let at):
            guard seat == mine else { break }
            popup("close!", at: stage.screenPoint(at), color: Toon.cream, size: 12)
            FX.burst(in: self, at: stage.screenPoint(at), color: Toon.gold, count: 5, reach: 18)
            Feedback.play(.nearMiss)
        case .warned(let h):
            // A corridor full of traps should tick, not clatter.
            if let gauntlet, stage.inEarshot(gauntlet.hazards[h].a), lastTime - lastWarn > 0.12 {
                lastWarn = lastTime
                Feedback.play(.warn)
            }
        case .fired(let h):
            if let gauntlet, stage.inEarshot(gauntlet.hazards[h].a) { Feedback.play(.strike) }
        case .cracked:
            break
        case .gave(let at):
            if stage.inEarshot(at) { FX.burst(in: self, at: stage.screenPoint(at), color: Toon.flagstoneHi, count: 5, reach: 16, z: 120) }
        case .lights(_, let out):
            if out { toast("The candles gutter") }
            Feedback.play(out ? .lightsOut : .lightsOn)
        case .spilled(let at, let bags):
            toast("The vault has burst!")
            popup("-\(bags)", at: stage.screenPoint(at), color: Toon.danger, size: 20)
            if stage.inEarshot(at) { stage.shake(0.45) }
            Feedback.play(.spill)
        case .act(let n):
            toast(n == 1 ? "The traps quicken" : "The last stretch")
            Feedback.play(.banner)
        case .sealing:
            toast("The goal is in. Hold it!")
            Feedback.play(.sealing)
        case .unsealed:
            toast("The seal is broken")
        case .sealed:
            flash(Toon.gold, 0.25)
        case .overtime:
            toast("Last run home")
            Feedback.play(.banner)
        case .hand(let seat):
            if seat == mine { Feedback.play(.hand) }
        case .popup(let text, let at, let seat, let bad):
            // What somebody out of the player's sight is doing is not put on the screen.
            if let seat, seat != mine, let arena, arena.hidesUnseen, let me = arena.human, arena.actor(seat)?.seenBy.has(me.id) == false { break }
            guard stage.inEarshot(at) else { break }
            let own = seat == mine && seat != nil
            popup(text, at: stage.screenPoint(at), color: bad ? Toon.danger : own ? Toon.gold : seat.map(config.color) ?? Toon.cream,
                  size: own || seat == nil ? 19 : 13)
            if own {
                Feedback.play(bad ? .hit : .score(note))
                if !bad { freeze = max(freeze, 0.034) }
                stage.figure(seat!)?.squash()
            } else if seat == nil {
                Feedback.play(bad ? .spill : .sealing)
                if bad { flash(Toon.danger, 0.18) }
            } else {
                Feedback.play(bad ? .bump : .otherScore)
            }
        case .banner(let text):
            toast(String(text.prefix(1)) + text.dropFirst().lowercased())
            Feedback.play(.banner)
        case .flash(let bad):
            flash(bad ? Toon.danger : Toon.gold, 0.25)
        case .shake:
            stage.shake(0.45)
        case .burst(let at, let seat):
            guard stage.inEarshot(at) else { break }
            FX.burst(in: self, at: stage.screenPoint(at), color: seat.map(config.color) ?? Toon.cream, count: 6, reach: 20)
            if seat == mine, seat != nil { Feedback.play(.pickup) } else if seat == nil { Feedback.play(.bump) }
        }
    }

    /// The note a score is played on: it climbs as the company closes on its goal.
    private var note: Int { Int(16 * min(1, Double(game.teamTotal) / Double(max(game.goal, 1)))) }

    private func toast(_ text: String) {
        model.toast = text
        model.toastCount += 1
        AccessibilityNotification.Announcement(text).post()
    }

    private func flash(_ color: UIColor, _ strength: CGFloat) {
        guard !Tokens.Motion.reduced else { return }
        flashNode.color = color
        flashNode.removeAllActions()
        flashNode.alpha = strength
        flashNode.run(.fadeOut(withDuration: 0.35))
    }

    private func popup(_ text: String, at p: CGPoint, color: UIColor, size: CGFloat) {
        let label = ToonLabel(text, size: size, color: color)
        label.position = CGPoint(x: min(max(p.x, 30), ArenaLayout.width - 30), y: min(p.y + 24, layout.hudFloor - 14))
        label.zPosition = 800
        addChild(label)
        FX.pop(label)
        label.run(.sequence([.group([.moveBy(x: 0, y: 30, duration: 0.7),
                                     .sequence([.wait(forDuration: 0.4), .fadeOut(withDuration: 0.3)])]), .removeFromParent()]))
    }

    // MARK: - Touches

    /// The stick can be taken up at any time, the countdown included, so a thumb that is already
    /// down when the round starts is already steering.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard me != nil, !model.paused, !ended else { return }
        for t in touches {
            let p = t.location(in: self)
            if let button, buttonTouch == nil, p.distance(to: button.position) < ActionButton.radius + 16 {
                buttonTouch = t
                if resume <= 0 { runner.press() }
            } else if aims {
                // Anywhere on the lawn is somewhere to pull a strike back from.
                if aimTouch == nil, runner.stage == .playing, resume <= 0 {
                    aimTouch = t
                    aimFrom = p
                    aimTo = p
                }
            } else if steers, stickTouch == nil {
                stickTouch = t
                stick.begin(p)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            if t === stickTouch { stick.move(t.location(in: self)) }
            if t === aimTouch { aimTo = t.location(in: self) }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches, strike: true) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches, strike: false) }

    /// The pull of a strike as the game wants it: which way, and how hard out of 1.
    private var pull: Vec2 {
        let v = CGVector(dx: aimFrom.x - aimTo.x, dy: aimFrom.y - aimTo.y)
        let length = hypot(v.dx, v.dy)
        guard length > 1 else { return .zero }
        let power = min(1, length / 150)
        return Vec2(Double(v.dx / length * power), Double(v.dy / length * power))
    }

    private func lift(_ touches: Set<UITouch>, strike: Bool) {
        for t in touches {
            if t === stickTouch {
                stickTouch = nil
                stick.end()
            }
            if t === buttonTouch { buttonTouch = nil }
            if t === aimTouch {
                aimTo = t.location(in: self)
                if strike, pull.length > 0.12 { runner.shoot(pull) }
                aimTouch = nil
                aimLine.path = nil
            }
        }
    }

    // MARK: - What stays in SpriteKit

    private func refresh(_ dt: TimeInterval) {
        feedModel()
        // How far the player can see, and from where, in the games where that is not the whole floor.
        var sight: Double?
        var eye = Vec2.zero
        if let gauntlet, let i = gauntlet.human {
            let r = gauntlet.runners[i]
            let inReach = config.handVisible && r.up && r.handCool == 0 && gauntlet.mechanism(near: r.pos) != nil
            let ready = runner.stage == .playing ? r.dashReady : 1
            button?.show(ring: ready < 1 ? ready : nil, lit: ready >= 1, pressed: buttonTouch != nil, hand: inReach)
            let far = gauntlet.vision(r.pos, r.pos)
            if far < 250 { sight = far }
            eye = r.last + (r.pos - r.last) * runner.alpha
        } else if let arena, let a = arena.human {
            let working = buttonTouch != nil && a.holdSpot >= 0
            button?.show(ring: working ? a.hold / max(a.holdNeed, 0.01) : nil, lit: arena.canInteract(a), pressed: buttonTouch != nil,
                         hand: config.handVisible && arena.canSabotage(a) != nil)
            sight = arena.sightRadius
            eye = a.last + (a.pos - a.last) * runner.alpha
            aim(from: a, in: arena)
        } else {
            dark.isHidden = true
            return
        }

        // The edge of what the player can see, by candlelight, in fog or with the candles out.
        if let sight, runner.stage != .countdown {
            if dark.isHidden {
                dark.isHidden = false
                dark.setScale(4)
            }
            dark.position = stage.screenPoint(eye)
            let want = CGFloat(sight) * stage.pointScale / 125
            dark.setScale(dark.xScale + (want - dark.xScale) * CGFloat(1 - exp(-7 * dt)))
        } else if !dark.isHidden {
            // The light comes back the way it went.
            dark.setScale(dark.xScale + (5 - dark.xScale) * CGFloat(1 - exp(-7 * dt)))
            if dark.xScale > 4.6 { dark.isHidden = true }
        }
    }

    /// Draws where a strike being pulled back would come down.
    private func aim(from a: ArenaActor, in arena: ArenaCore) {
        guard aimTouch != nil, let lawn = arena as? HurleyCore, pull.length > 0.05 else {
            aimLine.path = nil
            return
        }
        let from = stage.screenPoint(a.pos), to = stage.screenPoint(lawn.landing(from: a.pos, pull))
        let path = CGMutablePath()
        path.move(to: CGPoint(x: from.x, y: from.y + 10))
        path.addLine(to: to)
        path.addEllipse(in: CGRect(x: to.x - 7, y: to.y - 5, width: 14, height: 10))
        aimLine.path = path
        aimLine.alpha = pull.length > 0.12 && a.stun <= 0 && a.aux >= 1 ? 0.9 : 0.3
    }

    /// Hands the numbers to SwiftUI. Each value is only written when it has changed, so the view is
    /// left alone on the frames where nothing has.
    private func feedModel() {
        func put<T: Equatable>(_ path: ReferenceWritableKeyPath<ArenaHUDModel, T>, _ value: T) {
            if model[keyPath: path] != value { model[keyPath: path] = value }
        }
        put(\.seconds, Int(game.timeLeft.rounded(.up)))
        put(\.timeFraction, (game.timeLeft / max(game.totalTime, 1) * 200).rounded() / 200)
        put(\.urgent, game.timeLeft < 8)
        put(\.teamTotal, game.teamTotal)
        put(\.canPause, runner.stage == .playing && resume <= 0)
        let tally = game.tally
        if model.tally != tally {
            model.tally = tally
            // Best first, and seat order among those level, so nobody jumps about for nothing.
            let order = tally.indices.sorted { tally[$0] != tally[$1] ? tally[$0] > tally[$1] : $0 < $1 }
            if let me, let now = order.firstIndex(of: me) {
                if now < place, runner.stage == .playing { Feedback.play(.nearMiss) }
                place = now
            }
            put(\.order, order)
        }
        if let gauntlet {
            put(\.sealing, (gauntlet.sealing * 40).rounded() / 40)
            if let i = gauntlet.human {
                put(\.load, .bags(have: gauntlet.runners[i].carry, of: Feel.maxCarry, streak: gauntlet.runners[i].streak))
            }
        } else if let arena, let a = arena.human, let m = arena.meter(for: a) {
            put(\.meter, ArenaHUDModel.Meter(label: m.label, value: (m.value * 100).rounded() / 100))
        }
    }
}
