import SpriteKit
import SwiftUI

/// The round button that does whatever there is to do where you are standing. It always says
/// Interact, so it never gives away that there is something secret within reach.
final class InteractButton: SKNode {
    static let radius: CGFloat = 34
    private let face = SKShapeNode(circleOfRadius: InteractButton.radius)
    private let ring = SKShapeNode()
    private let label = ToonLabel("Interact", size: 12, color: Toon.cream)

    override init() {
        super.init()
        face.lineWidth = 2
        addChild(face)
        ring.strokeColor = Toon.ember
        ring.lineWidth = 4
        ring.lineCap = .round
        ring.fillColor = .clear
        addChild(ring)
        addChild(label)
        zPosition = 900
        show(enabled: false, pressed: false, progress: 0)
    }

    required init?(coder: NSCoder) { return nil }

    func show(enabled: Bool, pressed: Bool, progress: CGFloat) {
        face.fillColor = (enabled ? Toon.goldDark : Toon.ink).withAlphaComponent(pressed ? 0.95 : 0.72)
        face.strokeColor = enabled ? Toon.gold : Toon.cream.withAlphaComponent(0.3)
        label.alpha = enabled ? 1 : 0.45
        setScale(pressed ? 0.93 : 1)
        if progress > 0.01 {
            let path = CGMutablePath()
            path.addArc(center: .zero, radius: Self.radius + 6, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi * min(progress, 1), clockwise: true)
            ring.path = path
        } else {
            ring.path = nil
        }
    }
}

/// Runs a mini-game and everything the thumbs touch: the stick, the Interact button, the strike in
/// the hurling. The game itself is an `ArenaCore`, a stage underneath draws it, and the scores along
/// the top are SwiftUI, fed through `model`.
final class ArenaHUDScene: SKScene {
    let config: ArenaConfig
    let layout: ArenaLayout
    let runner: ArenaRunner
    let stage: ArenaStage
    let model: ArenaHUDModel
    var core: ArenaCore { runner.core }
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
    private var watch = ArenaWatch()

    private let flashNode = SKSpriteNode(color: Toon.red, size: .zero)
    private let dark = Sprites.darkness()
    private var mapCells: [SKSpriteNode] = []
    private let mapDot = SKSpriteNode(color: Toon.gold, size: CGSize(width: 4, height: 4))
    private var mapCentre = CGPoint.zero

    private let stick = ThumbStick()
    private let button = InteractButton()
    private var stickTouch: UITouch?
    private var buttonTouch: UITouch?
    private var aimTouch: UITouch?
    private var aimFrom = CGPoint.zero
    private var aimNow = CGPoint.zero
    private let aimLine = SKShapeNode()
    private var pendingShot: Vec2?

    private var me: Contestant? { config.spectating ? nil : config.cast.first { $0.isHuman } }
    private var spec: MissionSpec { core.spec }

    init(config: ArenaConfig, layout: ArenaLayout) {
        self.config = config
        self.layout = layout
        runner = ArenaRunner(config.setup)
        stage = ArenaStages.make(config, runner.core, layout)
        model = ArenaHUDModel(config: config, core: runner.core)
        super.init(size: layout.size)
        scaleMode = .aspectFit
        // The games seen from above are drawn underneath, in their own view.
        backgroundColor = stage is SKNode ? Toon.outline : .clear
    }

    required init?(coder: NSCoder) { return nil }

    override func didMove(to view: SKView) {
        guard !built else { return }
        built = true
        view.isMultipleTouchEnabled = true
        if let drawn = stage as? SKNode {
            // Raised whole, and held in a node of its own so a shake can throw the stage about freely.
            let holder = SKNode()
            holder.position.y = layout.lift
            holder.addChild(drawn)
            addChild(holder)
        }
        dark.zPosition = 600
        // Dusk does half the work in the games seen from above.
        dark.alpha = stage is SKNode ? 0.82 : 0.66
        dark.isHidden = true
        addChild(dark)
        flashNode.size = layout.size
        flashNode.anchorPoint = .zero
        flashNode.alpha = 0
        flashNode.zPosition = 700
        addChild(flashNode)
        buildMap()
        addChild(stick)
        button.position = CGPoint(x: ArenaLayout.width - 54, y: layout.safeBottom + 62)
        aimLine.strokeColor = Toon.cream
        aimLine.lineWidth = 4
        aimLine.lineCap = .round
        aimLine.zPosition = 850
        addChild(aimLine)
        if me != nil, !config.setup.autopilot, config.setup.kind != .hurley, config.setup.kind != .ceiliChaos { addChild(button) }
        refresh()
    }

    // MARK: - The loop

    override func update(_ currentTime: TimeInterval) {
        let real = lastTime == 0 ? 0 : min(currentTime - lastTime, 1.0 / 30)
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

        let dt = real * pace
        var input = ArenaInput()
        input.move = stage.arenaVector(stick.vector)
        input.interact = buttonTouch != nil
        input.shot = pendingShot
        pendingShot = nil
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
            }
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

