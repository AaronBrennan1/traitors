import SpriteKit
import SwiftUI
import TraitorsEngine
import TraitorsGauntlet

/// What a reel says back to the card it plays in. The scene writes it; the view only reads.
@Observable final class ReelClock {
    /// 0 at the start of the loop, 1 at the end.
    var progress = 0.0
    /// Where each beat starts, as a share of the whole.
    var beats: [Double] = [0]
    /// How many times it has played through.
    var loops = 0
    /// Standing still on its poster, waiting to be asked to play.
    var waiting = false
}

/// How the camera takes a game.
private enum Shot {
    /// The whole floor, held still, clear of the controls by so much.
    case whole(deck: CGFloat)
    /// The stage as it draws itself for a tall screen, seen through a window this far up it.
    case window(CGFloat)
    /// The whole floor for a moment, then in close on the player, this much closer.
    case follow(CGFloat)
}

/// A few seconds of a mini-game, playing itself in a small frame. The stage is the game's own
/// stage and the game is the game; only the thumbs are a script's. Nothing here makes a sound or
/// keeps a score: it is a picture of how the game is played.
final class DemoScene: SKScene {
    /// The picture is always this size in its own points, three wide to four tall.
    static let picture = CGSize(width: 390, height: 520)

    let clock = ReelClock()
    private(set) var kind: MissionKind
    private(set) var reel: ArenaDemo.Reel
    /// Shows one moment and plays only when asked: for anyone who has asked for less movement.
    private let still: Bool

    private var demo: ArenaDemo
    private var config: ArenaConfig
    private var stage: (any ArenaStage)?
    private var thumbs: GhostThumbs?
    /// Holds the stage, so the camera can move and zoom without the stage knowing.
    private let rig = SKNode()
    private let dark = Sprites.darkness()
    private let curtain = SKSpriteNode(color: Toon.ink, size: DemoScene.picture)
    private let flashNode = SKSpriteNode(color: Toon.red, size: DemoScene.picture)
    private let aimLine = SKShapeNode()
    private let reach = SKShapeNode(ellipseOf: CGSize(width: 46, height: 22))

    /// False while nobody is looking: off the screen, or with the app set aside. Nothing moves and nothing is drawn.
    var playing = true {
        didSet { view?.isPaused = !playing }
    }

    private var lastTime: TimeInterval = 0
    private var built = false
    private var cutting = false
    private var playingOnce = false
    /// Seconds since this run of the loop began, for the camera's opening move.
    private var runTime = 0.0
    private var zoom: CGFloat = 1
    private var centre = CGPoint.zero
    private var layout = ArenaLayout(height: 760, safeTop: 0, safeBottom: 0)

    init(kind: MissionKind, reel: ArenaDemo.Reel, still: Bool = Tokens.Motion.reduced) {
        self.kind = kind
        self.reel = reel
        self.still = still
        demo = ArenaDemo(kind, reel: reel)
        config = DemoScene.config(for: demo)
        super.init(size: Self.picture)
        scaleMode = .aspectFill
        backgroundColor = Toon.pit
        clock.beats = demo.beatStarts
        clock.waiting = still
    }

    required init?(coder: NSCoder) { return nil }

    /// The player in their own pale cloak, and the first of the cast for company.
    private static func config(for demo: ArenaDemo) -> ArenaConfig {
        let cast = demo.setup.cast.map { seat -> Contestant in
            if seat.isHuman { return Contestant(id: seat.id, name: "You", color: Tokens.Hue.youCloak.ui, isHuman: true) }
            let bot = Cast.bots[(seat.id - 1) % Cast.bots.count]
            return Contestant(id: seat.id, name: bot.name, color: Toon.cloak(bot.hue), isHuman: false)
        }
        return ArenaConfig(setup: demo.setup, cast: cast)
    }

    private var shot: Shot {
        switch kind {
        case .greatHall, .cellars, .armoury, .battlements, .crypt: return .whole(deck: 0)
        case .ceiliChaos: return .whole(deck: GhostThumbs.deck - 20)
        case .bogRelay: return .window(0)
        case .kiteRace: return .window(0)
        case .hurley: return .window(10)
        case .shipwreckDive: return .follow(1.35)
        case .hedgeMaze: return .follow(1.9)
        case .lanternRun: return .follow(1.45)
        case .marketDay: return .follow(1.4)
        case .sheepRoundUp: return .follow(1.3)
        case .banquetPrep: return .follow(1.25)
        }
    }

