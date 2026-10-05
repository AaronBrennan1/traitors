import SwiftUI
import SpriteKit

/// Where the arena sits in the space it is given: the whole screen on a phone, a tall column on anything wider.
private struct ArenaFrame {
    let size: CGSize
    let layout: ArenaLayout
    /// The status bar's height in the view's own points, for the tally to clear.
    let topInset: CGFloat
    let column: Bool

    init(_ geo: GeometryProxy) {
        let insets = geo.safeAreaInsets
        let full = CGSize(width: geo.size.width + insets.leading + insets.trailing, height: geo.size.height + insets.top + insets.bottom)
        if full.width > 0, full.height / full.width >= 680 / ArenaLayout.width {
            let k = ArenaLayout.width / full.width
            size = full
            layout = ArenaLayout(height: min(full.height * k, 900), safeTop: insets.top * k, safeBottom: insets.bottom * k)
            topInset = insets.top
            column = false
        } else {
            let height = min(geo.size.height, geo.size.width * 700 / ArenaLayout.width)
            size = CGSize(width: height * ArenaLayout.width / 700, height: height)
            layout = ArenaLayout(height: 700, safeTop: 0, safeBottom: 0)
            topInset = 0
            column = true
        }
    }
}

/// Hosts the day's mini-game while everyone plays it, then what the company made of it.
struct MissionView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    var onExit: () -> Void = {}
    @State private var scene: ArenaScene?

    var body: some View {
        if let game = store.game, let run = game.mission {
            if game.phase == .mission {
                GeometryReader { geo in
                    let frame = ArenaFrame(geo)
                    ZStack {
                        if let scene {
                            ZStack {
                                SpriteView(scene: scene)
                                    // The thumbs go straight through to the game, VoiceOver or not.
                                    .accessibilityElement()
                                    .accessibilityLabel("\(run.kind.title), play area")
                                    .accessibilityHint(MissionKind.controls.joined(separator: " "))
                                    .accessibilityDirectTouch(true, options: .silentOnTouch)
                                ArenaHUDView(model: scene.model, topInset: frame.topInset)
                                if !game.humanAlive, !scene.model.paused {
                                    Button("Skip to the result") { store.send(.next) }
                                        .buttonStyle(GhostButtonStyle())
                                        .padding(.horizontal, 60)
                                        .padding(.bottom, 40)
                                        .frame(maxHeight: .infinity, alignment: .bottom)
                                }
                                if scene.model.paused { ArenaPauseView(model: scene.model, topInset: frame.topInset, onLeave: onExit) }
                            }
                            .animation(.easeOut(duration: Tokens.Motion.standard), value: scene.model.paused)
                            .animation(.easeOut(duration: Tokens.Motion.standard), value: scene.model.countdown == nil)
                            .animation(.easeOut(duration: Tokens.Motion.standard), value: scene.model.ended)
                            .frame(width: frame.size.width, height: frame.size.height)
                            .clipShape(RoundedRectangle(cornerRadius: frame.column ? Tokens.Radius.sheet : 0))
                            .overlay { if frame.column { RoundedRectangle(cornerRadius: Tokens.Radius.sheet).stroke(Palette.line) } }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(edges: frame.column ? [] : .all)
                    .onAppear { start(game, run, frame.layout) }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { scene?.model.pause() }
                }
                .onDisappear {
                    scene?.onFinish = nil
                    scene = nil
                }
            } else {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            if let report = game.report {
                                MissionResultCard(report: report)
                            }
                            // The card says how the day went; the feed adds what you saw and any traitor business.
                            ForEach(game.feed.indices, id: \.self) { i in
                                if game.feed[i].kind != .result, game.feed[i].kind != .host { BeatRow(beat: game.feed[i]) }
                            }
                        }
                        .padding(16)
                    }
                    BottomBar {
                        if !game.humanAlive, game.human != nil { SpectatorNote() }
                        Button("To the Round Table") { store.send(.next) }.buttonStyle(GoldButtonStyle())
                    }
                }
            }
        }
    }

    private func start(_ game: Game, _ run: MissionRun, _ layout: ArenaLayout) {
        guard scene == nil else { return }
        let cast = run.order.sorted().map { p in
            let player = game.players[p]
            return Contestant(id: p, name: player.name, color: Tokens.Hue.cloak(for: player).ui, isHuman: player.isHuman)
        }
        var autopilot = false
        var pace = 1.0
        #if DEBUG
        // `-arenaBots 1` has a bot play the human's seat; `-arenaSpeed 4` runs the game four times as fast.
        // `-arenaPause 1` opens on the pause menu.
        autopilot = UserDefaults.standard.bool(forKey: "arenaBots")
        pace = max(1, UserDefaults.standard.double(forKey: "arenaSpeed"))
        #endif
        let made = ArenaScene(config: ArenaConfig(setup: ArenaSetup(run: run, autopilot: autopilot), cast: cast,
                                                  handVisible: game.humanAlive && game.humanIsTraitor, spectating: run.human == nil),
                              layout: layout)
        made.pace = pace
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "arenaPause") {
            Task {
                try? await Task.sleep(for: .seconds(4))
                made.model.pause()
            }
        }
        #endif
        made.onFinish = { [store] result in store.send(.mission(result)) }
        scene = made
    }
}
