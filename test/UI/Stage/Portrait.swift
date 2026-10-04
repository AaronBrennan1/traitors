import SwiftUI

/// How one of the cast is drawn.
struct Look {
    enum Hair { case short, bob, long, bun, bald, curly, cap, quiff }
    enum Beard { case none, full, moustache, stubble }

    var skin: Color
    var hair: Color
    var style: Hair
    var beard: Beard = .none
    var glasses = false

    private static let skins = [
        Color(red: 0.93, green: 0.78, blue: 0.68), Color(red: 0.88, green: 0.70, blue: 0.58),
        Color(red: 0.96, green: 0.83, blue: 0.75), Color(red: 0.78, green: 0.60, blue: 0.48),
    ]
    private static let grey = Color(red: 0.72, green: 0.72, blue: 0.74)
    private static let black = Color(red: 0.12, green: 0.10, blue: 0.10)
    private static let brown = Color(red: 0.36, green: 0.24, blue: 0.16)
    private static let ginger = Color(red: 0.72, green: 0.36, blue: 0.16)
    private static let blonde = Color(red: 0.86, green: 0.72, blue: 0.42)
    private static let red = Color(red: 0.60, green: 0.20, blue: 0.12)

    static func of(_ name: String) -> Look {
        switch name {
        case "Siobhán": return Look(skin: skins[0], hair: grey, style: .bob)
        case "Declan": return Look(skin: skins[1], hair: ginger, style: .bald, beard: .full)
        case "Aoife": return Look(skin: skins[2], hair: black, style: .bun, glasses: true)
        case "Pádraig": return Look(skin: skins[1], hair: grey, style: .cap, beard: .stubble)
        case "Niamh": return Look(skin: skins[2], hair: red, style: .long)
        case "Cian": return Look(skin: skins[3], hair: black, style: .quiff, beard: .stubble)
        case "Gráinne": return Look(skin: skins[0], hair: blonde, style: .curly)
        case "Tadhg": return Look(skin: skins[3], hair: brown, style: .short, beard: .full)
        default:
            // The player's own face: the same every time for the same name.
            var h: UInt64 = 1_469_598_103_934_665_603
            for b in name.utf8 { h = (h ^ UInt64(b)) &* 1_099_511_628_211 }
            let hairs = [brown, black, blonde, ginger]
            let styles: [Hair] = [.short, .quiff, .bob, .long]
            return Look(skin: skins[Int(h % 4)], hair: hairs[Int((h >> 8) % 4)], style: styles[Int((h >> 16) % 4)])
        }
    }
}

/// A player's face in their cloak colour, or the cloak with the hood up. Small sizes keep the
/// initial instead, where a face would be too fine to tell apart.
struct Portrait: View {
    let name: String
    /// The cloak colour, which is also the ground the face sits on.
    let cloak: Color
    var size: CGFloat = 44
    var hooded = false
    /// The player's own token is pale, so its initial is drawn dark.
    var human = false