    /// The height of screen each stage is built for. A side-on stage rises with it, which is what
    /// lifts its ground clear of the controls.
    private var stageHeight: CGFloat {
        switch kind {
        case .bogRelay: return 740
        case .kiteRace: return 730
        case .hurley: return 700
        case .shipwreckDive: return 640
        default: return 760
        }
    }

    override func didMove(to view: SKView) {
        view.isPaused = !playing
        guard !built else { return }
        built = true
        view.isUserInteractionEnabled = false
        addChild(rig)
        dark.zPosition = 600
        dark.alpha = 0.9
        dark.isHidden = true
        addChild(dark)
        let vignette = Sprites.vignette(size: Self.picture, strength: 0.5)
        vignette.position = CGPoint(x: Self.picture.width / 2, y: Self.picture.height / 2)
        vignette.zPosition = 610
        addChild(vignette)
        for node in [flashNode, curtain] {
            node.anchorPoint = .zero
            node.alpha = 0
            addChild(node)
        }
        flashNode.zPosition = 700
        curtain.zPosition = 2000
        aimLine.strokeColor = Toon.cream
        aimLine.lineWidth = 4
        aimLine.lineCap = .round
        aimLine.zPosition = 880
        addChild(aimLine)
        reach.strokeColor = Toon.red
        reach.lineWidth = 2
        reach.fillColor = Toon.red.withAlphaComponent(0.12)
        reach.zPosition = 590
        reach.alpha = 0
        addChild(reach)
        mount()
    }

    /// Shows another game, or the other reel of this one, in the same frame.
    func load(kind: MissionKind, reel: ArenaDemo.Reel) {
        guard kind != self.kind || reel != self.reel else { return }
        self.kind = kind
        self.reel = reel
        demo = ArenaDemo(kind, reel: reel)
        clock.beats = demo.beatStarts
        clock.loops = 0
        if built { mount() }
    }

    /// For anyone watching a still: plays the loop through once and comes back to the poster.
    func playOnce() {
        guard still, !playingOnce else { return }
        playingOnce = true
        clock.waiting = false
        demo.restart()
        mount()
    }

    /// Builds the stage for the game as it now stands. The game is a new one every time the loop
    /// starts over, so its stage is too.
    private func mount() {
        if still, !playingOnce { demo.seek(demo.poster) }
        config = Self.config(for: demo)
        layout = ArenaLayout(height: stageHeight, safeTop: 0, safeBottom: 0)
        rig.removeAllChildren()
        thumbs?.removeFromParent()
        for node in children where node.name == "passing" { node.removeFromParent() }
        let made = ArenaStages.make(config, demo.session.game, layout)
        stage = made
        backgroundColor = made.backdrop
        rig.addChild(made)
        let ghost = GhostThumbs(kind: kind, hand: reel == .hand, frame: Self.picture)
        thumbs = ghost
        addChild(ghost)
        runTime = 0
        dark.isHidden = true
        aimLine.path = nil
        reach.alpha = 0
        compose(0, snap: true)
    }

    // MARK: - The loop

    override func update(_ currentTime: TimeInterval) {
        let real = lastTime == 0 ? 0 : min(currentTime - lastTime, 0.1)
        lastTime = currentTime
        guard built, stage != nil, !cutting else { return }
        if still, !playingOnce { return }
        runTime += real
        demo.advance(real)
        stage?.sync(alpha: demo.session.alpha, dt: real)
        for cue in demo.session.takeCues() { play(cue) }
        compose(real, snap: false)
        let progress = (demo.progress * 250).rounded() / 250
        if clock.progress != progress { clock.progress = progress }
        if demo.ended { cut() }
    }

    /// The end of the loop: down to black, back to the top, and up again.
    private func cut() {
        cutting = true
        curtain.run(.sequence([.fadeIn(withDuration: 0.2), .run { [weak self] in self?.rewind() }, .fadeOut(withDuration: 0.28)]))
    }

    private func rewind() {
        clock.loops += 1
        clock.progress = 0
        if playingOnce {
            playingOnce = false
            clock.waiting = true
        } else {
            demo.restart()
        }
        mount()
        cutting = false
    }

    // MARK: - The camera, the dark and the thumbs

    /// Where a point of the arena is in the picture.
    private func point(_ p: Vec2) -> CGPoint {
        guard let at = stage?.screenPoint(p) else { return .zero }
        return CGPoint(x: rig.position.x + at.x * zoom, y: rig.position.y + at.y * zoom)
    }

