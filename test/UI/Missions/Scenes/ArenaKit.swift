import SpriteKit
import TraitorsEngine

/// The arena's colours as SpriteKit wants them. Every one comes from `Tokens`.
enum Toon {
    static let outline = Tokens.Hue.outline.ui
    /// The weight a shape's edge is asked for. Painted shapes draw it at half that, in their own colour.
    static let line: CGFloat = 3
    static let gold = Tokens.Hue.gold.ui
    static let goldDark = Tokens.Hue.goldDeep.ui
    static let cream = Tokens.Hue.parchment.ui
    static let red = Tokens.Hue.blood.ui
    static let green = Tokens.Hue.faithful.ui
    static let grass = Tokens.Hue.grass.ui
    static let wood = Tokens.Hue.wood.ui
    static let woodDark = Tokens.Hue.woodDark.ui
    static let steel = Tokens.Hue.steel.ui
    static let straw = Tokens.Hue.straw.ui
    static let ink = Tokens.Hue.ink.ui
    static let ember = Tokens.Hue.ember.ui
    static let flagstone = Tokens.Hue.flagstone.ui
    static let flagstoneHi = Tokens.Hue.flagstoneHi.ui
    static let wallStone = Tokens.Hue.wallStone.ui
    static let pit = Tokens.Hue.pit.ui
    static let danger = Tokens.Hue.danger.ui
    static let mist = Tokens.Hue.mist.ui

    static func cloak(_ hue: Double) -> UIColor { Tokens.Hue.cloak(hue).ui }
}

extension UIColor {
    /// Darker below 1, lighter above it.
    func shaded(_ k: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        if k <= 1 { return UIColor(red: r * k, green: g * k, blue: b * k, alpha: a) }
        let t = min(k - 1, 1)
        return UIColor(red: r + (1 - r) * t, green: g + (1 - g) * t, blue: b + (1 - b) * t, alpha: a)
    }
}

extension SeededRNG {
    mutating func cg(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { CGFloat(range(Double(lo), Double(hi))) }
}

/// Everything in the arena is drawn once into a texture and reused. Drawing is y-down, in points.
enum Props {
    private static var cache: [String: SKTexture] = [:]

