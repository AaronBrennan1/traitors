import Foundation
import TraitorsCore

/// How the gauntlet feels under the thumb. Lengths are in points and speeds in points a second;
/// anything counted in steps says so.
public enum Feel {
    /// Steps a second. The game only ever moves in whole steps.
    static let hz = 60
    static let tick = 1.0 / Double(hz)
    public static func ticks(_ seconds: Double) -> Int { Int((seconds * Double(hz)).rounded()) }

    // MARK: Running

    static let radius = 9.0
    static let speed = 165.0
    /// How much of their speed a runner gives up for each bag in their arms.
    static let carryDrag = 0.09
    static let accel = 1400.0
    static let brake = 1800.0
    /// How quickly a shoved runner comes to rest.
    static let skid = 700.0

    // MARK: The dash

    static let dashSpeed = 430.0
    /// Steps a dash lasts: about 70 points, enough for two tiles of nothing and never three.
    static let dashTicks = 10
    static let dashCooldown = ticks(1.6)
    /// Steps at the start of a dash when nothing can touch the runner.
    static let dashGrace = 7
    /// Steps a press is remembered, so one made a moment early still counts.
    static let buffer = 8
    static let shove = 140.0
    static let stagger = ticks(0.25)

    // MARK: Fairness

    /// A hazard hits a little smaller than it is drawn.
    static let forgiveness = 0.8
    /// Steps a runner may stand on nothing before they fall.
    static let coyote = 5
    /// How close a miss has to be to count as a near one.
    static let nearMiss = 10.0
    /// Steps of dash cooldown a near miss gives back.
    static let nearRefund = ticks(0.4)

    // MARK: Gold

    public static let maxCarry = 3
    /// Steps stood at the hoard for each bag after the first.
    static let greed = ticks(0.5)
    static let scatter = 40.0
    /// Steps a dropped bag lies there before it is gone.
    static let looseTicks = ticks(6)
    static let pickup = 16.0
    static let respawn = ticks(1.2)
    static let blink = ticks(1.5)
    /// Deliveries in a row without going down before each one earns a bag extra.
    public static let streakBonus = 3

    // MARK: The round

    /// Steps the vault takes to seal once the goal is in it.
    static let seal = ticks(5)
    static let overtime = ticks(8)
    /// Where the second and third acts begin, as a share of the clock.
    static let acts = [0.35, 0.7]
    /// How much quicker the traps cycle in each act.
    static let actPace = [1.0, 0.82, 0.68]

    // MARK: The shadow's hand

    /// How near a mechanism a hand has to be to work it.
    static let reach = 60.0
    /// A runner going slower than this is standing about, as far as anyone watching can tell.
    static let slow = 60.0
    /// The stick has to be at rest, and the runner all but still, for a press to be the hand and not a dash.
    static let restStick = 0.2
    static let restSpeed = 25.0
    static let sabotageCooldown = ticks(10)
    static let douseTicks = ticks(6)
    static let douseVision = 90.0
    /// Steps a tripped blade runs fast for.
    static let hurry = ticks(4)
    static let hurryPace = 2.1

    /// Steps between the looks the record takes at who is where.
    static let sampleEvery = hz / MissionLedger.hz
}
