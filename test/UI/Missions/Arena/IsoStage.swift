import SceneKit
import SwiftUI

/// The light and air of a game seen from above. Each stage says what its own are.
struct Atmosphere {
    /// What lies beyond the edge of the ground, and what the far side of the scene fades into.
    var sky = Toon.ink
    /// The country round the arena, running off into the distance. Nil leaves the sky to show.
    var land: UIColor?
    /// The one light that casts shadows: a low sun, a hearth, the moon.
    var key = UIColor(red: 1.0, green: 0.84, blue: 0.62, alpha: 1)
    var keyIntensity: CGFloat = 1500
    /// How steeply the key comes down, and from which side.
    var keyPitch: Float = -0.8
    var keyTurn: Float = 0.75
    var ambient = UIColor(red: 0.50, green: 0.58, blue: 0.74, alpha: 1)
    var ambientIntensity: CGFloat = 480
    /// A cool light from behind, to pick the edges of things out of the dark.
    var rimIntensity: CGFloat = 220
    var shadow: CGFloat = 0.5
    var fogStart: CGFloat = 1300
    var fogEnd: CGFloat = 2500
    var bloom: CGFloat = 0.9
    var vignette: CGFloat = 0.55
    var saturation: CGFloat = 0.95
    var contrast: CGFloat = 0.1
    /// Stops of exposure over what the lights alone give.
    var exposure: CGFloat = 0.45
    /// Dust, embers or fireflies drifting through, if any.
    var motes: UIColor?
}

/// Building blocks for the games seen from above: plain shapes, given weight by grain, light and shadow.
/// One arena point is one SceneKit unit; the arena's `y` runs along SceneKit's negative `z`.
enum Iso {
    private static var images: [String: UIImage] = [:]

    /// A fine mottle multiplied into every surface, so nothing is a flat slab of colour.
    static let grain: UIImage = image("grain", CGSize(width: 96, height: 96), scale: 1) { c in
        c.setFillColor(UIColor.white.cgColor)
        c.fill(CGRect(x: 0, y: 0, width: 96, height: 96))
        var rng = SeededRNG(seed: 404)
        for _ in 0..<900 {
            c.setFillColor(UIColor(white: rng.chance(0.5) ? 0.6 : 0.82, alpha: 0.2).cgColor)
            let w = rng.cg(1, 5)
            c.fillEllipse(in: CGRect(x: rng.cg(-2, 96), y: rng.cg(-2, 96), width: w, height: w * rng.cg(0.5, 1)))
        }
    }

    static func at(_ p: Vec2, _ height: Double = 0) -> SCNVector3 {
        SCNVector3(Float(p.x), Float(height), Float(-p.y))
    }

