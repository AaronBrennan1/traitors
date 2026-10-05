# Refactoring plan: fewer, deeper modules

The goal is code that is simpler to change and to test. The means is a small number of modules,
each hiding a lot behind a narrow interface, with the compiler enforcing the boundaries.
[ARCHITECTURE.md](ARCHITECTURE.md) describes the code as it is; this says where to take it and
in what order.

- [1. What is wrong today](#1-what-is-wrong-today)
- [2. Target shape](#2-target-shape)
- [3. The interfaces](#3-the-interfaces)
- [4. Order of work](#4-order-of-work)
- [5. How testing changes](#5-how-testing-changes)
- [6. Risks](#6-risks)
- [7. Decisions needed](#7-decisions-needed)

## 1. What is wrong today

The code inside each file is mostly good: small pure functions, careful comments, real
invariants. The problem is between the files. Six things make changes harder than they should
be, in rough order of cost.

**1. There is no boundary between engine and UI.** The app compiles the engine's sources into
its own module, so every view can read and write every field of every engine type. In practice
the UI reads 25 fields of `Game` and about 20 of the live `Gauntlet`, including ones documented
as private. Nothing in the engine can be renamed or restructured without searching the UI.

**2. `Game` exposes its state instead of an interface.** It has about 30 public mutable fields
and one method, `advance`, which silently ignores inputs that do not suit the phase. Every
caller has to know which input is legal when, by reading `phase`, `tableStep`, `voteRound`,
`nightChoice` and `choices`. That knowledge is written out in the UI's views and in **three
separate stand-ins for the human seat** (`Autopilot.input`, `TraitorsSim.seatInput`, the tests'
`autoInput`). The UI also guesses what the next phase will be, in three places, to label a
button.

**3. The feed is the only channel for "what just happened", and it is text.** The rules know a
vote's ballots, who was banished and who died in the night as data, but publish them as `Beat`s.
`VoteScript`, `MorningScript` and `GameStore.concealed` then each reverse-engineer the data from
beat kinds. The UI re-implements two of `VoteScript`'s methods rather than use them.

**4. The public log is interpreted four times.** `LogIndex`, `Replay`, `Game.apply` and the
simulator each carry their own copy of the bookkeeping: who named whom first, what counts as an
attack and how hard, declared votes, ballots. A new kind of statement means four edits that must
agree, and nothing checks that they do. Separately, `view()` rebuilds the whole index and
`Inference.compute` replays the whole log on every bot decision.

**5. Bot decisions have no interface.** `FaithfulBrain` and `TraitorBrain` are bags of static
functions with eight-argument signatures. `Game` assembles those arguments in five places and
checks the sim's `randomFaithful`/`randomTraitors` switches in seven. Adding a kind of player, or
a decision, means threading it through all of them.

**6. About 50 tuning values are global mutable statics**, settable by string name. Two tests
with different tunings cannot run in the same process safely, and a sim's `--tune` leaks into
everything after it.

Smaller, but worth fixing on the way past: the simulator and course-measuring code ship inside
the app; `GameStore` mixes persistence, game driving and information-hiding rules and cannot be
built in a test; there are two parallel sound-and-haptics stacks behind statics; a mission can
resolve two different ways for a spectator; build output is committed.

## 2. Target shape

Five modules in the engine, a lab that does not ship, and a thinner app.

```
                         ┌──────────────────────────── App ────────────────────────────┐
                         │  GameSession   SaveStore   Effects   Screens / Ceremonies   │
                         └───────┬───────────────────────────────────────┬─────────────┘
                                 │ Prompt, Scene, advance                │ ArenaSession, Frame, Cue
                                 ▼                                       ▼
   Lab ─────────────────►  ┌──────────┐   MissionRun / MissionResult   ┌──────────┐
   (sim, measuring,        │   Game   │ ─────────────────────────────► │ Gauntlet │
    scene finder)          └─┬──────┬─┘                                └────┬─────┘
                             │      │ Mind                                  │
                             │      ▼                                       │
                             │  ┌───────┐                                  │
                             │  │ Minds │                                  │
                             │  └───┬───┘                                  │
                             ▼      ▼                                       ▼
                         ┌──────────────────────────── Core ───────────────────────────┐
                         │  vocabulary · PublicRecord · SeededRNG · MissionLedger      │
                         └─────────────────────────────────────────────────────────────┘
```

| Module | Hides | Interface, in one line |
|---|---|---|
| **Core** | How the log is indexed; what each kind of statement means | `PublicRecord`: append an event, ask questions of it |
| **Minds** | Inference, listener models, vote simulation, team planning, defences | `Mind`: six decisions a seat can be asked to make |
| **Game** | Every transition, all turn bookkeeping, the hidden truth | `prompt`, `advance(_:)`, `scene` |
| **Gauntlet** | Physics, traps, bots, sabotage, the ledger | `ArenaSession`: `advance`, `press`, `frame`, `result` |
| **Telling** *(inside Game's target)* | Wording and the order things are revealed | Typed outcomes in, lines and scripts out |
| **Lab** | Statistics and printing | A CLI |
| **App** | Files, audio, SpriteKit | — |

Each engine module becomes a SwiftPM target, so `internal` means "inside this module" and the
compiler holds the line. The app depends on the package instead of compiling its sources.

What decides whether a module is deep enough: a caller should be able to use it correctly
knowing only the table above.

## 3. The interfaces

Sketches, to fix the idea. Names are open.

### Game

```swift
public struct Game: Codable {
    public init(seed: UInt64, human: HumanSeat?, options: GameOptions = .init())

    /// What the game is waiting for. Everything needed to answer it is in the value.
    public var prompt: Prompt { get }

    /// Applies an answer to the current prompt. Throws if it does not fit; never ignores it.
    public mutating func advance(_ answer: Answer) throws

    /// What the human seat is entitled to see right now.
    public var scene: Scene { get }
}

public enum Prompt {
    case proceed(then: Step)                       // tap to continue, and what comes next
    case playMission(MissionRun)                   // or watch it, when the human is out
    case speak(turn: Int, targets: [PlayerID], defences: [DefenceOption])
    case vote(round: Int, candidates: [PlayerID])
    case murder(candidates: [PlayerID], advice: PlayerID?)
    case recruit(candidates: [PlayerID])
    case answerOffer(from: PlayerID)
    case endOrBanish
    case over(winner: Role)
}
```

What this buys:

- The three human stand-ins collapse into one `SeatPolicy` that maps a `Prompt` to an `Answer`.
  `Autopilot`, the sim's `--seat` strategies and the tests' driver become policies.
- Views stop reading `tableStep`, `voteRound`, `nightChoice`, `choices`, `recruiter`,
  `partnerAdvice`. Those become `private`.
- `proceed(then:)` removes the UI's three guesses at the next phase.
- An illegal input is a thrown error in a test, not a game that quietly fails to move.

`Scene` is the read side: day, pot, the seats as the human may see them (role included only
where they are entitled to it), the lines to present, and a **typed outcome** for whatever just
resolved:

```swift
public enum Outcome {
    case vote(VoteOutcome)        // ballots by round, who went, role if revealed, verdict
    case morning(MorningOutcome)  // victim or quiet night, who was never out of sight
    case mission(MissionReport, noticed: [Sighting])
    ...
}
```

`VoteScript` and `MorningScript` then take an outcome, not a feed, and stop pattern-matching
beats. `GameStore.concealed` and `roleShown` move into `Scene`, because "what may the human see"
is a rule, and the engine is where rules are tested. The ceremony tells the scene how far the
telling has got; the scene answers who is shown as seated.

The recruit-night condition, the win check and the "undo the counter" early returns in
`resolveNight` each get written once on the way.

### Core: PublicRecord

```swift
public struct PublicRecord: Codable {
    public private(set) var events: [PublicEvent]
    public mutating func append(_ event: PublicEvent)

    // The questions LogIndex answers today, kept up to date as events arrive.
    public var banishments: [Banishment] { get }
    public func declared(day: Int, by: PlayerID) -> PlayerID?
    public func accuser(of: PlayerID, day: Int) -> PlayerID?
    public func chips(about: PlayerID, suspicious: Bool, sightings: [Sighting]) -> [Chip]
    ...
}
```

and one table that says what each `StatementKind` means:

```swift
extension StatementKind {
    var effect: StatementEffect { get }   // names the target? attack weight? declares a vote? heat?
}
```

`LogIndex`, `Replay.hear`, `Game.apply` and the lab's statistics all read that table instead of
carrying their own `switch`. `Game` holds a `PublicRecord` in place of `log` + rebuilding
`view()`; `TableView` becomes a cheap wrapper over the record plus seats and heat.

### Minds

```swift
public protocol Mind {
    mutating func speak(at table: TableView, phase: TablePhase, replyTo: PlayerID?) -> Intent?
    mutating func vote(at table: TableView, among: [PlayerID], declared: PlayerID?) -> PlayerID
    func endTheGame(at table: TableView) -> Bool
    mutating func useTheHand(at table: TableView, mustKill: Bool) -> Bool
    mutating func murder(at table: TableView) -> PlayerID?
    mutating func recruit(at table: TableView) -> PlayerID?
}
```

Three implementations: faithful, traitor, random. A traitor mind is constructed with what
traitors know (team, plan, what was seen of them); `Game` no longer passes it on every call.
`Game` asks `mind(for: seat)` and calls one method. `options.randomFaithful` and
`randomTraitors` are consulted once, where minds are made.

`Replay`, `Belief`, `Listeners`, `VoteSim`, `TeamPlanner` and `Defences` become internal to the
module. A mind may then keep its `Replay` between calls and feed it only new events, which
removes the replay-from-scratch on every decision without changing any caller. (This changes no
random draws, so games stay identical; see §6.)

The defences the human is offered come from the same module through one public function, so
`Game.defenceOptions()` stops reaching into inference itself.

### Gauntlet

```swift
public final class ArenaSession {
    public init(_ setup: ArenaSetup)
    public let course: Course                 // static geometry, for building the scene once

    public func advance(_ dt: Double, stick: Vec2)
    public func press()

    public var stage: Stage { get }           // countdown(remaining), playing, finished
    public var frame: Frame { get }           // everything to draw this frame, read-only
    public func takeCues() -> [ArenaCue]
    public func result() -> MissionResult
}

public struct Frame {
    public let alpha: Double
    public let clock: Clock                   // secondsLeft, fraction, sealing
    public let teamTotal: Int, goal: Int
    public let runners: [RunnerView]          // pos, last, carry, up, dashReady, visibleToHuman …
    public let hazards: [HazardView]
    public let bags: [Vec2]
    public let floorGone: Set<Int>
    public let darkBands: Set<Int>
    public let handInReach: Bool              // the engine's own answer, not the UI's guess
    public let ownHand: HandSummary?          // only ever the human's
}
```

`Gauntlet`, `Runner`, `Bot`, `Hazard`'s mutators and `Feel` become internal. `ArenaScene` and
`CourseStage` draw from `Frame`. Fog-of-war, hand eligibility and clock maths are answered once,
in the engine, and the renderer's index-alignment assumptions become the snapshot's guarantee.
The traitor's end card gets its numbers from `ownHand` instead of the private `acts`/`loss`.

`ArenaRunner`'s measuring half (`sample`, `winRate`, `par`, `trace`, `report`) moves to Lab.

The spectator's skip plays the session out headless (`ArenaSession.finish()`) and sends that
result, so a mission resolves one way whether or not it was watched.

### Tuning

One value, passed in:

```swift
public struct Tuning: Codable {
    public var belief = BeliefTuning()
    public var mission = MissionTuning()
    public var sightings = SightingTuning()
    public var gauntlet = GauntletTuning()
    public mutating func set(_ name: String, _ value: Double) throws
}
```

carried on `GameOptions` and `ArenaSetup`. No `static var` remains in the engine. `Feel`'s
constants can stay constants.

### App

- `GameStore` splits into **`GameSession`** (holds the `Game`, forwards `advance`, exposes
  `prompt` and `scene`; pure, constructible in a test) and **`SaveStore`** (a protocol with a
  file implementation and an in-memory one). The save gets an envelope with an explicit version
  field instead of a version in the file name.
- **`Effects`**: one protocol for sound and haptics, injected through the environment, with the
  real implementation wrapping `Soundscape` and a recording one for tests and previews. The two
  synth stacks and two haptics stacks merge behind it.
- Ceremony scripts (`moments`) move out of the view types into plain `Equatable` values so they
  can be asserted on.
- Leaf components (`Avatar`, `PlayerPicker`, `BeatRow`) take values, not the store.

## 4. Order of work

Each phase leaves the app shippable and the tests green. Later phases depend on earlier ones
only where noted.

### Phase 0: a safety net (half a day)

1. Add a `.gitignore` for `.build/`, `build/`, `xcuserdata/`, `.DS_Store`, and remove the 5,464
   tracked build products from the index.
2. Commit the arena rewrite that is sitting in the working tree, so there is a known point to
   compare against.
3. Add a **golden-master test**: for a fixed set of seeds (say 200 all-bot, 50 with a scripted
   human in each role, 20 with `options.arena`), record a digest of the final log, winner and
   pot in a checked-in file, and fail if any changes. Add the same for one gauntlet ledger per
   course. This is the test that makes every later phase safe: the existing suite checks that
   rules hold, not that behaviour is unchanged.
4. Record a baseline of `traitors-sim --games 2000` output alongside it, for the phases that are
   allowed to change draws.
5. Split `EngineTests.swift` into one file per section. It already has the `MARK`s.
6. **Get a full green run, and make it fast.** While writing this plan, the package built and
   four quick tests passed, but two attempts at the whole suite with `swift test` (debug) were
   stopped at their time limits without reporting a result, the first after ten minutes. Either
   one test hangs or the statistical tests are far too slow unoptimised. Find out which before
   anything else (`swift test -c release`, then per-test timings), and tag the slow sampling
   tests so the default run finishes in under a minute. A refactor needs a suite that is run
   after every step.

### Phase 1: a real boundary (1–2 days)

1. Make the app depend on the local package and `import TraitorsEngine`, instead of compiling
   `test/Engine` into the app target.
2. Mark `public` exactly what the UI uses today. ARCHITECTURE §11 lists it. This surface is wide
   and ugly, and that is the point: it is now written down and compiler-checked, and every later
   phase is measured by how much of it disappears.
3. Move `Simulator.swift`, the measuring half of `ArenaRunner`, and `Autopilot.scenes` into a
   `TraitorsLab` target that the CLI uses and the app does not. Use `package` access for what
   Lab needs and the app does not.
4. Rename the files that are named for something else (`Audio/Feel.swift`,
   `MissionLeaderboard.swift`, `NightCeremony.swift`, `Rules/GameEngine.swift`) and delete the
   dead code listed in ARCHITECTURE §11.

No behaviour changes. Golden master must be byte-identical.

### Phase 2: Game's interface (3–4 days)

1. Add `Prompt` as a computed property over the existing fields, and `advance(_ answer:) throws`
   beside the old `advance`. Nothing else changes yet.
2. Write `SeatPolicy`; reimplement `Autopilot.input`, `seatInput` and `autoInput` on it; delete
   the three originals.
3. Move the views onto `prompt`, one screen at a time: `TableScreen`, `NightView`,
   `VoteCeremony`, then the "continue" buttons.
4. Add typed `Outcome`s where the rules resolve a vote, a night and a mission. Rebuild
   `VoteScript` and `MorningScript` on them. Use `VoteScript.tally` and `revoteStart` from the
   UI and delete the UI's copies.
5. Add `Scene`; move `concealed`, `shown`, `roleShown`, `spectating` into it with tests.
6. Make the bookkeeping fields `private`. Remove them from the public surface.
7. Bump the save version; add the envelope.

Golden master must be byte-identical: none of this touches a random draw.

### Phase 3: Core and Minds (3–4 days)

1. Introduce `StatementEffect`; point `LogIndex`, `Replay.hear`, `Game.apply` and the lab at it.
   Identical output is the test.
2. Wrap log + index as `PublicRecord` with incremental indexing; a property test checks it
   against a from-scratch rebuild after every event.
3. Introduce `Mind`; move the argument assembly out of `Game` into the three implementations.
4. Split `Core` and `Minds` into their own targets. Make `Replay` and friends internal.
5. Only then: let a mind keep its `Replay` between calls. Measure the sim before and after.

Steps 1–4 must leave the golden master identical. Step 5 should too, since it changes when
inference runs and not what is drawn; if it does not, that is a bug to find, not a golden file
to regenerate.

### Phase 4: Gauntlet and Tuning (3–4 days)

Independent of phases 2 and 3; can run in parallel with them.

1. Add `Frame` and `takeCues()` on `ArenaRunner`; move `CourseStage` then `ArenaScene` onto
   them. Rename to `ArenaSession`.
2. Move fog-of-war, hand-in-reach and clock values into the frame; delete the UI's versions.
3. Make the spectator skip finish the session rather than fall back to dice.
4. Split `Gauntlet` into its own target; make `Gauntlet`, `Runner`, `Bot` internal.
5. Replace the static tuning values with the `Tuning` value, one group at a time. Tests that set
   a static and restore it become tests that pass a value.

Step 3 deliberately changes what a skipped mission returns. Everything else leaves the ledger
golden identical.

### Phase 5: the app (2–3 days)

1. Split `GameStore` into `GameSession` and `SaveStore`. Batch the spectator's skip-to-end into
   one save.
2. Introduce `Effects`; route `Cue`, `Feedback` and `Haptics` through it; merge the synth caches
   and move first-use rendering off the main thread.
3. Lift ceremony scripts into testable values; take the store out of the leaf components.
4. Add an app test target covering `GameSession`, the scripts and save round-trips.

## 5. How testing changes

| Today | After |
|---|---|
| One file, whole games, inspecting `Game`'s fields | A file per module, most tests against one interface |
| Rule tests reach into `tableStep`, `nightChoice`, `lockedVotes` | Rule tests drive `Prompt` → `Answer` and assert on `Outcome` |
| An illegal input does nothing, silently | It throws; one test per prompt checks every wrong answer is refused |
| "Unchanged behaviour" is unchecked | Golden master over a few hundred seeds |
| Inference tested through hand-built logs (good) | The same, plus `PublicRecord` checked against a rebuild |
| Bot behaviour tested by playing games and scanning the log | Also testable by handing a `Mind` a table and asking one question |
| Gauntlet tests poke `runners[i]` and `hazards[i]` | Physics tests stay inside the module with `@testable`; the UI contract is tested on `Frame` |
| Tuning tests mutate globals | They pass a value; tests can run in parallel |
| Nothing in the app is tested | `GameSession`, `Scene`'s concealment rules, ceremony scripts, save round-trip |

The existing 53 tests are worth keeping almost as they are. They state the game's real
invariants, and they are what will catch a refactor that breaks a rule rather than merely
changing a draw.

## 6. Risks

**Draw order.** Every game is a function of its seed and of the exact order random draws are
made in. A refactor that reorders two calls, or evaluates something eagerly that used to be
lazy, changes every game without breaking any rule. The golden master is the defence. Where a
phase is meant to change draws, regenerate the golden file in a commit of its own and check the
sim's rates against the Phase 0 baseline within sampling noise.

**The dice path and the gauntlet must stay in step.** Any change to gauntlet behaviour means
re-measuring `MissionRun`'s constants and `sightLift`. Nothing in this plan changes gauntlet
behaviour on purpose except the spectator skip.

**Saves.** `Game`'s encoded form is the save format, and Phase 2 changes it. See the first
decision below.

**A wide `public` surface in Phase 1** looks like a step backwards. It is the same surface as
today, made visible. Resist tidying it in that phase.

**Performance of `Frame`.** Building a snapshot 60 times a second must not allocate much. Keep
it to flat arrays of small structs and measure on a device before moving the renderer over.

**Default main-actor isolation** applies to every target. Splitting targets does not change
that, but the lab would benefit from running games in parallel, and that needs the engine's
value types to be `nonisolated`. Out of scope here; worth knowing it is waiting.

## 7. Decisions needed

1. **Do saved games need to survive the refactor?** The code today deletes old saves on launch
   whenever the format changes, which suggests not. If that is still acceptable, Phase 2 is
   simpler. If the game has shipped to people with games in progress, Phase 2 needs a migration
   from v7.
2. **How many targets?** The plan ends with Core, Minds, Gauntlet, Engine and Lab. A cheaper
   stopping point is Engine + Lab only, with the inner seams kept by convention. I recommend the
   full split, because convention is what the code has now.
3. **Is the dice path staying?** It exists so headless games are fast and so `Autopilot` can
   reach a scene quickly. If the gauntlet can be played headless fast enough for both, deleting
   the dice path removes a whole second model of a mission and the need to keep two sets of
   constants in agreement. Worth measuring during Phase 4 before deciding.