    static func texture(_ key: String, _ size: CGSize, scale: CGFloat = 3, _ draw: (CGContext) -> Void) -> SKTexture {
        if let t = cache[key] { return t }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext) }
        let t = SKTexture(image: image)
        cache[key] = t
        return t
    }

    static func sprite(_ key: String, _ size: CGSize, _ draw: (CGContext) -> Void) -> SKSpriteNode {
        SKSpriteNode(texture: texture(key, size, draw), size: size)
    }

    // MARK: Paths and inking

    static func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat) -> CGPath {
        UIBezierPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: radius).cgPath
    }

    static func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: x, y: y, width: w, height: h), transform: nil)
    }

    static func poly(_ pts: [(CGFloat, CGFloat)]) -> CGPath {
        let p = CGMutablePath()
        for (i, pt) in pts.enumerated() {
            if i == 0 { p.move(to: CGPoint(x: pt.0, y: pt.1)) } else { p.addLine(to: CGPoint(x: pt.0, y: pt.1)) }
        }
        p.closeSubpath()
        return p
    }

    static func fill(_ c: CGContext, _ path: CGPath, _ color: UIColor) {
        c.addPath(path)
        c.setFillColor(color.cgColor)
        c.fillPath()
    }

    static func stroke(_ c: CGContext, _ path: CGPath, _ color: UIColor = Toon.outline, _ width: CGFloat = Toon.line) {
        c.addPath(path)
        c.setStrokeColor(color.cgColor)
        c.setLineWidth(width)
        c.setLineJoin(.round)
        c.setLineCap(.round)
        c.strokePath()
    }

    /// Paint, not ink: lit from above, darker towards the foot, with a thin edge in a deeper shade of itself.
    static func ink(_ c: CGContext, _ path: CGPath, _ color: UIColor, line: CGFloat = Toon.line) {
        let box = path.boundingBoxOfPath
        c.saveGState()
        c.addPath(path)
        c.clip()
        let colors = [color.shaded(1.16).cgColor, color.cgColor, color.shaded(0.66).cgColor] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.4, 1]) {
            c.drawLinearGradient(g, start: CGPoint(x: box.midX, y: box.minY), end: CGPoint(x: box.midX, y: box.maxY),
                                 options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        c.restoreGState()
        stroke(c, path, color.shaded(0.38), max(1, line * 0.5))
    }

    /// A vertical wash of colour, top to bottom, for skies and water.
    static func wash(_ c: CGContext, _ rect: CGRect, _ stops: [(UIColor, CGFloat)]) {
        let colors = stops.map { $0.0.cgColor } as CFArray
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: stops.map { $0.1 }) else { return }
        c.saveGState()
        c.clip(to: rect)
        c.drawLinearGradient(g, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY),
                             options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        c.restoreGState()
    }

    /// Fills `color` over the part of `path` inside `rect`: the darker band that gives a shape its weight.
    static func shade(_ c: CGContext, _ path: CGPath, _ color: UIColor, in rect: CGRect) {
        c.saveGState()
        c.addPath(path)
        c.clip()
        c.setFillColor(color.cgColor)
        c.fill(rect)
        c.restoreGState()
    }

    // MARK: Text

    static func font(_ size: CGFloat) -> UIFont { Tokens.TypeRole.title.ui(size) }

    /// Serif lettering with a soft dark halo, so it reads over anything.
    static func text(_ s: String, size: CGFloat, color: UIColor) -> (SKTexture, CGSize) {
        let f = font(size)
        let pad = ceil(size * 0.3) + 2
        let bounds = (s as NSString).size(withAttributes: [.font: f])
        let box = CGSize(width: ceil(bounds.width) + pad * 2, height: ceil(bounds.height) + pad * 2)
        let t = texture("text|\(s)|\(size)|\(color.description)", box) { c in
            let at = CGPoint(x: pad, y: pad)
            c.setShadow(offset: CGSize(width: 0, height: size * 0.04), blur: size * 0.22, color: Toon.outline.cgColor)
            for _ in 0..<3 { (s as NSString).draw(at: at, withAttributes: [.font: f, .foregroundColor: color]) }
            c.setShadow(offset: .zero, blur: 0, color: nil)
            (s as NSString).draw(at: at, withAttributes: [.font: f, .foregroundColor: color])
        }
        return (t, box)
    }

    // MARK: Characters

    /// The courtier, facing right: a bell cloak with a pointed hood, and a pale face under it.
    /// `trim` is the gold hem only the human wears.
    static func body(_ color: UIColor, trim: Bool = false) -> SKSpriteNode {
        sprite("body|\(color.description)|\(trim)", CGSize(width: 32, height: 38)) { c in
            let cloak = CGMutablePath()
            cloak.move(to: CGPoint(x: 11, y: 1.5))
            cloak.addQuadCurve(to: CGPoint(x: 27, y: 15), control: CGPoint(x: 25, y: 3))
            cloak.addQuadCurve(to: CGPoint(x: 29.5, y: 33), control: CGPoint(x: 30, y: 25))
            cloak.addQuadCurve(to: CGPoint(x: 2.5, y: 33), control: CGPoint(x: 16, y: 38))
            cloak.addQuadCurve(to: CGPoint(x: 6, y: 13), control: CGPoint(x: 2, y: 23))
            cloak.addQuadCurve(to: CGPoint(x: 11, y: 1.5), control: CGPoint(x: 7, y: 5))
            cloak.closeSubpath()
            ink(c, cloak, color)
            // A fold down the back, and the light on the hood.
            shade(c, cloak, color.shaded(0.62).withAlphaComponent(0.55), in: CGRect(x: 0, y: 14, width: 10, height: 24))
            shade(c, cloak, color.shaded(1.3).withAlphaComponent(0.5), in: CGRect(x: 12, y: 3, width: 9, height: 3))
            if trim {
                shade(c, cloak, Toon.gold, in: CGRect(x: 0, y: 31.5, width: 32, height: 2.2))
                stroke(c, cloak, color.shaded(0.38), 1.5)
            }
            let face = oval(13, 9, 13.5, 11.5)
            fill(c, face, Toon.cream)
            shade(c, face, Toon.outline.withAlphaComponent(0.28), in: CGRect(x: 12, y: 8, width: 16, height: 4))
            stroke(c, face, color.shaded(0.38), 1.2)
            fill(c, oval(18.2, 13, 2.8, 4.2), Toon.outline)
            fill(c, oval(23, 13, 2.8, 4.2), Toon.outline)
        }
    }

    static func foot(_ color: UIColor) -> SKSpriteNode {
        sprite("foot|\(color.description)", CGSize(width: 13, height: 10)) { c in
            ink(c, rr(2, 2, 9, 6, 3), color.shaded(0.76), line: 2.5)
        }
    }

    static func shadow(_ width: CGFloat) -> SKSpriteNode {
        let n = sprite("shadow|\(width)", CGSize(width: width, height: width * 0.42)) { c in
            fill(c, oval(0, 0, width, width * 0.42), UIColor.black.withAlphaComponent(0.36))
        }
        n.zPosition = -5
        return n
    }

    static func dot(_ color: UIColor, _ radius: CGFloat) -> SKSpriteNode {
        sprite("dot|\(color.description)|\(radius)", CGSize(width: radius * 2 + 4, height: radius * 2 + 4)) { c in
            ink(c, oval(2, 2, radius * 2, radius * 2), color, line: 2)
        }
    }

    static func star(_ color: UIColor) -> SKSpriteNode {
        sprite("star|\(color.description)", CGSize(width: 16, height: 16)) { c in
            var pts: [(CGFloat, CGFloat)] = []
            for i in 0..<10 {
                let a = CGFloat(i) * .pi / 5 - .pi / 2
                let r: CGFloat = i % 2 == 0 ? 6 : 2.8
                pts.append((8 + cos(a) * r, 8 + sin(a) * r))
            }
            ink(c, poly(pts), color, line: 1.5)
        }
    }

    // MARK: Vault

    static func chest(_ color: UIColor) -> SKSpriteNode {
        sprite("chest|\(color.description)", CGSize(width: 44, height: 38)) { c in
            ink(c, rr(3, 14, 38, 21, 4), Toon.wood)
            shade(c, rr(3, 14, 38, 21, 4), Toon.woodDark, in: CGRect(x: 0, y: 27, width: 44, height: 8))
            stroke(c, rr(3, 14, 38, 21, 4))
            ink(c, rr(2, 4, 40, 15, 7), color)
            shade(c, rr(2, 4, 40, 15, 7), color.shaded(0.76), in: CGRect(x: 0, y: 14, width: 44, height: 6))
            stroke(c, rr(2, 4, 40, 15, 7))
            ink(c, rr(18, 15, 8, 9, 2.5), Toon.gold, line: 2)
        }
    }

    static func flag(_ color: UIColor) -> SKSpriteNode {
        sprite("flag|\(color.description)", CGSize(width: 26, height: 30)) { c in
            ink(c, poly([(7, 3), (25, 9), (7, 16)]), color, line: 2.5)
            ink(c, rr(4, 2, 4, 26, 2), Toon.cream, line: 2)
        }
    }

    static func bell() -> SKSpriteNode {
        sprite("bell", CGSize(width: 30, height: 32)) { c in
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 4, y: 24))
            p.addQuadCurve(to: CGPoint(x: 9, y: 12), control: CGPoint(x: 9, y: 20))
            p.addQuadCurve(to: CGPoint(x: 21, y: 12), control: CGPoint(x: 15, y: 0))
            p.addQuadCurve(to: CGPoint(x: 26, y: 24), control: CGPoint(x: 21, y: 20))
            p.closeSubpath()
            ink(c, oval(11.5, 22, 7, 7), Toon.goldDark, line: 2.5)
            ink(c, p, Toon.gold)
            fill(c, oval(11, 9, 3, 6), UIColor.white.withAlphaComponent(0.7))
        }
    }

    private static func bullseye(_ c: CGContext, _ x: CGFloat, _ y: CGFloat, gold: Bool) {
        ink(c, oval(x - 7, y - 7, 14, 14), gold ? Toon.gold : Toon.cream, line: 2)
        fill(c, oval(x - 3, y - 3, 6, 6), Toon.red)
    }

    static func strawKnight(gold: Bool) -> SKSpriteNode {
        sprite("knight|\(gold)", CGSize(width: 34, height: 44)) { c in
            let body = gold ? Toon.gold : Toon.straw
            ink(c, rr(14, 30, 6, 12, 2), Toon.woodDark, line: 2.5)
            ink(c, rr(1, 19, 32, 6, 3), body, line: 2.5)
            ink(c, rr(7, 15, 20, 21, 7), body)
            ink(c, rr(9, 2, 16, 15, 5), Toon.steel)
            fill(c, rr(12, 8, 10, 3, 1.5), Toon.outline)
            bullseye(c, 17, 26, gold: gold)
        }
    }

    static func cart(gold: Bool) -> SKSpriteNode {
        sprite("cart|\(gold)", CGSize(width: 46, height: 34)) { c in
            ink(c, rr(4, 6, 38, 18, 4), gold ? Toon.gold : Toon.wood)
            shade(c, rr(4, 6, 38, 18, 4), gold ? Toon.goldDark : Toon.woodDark, in: CGRect(x: 0, y: 18, width: 46, height: 7))
            stroke(c, rr(4, 6, 38, 18, 4))
            ink(c, oval(6, 19, 13, 13), Toon.woodDark, line: 2.5)
            ink(c, oval(27, 19, 13, 13), Toon.woodDark, line: 2.5)
            bullseye(c, 23, 14, gold: gold)
        }
    }
}