    var body: some View {
        if size < 34 && !hooded {
            ZStack {
                Circle().fill(backing)
                Text(String(name.prefix(1)))
                    .font(.system(size: size * 0.46, weight: .bold, design: .serif))
                    .foregroundStyle(human ? Palette.ink.opacity(0.85) : .white.opacity(0.92))
            }
            .frame(width: size, height: size)
        } else {
            Canvas { ctx, canvas in
                let s = canvas.width
                func r(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
                    CGRect(x: x * s, y: y * s, width: w * s, height: h * s)
                }
                func oval(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) -> Path {
                    Path(ellipseIn: r(cx - rx, cy - ry, rx * 2, ry * 2))
                }
                ctx.fill(Path(ellipseIn: r(0, 0, 1, 1)), with: .linearGradient(
                    Gradient(colors: [cloak, cloak.opacity(0.55)]),
                    startPoint: .zero, endPoint: CGPoint(x: s, y: s)))
                let look = Look.of(name)
                // The cloth itself, in shadow against its own colour.
                func cloth(_ path: Path) {
                    ctx.fill(path, with: .color(cloak))
                    ctx.fill(path, with: .color(.black.opacity(hooded ? 0.62 : 0.48)))
                }

                if hooded {
                    cloth(oval(0.5, 1.04, 0.46, 0.32))
                    cloth(oval(0.5, 0.44, 0.31, 0.36))
                    ctx.fill(oval(0.5, 0.50, 0.19, 0.24), with: .color(Color.black.opacity(0.88)))
                    // A rim of light on the hood, and the suggestion of eyes inside it.
                    ctx.stroke(oval(0.5, 0.50, 0.19, 0.24), with: .color(cloak.opacity(0.7)), lineWidth: max(1, s * 0.02))
                    ctx.fill(oval(0.435, 0.48, 0.018, 0.012), with: .color(.white.opacity(0.35)))
                    ctx.fill(oval(0.565, 0.48, 0.018, 0.012), with: .color(.white.opacity(0.35)))
                    return
                }

                // Hair that falls behind the head.
                switch look.style {
                case .long: ctx.fill(Path(roundedRect: r(0.25, 0.22, 0.50, 0.62), cornerRadius: s * 0.22), with: .color(look.hair))
                case .bob: ctx.fill(Path(roundedRect: r(0.26, 0.20, 0.48, 0.46), cornerRadius: s * 0.20), with: .color(look.hair))
                case .curly:
                    for (x, y) in [(0.30, 0.36), (0.34, 0.24), (0.46, 0.18), (0.58, 0.19), (0.68, 0.27), (0.71, 0.39), (0.29, 0.50), (0.71, 0.52)] {
                        ctx.fill(oval(x, y, 0.10, 0.10), with: .color(look.hair))
                    }
                case .bun: ctx.fill(oval(0.5, 0.16, 0.09, 0.09), with: .color(look.hair))
                default: break
                }

                cloth(oval(0.5, 1.04, 0.44, 0.30))
                ctx.fill(Path(roundedRect: r(0.43, 0.60, 0.14, 0.20), cornerRadius: s * 0.04), with: .color(look.skin.opacity(0.82)))
                ctx.fill(oval(0.5, 0.46, 0.19, 0.23), with: .color(look.skin))
                ctx.fill(oval(0.31, 0.47, 0.03, 0.045), with: .color(look.skin))
                ctx.fill(oval(0.69, 0.47, 0.03, 0.045), with: .color(look.skin))

                // Everything on the face is clipped to it.
                var face = ctx
                face.clip(to: oval(0.5, 0.46, 0.19, 0.23))
                switch look.beard {
                case .full: face.fill(Path(r(0.28, 0.52, 0.44, 0.22)), with: .color(look.hair))
                case .stubble: face.fill(Path(r(0.28, 0.54, 0.44, 0.20)), with: .color(look.hair.opacity(0.28)))
                default: break
                }
                switch look.style {
                case .short, .bun: face.fill(oval(0.5, 0.25, 0.24, 0.11), with: .color(look.hair))
                case .bob, .long: face.fill(oval(0.42, 0.24, 0.24, 0.12), with: .color(look.hair))
                case .curly: face.fill(oval(0.5, 0.24, 0.24, 0.09), with: .color(look.hair))
                case .quiff: face.fill(oval(0.54, 0.24, 0.24, 0.12), with: .color(look.hair))
                case .bald, .cap: break
                }

                if look.style == .quiff { ctx.fill(oval(0.56, 0.21, 0.15, 0.07), with: .color(look.hair)) }
                if look.style == .bald {
                    ctx.fill(oval(0.31, 0.40, 0.035, 0.07), with: .color(look.hair))
                    ctx.fill(oval(0.69, 0.40, 0.035, 0.07), with: .color(look.hair))
                }
                if look.style == .cap {
                    let tweed = Color(red: 0.30, green: 0.32, blue: 0.24)
                    ctx.fill(oval(0.5, 0.27, 0.23, 0.09), with: .color(tweed))
                    ctx.fill(oval(0.60, 0.31, 0.17, 0.04), with: .color(tweed.opacity(0.85)))
                }

                let ink = Color(red: 0.12, green: 0.09, blue: 0.08)
                ctx.fill(oval(0.43, 0.46, 0.02, 0.022), with: .color(ink))
                ctx.fill(oval(0.57, 0.46, 0.02, 0.022), with: .color(ink))
                var mouth = Path()
                mouth.move(to: CGPoint(x: 0.45 * s, y: 0.575 * s))
                mouth.addQuadCurve(to: CGPoint(x: 0.55 * s, y: 0.575 * s), control: CGPoint(x: 0.5 * s, y: 0.60 * s))
                ctx.stroke(mouth, with: .color(look.beard == .full ? look.skin : ink.opacity(0.7)), lineWidth: max(1, s * 0.018))
                if look.beard == .moustache {
                    ctx.fill(Path(roundedRect: r(0.43, 0.535, 0.14, 0.03), cornerRadius: s * 0.015), with: .color(look.hair))
                }
                if look.glasses {
                    let frame = Color(red: 0.10, green: 0.10, blue: 0.12)
                    ctx.stroke(oval(0.43, 0.46, 0.055, 0.05), with: .color(frame), lineWidth: max(1, s * 0.016))
                    ctx.stroke(oval(0.57, 0.46, 0.055, 0.05), with: .color(frame), lineWidth: max(1, s * 0.016))
                    ctx.stroke(Path(r(0.485, 0.455, 0.03, 0.001)), with: .color(frame), lineWidth: max(1, s * 0.016))
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        }
    }

    private var backing: LinearGradient {
        LinearGradient(colors: [cloak, cloak.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