    static func material(_ color: UIColor, glow: UIColor? = nil) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color
        m.lightingModel = .blinn
        m.specular.contents = UIColor(white: 0.10, alpha: 1)
        m.shininess = 0.25
        m.multiply.contents = grain
        m.multiply.wrapS = .repeat
        m.multiply.wrapT = .repeat
        // Bright enough to bloom: whatever glows gives off light, and nothing else does.
        m.emission.intensity = 2.4
        if let glow { m.emission.contents = glow }
        return m
    }

    /// A drawing made once and kept, for ground textures and lettering. Drawn y-down, in points.
    static func image(_ key: String, _ size: CGSize, scale: CGFloat = 2, _ draw: (CGContext) -> Void) -> UIImage {
        if let i = images[key] { return i }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext) }
        images[key] = image
        return image
    }

    /// A box standing on the ground.
    static func box(_ w: CGFloat, _ h: CGFloat, _ l: CGFloat, _ color: UIColor, round: CGFloat = 1, glow: UIColor? = nil) -> SCNNode {
        let g = SCNBox(width: w, height: h, length: l, chamferRadius: round)
        g.materials = [material(color, glow: glow)]
        let n = SCNNode(geometry: g)
        n.position.y = Float(h / 2)
        return n
    }

    static func cylinder(_ radius: CGFloat, _ h: CGFloat, _ color: UIColor, glow: UIColor? = nil) -> SCNNode {
        let g = SCNCylinder(radius: radius, height: h)
        g.materials = [material(color, glow: glow)]
        let n = SCNNode(geometry: g)
        n.position.y = Float(h / 2)
        return n
    }

    static func cone(_ top: CGFloat, _ bottom: CGFloat, _ h: CGFloat, _ color: UIColor, glow: UIColor? = nil) -> SCNNode {
        let g = SCNCone(topRadius: top, bottomRadius: bottom, height: h)
        g.materials = [material(color, glow: glow)]
        let n = SCNNode(geometry: g)
        n.position.y = Float(h / 2)
        return n
    }

    static func ball(_ radius: CGFloat, _ color: UIColor, glow: UIColor? = nil) -> SCNNode {
        let g = SCNSphere(radius: radius)
        g.segmentCount = 16
        g.materials = [material(color, glow: glow)]
        return SCNNode(geometry: g)
    }

    /// A flat sheet lying on the ground, with a colour or a drawing on it.
    static func sheet(_ w: CGFloat, _ l: CGFloat, _ contents: Any, lit: Bool = true) -> SCNNode {
        let g = SCNPlane(width: w, height: l)
        let m = SCNMaterial()
        m.diffuse.contents = contents
        m.lightingModel = lit ? .lambert : .constant
        m.isDoubleSided = true
        if lit {
            m.multiply.contents = grain
            m.multiply.wrapS = .repeat
            m.multiply.wrapT = .repeat
            m.multiply.contentsTransform = SCNMatrix4MakeScale(Float(min(40, max(1, w / 120))), Float(min(40, max(1, l / 120))), 1)
        }
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.eulerAngles.x = -.pi / 2
        return n
    }

    /// Lettering that always faces the camera.
    static func label(_ text: String, size: CGFloat = 11, color: UIColor = Toon.cream) -> SCNNode {
        let font = Props.font(size * 2)
        let bounds = (text as NSString).size(withAttributes: [.font: font])
        let box = CGSize(width: ceil(bounds.width) + 16, height: ceil(bounds.height) + 10)
        let image = image("label|\(text)|\(size)|\(color.description)", box) { c in
            let at = CGPoint(x: 8, y: 5)
            c.setShadow(offset: CGSize(width: 0, height: 1), blur: size * 0.5, color: Toon.outline.cgColor)
            for _ in 0..<3 { (text as NSString).draw(at: at, withAttributes: [.font: font, .foregroundColor: color]) }
            c.setShadow(offset: .zero, blur: 0, color: nil)
            (text as NSString).draw(at: at, withAttributes: [.font: font, .foregroundColor: color])
        }
        let g = SCNPlane(width: box.width / 2, height: box.height / 2)
        let m = SCNMaterial()
        m.diffuse.contents = image
        m.lightingModel = .constant
        m.readsFromDepthBuffer = false
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.constraints = [SCNBillboardConstraint()]
        n.renderingOrder = 50
        return n
    }

    static func light(_ color: UIColor, intensity: CGFloat, reach: CGFloat) -> SCNNode {
        let l = SCNLight()
        l.type = .omni
        l.color = color
        l.intensity = intensity
        l.attenuationStartDistance = reach * 0.25
        l.attenuationEndDistance = reach
        let n = SCNNode()
        n.light = l
        return n
    }

    /// The mark only a traitor on the side quest sees.
    static func questMark() -> SCNNode {
        let g = SCNPyramid(width: 9, height: 9, length: 9)
        g.materials = [material(Toon.red, glow: Toon.red)]
        g.firstMaterial?.emission.intensity = 1.2
        let top = SCNNode(geometry: g)
        let bottom = SCNNode(geometry: g)
        bottom.eulerAngles.x = .pi
        let n = SCNNode()
        n.addChildNode(top)
        n.addChildNode(bottom)
        n.runAction(.repeatForever(.group([.rotateBy(x: 0, y: 2, z: 0, duration: 1),
                                           .sequence([.moveBy(x: 0, y: 5, z: 0, duration: 0.5), .moveBy(x: 0, y: -5, z: 0, duration: 0.5)])])))
        return n
    }
}