/// Outlined cartoon lettering that can change its text.
final class ToonLabel: SKSpriteNode {
    private var shown = ""
    private let points: CGFloat
    private var ink: UIColor

    init(_ text: String = "", size: CGFloat, color: UIColor = Toon.cream) {
        points = size
        ink = color
        super.init(texture: nil, color: .clear, size: .zero)
        set(text)
    }

    required init?(coder: NSCoder) { return nil }

    func set(_ text: String, color: UIColor? = nil) {
        if text == shown, color == nil || color == ink { return }
        shown = text
        if let color { ink = color }
        guard !text.isEmpty else { texture = nil; size = .zero; return }
        let (t, box) = Props.text(text, size: points, color: ink)
        texture = t
        size = box
    }
}

/// Small bursts of life: none of it affects play.
enum FX {
    static func burst(in parent: SKNode, at p: CGPoint, color: UIColor, count: Int = 8, reach: CGFloat = 34, z: CGFloat = 700) {
        for i in 0..<count {
            let a = CGFloat(i) / CGFloat(count) * 2 * .pi + CGFloat.random(in: -0.3...0.3)
            let d = reach * CGFloat.random(in: 0.6...1.1)
            let bit = Props.dot(color, CGFloat.random(in: 2...3.5))
            bit.position = p
            bit.zPosition = z
            parent.addChild(bit)
            let move = SKAction.moveBy(x: cos(a) * d, y: sin(a) * d, duration: 0.35)
            move.timingMode = .easeOut
            bit.run(.sequence([.group([move, .sequence([.wait(forDuration: 0.18), .fadeOut(withDuration: 0.17)]),
                                       .scale(to: 0.4, duration: 0.35)]), .removeFromParent()]))
        }
    }

