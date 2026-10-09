import SwiftUI

@main
struct TraitorsApp: App {
    @State private var session = TraitorsApp.launch()

    private static func launch() -> GameSession {
        let session = GameSession()
        #if DEBUG
        Autoplay.applyLaunchArguments(to: session)
        #endif
        return session
    }

    @ViewBuilder private var root: some View {
        #if DEBUG
        // `-demo all` or `-demo kiteRace` opens on the demonstrations alone, for looking them over.
        if let which = UserDefaults.standard.string(forKey: "demo") { DemoGallery(which: which) } else { RootView() }
        #else
        RootView()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            root
                .environment(session)
                .environment(\.effects, session.effects)
                .preferredColorScheme(.dark)
                .tint(Palette.gold)
        }
    }
}

struct RootView: View {
    @Environment(GameSession.self) private var session
    @State private var playing = false
    /// The walkthrough runs before every freshly set-up game.
    @State private var showTutorial = false

    var body: some View {
        ZStack {
            if playing, session.game != nil {
                if showTutorial {
                    TutorialView { showTutorial = false }
                        .transition(.opacity)
                } else {
                    GameView(onExit: { playing = false })
                        // Everyone as the human may see them, for the small components, sheets included.
                        .environment(\.roster, Roster(session.scene))
                        .transition(.opacity)
                }
            } else {
                TitleView(onPlay: { isNew in
                    showTutorial = isNew
                    playing = true
                })
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: playing)
        .animation(.easeInOut(duration: 0.3), value: showTutorial)
        .onAppear {
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "autoplay") {
                showTutorial = UserDefaults.standard.bool(forKey: "tutorial")
                playing = true
            }
            #endif
        }
    }
}