/// A player in a game seen from above: the same hooded figure as in the side-on games, a bell
/// cloak in their colour, a pale face under a pointed hood, and a name.
final class IsoFigure: SCNNode {
    let rig = SCNNode()
    /// Sits above the head, for whatever is being carried.
    let carry = SCNNode()
    private var stride = 0.0

    init(color: UIColor, name: String?, you: Bool) {
        super.init()
        let shadow = Iso.sheet(20, 20, Iso.image("shadow", CGSize(width: 32, height: 32)) { c in
            let colors = [UIColor.black.withAlphaComponent(0.45).cgColor, UIColor.black.withAlphaComponent(0).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.2, 1]) {
                c.drawRadialGradient(g, startCenter: CGPoint(x: 16, y: 16), startRadius: 0, endCenter: CGPoint(x: 16, y: 16), endRadius: 15, options: [])
            }
        }, lit: false)
        shadow.position.y = 0.4
        addChildNode(shadow)
        if you {
            let g = SCNTorus(ringRadius: 12, pipeRadius: 1.1)
            g.materials = [Iso.material(Toon.gold, glow: Toon.gold)]
            let ring = SCNNode(geometry: g)
            ring.position.y = 1
            addChildNode(ring)
            if !Tokens.Motion.reduced {
                ring.runAction(.repeatForever(.sequence([.scale(to: 1.15, duration: 0.5), .scale(to: 1, duration: 0.5)])))
            }
        }
        addChildNode(rig)
        rig.addChildNode(Iso.cone(2.6, 9, 17, color))
        let shoulders = Iso.ball(5.2, color)
        shoulders.scale = SCNVector3(1, 0.8, 1)
        shoulders.position.y = 15.5
        rig.addChildNode(shoulders)
        if you {
            // Gold at the hem, so the ivory cloak is unmistakable.
            let g = SCNTorus(ringRadius: 8.7, pipeRadius: 0.8)
            g.materials = [Iso.material(Toon.gold)]
            let hem = SCNNode(geometry: g)
            hem.position.y = 1.4
            rig.addChildNode(hem)
        }
        let head = Iso.ball(5.3, Toon.cream)
        head.position.y = 21
        rig.addChildNode(head)
        for x in [-1.9, 1.9] {
            let eye = Iso.ball(0.95, Toon.outline)
            eye.position = SCNVector3(Float(x), 21.4, 4.75)
            rig.addChildNode(eye)
        }
        let hood = Iso.ball(6.2, color)
        hood.position = SCNVector3(0, 22.4, -1.7)
        rig.addChildNode(hood)
        let tip = Iso.cone(0, 3.6, 7.5, color)
        tip.position = SCNVector3(0, 27.2, -4.2)
        tip.eulerAngles.x = -0.75
        rig.addChildNode(tip)
        carry.position.y = 36
        rig.addChildNode(carry)
        if let name {
            let tag = Iso.label(you ? "YOU" : name, size: you ? 10 : 8, color: you ? Toon.gold : Toon.cream)
            tag.position.y = 46
            addChildNode(tag)
        }
    }

    required init?(coder: NSCoder) { return nil }

    func animate(_ dt: TimeInterval, velocity v: Vec2, stunned: Bool) {
        let speed = v.length
        if speed > 12 {
            stride += dt * (9 + speed * 0.05)
            rig.position.y = Float(abs(sin(stride)) * 2.2)
            rig.eulerAngles.y = Float(atan2(v.x, -v.y))
        } else {
            rig.position.y = 0
        }
        rig.eulerAngles.z = stunned ? Float(sin(stride * 3 + dt) * 0.3) : 0
        if stunned { stride += dt * 6 }
    }

    /// Shows one thing held overhead, built only when it changes.
    func hold(_ key: String?, _ make: () -> SCNNode) {
        if carry.childNodes.first?.name == key { return }
        carry.childNodes.forEach { $0.removeFromParentNode() }
        guard let key else { return }
        let node = make()
        node.name = key
        carry.addChildNode(node)
    }
}

