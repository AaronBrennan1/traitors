import SpriteKit

/// The little hooded figure every player is in the arena: a cloak in their colour, a face, two feet.
final class Courtier: SKNode {
    /// Everything that squashes, leans and bobs. The shadow and name stay put.
    let rig = SKNode()
    /// Sits above the head, for whatever is being carried.
    let carry = SKNode()
    private let body: SKSpriteNode
    private let left: SKSpriteNode
    private let right: SKSpriteNode
    private let tag: ToonLabel?
    private var stride: CGFloat = 0
    private var facing: CGFloat = 1

    init(color: UIColor, name: String? = nil, you: Bool = false) {
        body = Props.body(color, trim: you)
        left = Props.foot(color)
        right = Props.foot(color)
        tag = name.map { ToonLabel(you ? "YOU" : $0, size: you ? 11 : 8.5, color: you ? Toon.gold : Toon.cream) }
        super.init()

        let shadow = Props.shadow(26)
        shadow.position = CGPoint(x: 0, y: -17)
        addChild(shadow)
        if you {
            let ring = SKShapeNode(ellipseOf: CGSize(width: 34, height: 15))
            ring.strokeColor = Toon.gold
            ring.lineWidth = 2
            ring.fillColor = .clear
            ring.position = CGPoint(x: 0, y: -17)
            ring.zPosition = -4
            addChild(ring)
            if !Tokens.Motion.reduced { ring.run(.repeatForever(.sequence([.scale(to: 1.15, duration: 0.5), .scale(to: 1, duration: 0.5)]))) }
        }
        addChild(rig)
        left.position = CGPoint(x: -6, y: -16)
        right.position = CGPoint(x: 6, y: -16)
        left.zPosition = -1
        right.zPosition = -1
        rig.addChild(left)
        rig.addChild(right)
        rig.addChild(body)
        carry.position = CGPoint(x: 0, y: 24)
        carry.zPosition = 2
        rig.addChild(carry)
        if let tag {
            tag.position = CGPoint(x: 0, y: -29)
            tag.zPosition = 3
            addChild(tag)
        }
    }

    required init?(coder: NSCoder) { return nil }

    /// Call every frame with how fast the figure is moving, in points a second.
    func animate(_ dt: TimeInterval, velocity v: CGVector) {
        let speed = hypot(v.dx, v.dy)
        if abs(v.dx) > 8 { facing = v.dx > 0 ? 1 : -1 }
        body.xScale = facing
        if speed > 12 {
            stride += CGFloat(dt) * (7 + speed * 0.07)
            let s = sin(stride)
            left.position.y = -16 + max(0, s) * 4
            right.position.y = -16 + max(0, -s) * 4
            left.position.x = -6 + s * 2 * facing
            right.position.x = 6 - s * 2 * facing
            body.position.y = abs(s) * 1.6
            body.zRotation = -facing * min(speed, 300) / 300 * 0.16
        } else {
            stride = 0
            left.position = CGPoint(x: -6, y: -16)
            right.position = CGPoint(x: 6, y: -16)
            body.position.y = 0
            body.zRotation = 0
        }
    }

    func squash() { FX.squash(rig) }

    /// Knocked silly: wobbles and blinks for a moment.
    func daze(_ seconds: TimeInterval) {
        rig.removeAction(forKey: "daze")
        let wobble = SKAction.sequence([.rotate(toAngle: 0.3, duration: 0.07), .rotate(toAngle: -0.3, duration: 0.07)])
        let blink = SKAction.sequence([.fadeAlpha(to: 0.45, duration: 0.07), .fadeAlpha(to: 1, duration: 0.07)])
        let n = max(1, Int(seconds / 0.14))
        rig.run(.sequence([.repeat(.group([wobble, blink]), count: n), .rotate(toAngle: 0, duration: 0.05),
                           .fadeAlpha(to: 1, duration: 0)]), withKey: "daze")
        squash()
    }
}