        stage.sync(core, dt: dt)
        for cue in core.cues { play(cue) }
        core.cues.removeAll()
        refresh()
        if runner.stage == .playing { watch.observe(core, human: me.flatMap { core.actor($0.id) }) }
    }

    private func finish() {
        let human = me.flatMap { core.actor($0.id) }
        model.summary = ArenaHUDModel.Summary(count: human.map(core.count(of:)) ?? 0, teamTotal: core.teamTotal,
                                              quest: config.questVisible ? (core.questBy == me?.id) : nil)
        model.ended = true
        Feedback.play(.time)
        dropTouches()
        let mine = me.flatMap { core.actor($0.id) }.map(core.count(of:))
        if (mine == nil || mine! >= spec.par), !Tokens.Motion.reduced {
            FX.confetti(in: self, size: layout.size, colors: config.cast.map(\.color) + [Toon.gold])
        }
    }

    private func dropTouches() {
        stick.end()
        stickTouch = nil
        buttonTouch = nil
        aimTouch = nil
    }

    private func play(_ cue: ArenaCue) {
        switch cue {
        case .popup(let text, let at, let seat, let bad):
            let mine = seat != nil && seat == me?.id
            // Nothing pops up over somebody you cannot see.
            if let seat, !mine, core.hidesUnseen, let h = core.human, core.actor(seat)?.seenBy.has(h.id) == false { return }
            let color = bad ? Toon.red : (mine ? Toon.gold : (seat.map(config.color) ?? Toon.cream))
            popup(text, at: stage.screenPoint(at, z: 0), color: color, size: mine ? 20 : (seat == nil ? 15 : 13))
            if mine {
                Feedback.play(bad ? .penalty : .score(me.flatMap { core.actor($0.id) }.map(core.count(of:)) ?? 0))
            } else {
                Feedback.play(seat == nil ? .teamBonus : .otherScore)
            }
        case .banner(let text):
            model.toast = text
            model.toastCount += 1
            AccessibilityNotification.Announcement(text).post()
            Feedback.play(.banner)
        case .flash(let bad):
            flashNode.color = bad ? Toon.red : Toon.gold
            flashNode.removeAllActions()
            flashNode.alpha = 0.3
            flashNode.run(.fadeOut(withDuration: 0.35))
        case .shake:
            stage.shake(5)
            Feedback.play(.shake)
        case .burst(let at, let seat):
            FX.burst(in: self, at: stage.screenPoint(at, z: 0), color: seat.map(config.color) ?? Toon.cream, count: 6, reach: 20)
            Feedback.play(.burst)
        }
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

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard runner.stage == .playing, me != nil, !config.setup.autopilot, !model.paused, resume <= 0 else { return }
        for t in touches {
            let p = t.location(in: self)
            if button.parent != nil, buttonTouch == nil, p.distance(to: button.position) < InteractButton.radius + 14 {
                buttonTouch = t
            } else if config.setup.kind == .hurley {
                if aimTouch == nil {
                    aimTouch = t
                    aimFrom = p
                    aimNow = p
                }
            } else if stickTouch == nil {
                stickTouch = t
                stick.begin(p)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            if t === stickTouch { stick.move(t.location(in: self)) }
            if t === aimTouch { aimNow = t.location(in: self) }
        }
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
            if t === aimTouch {
                aimTouch = nil
                // Pulled back and let go: the strike flies the opposite way.
                let pull = CGVector(dx: aimFrom.x - aimNow.x, dy: aimFrom.y - aimNow.y)
                let power = min(1, hypot(pull.dx, pull.dy) / 150)
                if power > 0.12, runner.stage == .playing {
                    let len = hypot(pull.dx, pull.dy)
                    pendingShot = Vec2(Double(pull.dx / len), Double(pull.dy / len)) * Double(power)
                }
            }
        }
    }

    // MARK: - What stays in SpriteKit

    /// The shared map of the maze, filled in as anyone walks it. It sits under the scores, on the right.
    private func buildMap() {
        guard core is MazeCore else { return }
        let n = MazeCore.cells
        mapCentre = CGPoint(x: ArenaLayout.width - 38, y: layout.hudFloor - 34)
        let back = SKShapeNode(rectOf: CGSize(width: CGFloat(n) * 6 + 8, height: CGFloat(n) * 6 + 8), cornerRadius: 5)
        back.fillColor = Toon.ink.withAlphaComponent(0.78)
        back.strokeColor = Toon.gold.withAlphaComponent(0.45)
        back.lineWidth = 1
        back.position = mapCentre
        back.zPosition = 880
        addChild(back)
        for i in 0..<n * n {
            let cell = SKSpriteNode(color: Toon.cream, size: CGSize(width: 5, height: 5))
            cell.position = CGPoint(x: mapCentre.x + (CGFloat(i % n) - CGFloat(n - 1) / 2) * 6,
                                    y: mapCentre.y + (CGFloat(i / n) - CGFloat(n - 1) / 2) * 6)
            cell.zPosition = 881
            addChild(cell)
            mapCells.append(cell)
        }
        mapDot.zPosition = 882
        addChild(mapDot)
    }

    private func refresh() {
        let human = me.flatMap { core.actor($0.id) }
        feedModel(human)

        if let human {
            let enabled = runner.stage == .playing && core.canInteract(human)
            button.show(enabled: enabled, pressed: buttonTouch != nil, progress: human.hold > 0 ? CGFloat(human.hold / human.holdNeed) : 0)
        }

        // The edge of what the player can see, where a game has one.
        if let human, let radius = core.sightRadius, runner.stage != .countdown {
            dark.isHidden = false
            dark.position = stage.screenPoint(human.pos, z: 0)
            let want = CGFloat(radius) * stage.pointScale / 125
            dark.xScale += (want - dark.xScale) * 0.15
            dark.yScale = dark.xScale * stage.squash
        } else {
            dark.isHidden = true
            dark.setScale(4)
        }

        if let maze = core as? MazeCore {
            let n = MazeCore.cells
            for (i, cell) in mapCells.enumerated() { cell.alpha = maze.revealed[i] ? 0.85 : 0.12 }
            if let human {
                let block = MazeCore.block
                mapDot.isHidden = false
                mapDot.position = CGPoint(x: mapCentre.x + (CGFloat(human.pos.x / block - 1.5) / 2 - CGFloat(n - 1) / 2) * 6,
                                          y: mapCentre.y + (CGFloat(human.pos.y / block - 1.5) / 2 - CGFloat(n - 1) / 2) * 6)
            } else {
                mapDot.isHidden = true
            }
        }

        if aimTouch != nil, let human {
            let from = stage.screenPoint(human.pos, z: 0)
            let pull = CGVector(dx: aimFrom.x - aimNow.x, dy: aimFrom.y - aimNow.y)
            let path = CGMutablePath()
            path.move(to: from)
            path.addLine(to: CGPoint(x: from.x + pull.dx * 0.8, y: from.y + pull.dy * 0.8))
            aimLine.path = path
            aimLine.alpha = 0.4 + 0.6 * min(1, hypot(pull.dx, pull.dy) / 150)
        } else {
            aimLine.path = nil
        }
    }

    /// Hands the scores to SwiftUI. Each value is only written when it has changed, so the view is
    /// left alone on the frames where nothing has.
    private func feedModel(_ human: ArenaActor?) {
        func put<T: Equatable>(_ path: ReferenceWritableKeyPath<ArenaHUDModel, T>, _ value: T) {
            if model[keyPath: path] != value { model[keyPath: path] = value }
        }
        put(\.seconds, Int(core.timeLeft.rounded(.up)))
        put(\.timeFraction, (core.timeLeft / core.totalTime * 200).rounded() / 200)
        put(\.urgent, core.timeLeft < 8)
        put(\.teamTotal, core.teamTotal)
        put(\.questProgress, core.questProgress)
        put(\.canPause, runner.stage == .playing && resume <= 0)

        let counts = Dictionary(uniqueKeysWithValues: core.actors.map { ($0.id, core.count(of: $0)) })
        if counts != model.counts {
            model.counts = counts
            model.order = config.cast.map(\.id).sorted { (counts[$0] ?? 0, -$0) > (counts[$1] ?? 0, -$1) }
        }
        put(\.count, human.map(core.count(of:)) ?? 0)

        if let human, let m = core.meter(for: human) {
            put(\.meterLabel, m.label)
            put(\.meterValue, (clamp(m.value, 0, 1) * 50).rounded() / 50)
        } else {
            put(\.meterLabel, nil)
        }
    }
}