/// A game seen at an angle from above, drawn in SceneKit with a camera that has no perspective.
/// The HUD and the controls sit on top in SpriteKit, and drive this from there.
class IsoStage: NSObject, ArenaStage {
    let config: ArenaConfig
    let core: ArenaCore
    let layout: ArenaLayout
    let scene = SCNScene()
    let cameraNode = SCNNode()
    let ambient = SCNLight()
    let key = SCNLight()
    private let moteNode = SCNNode()
    private let keyNode = SCNNode()
    private(set) var figures: [PlayerID: IsoFigure] = [:]
    private var props: [String: SCNNode] = [:]
    private var walls: SCNNode?
    private var wallVersion = -1
    private var target = Vec2.zero
    private var jolt: CGFloat = 0
    private static let rise = 1.0 / 3.0.squareRoot()

    init(_ config: ArenaConfig, _ core: ArenaCore, _ layout: ArenaLayout) {
        self.config = config
        self.core = core
        self.layout = layout
        super.init()
        let air = atmosphere
        scene.background.contents = air.sky
        scene.fogColor = air.sky
        scene.fogStartDistance = air.fogStart
        scene.fogEndDistance = air.fogEnd
        if let land = air.land {
            let far = Iso.sheet(5000, 5000, land)
            far.position = Iso.at(Vec2(core.size.x / 2, core.size.y / 2), -1.5)
            scene.rootNode.addChildNode(far)
        }
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        // A taller screen shows more of the world above and below; nothing is drawn any bigger.
        camera.orthographicScale = halfHeight * Double(layout.height / ArenaLayout.base)
        camera.zNear = 1
        camera.zFar = 4000
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = air.exposure
        camera.bloomIntensity = air.bloom
        camera.bloomThreshold = 1.0
        camera.bloomBlurRadius = 9
        camera.vignettingIntensity = air.vignette
        camera.vignettingPower = 1.1
        camera.saturation = air.saturation
        camera.contrast = air.contrast
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(700, 700, 700)
        cameraNode.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(cameraNode)

        ambient.type = .ambient
        ambient.intensity = air.ambientIntensity
        ambient.color = air.ambient
        let fill = SCNNode()
        fill.light = ambient
        scene.rootNode.addChildNode(fill)

        key.type = .directional
        key.color = air.key
        key.intensity = air.keyIntensity
        key.castsShadow = air.shadow > 0
        key.shadowColor = UIColor.black.withAlphaComponent(air.shadow)
        key.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.shadowSampleCount = 8
        key.shadowRadius = 4
        // The shadow map is a fixed window that travels with the camera: the automatic one does not
        // cope with a camera that has no perspective.
        key.automaticallyAdjustsShadowProjection = false
        key.orthographicScale = 560
        key.zNear = 10
        key.zFar = 2400
        // Measured from the camera, which stands a long way back.
        key.maximumShadowDistance = 3000
        key.shadowBias = 3
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(air.keyPitch, air.keyTurn, 0)
        scene.rootNode.addChildNode(keyNode)

        if air.rimIntensity > 0 {
            let rim = SCNLight()
            rim.type = .directional
            rim.color = UIColor(red: 0.50, green: 0.62, blue: 0.90, alpha: 1)
            rim.intensity = air.rimIntensity
            let rimNode = SCNNode()
            rimNode.light = rim
            rimNode.eulerAngles = SCNVector3(-0.5, air.keyTurn + .pi, 0)
            scene.rootNode.addChildNode(rimNode)
        }

        if let color = air.motes, !Tokens.Motion.reduced {
            let dust = SCNParticleSystem()
            dust.particleImage = Iso.image("mote", CGSize(width: 16, height: 16)) { c in
                let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
                if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                    c.drawRadialGradient(g, startCenter: CGPoint(x: 8, y: 8), startRadius: 0, endCenter: CGPoint(x: 8, y: 8), endRadius: 8, options: [])
                }
            }
            dust.particleColor = color
            dust.birthRate = 14
            dust.particleLifeSpan = 7
            dust.particleLifeSpanVariation = 3
            dust.particleSize = 2.4
            dust.particleSizeVariation = 1.4
            dust.particleVelocity = 5
            dust.particleVelocityVariation = 4
            dust.spreadingAngle = 180
            dust.acceleration = SCNVector3(2, 1.5, -2)
            dust.blendMode = .additive
            dust.isLightingEnabled = false
            dust.emitterShape = SCNBox(width: 560, height: 70, length: 560, chamferRadius: 0)
            let fade = CAKeyframeAnimation()
            fade.values = [0, 0.8, 0.8, 0]
            fade.keyTimes = [0, 0.2, 0.75, 1]
            dust.propertyControllers = [.opacity: SCNParticlePropertyController(animation: fade)]
            moteNode.position.y = 40
            moteNode.addParticleSystem(dust)
            scene.rootNode.addChildNode(moteNode)
        }

