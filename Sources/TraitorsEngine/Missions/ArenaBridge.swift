import Foundation
import TraitorsCore
import TraitorsGauntlet

// Where a day's mission, as the rules planned it, becomes a mini-game to play. The mini-games
// know nothing of the rules; this is the only place the two meet.

extension ArenaSetup {
    /// The day's mission as the engine planned it.
    public init(run: MissionRun, autopilot: Bool) {
        var saboteurs: [PlayerID] = []
        if let r = run.runner, r != run.human, run.runnerAttempt { saboteurs.append(r) }
        if let h = run.human, run.traitors.contains(h) { saboteurs.append(h) }
        let cast = run.order.sorted().map { p in
            ArenaSeat(id: p, skill: run.skill[p], perception: run.perception[p], deceit: run.deceit[p], isHuman: p == run.human)
        }
        self.init(kind: run.kind, day: run.day, seed: run.layoutSeed, quirkSeed: run.quirkSeed, cast: cast,
                  saboteurs: saboteurs, form: run.form, autopilot: autopilot, tuning: run.tuning)
    }
}

extension ArenaSession {
    /// Plays a planned mission out with a bot in every seat.
    package static func play(_ run: MissionRun) -> MissionResult {
        play(ArenaSetup(run: run, autopilot: true))
    }
}