    static func confetti(in parent: SKNode, size: CGSize, colors: [UIColor], z: CGFloat = 1150) {
        for i in 0..<36 {
            let bit = SKSpriteNode(color: colors[i % max(colors.count, 1)], size: CGSize(width: 7, height: 11))
            bit.position = CGPoint(x: CGFloat.random(in: 10...(size.width - 10)), y: size.height + CGFloat.random(in: 0...100))
            bit.zPosition = z
            bit.zRotation = CGFloat.random(in: 0...3)
            parent.addChild(bit)
            let fall = Double.random(in: 1.0...1.9)
            bit.run(.sequence([.group([.moveBy(x: CGFloat.random(in: -40...40), y: -(size.height + 120), duration: fall),
                                       .rotate(byAngle: CGFloat.random(in: -8...8), duration: fall)]), .removeFromParent()]))
        }
    }

    /// Springs a node in from nothing.
    static func pop(_ node: SKNode, to scale: CGFloat = 1) {
        node.setScale(0.1)
        let up = SKAction.scale(to: scale * 1.2, duration: 0.12)
        up.timingMode = .easeOut
        node.run(.sequence([up, .scale(to: scale, duration: 0.08)]))
    }

    /// A quick squash and stretch on something that just got bumped or landed.
    static func squash(_ node: SKNode) {
        node.removeAction(forKey: "squash")
        node.run(.sequence([.scaleX(to: 1.25, y: 0.75, duration: 0.07), .scaleX(to: 0.9, y: 1.12, duration: 0.08),
                            .scaleX(to: 1, y: 1, duration: 0.07)]), withKey: "squash")
    }
}