        build()
        for c in config.cast {
            let f = IsoFigure(color: c.color, name: c.name, you: c.isHuman && !config.spectating)
            figures[c.id] = f
            scene.rootNode.addChildNode(f)
        }
        populated()
        target = core.human?.pos ?? Vec2(core.size.x / 2, core.size.y / 2)
        sync(core, dt: 0)
    }

    // MARK: For each game

    /// The light and air. Each game has its own hour of the day.
    var atmosphere: Atmosphere { Atmosphere() }
    var backdrop: UIColor { atmosphere.sky }
    /// Half the height of what the camera takes in, in arena points.
    var halfHeight: Double { 280 }
    /// Whether the camera keeps the player in the middle. Otherwise it sits over the middle of the arena.
    var follows: Bool { true }
    var wallHeight: CGFloat { 30 }
    var wallColor: UIColor { Toon.limestone }
    /// Lays down the ground and anything that never moves.
    func build() {}
    /// Called once the players are standing in it.
    func populated() {}
    func makeProp(_ p: Prop) -> SCNNode? { nil }
    func updateProp(_ node: SCNNode, _ p: Prop, dt: TimeInterval) {}
    func dress(_ figure: IsoFigure, _ a: ArenaActor) {}

    // MARK: Shared

    var pointScale: CGFloat { 300 / halfHeight }
    var squash: CGFloat { CGFloat(Self.rise) }

    /// A plain ground the size of the arena.
    func ground(_ contents: Any, margin: CGFloat = 60) {
        let sheet = Iso.sheet(CGFloat(core.size.x) + margin * 2, CGFloat(core.size.y) + margin * 2, contents)
        sheet.position = Iso.at(Vec2(core.size.x / 2, core.size.y / 2), -0.5)
        scene.rootNode.addChildNode(sheet)
    }

    func shake(_ amount: CGFloat) {
        if !Tokens.Motion.reduced { jolt = amount * 1.6 }
    }

    func arenaVector(_ v: CGVector) -> Vec2 {
        let k = 0.5.squareRoot()
        return Vec2((Double(v.dx) - Double(v.dy)) * k, (Double(v.dx) + Double(v.dy)) * k)
    }

    func screenPoint(_ p: Vec2, z: Double) -> CGPoint {
        let dx = p.x - target.x, dy = p.y - target.y
        let across = (dx + dy) * 0.5.squareRoot()
        let up = (dy - dx) / 6.0.squareRoot() + 2 * z / 6.0.squareRoot()
        let k = 300 / halfHeight
        return CGPoint(x: layout.centre.x + across * k, y: layout.centre.y + up * k)
    }

    func sync(_ core: ArenaCore, dt: TimeInterval) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        defer { SCNTransaction.commit() }

        // The player sits a little below the middle, clear of the scoreboard along the top.
        var want = Vec2(core.size.x / 2, core.size.y / 2)
        if follows, let f = core.human ?? core.actors.max(by: { core.count(of: $0) < core.count(of: $1) }) { want = f.pos }
        want = want + Vec2(-1, 1) * 40
        target = target + (want - target) * min(1, dt * 5 + (dt == 0 ? 1 : 0))
        moteNode.position = SCNVector3(Float(target.x), 40, Float(-target.y))
        let toward = keyNode.simdWorldFront
        keyNode.simdPosition = SIMD3(Float(target.x), 0, Float(-target.y)) - toward * 1100
        // A shake slides the camera across the ground and dies away.
        jolt = dt == 0 ? jolt : max(0, jolt - CGFloat(dt) * 28)
        let jx = Float(jolt > 0 ? CGFloat.random(in: -jolt...jolt) : 0), jz = Float(jolt > 0 ? CGFloat.random(in: -jolt...jolt) : 0)
        cameraNode.position = SCNVector3(Float(target.x) + 700 + jx, 700, Float(-target.y) + 700 + jz)

        if let grid = core.grid, wallVersion != core.gridVersion {
            wallVersion = core.gridVersion
            walls?.removeFromParentNode()
            let all = SCNNode()
            for r in 0..<grid.rows {
                for c in 0..<grid.cols where grid.opaque[grid.index(c, r)] {
                    let block = Iso.box(CGFloat(grid.cell), wallHeight, CGFloat(grid.cell), wallColor, round: 0)
                    let p = Iso.at(grid.centre(c, r))
                    block.position = SCNVector3(p.x, block.position.y, p.z)
                    all.addChildNode(block)
                }
            }
            // One mesh for the lot.
            let flat = all.flattenedClone()
            scene.rootNode.addChildNode(flat)
            walls = flat
        }

        let me = core.human
        for a in core.actors {
            guard let f = figures[a.id] else { continue }
            f.position = Iso.at(a.pos, a.z)
            f.animate(dt, velocity: a.vel, stunned: a.stun > 0)
            let seen = me == nil || a === me || !core.hidesUnseen || a.seenBy.has(me!.id)
            f.opacity += ((seen ? 1 : 0) - f.opacity) * min(1, CGFloat(dt) * 8 + (dt == 0 ? 1 : 0))
            dress(f, a)
        }

        var live: Set<String> = []
        for p in core.props() {
            let key = "\(p.kind.rawValue)-\(p.id)"
            live.insert(key)
            var node = props[key]
            if node == nil {
                guard let made = makeProp(p) else { continue }
                props[key] = made
                scene.rootNode.addChildNode(made)
                node = made
            }
            guard let node else { continue }
            node.position = Iso.at(p.pos, p.z)
            node.isHidden = p.hidden
            let marked = p.secret && config.questVisible
            let mark = node.childNode(withName: "mark", recursively: false)
            if marked, mark == nil {
                let m = Iso.questMark()
                m.name = "mark"
                m.position.y = 52
                node.addChildNode(m)
            } else if !marked {
                mark?.removeFromParentNode()
            }
            updateProp(node, p, dt: dt)
        }
        for (key, node) in props where !live.contains(key) {
            node.removeFromParentNode()
            props[key] = nil
        }
    }
}

/// Hosts a SceneKit stage underneath the SpriteKit HUD.
struct IsoView: UIViewRepresentable {
    let stage: IsoStage

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = stage.scene
        view.pointOfView = stage.cameraNode
        view.backgroundColor = stage.backdrop
        view.antialiasingMode = .multisampling4X
        view.isUserInteractionEnabled = false
        view.rendersContinuously = true
        view.isPlaying = true
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {}
}
