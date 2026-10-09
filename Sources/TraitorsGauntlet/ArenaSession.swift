import Foundation
import TraitorsCore

/// Something other than thumbs at the controls. It is asked once for every step of the game, so
/// a round it plays comes out the same however the frames fall.
protocol ArenaDirector: AnyObject {
    func drive(_ play: any ArenaPlay) -> (input: ArenaInput, press: Bool, shot: Vec2?)
}

/// One mini-game from the countdown to the hand-back of the result, on screen or headless.
/// Whatever is driving it gives it time and the thumbs, and asks it what to show and to sound.
public final class ArenaSession {
    public enum Stage { case countdown, playing, finished }

    /// The clock as the top of the screen shows it.
    public struct Clock: Equatable {
        public let secondsLeft: Int
        /// 1 at the start of play, 0 when time is up.
        public let fraction: Double
        public let urgent: Bool
    }

    package let setup: ArenaSetup
    /// The game itself, for a stage to draw from and nothing more. Everything else is asked of the session.
    public var game: any ArenaGame { play }
    /// The game as the session drives it.
    package let play: any ArenaPlay
    /// The game, when it is the gauntlet.
    package var gauntlet: Gauntlet? { play as? Gauntlet }
    public private(set) var stage = Stage.countdown
    private var countdown = 2.7
    private var owed = 0.0
    /// A press of the button, and a strike let go, that no step has taken yet.
    private var pressed = false
    private var shot: Vec2?
    private var held = false
    /// Something other than thumbs at the controls, asked once for every step.
    private let director: (any ArenaDirector)?

    public init(_ setup: ArenaSetup) {
        self.setup = setup
        play = ArenaGames.make(setup)
        director = nil
    }

    /// A game already laid out, played by a director. With no countdown it starts at once.
    init(_ setup: ArenaSetup, play: any ArenaPlay, director: any ArenaDirector, countdown: Double = 0) {
        self.setup = setup
        self.play = play
        self.director = director
        self.countdown = countdown
        if countdown <= 0 { stage = .playing }
    }

    /// How far the screen is between the last step and the next, 0...1, for drawing in between.
    public var alpha: Double { stage == .playing ? min(1, owed / play.stepSeconds) : 1 }

    /// The 3, 2, 1 before the start. Nil once play has begun.
    public var countdownNumber: Int? { stage == .countdown ? min(3, Int(countdown / 0.9) + 1) : nil }

    public var clock: Clock {
        Clock(secondsLeft: Int(play.timeLeft.rounded(.up)), fraction: (play.timeLeft / max(play.totalTime, 1) * 200).rounded() / 200,
              urgent: play.timeLeft < 8)
    }

    public var teamTotal: Int { play.teamTotal }
    public var goal: Int { play.goal }
    public var won: Bool { play.won }
    /// What each seat has brought home, in the order of `setup.cast`.
    public var tally: [Int] { play.tally }
    /// 0...1 while a full vault is sealing. Nil in the games with nothing to seal.
    public var sealing: Double? { gauntlet?.sealing }

    /// The seat of whoever is at the controls, and their place in the cast.
    public var player: PlayerID? { play.humanSeat }
    private var playerIndex: Int? { player.flatMap { seat in setup.cast.firstIndex { $0.id == seat } } }

    /// The human pressed the button. It is kept until a step can take it, however the frames fall.
    public func press() {
        if stage == .playing { pressed = true }
    }

    /// The human let a strike go.
    public func shoot(_ v: Vec2) {
        if stage == .playing { shot = v }
    }

    /// Moves the game on by a frame. The game itself always runs in whole steps, and a long
    /// frame is caught up, not slowed down.
    public func advance(_ dt: Double, input: ArenaInput) {
        held = input.hold
        switch stage {
        case .countdown:
            countdown -= dt
            if countdown <= 0 { stage = .playing }
        case .playing:
            play.input = input
            owed = min(owed + dt, 0.25)
            let tick = play.stepSeconds
            while owed >= tick, !play.finished {
                if let director {
                    let hands = director.drive(play)
                    play.input = hands.input
                    held = hands.input.hold
                    if hands.press { pressed = true }
                    if let v = hands.shot { shot = v }
                }
                if pressed {
                    play.press()
                    pressed = false
                }
                if let v = shot {
                    play.shoot(v)
                    shot = nil
                }
                play.step()
                owed -= tick
            }
            if play.finished { stage = .finished }
        case .finished:
            break
        }
    }

    /// Plays whatever is left of the round at once, with nobody at the controls from here on.
    /// A round that is skipped is still a round that was played.
    public func finish() {
        play.input = ArenaInput()
        while !play.finished { play.step() }
        owed = 0
        stage = .finished
    }

    /// Everything the game has asked to be shown or sounded since this was last called.
    public func takeCues() -> [ArenaCue] {
        let cues = play.cues
        play.cues.removeAll(keepingCapacity: true)
        return cues
    }

    /// The player's button, eyes and hands this frame. Nil when nobody is at the controls.
    public var panel: PlayerPanel? { play.panel(alpha: alpha, pressed: held, playing: stage == .playing) }
    public func playerSees(_ seat: PlayerID) -> Bool { play.playerSees(seat) }
    public func trap(_ index: Int) -> Vec2? { play.trap(index) }
    public func aim(_ pull: Vec2) -> (from: Vec2, to: Vec2, ready: Bool)? { play.aim(pull) }

    /// How the round went for the player themselves. Nil when nobody was at the controls.
    public var playerResult: PlayerResult? {
        guard let me = playerIndex else { return nil }
        let count = tally[me]
        return PlayerResult(count: count, extras: play.ownExtras(place: tally.filter { $0 > count }.count + 1))
    }

    /// What the human's own hand did, when they had it.
    public var ownHand: HandSummary? {
        guard setup.humanHasHand, let me = playerIndex else { return nil }
        return HandSummary(uses: play.acts[me], cost: Int(play.loss[me].rounded()), sank: play.sunkBy == player)
    }

    public func result() -> MissionResult {
        MissionResult(teamTotal: play.teamTotal, sunkBy: play.sunkBy, ledger: play.ledger)
    }


    package static func play(_ setup: ArenaSetup) -> MissionResult {
        let session = ArenaSession(setup)
        while !session.play.finished { session.play.step() }
        return session.result()
    }
}
