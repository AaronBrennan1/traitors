import SpriteKit
import SwiftUI

/// The one button. It always says Dash, and for a traitor standing by something they could work
/// it wears the faintest red rim: nothing anyone looking over a shoulder would notice.
final class DashButton: SKNode {
    static let radius: CGFloat = 36
    private let face = SKShapeNode(circleOfRadius: DashButton.radius)
    private let ring = SKShapeNode()
    private let rim = SKShapeNode(circleOfRadius: DashButton.radius + 3)
    private let label = ToonLabel("Dash", size: 13, color: Toon.cream)
    private var step = -1

    override init() {
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
        show(ready: 1, pressed: false, hand: false)
    }

    required init?(coder: NSCoder) { return nil }

    /// `ready` runs from 0, just used, to 1.
    func show(ready: Double, pressed: Bool, hand: Bool) {
        let full = ready >= 1
        face.fillColor = (full ? Toon.goldDark : Toon.ink).withAlphaComponent(pressed ? 0.95 : 0.72)
        face.strokeColor = full ? Toon.gold : Toon.cream.withAlphaComponent(0.3)
        label.alpha = full ? 1 : 0.45
        setScale(pressed ? 0.93 : 1)
        rim.alpha = hand ? 0.55 : 0
        // The ring is only redrawn when it has visibly moved on.
        let now = full ? 24 : Int(ready * 24)
        guard now != step else { return }
        step = now
        if full {
            ring.path = nil
        } else {
            let path = CGMutablePath()
            path.addArc(center: .zero, radius: Self.radius + 6, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi * CGFloat(now) / 24, clockwise: true)
            ring.path = path
        }
    }
}

/// Runs the gauntlet and everything the thumbs touch: the stick and the Dash button. The game
/// itself is a `Gauntlet`, the stage underneath draws it, and the tally along the top is SwiftUI,
/// fed through `model`.
final class ArenaScene: SKScene {
    let config: ArenaConfig
    let layout: ArenaLayout
    let runner: ArenaRunner
    let stage: CourseStage
    let model: ArenaHUDModel
    var core: Gauntlet { runner.core }
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
    private let button = DashButton()
    private var stickTouch: UITouch?
    private var buttonTouch: UITouch?

    /// The player's place among the runners, while they are the one at the controls.
    private var me: Int? { core.human }
    private var mine: PlayerID? { me.map { core.runners[$0].id } }

    init(config: ArenaConfig, layout: ArenaLayout) {
        self.config = config
        self.layout = layout
        runner = ArenaRunner(config.setup)
        stage = CourseStage(config, runner.core, layout)
        model = ArenaHUDModel(config: config, core: runner.core)
        super.init(size: layout.size)
        scaleMode = .aspectFit
        backgroundColor = Toon.pit
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
        addChild(stick)
        button.position = CGPoint(x: ArenaLayout.width - 58, y: layout.safeBottom + 66)
        if me != nil { addChild(button) }
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
        input.move = Vec2(Double(stick.vector.dx), Double(stick.vector.dy))
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
            let s = Int(core.timeLeft.rounded(.up))
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
        for cue in core.cues { play(cue) }
        core.cues.removeAll(keepingCapacity: true)
        refresh(real)
    }

    private func finish() {
        var own: ArenaHUDModel.Summary.Own?
        if let me {
            let r = core.runners[me]
            let key = "best.\(config.setup.kind.rawValue)"
            let best = UserDefaults.standard.integer(forKey: key)
            if r.banked > best { UserDefaults.standard.set(r.banked, forKey: key) }
            own = .init(bags: r.banked, streak: r.bestStreak, near: r.nearMisses, best: max(best, r.banked), record: r.banked > best && r.banked > 0)
        }
        var hand: ArenaHUDModel.Summary.Hand?
        if config.handVisible, let me {
            hand = .init(uses: core.acts[me], cost: Int(core.loss[me].rounded()), sank: core.sunkBy == core.runners[me].id)
        }
        model.summary = ArenaHUDModel.Summary(teamTotal: core.teamTotal, own: own, hand: hand)
        model.ended = true
        Feedback.play(core.won ? .teamGoal : .time)
        dropTouches()
        if core.won, !Tokens.Motion.reduced {
            FX.confetti(in: self, size: layout.size, colors: config.cast.map(\.color) + [Toon.gold])
        }
    }

