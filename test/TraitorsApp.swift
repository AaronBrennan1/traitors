import SwiftUI

@main
struct TraitorsApp: App {
    @State private var store = GameStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(Palette.gold)
        }
    }
}

struct RootView: View {
    @Environment(GameStore.self) private var store
    @State private var playing = false
    /// The walkthrough runs before every freshly set-up game.
    @State private var showTutorial = false

    var body: some View {
        ZStack {
            if playing, store.game != nil {
                if showTutorial {
                    TutorialView { showTutorial = false }
                        .transition(.opacity)
                } else {
                    GameView(onExit: { playing = false })
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
