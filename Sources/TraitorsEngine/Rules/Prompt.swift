import Foundation
import TraitorsCore
import TraitorsMinds

/// What a tap to continue leads to, so a button can say where it goes.
public enum Step: Equatable {
    case breakfast, missionBrief, mission, roundTable, fireOfTruth, vote, night, morning, ending
}

/// What the game is waiting for. Everything needed to answer it is in the value.
public enum Prompt {
    /// Nothing to decide: continue, and this is what comes next.
    case proceed(then: Step)
    /// The day's mission, to be played and handed back. When the human is out (`run.human` is
    /// nil) they only watch, and may move on without a result.
    case playMission(MissionRun)
    /// The human's turn at the table: say something about one of `targets`, answer the charge
    /// with one of `defences`, or stay quiet.
    case speak(turn: Int, targets: [PlayerID], defences: [DefenceOption])
    case vote(round: Int, candidates: [PlayerID])
    case murder(candidates: [PlayerID], advice: PlayerID?)
    case recruit(candidates: [PlayerID])
    /// The last traitor is in the human's room with an offer.
    case answerOffer(from: PlayerID)
    /// The Fire of Truth: end the game, or banish again.
    case endOrBanish
    case over(winner: Role?)
}

/// An answer to the current `Prompt`.
public enum Answer {
    case proceed
    case mission(MissionResult)
    case say(HumanSay, target: PlayerID?, chip: Chip?)
    /// Answer an accusation with the defence at this index of the prompt's `defences`.
    case rebut(Int)
    case vote(PlayerID)
    case murder(PlayerID)
    case recruit(PlayerID)
    case offer(accept: Bool)
    case finale(end: Bool)
}

/// Why an answer was refused. The game is left exactly as it was.
public enum GameError: Error, Equatable {
    /// The answer is not one the current prompt takes.
    case notAskedFor
    /// The player named is not one of those offered.
    case notACandidate(PlayerID?)
    case noSuchDefence(Int)
    case gameOver
}

/// Something that plays a seat: given what the game is asking, what does it answer?
/// The app's autoplay, the simulator's lazy players and the tests' driver are all one of these.
public protocol SeatPolicy {
    mutating func answer(_ prompt: Prompt, in game: Game) -> Answer
}

extension Game {
    /// Plays on with `seat` answering every prompt, until the game is over, `stop` says so, or `limit` answers have been given.
    @discardableResult
    package mutating func play<S: SeatPolicy>(_ seat: inout S, limit: Int = 600, until stop: (Game) -> Bool = { _ in false }) -> Int {
        var steps = 0
        while phase != .gameOver, steps < limit, !stop(self) {
            let answer = seat.answer(prompt, in: self)
            do { try advance(answer) } catch {
                assertionFailure("\(type(of: seat)) answered \(prompt) with \(answer): \(error)")
                break
            }
            steps += 1
        }
        return steps
    }
}

extension NightChoice {
    /// The night decision a prompt is asking for, if it is one.
    public init(_ prompt: Prompt) {
        switch prompt {
        case .murder: self = .murder
        case .recruit: self = .recruit
        case .answerOffer: self = .offer
        default: self = .none
        }
    }
}