    /// The floor of the game, in the stage's own screen points.
    private var floor: CGRect {
        guard let stage else { return .zero }
        var size = Vec2(390, 520)
        if let g = demo.session.game as? Gauntlet { size = g.course.size }
        if let core = demo.session.game as? ArenaCore { size = core.size }
        let a = stage.screenPoint(.zero), b = stage.screenPoint(size)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    private func compose(_ dt: TimeInterval, snap: Bool) {
        guard let stage else { return }
        let size = Self.picture
        let panel = demo.session.panel
        let ease = snap ? 1 : CGFloat(1 - exp(-5 * dt))

        switch shot {
        case .window(let up):
            zoom = 1
            centre = CGPoint(x: size.width / 2, y: up + size.height / 2)
        case .whole(let deck):
            let box = floor
            zoom = min(size.width / box.width, (size.height - deck) / box.height)
            centre = CGPoint(x: box.midX, y: box.midY - deck / 2 / zoom)
        case .follow(let closer):
            let box = floor
            let deck = GhostThumbs.deck - 14
            let wide = min(size.width / box.width, (size.height - deck) / box.height)
            // Half a second on the whole floor, then in on the player. Not for anyone who would rather it kept still.
            let t = still ? 0 : min(max((runTime - 0.5) / 0.9, 0), 1)
            let k = CGFloat(t * t * (3 - 2 * t))
            zoom = wide * (1 + (max(closer, 1) - 1) * k)
            let all = CGPoint(x: box.midX, y: box.midY - deck / 2 / wide)
            var want = all
            if let eye = panel?.eye {
                let me = stage.screenPoint(eye)
                // The player sits a little above the middle of what is left over the controls.
                let near = CGPoint(x: me.x, y: me.y - deck * 0.42 / zoom)
                want = CGPoint(x: all.x + (near.x - all.x) * k, y: all.y + (near.y - all.y) * k)
            }
            // The picture never runs off the floor, except underneath the controls.
            let halfW = size.width / 2 / zoom, halfH = size.height / 2 / zoom
            let lowX = box.minX + halfW, highX = box.maxX - halfW
            let lowY = box.minY - deck * 0.55 / zoom + halfH, highY = box.maxY - halfH
            want.x = lowX <= highX ? min(max(want.x, lowX), highX) : box.midX
            want.y = lowY <= highY ? min(max(want.y, lowY), highY) : (lowY + highY) / 2
            centre = snap || t < 1 ? want : CGPoint(x: centre.x + (want.x - centre.x) * ease, y: centre.y + (want.y - centre.y) * ease)
        }
        rig.setScale(zoom)
        rig.position = CGPoint(x: size.width / 2 - centre.x * zoom, y: size.height / 2 - centre.y * zoom)

        thumbs?.show(demo.thumbs, panel: panel, dt: snap ? 0 : dt)

        // The edge of what the player can see, where the game says they cannot see it all.
        if let sight = panel?.sight, let eye = panel?.eye {
            let want = CGFloat(sight) * stage.pointScale * zoom / 125
            if dark.isHidden || snap {
                dark.isHidden = false
                dark.setScale(snap ? want : 4)
            }
            dark.position = point(eye)
            dark.setScale(dark.xScale + (want - dark.xScale) * CGFloat(1 - exp(-7 * dt)))
        } else {
            dark.isHidden = true
        }

        // Standing where a press would be the hand: a ring of blood at the player's feet.
        let inReach = panel?.handInReach == true
        reach.alpha += ((inReach ? 1 : 0) - reach.alpha) * (snap ? 1 : CGFloat(1 - exp(-10 * dt)))
        if let eye = panel?.eye {
            let at = point(eye)
            reach.position = CGPoint(x: at.x, y: at.y - 4 * zoom)
            reach.setScale(zoom * (inReach && !still ? 1 + 0.12 * CGFloat(sin(runTime * 7)) : 1))
        }
        drawAim()
    }

    /// Where a strike being drawn back would come down.
    private func drawAim() {
        guard let pull = demo.thumbs.pull, pull.length > 0.05, let aim = demo.session.aim(pull) else {
            aimLine.path = nil
            return
        }
        let from = point(aim.from), to = point(aim.to)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: from.x, y: from.y + 10))
        path.addLine(to: to)
        path.addEllipse(in: CGRect(x: to.x - 7, y: to.y - 5, width: 14, height: 10))
        aimLine.path = path
        aimLine.alpha = pull.length > 0.12 && aim.ready ? 0.9 : 0.3
    }

    // MARK: - What the game says back

    private func play(_ cue: ArenaCue) {
        guard let stage else { return }
        let mine = demo.session.player
        switch cue {
        case .pickup(let seat):
            if seat == mine { stage.figure(seat)?.squash() }
        case .banked(let seat, let bags, _, let at):
            let own = seat == mine
            popup("+\(bags)", at: point(at), color: own ? Toon.gold : config.color(seat), size: own ? 26 : 13)
            if own { burst(at: point(at), color: Toon.gold) }
        case .downed(let seat, let at, _):
            FX.burst(in: self, at: point(at), color: config.color(seat), count: 9, reach: 30)
            stage.shake(seat == mine ? 0.75 : 0.18)
        case .woke(let seat), .dash(let seat):
            stage.figure(seat)?.squash()
        case .nearMiss(let seat, let at):
            if seat == mine { popup("close!", at: point(at), color: Toon.cream, size: 12) }
        case .gave(let at):
            FX.burst(in: self, at: point(at), color: Toon.flagstoneHi, count: 5, reach: 16, z: 120)
        case .spilled(let at, let bags):
            banner("The vault has burst!", bad: true)
            popup("-\(bags)", at: point(at), color: Toon.danger, size: 26)
            stage.shake(0.6)
            flash(Toon.danger, 0.22)
        case .hand:
            flash(Toon.red, 0.16)
        case .popup(let text, let at, let seat, let bad):
            if let seat, seat != mine, !demo.session.playerSees(seat) { break }
            let own = seat == mine && seat != nil
            popup(text, at: point(at), color: bad ? Toon.danger : own ? Toon.gold : seat.map(config.color) ?? Toon.cream,
                  size: own ? 26 : seat == nil ? 20 : 13)
            if own, !bad {
                stage.figure(seat!)?.squash()
                burst(at: point(at), color: Toon.gold)
            } else if seat == nil, bad {
                flash(Toon.danger, 0.2)
            }
        case .banner(let text):
            banner(String(text.prefix(1)) + text.dropFirst().lowercased(), bad: reel == .hand && demo.session.ownHand?.uses ?? 0 > 0)
        case .flash(let bad):
            flash(bad ? Toon.danger : Toon.gold, 0.25)
        case .shake:
            stage.shake(0.45)
        case .burst(let at, let seat):
            FX.burst(in: self, at: point(at), color: seat.map(config.color) ?? Toon.cream, count: 6, reach: 20)
            if seat == mine, let seat { stage.figure(seat)?.squash() }
        case .warned, .fired, .cracked, .bump, .lights, .act, .sealing, .unsealed, .sealed, .overtime:
            break
        }
    }

    private func burst(at p: CGPoint, color: UIColor) {
        guard !Tokens.Motion.reduced else { return }
        FX.burst(in: self, at: p, color: color, count: 10, reach: 30)
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
        label.name = "passing"
        label.position = CGPoint(x: min(max(p.x, 34), Self.picture.width - 34), y: min(max(p.y + 26, GhostThumbs.deck), Self.picture.height - 70))
        label.zPosition = 950
        addChild(label)
        FX.pop(label)
        label.run(.sequence([.group([.moveBy(x: 0, y: 34, duration: 0.9),
                                     .sequence([.wait(forDuration: 0.6), .fadeOut(withDuration: 0.3)])]), .removeFromParent()]))
    }

    /// What the game announces, across the top of the picture on a strip of ink.
    private func banner(_ text: String, bad: Bool) {
        for node in children where node.name == "passing" && node.zPosition == 960 { node.removeFromParent() }
        let label = ToonLabel(text, size: 17, color: bad ? Toon.danger.shaded(1.25) : Toon.cream)
        let plate = SKShapeNode(rectOf: CGSize(width: label.size.width + 14, height: 30), cornerRadius: 15)
        plate.fillColor = Toon.ink.withAlphaComponent(0.82)
        plate.strokeColor = (bad ? Toon.red : Toon.gold).withAlphaComponent(0.7)
        plate.lineWidth = 1
        plate.name = "passing"
        plate.position = CGPoint(x: Self.picture.width / 2, y: Self.picture.height - 62)
        plate.zPosition = 960
        plate.addChild(label)
        addChild(plate)
        FX.pop(plate)
        plate.run(.sequence([.wait(forDuration: 1.5), .fadeOut(withDuration: 0.3), .removeFromParent()]))
    }
}
