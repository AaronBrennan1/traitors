import SwiftUI

/// What the room is doing right now, shared between a scene and the backdrop behind it.
@Observable
final class Stage {
    /// A colour washing over the room, for a declaration.
    var flood: Color?
    /// 0...1 darkness over everything behind the text: blindfolds, a candle put out.
    var dim = 0.0

    func clear() {
        flood = nil
        dim = 0
    }
}

extension EnvironmentValues {
    /// False while the title card for a new scene is still down, so nothing plays behind it.
    @Entry var curtainUp = true
}

/// Whether the castle may be heard and felt, from the player's settings.
enum Senses {
    static var sound: Bool { Feedback.settings.sound && !Feedback.muted }
    static var haptics: Bool { Feedback.settings.haptics && !Feedback.muted }

    /// `-ceremony settled` opens every staged scene on its last frame, for screenshots.
    static var settledCeremonies: Bool {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "ceremony") == "settled"
        #else
        return false
        #endif
    }
}

/// Counts up through the moments of a scene, waiting as long as each one asks for.
/// Tapping the scene sets `shown` to `count`; VoiceOver users get the whole scene at once.
struct StepClock: ViewModifier {
    @Binding var shown: Int
    let count: Int
    let key: String
    /// Seconds to hold before moment `i` appears.
    var hold: (Int) -> Double
    /// Called once as moment `i` appears on its own; not for moments skipped past.
    var cue: (Int) -> Void = { _ in }
    @Environment(\.curtainUp) private var curtainUp
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    func body(content: Content) -> some View {
        content.task(id: "\(key)|\(count)|\(curtainUp)") {
            guard curtainUp else { return }
            if voiceOver || Senses.settledCeremonies {
                shown = count
                return
            }
            while shown < count {
                try? await Task.sleep(for: .seconds(hold(shown)))
                if Task.isCancelled || shown >= count { return }
                let i = shown
                withAnimation(.easeOut(duration: 0.35)) { shown = i + 1 }
                cue(i)
            }
        }
    }
}

extension View {
    func stepClock(_ shown: Binding<Int>, count: Int, key: String, hold: @escaping (Int) -> Double,
                   cue: @escaping (Int) -> Void = { _ in }) -> some View {
        modifier(StepClock(shown: shown, count: count, key: key, hold: hold, cue: cue))
    }
}
