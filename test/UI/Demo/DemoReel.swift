import SwiftUI
import SpriteKit
import TraitorsEngine
import TraitorsGauntlet

/// The row of bars along the top of anything that plays in parts: one bar a part, filling as it goes.
struct StoryBar: View {
    /// Where each part starts, as a share of the whole. The first is 0.
    let starts: [Double]
    /// 0...1 through the whole.
    let progress: Double
    var tint: Color = Palette.gold

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 4
            let room = geo.size.width - gap * CGFloat(max(starts.count - 1, 0))
            HStack(spacing: gap) {
                ForEach(starts.indices, id: \.self) { i in
                    let from = starts[i], to = i + 1 < starts.count ? starts[i + 1] : 1
                    let width = max(0, room * CGFloat(to - from))
                    let done = to > from ? min(max((progress - from) / (to - from), 0), 1) : 1
                    Capsule().fill(Palette.parchment.opacity(0.24))
                        .overlay(alignment: .leading) {
                            Capsule().fill(tint).frame(width: width * CGFloat(done))
                        }
                        .frame(width: width)
                }
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

/// The frame a demonstration plays in: a dark bezel with a hairline of gold, the game's own
/// colour glowing behind it, and the picture set in like a screen. The tutorial's scenes sit in
/// the same frame, so the two read as one thing.
struct ReelFrame<Picture: View>: View {
    var tint: Color
    var edge: Color = Palette.gold
    var compact = false
    @ViewBuilder var picture: Picture

    var body: some View {
        let radius = compact ? Tokens.Radius.card : Tokens.Radius.sheet
        let inset: CGFloat = compact ? 3 : 5
        picture
            .clipShape(RoundedRectangle(cornerRadius: radius - inset, style: .continuous))
            .overlay {
                // Glass: a little light across the top, and a hairline where the picture meets the bezel.
                RoundedRectangle(cornerRadius: radius - inset, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.07), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.3)))
                    .allowsHitTesting(false)
            }
            .overlay(RoundedRectangle(cornerRadius: radius - inset, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
            .padding(inset)
            .background(Palette.ink, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(edge.opacity(0.5), lineWidth: 1))
            .shadow(color: tint.opacity(compact ? 0 : 0.5), radius: 26, y: 10)
            .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
    }
}

/// A mini-game demonstrating itself: a few seconds of the real game, played by a script, on a
/// loop. This is what stands where the written rules used to.
struct DemoReel: View {
    let kind: MissionKind
    var reel: ArenaDemo.Reel = .play
    /// Small, for the pause menu.
    var compact = false
    /// False while it is off the screen, on another page say, so it does not play to nobody.
    var active = true
    /// Called each time the loop comes round.
    var onLoop: () -> Void = {}

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scene: DemoScene?

    private var hand: Bool { reel == .hand }

    var body: some View {
        ReelFrame(tint: hand ? Palette.blood : kind.tint, edge: hand ? Palette.blood : Palette.gold, compact: compact) {
            ZStack {
                Palette.ink
                if let scene {
                    SpriteView(scene: scene)
                    chrome(scene)
                }
            }
            .aspectRatio(DemoScene.picture.width / DemoScene.picture.height, contentMode: .fit)
        }
        .onAppear { show() }
        .onChange(of: kind) { show() }
        .onChange(of: reel) { show() }
        .onChange(of: scene?.clock.loops) { _, loops in
            if let loops, loops > 0 { onLoop() }
        }
        .onChange(of: active && scenePhase == .active, initial: true) { _, playing in scene?.playing = playing }
        .onDisappear { scene = nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hand ? "The Shadow's Hand, demonstration" : "\(kind.title), demonstration")
        .accessibilityValue(hand ? kind.hand : (kind.controls + [kind.twist]).joined(separator: " "))
        .accessibilityAddTraits(.isImage)
        .accessibilityAction(named: "Play") { scene?.playOnce() }
    }

    private func show() {
        if let scene {
            scene.load(kind: kind, reel: reel)
        } else {
            let made = DemoScene(kind: kind, reel: reel, still: reduceMotion)
            made.playing = active && scenePhase == .active
            scene = made
        }
    }

    /// What sits over the picture: the bars along the top, the traitor's seal, and a way to play a still.
    @ViewBuilder private func chrome(_ scene: DemoScene) -> some View {
        let clock = scene.clock
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                StoryBar(starts: clock.beats, progress: clock.progress, tint: hand ? Palette.blood : Palette.gold)
                if hand, !compact {
                    Label("For your eyes only", systemImage: "eye.slash.fill")
                        .font(.serif(.caption2, weight: .heavy)).tracking(1.5).textCase(.uppercase)
                        .foregroundStyle(Palette.parchment)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Palette.blood.opacity(0.85), in: Capsule())
                }
            }
            .padding(.horizontal, compact ? 8 : 12)
            .padding(.top, compact ? 8 : 11)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Palette.ink.opacity(0.7), Palette.ink.opacity(0)], startPoint: .top, endPoint: .bottom))
            Spacer(minLength: 0)
        }
        if clock.waiting {
            Button {
                Feedback.play(.tap)
                scene.playOnce()
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: compact ? 18 : 24, weight: .bold))
                    .foregroundStyle(Palette.gold)
                    .frame(width: compact ? 44 : 60, height: compact ? 44 : 60)
                    .background(Palette.ink.opacity(0.78), in: Circle())
                    .overlay(Circle().strokeBorder(Palette.gold.opacity(0.7), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
        }
    }
}

#if DEBUG
/// Every demonstration on one screen, or one of them at the size the brief shows it, for looking
/// them over. `-demo all` or `-demo kiteRace`, and `-demoReel hand` for the traitor's.
struct DemoGallery: View {
    let which: String
    private var reel: ArenaDemo.Reel { ArenaDemo.Reel(rawValue: UserDefaults.standard.string(forKey: "demoReel") ?? "") ?? .play }
    private var page: Int { UserDefaults.standard.integer(forKey: "demoPage") }

    var body: some View {
        ZStack {
            CastleBackground()
            if let kind = MissionKind(rawValue: which) {
                VStack(spacing: 14) {
                    Text(kind.title).font(Tokens.TypeRole.display.font(.title2)).foregroundStyle(Palette.parchment)
                    DemoReel(kind: kind, reel: reel)
                    Text(reel == .hand ? kind.handGist : kind.gist)
                        .font(Tokens.TypeRole.title.font(.title3)).foregroundStyle(Palette.parchment)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .padding(20)
            } else {
                // Six to a screen, so each is big enough to judge.
                let kinds = Array(MissionKind.allCases.dropFirst(page * 6).prefix(6))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(kinds, id: \.self) { kind in
                        VStack(spacing: 4) {
                            DemoReel(kind: kind, reel: reel, compact: true)
                            Text(kind.title).font(.serif(.caption2)).foregroundStyle(Palette.muted).lineLimit(1)
                        }
                    }
                }
                .padding(8)
            }
        }
    }
}
#endif
