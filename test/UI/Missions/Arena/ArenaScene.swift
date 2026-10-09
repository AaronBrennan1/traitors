import SpriteKit
import SwiftUI
import TraitorsEngine
import TraitorsGauntlet

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
    /// The game in play. Time and the thumbs go in; what to show, sound and hand back comes out.
    let session: ArenaSession
    /// Draws the game. It is the only thing here that looks at the game itself.
    let stage: any ArenaStage
    let model: ArenaHUDModel
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

    /// The player's seat, while they are the one at the controls.
    private var mine: PlayerID? { session.player }

    init(config: ArenaConfig, layout: ArenaLayout) {
        self.config = config
        self.layout = layout
        session = ArenaSession(config.setup)
        stage = ArenaStages.make(config, session.game, layout)
        model = ArenaHUDModel(config: config, goal: session.goal)
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
        if let button, mine != nil {
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
            if session.stage == .playing { resume = 1.5 }
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
        let before = session.stage
        session.advance(dt, input: input)

        switch session.stage {
        case .countdown:
            let number = session.countdownNumber.map(String.init) ?? ""
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
            let s = session.clock.secondsLeft
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
                done(session.result())
            }
        }

        stage.sync(alpha: session.alpha, dt: real)
        for cue in session.takeCues() { play(cue) }
        refresh(real)
    }

    /// For someone only watching: plays out what is left at once and hands the round back as it
    /// was played, so a mission comes out the same way whether or not anyone sat through it.
    func skip() {
        guard let done = onFinish else { return }
        onFinish = nil
        session.finish()
        done(session.result())
    }

    private func finish() {
        var own: ArenaHUDModel.Summary.Own?
        if let result = session.playerResult {
            let key = "best.\(config.setup.kind.rawValue)"
            let best = UserDefaults.standard.integer(forKey: key)
            if result.count > best { UserDefaults.standard.set(result.count, forKey: key) }
            let extras = result.extras.map { extra -> ArenaHUDModel.Summary.Extra in
                switch extra.what {
                case .inARow: return .init(value: "\(extra.value)", label: "in a row")
                case .nearMisses: return .init(value: "\(extra.value)", label: "near misses")
                case .place(let of): return .init(value: "\(extra.value)", label: "your place of \(of)")
                case .mostByAnyone: return .init(value: "\(extra.value)", label: "the most by anyone")
                }
            }
            own = .init(count: result.count, best: max(best, result.count), record: result.count > best && result.count > 0, extras: extras)
        }
        let hand = session.ownHand.map { ArenaHUDModel.Summary.Hand(uses: $0.uses, cost: $0.cost, sank: $0.sank) }
        model.endTitle = config.setup.kind.isGauntlet && session.won ? "Sealed" : "Time"
        model.summary = ArenaHUDModel.Summary(teamTotal: session.teamTotal, own: own, hand: hand)
        model.ended = true
        Feedback.play(session.won ? .teamGoal : .time)
        dropTouches()
        if session.won, !Tokens.Motion.reduced {
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
            if let eye = session.panel?.eye, eye.distance(to: at) < 40 { Feedback.play(.bump) }
        case .nearMiss(let seat, let at):
            guard seat == mine else { break }
            popup("close!", at: stage.screenPoint(at), color: Toon.cream, size: 12)
            FX.burst(in: self, at: stage.screenPoint(at), color: Toon.gold, count: 5, reach: 18)
            Feedback.play(.nearMiss)
        case .warned(let h):
            // A corridor full of traps should tick, not clatter.
            if let at = session.trap(h), stage.inEarshot(at), lastTime - lastWarn > 0.12 {
                lastWarn = lastTime
                Feedback.play(.warn)
            }
        case .fired(let h):
            if let at = session.trap(h), stage.inEarshot(at) { Feedback.play(.strike) }
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
            if let seat, seat != mine, !session.playerSees(seat) { break }
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
    private var note: Int { Int(16 * min(1, Double(session.teamTotal) / Double(max(session.goal, 1)))) }

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
        guard mine != nil, !model.paused, !ended else { return }
        for t in touches {
            let p = t.location(in: self)
            if let button, buttonTouch == nil, p.distance(to: button.position) < ActionButton.radius + 16 {
                buttonTouch = t
                if resume <= 0 { session.press() }
            } else if aims {
                // Anywhere on the lawn is somewhere to pull a strike back from.
                if aimTouch == nil, session.stage == .playing, resume <= 0 {
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
                if strike, pull.length > 0.12 { session.shoot(pull) }
                aimTouch = nil
                aimLine.path = nil
            }
        }
    }

    // MARK: - What stays in SpriteKit

    private func refresh(_ dt: TimeInterval) {
        feedModel()
        // The button, and how far the player can see and from where, as the game itself has it.
        guard let panel = session.panel else {
            dark.isHidden = true
            return
        }
        button?.show(ring: panel.ring, lit: panel.lit, pressed: buttonTouch != nil, hand: panel.handInReach)
        let sight = panel.sight, eye = panel.eye
        drawAim()

        // The edge of what the player can see, by candlelight, in fog or with the candles out.
        if let sight, session.stage != .countdown {
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
    private func drawAim() {
        guard aimTouch != nil, pull.length > 0.05, let aim = session.aim(pull) else {
            aimLine.path = nil
            return
        }
        let from = stage.screenPoint(aim.from), to = stage.screenPoint(aim.to)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: from.x, y: from.y + 10))
        path.addLine(to: to)
        path.addEllipse(in: CGRect(x: to.x - 7, y: to.y - 5, width: 14, height: 10))
        aimLine.path = path
        aimLine.alpha = pull.length > 0.12 && aim.ready ? 0.9 : 0.3
    }

    /// Hands the numbers to SwiftUI. Each value is only written when it has changed, so the view is
    /// left alone on the frames where nothing has.
    private func feedModel() {
        func put<T: Equatable>(_ path: ReferenceWritableKeyPath<ArenaHUDModel, T>, _ value: T) {
            if model[keyPath: path] != value { model[keyPath: path] = value }
        }
        let clock = session.clock
        put(\.seconds, clock.secondsLeft)
        put(\.timeFraction, clock.fraction)
        put(\.urgent, clock.urgent)
        put(\.teamTotal, session.teamTotal)
        put(\.canPause, session.stage == .playing && resume <= 0)
        let tally = session.tally
        if model.tally != tally {
            model.tally = tally
            // Best first, and seat order among those level, so nobody jumps about for nothing.
            let order = tally.indices.sorted { tally[$0] != tally[$1] ? tally[$0] > tally[$1] : $0 < $1 }
            if let mine, let me = config.setup.cast.firstIndex(where: { $0.id == mine }), let now = order.firstIndex(of: me) {
                if now < place, session.stage == .playing { Feedback.play(.nearMiss) }
                place = now
            }
            put(\.order, order)
        }
        if let sealing = session.sealing { put(\.sealing, (sealing * 40).rounded() / 40) }
        let panel = session.panel
        if let bags = panel?.bags { put(\.load, .bags(have: bags.have, of: bags.of, streak: bags.streak)) }
        if let m = panel?.meter { put(\.meter, ArenaHUDModel.Meter(label: m.label, value: (m.value * 100).rounded() / 100)) }
    }
}