    private func dropTouches() {
        stick.end()
        stickTouch = nil
        buttonTouch = nil
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
                Feedback.play(.score(Int(16 * min(1, Double(core.teamTotal) / Double(max(core.goal, 1))))))
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
            if let me, core.runners[me].pos.distance(to: at) < 40 { Feedback.play(.bump) }
        case .nearMiss(let seat, let at):
            guard seat == mine else { break }
            popup("close!", at: stage.screenPoint(at), color: Toon.cream, size: 12)
            FX.burst(in: self, at: stage.screenPoint(at), color: Toon.gold, count: 5, reach: 18)
            Feedback.play(.nearMiss)
        case .warned(let h):
            // A corridor full of traps should tick, not clatter.
            if stage.inEarshot(core.hazards[h].a), lastTime - lastWarn > 0.12 {
                lastWarn = lastTime
                Feedback.play(.warn)
            }
        case .fired(let h):
            if stage.inEarshot(core.hazards[h].a) { Feedback.play(.strike) }
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
        }
    }

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
            if buttonTouch == nil, p.distance(to: button.position) < DashButton.radius + 16 {
                buttonTouch = t
                if resume <= 0 { runner.press() }
            } else if stickTouch == nil {
                stickTouch = t
                stick.begin(p)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches where t === stickTouch { stick.move(t.location(in: self)) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }

    private func lift(_ touches: Set<UITouch>) {
        for t in touches {
            if t === stickTouch {
                stickTouch = nil
                stick.end()
            }
            if t === buttonTouch { buttonTouch = nil }
        }
    }

    // MARK: - What stays in SpriteKit

    private func refresh(_ dt: TimeInterval) {
        feedModel()
        guard let me else {
            dark.isHidden = true
            return
        }
        let r = core.runners[me]
        let inReach = config.handVisible && r.up && r.handCool == 0 && core.mechanism(near: r.pos) != nil
        button.show(ready: runner.stage == .playing ? r.dashReady : 1, pressed: buttonTouch != nil, hand: inReach)

        // The edge of what the player can see, by candlelight or with the candles out.
        let sight = core.vision(r.pos, r.pos)
        if sight < 250, runner.stage != .countdown {
            let p = r.last + (r.pos - r.last) * runner.alpha
            if dark.isHidden {
                dark.isHidden = false
                dark.setScale(4)
            }
            dark.position = stage.screenPoint(p)
            let want = CGFloat(sight) / 125
            dark.setScale(dark.xScale + (want - dark.xScale) * CGFloat(1 - exp(-7 * dt)))
        } else if !dark.isHidden {
            // The light comes back the way it went.
            dark.setScale(dark.xScale + (5 - dark.xScale) * CGFloat(1 - exp(-7 * dt)))
            if dark.xScale > 4.6 { dark.isHidden = true }
        }
    }

    /// Hands the numbers to SwiftUI. Each value is only written when it has changed, so the view is
    /// left alone on the frames where nothing has.
    private func feedModel() {
        func put<T: Equatable>(_ path: ReferenceWritableKeyPath<ArenaHUDModel, T>, _ value: T) {
            if model[keyPath: path] != value { model[keyPath: path] = value }
        }
        put(\.seconds, Int(core.timeLeft.rounded(.up)))
        put(\.timeFraction, (core.timeLeft / (Double(core.totalTicks) * Feel.tick) * 200).rounded() / 200)
        put(\.urgent, core.timeLeft < 8)
        put(\.teamTotal, core.teamTotal)
        put(\.sealing, (core.sealing * 40).rounded() / 40)
        put(\.canPause, runner.stage == .playing && resume <= 0)
        put(\.banked, core.runners.map(\.banked))
        if let me {
            put(\.streak, core.runners[me].streak)
            put(\.carry, core.runners[me].carry)
        }
    }
}