/// Notices the moments the core has no cue for, by watching the numbers change from frame to frame.
struct ArenaWatch {
    private var par = false
    private var teamGoal = false
    private var quest = 0
    private var second = Int.max
    private var holding = false
    private var holdStep = 0

    mutating func observe(_ core: ArenaCore, human: ArenaActor?) {
        if let human {
            let reached = core.count(of: human) >= core.spec.par
            if reached, !par { Feedback.play(.par) }
            par = reached

            if human.hold > 0, human.holdNeed > 0 {
                let step = Int(human.hold / human.holdNeed * 6)
                if step != holdStep, holding { Feedback.play(.holdTick) }
                holdStep = step
                holding = true
            } else {
                if holding, human.stun <= 0 { Feedback.play(.holdDone) }
                holding = false
                holdStep = 0
            }
        }
        let goal = core.teamTotal >= core.teamGoal
        if goal, !teamGoal { Feedback.play(.teamGoal) }
        teamGoal = goal

        if core.questProgress > quest { Feedback.play(core.questProgress >= core.questGoal ? .questDone : .questStep) }
        quest = core.questProgress

        let s = Int(core.timeLeft.rounded(.up))
        if s != second, s <= 10, s > 0, second != Int.max { Feedback.play(.lastSeconds) }
        second = s
    }
}
