import Foundation

/// The shadow's hand: what a traitor can do to the course, and what the castle does to it by
/// itself so that a trap falling out of turn is never proof of anything.
extension Gauntlet {
    /// Bags a spill throws back out of the vault, and how many more once few are left to pick them up.
    static var spillBags = 7
    static var spillLate = 1
    /// How near a witness has to be to a mechanism to tell who was standing at it.
    static var witness = 130.0
    /// How far down the course a spilled bag can roll.
    static var spillThrow = 380.0

    func isSaboteur(_ r: Runner) -> Bool { setup.saboteurs.contains(r.id) }

    /// Whether a mechanism has anything to give right now.
    func usable(_ m: Mechanism) -> Bool {
        switch m.kind {
        case .lever(let h): return hazards[h].ready
        case .sconce(let b): return dark[b] == 0
        case .vault: return teamTotal > 0
        }
    }

    /// The nearest mechanism in reach that could be worked from here.
    func mechanism(near p: Vec2) -> Int? {
        var best: Int?
        var bestD = Feel.reach
        for (i, m) in course.mechanisms.enumerated() where usable(m) {
            let d = m.pos.distance(to: p)
            if d <= bestD { bestD = d; best = i }
        }
        return best
    }

    /// Whether a press right now would be the hand and not a dash: a traitor, standing still, with something in reach.
    func canSabotage(_ r: Runner) -> Bool {
        isSaboteur(r) && r.up && r.handCool == 0 && r.move.length < Feel.restStick && r.speed < Feel.restSpeed
            && mechanism(near: r.pos) != nil
    }

    func sabotage(_ i: Int) {
        guard let m = mechanism(near: runners[i].pos) else { return }
        runners[i].handCool = Feel.sabotageCooldown
        acts[i] += 1
        log(.sabotage, i, a: m)
        cues.append(.hand(runners[i].id))
        spring(m, by: runners[i].id)
    }

    /// Works a mechanism, whoever or whatever did it, and writes down everyone standing by it.
    /// The record of who was standing there is the same whether or not one of them did it.
    func spring(_ m: Int, by seat: PlayerID?) {
        let mech = course.mechanisms[m]
        switch mech.kind {
        case .lever(let h):
            guard hazards[h].trip(by: seat) else { return }
            cues.append(.warned(h))
        case .sconce(let b):
            dark[b] = Feel.douseTicks
            darkBy[b] = seat ?? -1
            cues.append(.lights(band: b, out: true))
            log(.darkStart, nil, a: b)
        case .vault:
            let n = min(Gauntlet.spillBags + (runners.count <= 6 ? Gauntlet.spillLate : 0), teamTotal)
            guard n > 0 else { return }
            teamTotal -= n
            scatter(n, from: mech.pos, blame: seat ?? -1, throwDown: true)
            cues.append(.spilled(mech.pos, bags: n))
            log(.spilled, nil, a: n)
        }
        for j in runners.indices where standingBy(runners[j], mech) {
            // Only somebody close can say for certain who was at it.
            var near: SeatMask = 0
            for w in runners.indices where w != j && runners[j].seenBy.has(runners[w].id)
                && runners[w].pos.distance(to: runners[j].pos) <= Gauntlet.witness { near |= SeatMask.seat(runners[w].id) }
            ledger.events.append(MissionEvent(tick: ledger.ticks, actor: runners[j].id, code: .sprung, a: m, seen: near))
            runners[j].lurk = 0
        }
    }

    func standingBy(_ r: Runner, _ m: Mechanism) -> Bool {
        r.up && r.speed < Feel.slow && r.pos.distance(to: m.pos) <= Feel.reach
    }

    // MARK: - What it cost

    func blame(_ seat: PlayerID, _ bags: Double) {
        if let i = index(of: seat) { loss[i] += bags }
    }

    /// Whose gust has hold of this spot, if it is anyone's.
    func gustBlame(_ p: Vec2) -> PlayerID? {
        hazards.first { $0.kind == .gust && $0.state == .live && $0.by != nil && $0.distance(to: p) < 45 }?.by
    }

    /// Whose darkness this spot is in, if it is anyone's.
    func darkBlame(_ p: Vec2) -> PlayerID? {
        for b in dark.indices where dark[b] > 0 && darkBy[b] >= 0 && course.band(b, holds: p) { return darkBy[b] }
        return nil
    }

    /// Private: the traitor whose hand made the difference between making the goal and not.
    var sunkBy: PlayerID? {
        guard teamTotal < goal else { return nil }
        let total = loss.reduce(0, +)
        guard total > 0, Double(teamTotal) + total >= Double(goal) else { return nil }
        var best = 0
        for i in loss.indices where loss[i] > loss[best] { best = i }
        return runners[best].id
    }

    // MARK: - The castle's own slips

    func scheduleCastle() {
        var dice = SeededRNG.derived(setup.seed, 9)
        let n = 2 + dice.int(2)
        misfires = (0..<n).map { _ in Int(Double(totalTicks) * dice.range(0.15, 0.9)) }.sorted()
        draught = course.bands.isEmpty ? -1 : Int(Double(totalTicks) * dice.range(0.2, 0.8))
        vaultSlips = dice.chance(0.35)
    }

    /// Lets the castle's mechanisms slip when their time comes. It waits a little for somebody to
    /// be standing by one, so that being there when it goes is something that happens to the honest too.
    func castle() {
        for b in dark.indices where dark[b] > 0 {
            dark[b] -= 1
            if dark[b] == 0 {
                darkBy[b] = -1
                cues.append(.lights(band: b, out: false))
                log(.darkEnd, nil, a: b)
            }
        }
        let patience = Feel.ticks(4)
        if let due = misfires.first, tick >= due {
            let door = misfires.count == 1 && vaultSlips && teamTotal >= 3
            let pool = course.mechanisms.indices.filter { m in
                let mech = course.mechanisms[m]
                guard usable(mech) else { return false }
                if case .lever = mech.kind { return !door }
                return door && mech.kind == .vault
            }
            let attended = pool.first { m in runners.contains { standingBy($0, course.mechanisms[m]) } }
            if let m = attended ?? (tick - due > patience && !pool.isEmpty ? pool[rng.int(pool.count)] : nil) {
                spring(m, by: nil)
                misfires.removeFirst()
            } else if tick - due > 2 * patience {
                misfires.removeFirst()
            }
        }
        if draught >= 0, tick >= draught {
            let pool = course.mechanisms.indices.filter { m in
                if case .sconce = course.mechanisms[m].kind { return usable(course.mechanisms[m]) }
                return false
            }
            let attended = pool.first { m in runners.contains { standingBy($0, course.mechanisms[m]) } }
            if let m = attended ?? (tick - draught > patience && !pool.isEmpty ? pool[rng.int(pool.count)] : nil) {
                spring(m, by: nil)
                draught = -1
            } else if tick - draught > 2 * patience {
                draught = -1
            }
        }
    }
}
