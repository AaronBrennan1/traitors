import SwiftUI
import TraitorsEngine

/// How the game works, shown and not told: six short scenes that play themselves, one line under
/// each. Shown before every new game and from the title screen. Tap either side to step, hold to
/// stop it where it is, or swipe.
struct TutorialView: View {
    /// Label on the last scene's button.
    var finishLabel = "Take your seat"
    var onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var page = TutorialView.firstPage
    /// When the scene on show began, less any time it has spent held.
    @State private var began = Date()
    /// Seconds into the scene at which it was stopped, while it is.
    @State private var held: Double?

    private let scenes = Vignette.all
    private var last: Bool { page == scenes.count - 1 }
    /// Nothing moves on, and nothing moves, for anyone who has asked for that or is listening and not watching.
    private var still: Bool { reduceMotion || voiceOver }

    private static var firstPage: Int {
        #if DEBUG
        // `-tutorialPage 3` opens on a scene, for looking at it.
        return min(max(UserDefaults.standard.integer(forKey: "tutorialPage"), 0), Vignette.all.count - 1)
        #else
        return 0
        #endif
    }

    var body: some View {
        ZStack {
            CastleBackground()
            VStack(spacing: 0) {
                HStack {
                    Text("How to play").font(.serif(.caption, weight: .heavy)).tracking(2).textCase(.uppercase).foregroundStyle(Palette.gold)
                    Spacer()
                    Button("Skip", action: onDone).font(.serif(.subheadline, weight: .semibold)).foregroundStyle(Palette.muted)
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)

                TimelineView(.animation(paused: held != nil || still)) { time in
                    let t = moment(at: time.date)
                    VStack(spacing: 16) {
                        ReelFrame(tint: Palette.gold.opacity(0.5)) {
                            ZStack(alignment: .top) {
                                VignetteView(index: page, t: t)
                                    .id(page)
                                    .transition(.opacity)
                                StoryBar(starts: scenes.indices.map { Double($0) / Double(scenes.count) },
                                         progress: (Double(page) + min(t / scenes[page].duration, 1)) / Double(scenes.count))
                                    .padding(.horizontal, 12).padding(.top, 11).padding(.bottom, 22)
                                    .background(LinearGradient(colors: [Palette.ink.opacity(0.7), Palette.ink.opacity(0)], startPoint: .top, endPoint: .bottom))
                            }
                            .aspectRatio(3.0 / 4, contentMode: .fit)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(SpatialTapGesture().onEnded { tap in step(tap.location.x < 130 ? -1 : 1) })
                        .onLongPressGesture(minimumDuration: 0.2, perform: {}, onPressingChanged: hold)
                        .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { drag in
                            if abs(drag.translation.width) > abs(drag.translation.height) { step(drag.translation.width < 0 ? 1 : -1) }
                        })

                        // The one line.
                        Text(scenes[page].line)
                            .font(Tokens.TypeRole.title.font(.title3)).foregroundStyle(Palette.parchment)
                            .multilineTextAlignment(.center).lineLimit(1).minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity)
                            .id(page)
                            .transition(.opacity.combined(with: .offset(y: 6)))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 16)
                .frame(maxWidth: 520)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(scenes[page].line)
                .accessibilityValue("\(scenes[page].spoken) Scene \(page + 1) of \(scenes.count).")
                .accessibilityAdjustableAction { way in step(way == .increment ? 1 : -1) }

                Button(last ? finishLabel : "Next") {
                    Feedback.play(.tap)
                    if last { onDone() } else { show(page + 1) }
                }
                .buttonStyle(GoldButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        // Each scene moves on by itself when it has played, all but the last.
        .task(id: "\(page)|\(held == nil)|\(still)") {
            guard !still, held == nil, !last else { return }
            let left = scenes[page].duration + 0.5 - Date().timeIntervalSince(began)
            try? await Task.sleep(for: .seconds(max(left, 0)))
            if !Task.isCancelled { show(page + 1) }
        }
    }

    /// How many seconds into the scene on show it is.
    private func moment(at now: Date) -> Double {
        if still { return scenes[page].poster }
        return held ?? now.timeIntervalSince(began)
    }

    private func show(_ next: Int) {
        guard scenes.indices.contains(next) else { return }
        withAnimation(.easeInOut(duration: Tokens.Motion.reveal)) { page = next }
        began = Date()
        held = nil
    }

    private func step(_ by: Int) {
        guard scenes.indices.contains(page + by) else { return }
        Feedback.play(.tap)
        show(page + by)
    }

    /// A finger held on the picture stops it there, and letting go carries on from the same moment.
    private func hold(_ down: Bool) {
        if down {
            if held == nil { held = Date().timeIntervalSince(began) }
        } else if let at = held {
            began = Date().addingTimeInterval(-at)
            held = nil
        }
    }
}
