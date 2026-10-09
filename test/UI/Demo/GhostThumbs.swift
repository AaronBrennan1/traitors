import SpriteKit
import TraitorsEngine
import TraitorsGauntlet

/// The thumbs of a demonstration, drawn over the picture: the game's own stick and its own
/// button, with a fingertip on each, so that watching the reel is watching how it is played.
final class GhostThumbs: SKNode {
    /// How much of the bottom of the picture the controls take.
    static let deck: CGFloat = 104

    private let frameSize: CGSize
    private let tint: UIColor
    private let stick: ThumbStick?
    private let button: ActionButton?
    private let leftTip = GhostThumbs.fingertip()
    private let rightTip = GhostThumbs.fingertip()
    private let halo = SKShapeNode(circleOfRadius: ActionButton.radius + 9)
    private let tether = SKShapeNode()
    private let stickHome = CGPoint(x: 72, y: 62)
    private let buttonHome: CGPoint
    private let pullHome: CGPoint

    private var push = CGVector.zero
    private var taps = 0
    /// Seconds the button still shows as pressed after a tap.
    private var pressed = 0.0
    private var wasPulling = false
    private var lastPull = CGPoint.zero

    /// `hand` is the shadow's hand being shown: what the thumbs do there is marked in blood.
    init(kind: MissionKind, hand: Bool, frame: CGSize) {
        frameSize = frame
        tint = hand ? Toon.red : Toon.gold
        let aims = kind == .hurley
        stick = aims ? nil : ThumbStick()
        button = kind.button.map(ActionButton.init)
        buttonHome = CGPoint(x: frame.width - 60, y: 64)
        pullHome = CGPoint(x: frame.width / 2, y: 178)
        super.init()
        zPosition = 900

        // A little dusk under the controls, so they read over any floor.
        let scrim = SKSpriteNode(texture: GhostThumbs.scrim, size: CGSize(width: frame.width, height: Self.deck + 40))
        scrim.anchorPoint = .zero
        scrim.zPosition = -10
        addChild(scrim)

        if let stick {
            stick.zPosition = 0
            addChild(stick)
            stick.show(at: stickHome, push: .zero)
            addChild(leftTip)
        }
        if let button {
            button.position = buttonHome
            button.zPosition = 0
            button.setScale(0.92)
            addChild(button)
            halo.strokeColor = Toon.red
            halo.lineWidth = 2.5
            halo.fillColor = .clear
            halo.glowWidth = 3
            halo.position = buttonHome
            halo.alpha = 0
            halo.zPosition = -1
            addChild(halo)
            addChild(rightTip)
        }
        if aims {
            tether.strokeColor = Toon.cream.withAlphaComponent(0.55)
            tether.lineWidth = 2
            tether.lineCap = .round
            tether.zPosition = 1
            addChild(tether)
            addChild(leftTip)
            leftTip.alpha = 0
        }
    }

    required init?(coder: NSCoder) { return nil }

    /// A fingertip: a pale pad with a gold rim, soft at the edge.
    private static func fingertip() -> SKNode {
        let tip = Props.sprite("fingertip", CGSize(width: 40, height: 40)) { c in
            Props.fill(c, Props.oval(3, 5, 34, 34), UIColor.black.withAlphaComponent(0.28))
            Props.fill(c, Props.oval(4, 3, 32, 32), Toon.cream.withAlphaComponent(0.92))
            Props.stroke(c, Props.oval(4, 3, 32, 32), Toon.gold, 1.6)
            Props.fill(c, Props.oval(11, 8, 13, 9), UIColor.white.withAlphaComponent(0.5))
        }
        let holder = SKNode()
        holder.addChild(tip)
        holder.zPosition = 5
        return holder
    }

    private static let scrim: SKTexture = {
        let size = CGSize(width: 8, height: 144)
        return Props.texture("demo|scrim", size, scale: 1) { c in
            // Drawing runs down the page: clear at the top, ink at the foot.
            Props.wash(c, CGRect(origin: .zero, size: size), [(Toon.ink.withAlphaComponent(0), 0), (Toon.ink.withAlphaComponent(0.34), 0.45),
                                                             (Toon.ink.withAlphaComponent(0.72), 1)])
        }
    }()

