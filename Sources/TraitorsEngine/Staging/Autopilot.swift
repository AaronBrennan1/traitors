import Foundation
import TraitorsCore
import TraitorsMinds
import TraitorsGauntlet

/// Plays the human seat with fixed choices up to a chosen point. The app uses it to open on a
/// given scene, and the simulator uses the same inputs to find seeds that reach the rare ones.
public enum Autopilot {
    public struct Stop {
        public var phase: Phase = .gameOver
        public var day = 1
        /// Only stop in this round of voting, when set.
        public var voteRound: Int?
        /// Only stop on a night with this decision in front of the human, when set.
        public var night: NightChoice?

        public init() {}

        func matches(_ g: Game) -> Bool {
            guard g.phase == phase, g.day >= day else { return false }
            let asked = g.prompt
            if let voteRound {
                guard case .vote(voteRound, _) = asked else { return false }
            }
            if let night, night != NightChoice(asked) { return false }
            return true
        }
    }

    public static func play(seed: UInt64, name: String, preference: RolePreference, stop: Stop, mission: MissionKind? = nil) -> Game {
        var g = Game(seed: seed, humanName: name, preference: preference)
        if let mission, mission.isGauntlet, let slot = g.missionDeck.firstIndex(where: \.isGauntlet) {
            // The deck holds one course of the gauntlet. Make it the one asked for.
            g.missionDeck[slot] = mission
        }
        if let mission, let at = g.missionDeck.firstIndex(of: mission) {
            // Deal the deck so the requested mission falls on the day we stop.
            g.missionDeck.swapAt(at, (stop.day - 1) % g.missionDeck.count)
        }
        var seat = Seat()
        g.play(&seat, until: stop.matches)
        return g
    }

    /// The fixed choices: work hard (or spoil the day, as a traitor), open with an accusation
    /// when there is something to cite, vote for the first name, take what is offered.
    public struct Seat: SeatPolicy {
        public init() {}

        public func answer(_ prompt: Prompt, in game: Game) -> Answer {
            switch prompt {
            case .proceed, .over:
                return .proceed
            case .playMission(let run):
                return .mission(MissionResult(effort: game.humanIsTraitor ? 0.7 : 1.2, sabotage: game.humanIsTraitor ? run.tuning.mission.sabotageCost : 0))
            case .speak(let turn, let targets, _):
                if let t = targets.first, let chip = game.notebook(about: t, suspicious: true).first, turn == 1 {
                    return .say(.accuse, target: t, chip: chip)
                }
                return .say(.pass, target: nil, chip: nil)
            case .vote(_, let candidates): return .vote(candidates[0])
            case .murder(let candidates, let advice): return .murder(advice ?? candidates[0])
            case .recruit(let candidates): return .recruit(candidates[0])
            case .answerOffer: return .offer(accept: true)
            case .endOrBanish: return .finale(end: false)
            }
        }
    }
}
