import Foundation
import TraitorsCore

/// A few seconds of one mini-game played by a script, to be shown where the rules used to be
/// written out. It is the game itself with a director at the controls, so what it shows is what
/// the game does. When it ends it is started again from the top and plays out the same way.
public final class ArenaDemo {
    /// Which demonstration: how the game is played, or what the shadow's hand does to it.
    public enum Reel: String, CaseIterable {
        case play, hand
    }

    /// What the thumbs are doing this step, for the screen to draw over the picture.
    public struct Thumbs {
        /// The stick, length 0...1, in the arena's own axes.
        public internal(set) var stick = Vec2.zero
        /// A thumb is on the stick, whether or not it is pushing.
        public internal(set) var steering = false
        /// The button is being held down.
        public internal(set) var holding = false
        /// Goes up by one for every press of the button.
        public internal(set) var taps = 0
        /// A strike being drawn back: which way it will fly and how hard, length 0...1.
        public internal(set) var pull: Vec2?
    }

    public let kind: MissionKind
    public let reel: Reel
    /// The game in play. A new one every time the demonstration starts over.
    public private(set) var session: ArenaSession
    private var director: DemoDirector
    /// Seconds from the first step to the last.
    public let duration: Double
    /// Where each beat starts, as a share of the whole. The first is always 0.
    public let beatStarts: [Double]
    /// What each beat shows, in a few words, for VoiceOver.
    public let beatNames: [String]
    /// Anything that did not go as written when it was played through. Empty when all is well.
    let faults: [String]

    public init(_ kind: MissionKind, reel: Reel = .play) {
        self.kind = kind
        self.reel = reel
        // Played through once unseen, to find how long it runs and where its beats fall.
        let (trial, script) = Self.build(kind, reel)
        var steps = 0
        while !script.done, !trial.play.finished, steps < 3600 {
            trial.advance(trial.play.stepSeconds, input: ArenaInput())
            steps += 1
        }
        let length = max(trial.play.time, 0.1)
        duration = length
        beatStarts = script.beats.isEmpty ? [0] : script.beats.enumerated().map { $0.offset == 0 ? 0 : $0.element.time / length }
        beatNames = script.beats.map(\.name)
        faults = script.faults + (script.done ? [] : ["never finished"])
        (session, director) = Self.build(kind, reel)
    }

    private static func build(_ kind: MissionKind, _ reel: Reel) -> (ArenaSession, DemoDirector) {
        let plan = DemoPlans.plan(kind, reel)
        let cast = (0...plan.bots).map { ArenaSeat(id: $0, skill: 0.6, perception: 0.6, deceit: 0.6, isHuman: $0 == 0) }
        let setup = ArenaSetup(kind: kind, day: 1, seed: plan.seed, quirkSeed: plan.seed, cast: cast,
                               saboteurs: reel == .hand ? [0] : [], autopilot: false)
        let play = plan.make?(setup) ?? ArenaGames.make(setup)
        plan.stage(play)
        let director = DemoDirector(plan)
        return (ArenaSession(setup, play: play, director: director), director)
    }

    public var setup: ArenaSetup { session.game.setup }
    public var thumbs: Thumbs { director.thumbs }
    /// Seconds played since it last started.
    public var time: Double { session.play.time }
    /// 0 at the start, 1 at the end.
    public var progress: Double { min(1, time / duration) }
    public var beat: Int { min(director.beat, beatStarts.count - 1) }
    public var ended: Bool { director.done }
    /// A moment that shows the game at a glance, for when nothing is to move.
    public var poster: Double { ((beatStarts.last ?? 0) + 1) / 2 }

    public func advance(_ dt: Double) {
        guard !ended else { return }
        session.advance(dt, input: ArenaInput())
    }

    /// Back to the top. The session is a new one, so whatever was drawing the old one has to be made again.
    public func restart() {
        (session, director) = Self.build(kind, reel)
    }

    /// Starts over and plays unseen up to a share of the way through.
    public func seek(_ share: Double) {
        restart()
        let until = clamp(share, 0, 1) * duration
        var steps = 0
        while time < until, !ended, steps < 3600 {
            session.advance(session.play.stepSeconds, input: ArenaInput())
            steps += 1
        }
        // What happened on the way there is not shown all at once on arriving.
        _ = session.takeCues()
    }
}