    /// Shows what the thumbs are doing this frame. `panel` is the game's own word on the button.
    func show(_ thumbs: ArenaDemo.Thumbs, panel: PlayerPanel?, dt: TimeInterval) {
        let ease = dt == 0 ? 1 : CGFloat(1 - exp(-16 * dt))
        let still = Tokens.Motion.reduced

        if let stick, stick.parent != nil {
            // The knob follows the thumb the way a thumb moves, not the way a script jumps.
            let want = thumbs.steering ? CGVector(dx: thumbs.stick.x, dy: thumbs.stick.y) : .zero
            push.dx += (want.dx - push.dx) * ease
            push.dy += (want.dy - push.dy) * ease
            stick.show(at: stickHome, push: push)
            stick.alpha += ((thumbs.steering ? 1 : 0.45) - stick.alpha) * ease
            let on = CGPoint(x: stickHome.x + push.dx * 40, y: stickHome.y + push.dy * 40)
            settle(leftTip, at: thumbs.steering ? on : CGPoint(x: stickHome.x - 24, y: stickHome.y - 30), down: thumbs.steering, ease)
        }

        if let button {
            if thumbs.taps != taps {
                taps = thumbs.taps
                pressed = 0.22
                if !still { ripple(at: buttonHome, radius: ActionButton.radius) }
            }
            pressed = max(0, pressed - dt)
            let down = thumbs.holding || pressed > 0
            button.show(ring: panel?.ring, lit: panel?.lit ?? true, pressed: down, hand: panel?.handInReach ?? false)
            button.setScale(down ? 0.86 : 0.92)
            settle(rightTip, at: down ? buttonHome : CGPoint(x: buttonHome.x + 26, y: buttonHome.y - 30), down: down, ease)
            // Where a press would be the hand, the button says so, and plainly: this is the lesson.
            let reach: CGFloat = panel?.handInReach == true ? 1 : 0
            halo.alpha += (reach - halo.alpha) * ease
        }

        if stick == nil { drawPull(thumbs.pull, ease) }
    }

    /// A fingertip resting just off a control, or pressed onto it.
    private func settle(_ tip: SKNode, at p: CGPoint, down: Bool, _ ease: CGFloat) {
        tip.position = CGPoint(x: tip.position.x + (p.x - tip.position.x) * ease, y: tip.position.y + (p.y - tip.position.y) * ease)
        let scale: CGFloat = down ? 0.9 : 1.12
        tip.setScale(tip.xScale + (scale - tip.xScale) * ease)
        tip.alpha += ((down ? 1 : 0.3) - tip.alpha) * ease
    }

    /// A strike being drawn back: the fingertip dragging away from where it came down, on a tether.
    private func drawPull(_ pull: Vec2?, _ ease: CGFloat) {
        guard let pull else {
            if wasPulling {
                wasPulling = false
                if !Tokens.Motion.reduced { ripple(at: lastPull, radius: 16) }
            }
            tether.path = nil
            leftTip.alpha += (0 - leftTip.alpha) * ease
            leftTip.setScale(leftTip.xScale + (1.25 - leftTip.xScale) * ease)
            return
        }
        // The thumb goes the opposite way to the ball.
        let to = CGPoint(x: pullHome.x - CGFloat(pull.x) * 150, y: pullHome.y - CGFloat(pull.y) * 150)
        if !wasPulling {
            wasPulling = true
            leftTip.position = pullHome
        }
        lastPull = to
        leftTip.position = CGPoint(x: leftTip.position.x + (to.x - leftTip.position.x) * ease, y: leftTip.position.y + (to.y - leftTip.position.y) * ease)
        leftTip.alpha += (1 - leftTip.alpha) * ease
        leftTip.setScale(leftTip.xScale + (0.9 - leftTip.xScale) * ease)
        let path = CGMutablePath()
        path.move(to: pullHome)
        path.addLine(to: leftTip.position)
        path.addEllipse(in: CGRect(x: pullHome.x - 4, y: pullHome.y - 4, width: 8, height: 8))
        tether.path = path
    }

    private func ripple(at p: CGPoint, radius: CGFloat) {
        let ring = SKShapeNode(circleOfRadius: radius)
        ring.strokeColor = tint
        ring.lineWidth = 3
        ring.fillColor = .clear
        ring.position = p
        ring.zPosition = 3
        addChild(ring)
        let grow = SKAction.scale(to: 1.9, duration: 0.42)
        grow.timingMode = .easeOut
        ring.run(.sequence([.group([grow, .fadeOut(withDuration: 0.42)]), .removeFromParent()]))
    }
}
