import SwiftUI

/// The room behind everything: painted once for where you are, with its lights moving on top.
/// Kept dark enough everywhere that text can sit straight on it.
struct CastleBackdrop: View {
    let place: Place
    /// Still lights, for the mission (which has its own moving picture) and for Reduce Motion.
    var paused = false
    @Environment(Stage.self) private var stage: Stage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Canvas { ctx, size in PlacePainter(place: place, size: size).paint(&ctx) }
                .id(place)
                .transition(.opacity)
            TimelineView(.animation(minimumInterval: 1.0 / 15, paused: paused || reduceMotion || scenePhase != .active)) { timeline in
                Canvas { ctx, size in
                    PlacePainter(place: place, size: size).lights(&ctx, t: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
            .id(place)
            .transition(.opacity)
            // The lower two thirds carry the text, so the room fades towards the floor.
            LinearGradient(colors: [Palette.ink.opacity(0.10), Palette.ink.opacity(0.55), Palette.ink.opacity(0.80)],
                           startPoint: .top, endPoint: .bottom)
            if let flood = stage?.flood {
                RadialGradient(colors: [flood.opacity(0.45), flood.opacity(0.10)], center: .center, startRadius: 0, endRadius: 520)
                    .transition(.opacity)
            }
            Color.black.opacity((stage?.dim ?? 0) * 0.94)
        }
        .animation(.easeInOut(duration: 0.8), value: place)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Draws one place. `paint` is everything that stays put; `lights` is whatever flickers.
struct PlacePainter {
    let place: Place
    let size: CGSize

    private var w: CGFloat { size.width }
    private var h: CGFloat { size.height }
    private func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }
    private func rect(_ x: CGFloat, _ y: CGFloat, _ rw: CGFloat, _ rh: CGFloat) -> CGRect {
        CGRect(x: x * w, y: y * h, width: rw * w, height: rh * h)
    }
    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

    // MARK: - The room

    func paint(_ ctx: inout GraphicsContext) {
        switch place {
        case .hall:
            wall(&ctx, Self.rgb(0.13, 0.10, 0.08), Self.rgb(0.04, 0.04, 0.04))
            stones(&ctx, rows: 16, alpha: 0.05)
            // The great door, shut.
            let door = arch(rect(0.30, 0.10, 0.40, 0.46))
            ctx.fill(door, with: .color(Self.rgb(0.05, 0.04, 0.03)))
            ctx.stroke(door, with: .color(Self.rgb(0.25, 0.19, 0.12)), lineWidth: 5)
            ctx.stroke(Path { $0.move(to: p(0.5, 0.12)); $0.addLine(to: p(0.5, 0.56)) }, with: .color(Self.rgb(0.16, 0.12, 0.08)), lineWidth: 2)
            banner(&ctx, x: 0.12, Palette.blood)
            banner(&ctx, x: 0.80, Palette.gold)
            floor(&ctx, y: 0.56, Self.rgb(0.07, 0.06, 0.05))
        case .breakfastRoom:
            wall(&ctx, Self.rgb(0.13, 0.15, 0.15), Self.rgb(0.04, 0.05, 0.05))
            stones(&ctx, rows: 18, alpha: 0.04)
            for x in [0.10, 0.39, 0.68] as [CGFloat] {
                let window = arch(rect(x, 0.07, 0.22, 0.34))
                ctx.fill(window, with: .linearGradient(
                    Gradient(colors: [Self.rgb(0.34, 0.40, 0.48), Self.rgb(0.62, 0.48, 0.40)]),
                    startPoint: p(0, 0.07), endPoint: p(0, 0.41)))
                mullions(&ctx, rect(x, 0.07, 0.22, 0.34))
                // Morning light falling across the room.
                var shaft = Path()
                shaft.move(to: p(x, 0.41)); shaft.addLine(to: p(x + 0.22, 0.41))
                shaft.addLine(to: p(x + 0.52, 1)); shaft.addLine(to: p(x + 0.12, 1))
                shaft.closeSubpath()
                ctx.fill(shaft, with: .linearGradient(
                    Gradient(colors: [Self.rgb(0.95, 0.80, 0.62).opacity(0.10), .clear]),
                    startPoint: p(0, 0.41), endPoint: p(0, 0.95)))
            }
            table(&ctx, y: 0.93, rim: Self.rgb(0.42, 0.30, 0.18))
        case .grounds:
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [Self.rgb(0.17, 0.23, 0.27), Self.rgb(0.28, 0.31, 0.30), Self.rgb(0.06, 0.09, 0.08)]),
                startPoint: .zero, endPoint: p(0, 0.62)))
            hill(&ctx, base: 0.44, peak: 0.33, shift: 0.25, Self.rgb(0.10, 0.15, 0.14))
            // The castle on its rise: a keep and two towers.
            let stone = Self.rgb(0.07, 0.09, 0.09)
            for r in [rect(0.52, 0.22, 0.10, 0.20), rect(0.62, 0.28, 0.16, 0.14), rect(0.78, 0.18, 0.08, 0.24)] {
                ctx.fill(Path(r), with: .color(stone))
                var x = r.minX
                while x < r.maxX - 1 {
                    ctx.fill(Path(CGRect(x: x, y: r.minY - 0.008 * h, width: r.width / 7, height: 0.008 * h)), with: .color(stone))
                    x += r.width / 3.5
                }
            }
            hill(&ctx, base: 0.52, peak: 0.40, shift: 0.70, Self.rgb(0.06, 0.10, 0.08))
            floor(&ctx, y: 0.52, Self.rgb(0.05, 0.08, 0.06))
        case .roundTable:
            wall(&ctx, Self.rgb(0.11, 0.08, 0.07), Self.rgb(0.03, 0.03, 0.03))
            // Dark panelling, and the night in two high windows.
            for i in 0..<7 {
                let x = CGFloat(i) / 7
                ctx.stroke(Path { $0.move(to: p(x, 0)); $0.addLine(to: p(x, 0.60)) }, with: .color(.black.opacity(0.25)), lineWidth: 2)
            }
            for x in [0.20, 0.66] as [CGFloat] {
                let window = arch(rect(x, 0.06, 0.14, 0.26))
                ctx.fill(window, with: .color(Self.rgb(0.07, 0.10, 0.17)))
                mullions(&ctx, rect(x, 0.06, 0.14, 0.26))
            }
            candelabra(&ctx, x: 0.09, y: 0.50)
            candelabra(&ctx, x: 0.91, y: 0.50)
            table(&ctx, y: 0.92, rim: Palette.gold.opacity(0.55))
        case .turret:
            wall(&ctx, Self.rgb(0.07, 0.08, 0.10), Self.rgb(0.02, 0.02, 0.03))
            // A round room: the courses of stone bow towards you.
            for i in 0..<14 {
                let y = CGFloat(i) / 14 * 0.70
                var course = Path()
                course.move(to: p(0, y))
                course.addQuadCurve(to: p(1, y), control: p(0.5, y + 0.05))
                ctx.stroke(course, with: .color(.white.opacity(0.035)), lineWidth: 1)
            }
            // An arrow slit with the moon behind it.
            ctx.fill(Path(roundedRect: rect(0.47, 0.09, 0.06, 0.24), cornerRadius: 0.03 * w), with: .color(Self.rgb(0.20, 0.26, 0.38)))
            ctx.fill(Path(ellipseIn: CGRect(x: 0.485 * w, y: 0.14 * h, width: 0.03 * w, height: 0.03 * w)), with: .color(Self.rgb(0.85, 0.88, 0.92)))
            // The chain the lantern hangs from.
            ctx.stroke(Path { $0.move(to: p(0.22, 0)); $0.addLine(to: p(0.22, 0.20)) }, with: .color(Self.rgb(0.18, 0.16, 0.14)), lineWidth: 2)
            floor(&ctx, y: 0.70, Self.rgb(0.03, 0.03, 0.04))
        case .bedchamber:
            wall(&ctx, Self.rgb(0.07, 0.09, 0.13), Self.rgb(0.02, 0.03, 0.04))
            let window = rect(0.60, 0.08, 0.26, 0.26)
            ctx.fill(Path(window), with: .color(Self.rgb(0.12, 0.17, 0.28)))
            ctx.fill(Path(ellipseIn: CGRect(x: 0.74 * w, y: 0.11 * h, width: 0.07 * w, height: 0.07 * w)), with: .color(Self.rgb(0.88, 0.90, 0.92)))
            mullions(&ctx, window)
            // Moonlight on the floor.
            var patch = Path()
            patch.move(to: p(0.30, 0.74)); patch.addLine(to: p(0.56, 0.74))
            patch.addLine(to: p(0.44, 0.92)); patch.addLine(to: p(0.10, 0.92))
            patch.closeSubpath()
            ctx.fill(patch, with: .color(Self.rgb(0.40, 0.50, 0.70).opacity(0.08)))
            // The door, bolted, and the bedside table.
            ctx.fill(arch(rect(0.08, 0.20, 0.24, 0.42)), with: .color(Self.rgb(0.05, 0.05, 0.06)))
            ctx.stroke(arch(rect(0.08, 0.20, 0.24, 0.42)), with: .color(Self.rgb(0.16, 0.14, 0.12)), lineWidth: 3)
            ctx.fill(Path(rect(0.27, 0.42, 0.035, 0.012)), with: .color(Self.rgb(0.30, 0.26, 0.18)))
            floor(&ctx, y: 0.62, Self.rgb(0.03, 0.04, 0.05))
            ctx.fill(Path(rect(0.40, 0.50, 0.14, 0.12)), with: .color(Self.rgb(0.10, 0.08, 0.06)))
        case .fireOfTruth:
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [Self.rgb(0.03, 0.04, 0.08), Self.rgb(0.09, 0.06, 0.06), Self.rgb(0.03, 0.03, 0.03)]),
                startPoint: .zero, endPoint: p(0, 0.70)))
            var seed: UInt64 = 77
            for _ in 0..<60 {
                let x = unit(&seed), y = unit(&seed) * 0.36, r = 0.6 + unit(&seed) * 1.1
                ctx.fill(Path(ellipseIn: CGRect(x: x * w, y: y * h, width: r, height: r)), with: .color(.white.opacity(0.25 + 0.4 * unit(&seed))))
            }
            // Standing stones around the fire.
            let stone = Self.rgb(0.05, 0.05, 0.06)
            for (x, top, width) in [(0.04, 0.26, 0.11), (0.20, 0.31, 0.08), (0.72, 0.30, 0.09), (0.86, 0.25, 0.11)] as [(CGFloat, CGFloat, CGFloat)] {
                ctx.fill(Path(roundedRect: rect(x, top, width, 0.50 - top), cornerRadius: 0.02 * w), with: .color(stone))
            }
            floor(&ctx, y: 0.48, Self.rgb(0.04, 0.04, 0.04))
            // The bowl.
            var bowl = Path()
            bowl.move(to: p(0.36, 0.42)); bowl.addQuadCurve(to: p(0.64, 0.42), control: p(0.5, 0.52))
            bowl.closeSubpath()
            ctx.fill(bowl, with: .color(Self.rgb(0.14, 0.11, 0.09)))
            ctx.fill(Path(rect(0.485, 0.46, 0.03, 0.06)), with: .color(Self.rgb(0.10, 0.08, 0.07)))
        }
    }

    // MARK: - The lights

    func lights(_ ctx: inout GraphicsContext, t: Double) {
        switch place {
        case .hall:
            glow(&ctx, at: p(0.5, 0.04), radius: 0.55 * w, Self.rgb(1.0, 0.72, 0.36), 0.16 + 0.03 * flicker(t, 1))
        case .breakfastRoom:
            glow(&ctx, at: p(0.5, 0.20), radius: 0.9 * w, Self.rgb(1.0, 0.80, 0.62), 0.07 + 0.01 * flicker(t * 0.2, 2))
        case .grounds:
            // A few lit windows in the keep.
            for (i, at) in [p(0.565, 0.30), p(0.70, 0.34), p(0.815, 0.26)].enumerated() {
                let a = 0.75 + 0.2 * flicker(t, Double(i) + 3)
                ctx.fill(Path(CGRect(x: at.x, y: at.y, width: 0.012 * w, height: 0.016 * h)), with: .color(Self.rgb(1.0, 0.76, 0.40).opacity(a)))
                glow(&ctx, at: at, radius: 0.05 * w, Self.rgb(1.0, 0.72, 0.36), 0.18 * a)
            }
        case .roundTable:
            for x in [0.09, 0.91] as [CGFloat] {
                for (i, dx) in [-0.035, 0, 0.035].enumerated() {
                    let lift: CGFloat = i == 1 ? 0.035 : 0.02
                    candle(&ctx, at: p(x + dx, 0.50 - lift), t: t, phase: Double(x) * 10 + Double(i), scale: 1)
                }
                glow(&ctx, at: p(x, 0.45), radius: 0.42 * w, Self.rgb(1.0, 0.66, 0.30), 0.20 + 0.04 * flicker(t, Double(x) * 7))
            }
            glow(&ctx, at: p(0.5, 0.94), radius: 0.6 * w, Self.rgb(1.0, 0.70, 0.36), 0.09)
        case .turret:
            glow(&ctx, at: p(0.5, 0.15), radius: 0.30 * w, Self.rgb(0.55, 0.65, 0.95), 0.16)
            // The lantern swings a little on its chain.
            let sway = CGFloat(sin(t * 0.9)) * 0.012
            let at = p(0.22 + sway, 0.23)
            ctx.fill(Path(roundedRect: CGRect(x: at.x - 0.022 * w, y: at.y - 0.03 * h, width: 0.044 * w, height: 0.045 * h), cornerRadius: 3),
                     with: .color(Self.rgb(0.16, 0.13, 0.10)))
            candle(&ctx, at: CGPoint(x: at.x, y: at.y + 0.008 * h), t: t, phase: 5, scale: 0.9)
            glow(&ctx, at: at, radius: 0.55 * w, Self.rgb(1.0, 0.62, 0.26), 0.22 + 0.05 * flicker(t, 9))
        case .bedchamber:
            glow(&ctx, at: p(0.775, 0.14), radius: 0.34 * w, Self.rgb(0.55, 0.65, 0.95), 0.14)
            // The candle by the bed.
            ctx.fill(Path(rect(0.462, 0.455, 0.016, 0.045)), with: .color(Self.rgb(0.80, 0.76, 0.66)))
            candle(&ctx, at: p(0.47, 0.455), t: t, phase: 8, scale: 1.1)
            glow(&ctx, at: p(0.47, 0.43), radius: 0.50 * w, Self.rgb(1.0, 0.66, 0.30), 0.20 + 0.05 * flicker(t, 11))
        case .fireOfTruth:
            glow(&ctx, at: p(0.5, 0.36), radius: 0.85 * w, Self.rgb(1.0, 0.50, 0.16), 0.30 + 0.06 * flicker(t, 13))
            for i in 0..<7 {
                let k = Double(i)
                let x = 0.40 + CGFloat(i) * 0.033
                let tall = 0.07 + 0.05 * CGFloat(flicker(t * 1.3, k * 2.1) * 0.5 + 0.5) + (i == 3 ? 0.04 : 0)
                let lean = CGFloat(flicker(t * 1.7, k * 3.3)) * 0.012 * w
                let tongue = flame(at: p(x, 0.43), width: 0.035 * w, height: tall * h, lean: lean)
                ctx.fill(tongue, with: .linearGradient(
                    Gradient(colors: [Self.rgb(1.0, 0.86, 0.45), Self.rgb(0.95, 0.42, 0.10), Self.rgb(0.6, 0.12, 0.05).opacity(0.3)]),
                    startPoint: p(0, 0.43), endPoint: CGPoint(x: 0, y: 0.43 * h - tall * h)))
            }
            // Embers going up.
            for i in 0..<14 {
                let k = Double(i)
                let life = (t * 0.16 + k * 0.071).truncatingRemainder(dividingBy: 1)
                let x = 0.5 + CGFloat(sin(k * 12.9898) * 0.11) + CGFloat(sin(t * 0.8 + k) * 0.015)
                let y = 0.40 - CGFloat(life) * 0.36
                ctx.fill(Path(ellipseIn: CGRect(x: x * w, y: y * h, width: 2.2, height: 2.2)),
                         with: .color(Self.rgb(1.0, 0.62, 0.22).opacity((1 - life) * 0.8)))
            }
        }
    }

    // MARK: - Pieces

    private func wall(_ ctx: inout GraphicsContext, _ top: Color, _ bottom: Color) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            Gradient(colors: [top, bottom]), startPoint: .zero, endPoint: p(0, 1)))
    }

    private func stones(_ ctx: inout GraphicsContext, rows: Int, alpha: Double) {
        let rowHeight = 0.60 * h / CGFloat(rows)
        for row in 0..<rows {
            let y = CGFloat(row) * rowHeight
            ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: w, y: y)) }, with: .color(.white.opacity(alpha)), lineWidth: 1)
            var x = row % 2 == 0 ? 0 : w / 10
            while x < w {
                ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: y)); $0.addLine(to: CGPoint(x: x, y: y + rowHeight)) }, with: .color(.white.opacity(alpha)), lineWidth: 1)
                x += w / 5
            }
        }
    }

    private func floor(_ ctx: inout GraphicsContext, y: CGFloat, _ color: Color) {
        ctx.fill(Path(rect(0, y, 1, 1 - y)), with: .linearGradient(
            Gradient(colors: [color, Self.rgb(0.02, 0.02, 0.02)]), startPoint: p(0, y), endPoint: p(0, 1)))
    }

    private func arch(_ r: CGRect) -> Path {
        var path = Path()
        let radius = r.width / 2
        path.move(to: CGPoint(x: r.minX, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
        path.addArc(center: CGPoint(x: r.midX, y: r.minY + radius), radius: radius, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        path.closeSubpath()
        return path
    }

    private func mullions(_ ctx: inout GraphicsContext, _ r: CGRect) {
        let lead = Self.rgb(0.05, 0.05, 0.05)
        ctx.stroke(Path { $0.move(to: CGPoint(x: r.midX, y: r.minY)); $0.addLine(to: CGPoint(x: r.midX, y: r.maxY)) }, with: .color(lead), lineWidth: 3)
        ctx.stroke(Path { $0.move(to: CGPoint(x: r.minX, y: r.midY)); $0.addLine(to: CGPoint(x: r.maxX, y: r.midY)) }, with: .color(lead), lineWidth: 3)
    }

    private func banner(_ ctx: inout GraphicsContext, x: CGFloat, _ color: Color) {
        var cloth = Path()
        cloth.move(to: p(x, 0.06)); cloth.addLine(to: p(x + 0.08, 0.06))
        cloth.addLine(to: p(x + 0.08, 0.36)); cloth.addLine(to: p(x + 0.04, 0.32)); cloth.addLine(to: p(x, 0.36))
        cloth.closeSubpath()
        ctx.fill(cloth, with: .color(color.opacity(0.32)))
    }

    private func hill(_ ctx: inout GraphicsContext, base: CGFloat, peak: CGFloat, shift: CGFloat, _ color: Color) {
        var hill = Path()
        hill.move(to: p(0, base))
        hill.addQuadCurve(to: p(1, base), control: p(shift, peak - (base - peak)))
        hill.addLine(to: p(1, 1)); hill.addLine(to: p(0, 1))
        hill.closeSubpath()
        ctx.fill(hill, with: .color(color))
    }

    /// The near edge of a great table, seen from your own chair.
    private func table(_ ctx: inout GraphicsContext, y: CGFloat, rim: Color) {
        let top = Path(ellipseIn: rect(-0.25, y - 0.09, 1.5, 0.40))
        ctx.fill(top, with: .color(Self.rgb(0.09, 0.06, 0.04)))
        ctx.stroke(top, with: .color(rim), lineWidth: 2)
    }

    private func candelabra(_ ctx: inout GraphicsContext, x: CGFloat, y: CGFloat) {
        let brass = Self.rgb(0.30, 0.23, 0.12)
        ctx.stroke(Path { $0.move(to: p(x, y)); $0.addLine(to: p(x, y + 0.16)) }, with: .color(brass), lineWidth: 4)
        var arms = Path()
        arms.move(to: p(x - 0.035, y - 0.01)); arms.addQuadCurve(to: p(x + 0.035, y - 0.01), control: p(x, y + 0.035))
        ctx.stroke(arms, with: .color(brass), lineWidth: 3)
        for (i, dx) in [-0.035, 0, 0.035].enumerated() {
            let lift: CGFloat = i == 1 ? 0.035 : 0.02
            ctx.fill(Path(rect(x + dx - 0.006, y - lift, 0.012, lift + 0.004)), with: .color(Self.rgb(0.78, 0.74, 0.64)))
        }
    }

    private func flame(at base: CGPoint, width: CGFloat, height: CGFloat, lean: CGFloat) -> Path {
        var path = Path()
        let tip = CGPoint(x: base.x + lean, y: base.y - height)
        path.move(to: tip)
        path.addQuadCurve(to: base, control: CGPoint(x: base.x + width, y: base.y - height * 0.2))
        path.addQuadCurve(to: tip, control: CGPoint(x: base.x - width, y: base.y - height * 0.2))
        return path
    }

    private func candle(_ ctx: inout GraphicsContext, at base: CGPoint, t: Double, phase: Double, scale: CGFloat) {
        let tall = (0.022 + 0.004 * CGFloat(flicker(t * 1.4, phase))) * h * scale
        let lean = CGFloat(flicker(t * 1.9, phase * 1.7)) * 2
        ctx.fill(flame(at: base, width: 0.012 * w * scale, height: tall, lean: lean),
                 with: .color(Self.rgb(1.0, 0.84, 0.50)))
    }

    private func glow(_ ctx: inout GraphicsContext, at c: CGPoint, radius: CGFloat, _ color: Color, _ alpha: Double) {
        var layer = ctx
        layer.blendMode = .plusLighter
        layer.fill(Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)),
                   with: .radialGradient(Gradient(colors: [color.opacity(alpha), color.opacity(0)]), center: c, startRadius: 0, endRadius: radius))
    }

    /// -1...1, wandering the way a flame does.
    private func flicker(_ t: Double, _ phase: Double) -> Double {
        (sin(t * 7.3 + phase * 1.9) * 0.5 + sin(t * 13.1 + phase * 4.3) * 0.3 + sin(t * 23.7 + phase) * 0.2)
    }

    private func unit(_ seed: inout UInt64) -> CGFloat {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return CGFloat(seed >> 40) / CGFloat(1 << 24)
    }
}
