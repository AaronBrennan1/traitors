# Architecture: how the code works today

This describes the code as it stands in the working tree on 2026-10-05, ahead of the refactor
laid out in [REFACTORING_PLAN.md](REFACTORING_PLAN.md). It is a map, not a wish list: everything
here is what the code does now. Problems are noted where they sit and collected in the plan.

- [1. What this is](#1-what-this-is)
- [2. Layout and build targets](#2-layout-and-build-targets)
- [3. The game loop](#3-the-game-loop)
- [4. Engine, area by area](#4-engine-area-by-area)
- [5. Who knows what](#5-who-knows-what)
- [6. The mission pipeline](#6-the-mission-pipeline)
- [7. Randomness and determinism](#7-randomness-and-determinism)
- [8. Invariants the code relies on](#8-invariants-the-code-relies-on)
- [9. Tests](#9-tests)
- [10. Tools](#10-tools)
- [11. App and UI](#11-app-and-ui)

## 1. What this is

A single-player iOS game modelled on *The Traitors*. One human and seven bots (or eight bots,
headless) sit at a table of eight with two hidden traitors. Each day runs breakfast → mission →
Round Table → vote → night, until the traitors are all banished or can no longer be outvoted.

Two things are unusual and shape the whole design:

- **The bots reason honestly.** A bot is handed only the public record and its own private
  notes, and does exact Bayesian inference over every possible traitor team. Nothing passes it
  the hidden roles.
- **The mission is a real-time mini-game** whose record of who stood where and who could see
  them becomes the evidence argued over at the table. There are eleven: the gauntlet (on one of
  five courses) and ten games of their own. The same simulation runs on screen and headless for
  balancing.

## 2. Layout and build targets

```
Package.swift            SwiftPM harness: library + sim CLI + tests
test/                    The app's sources (the Xcode target is also called "test")
  TraitorsApp.swift      @main
  App/                   GameStore (owns the Game, persistence), Settings
  Engine/                Everything with no UI in it. Imports Foundation only.
    Core/                Models, events, public table view, RNG
    Rules/               GameEngine.swift: the Game struct
    AI/                  Beliefs, bot decision-making, team planning
    Dialogue/            Turning intents into lines; the host; colour
    Missions/            The day's mission as the rules see it; ledger → sightings
    Arena/               The mini-games: the gauntlet, and `ArenaCore` with a game per file in Games/
    Staging/             Presentation ordering derived from game state; Autopilot
    Simulator.swift      Headless balancing harness (the CLI's body)
  UI/                    SwiftUI + SpriteKit
Tests/EngineTests/       One file, 53 Swift Testing tests
Tools/Sim/main.swift     Three lines: calls TraitorsSim.run
test.xcodeproj           The iOS app
```

About 5,900 lines of engine, 5,400 of UI and app, 1,150 of tests.

**The engine is compiled twice, into two different modules.**

| Build | Module | What is in it | How it sees the engine |
|---|---|---|---|
| Xcode app `test` | `test` | Every file under `test/` (a file-system-synchronised group) | Same module: every `internal` name in the engine is visible to every view |
| SwiftPM `TraitorsEngine` | `TraitorsEngine` | `test/Engine` only | Tests use `@testable import`; the sim sees one `public` symbol |

So there is **no compiler-enforced boundary between engine and UI**. The only `public`
declarations in the codebase are `TraitorsSim` and `TraitorsSim.run`
([Simulator.swift:6](../test/Engine/Simulator.swift#L6)). Everything else is `internal`, and
almost nothing is `private`.

Both builds set default actor isolation to `MainActor`, Swift language mode 5, and
`MemberImportVisibility` ([Package.swift:7-13](../Package.swift#L7-L13), project build
settings). The whole engine is therefore main-actor-isolated, including bulk simulation.

**Repository state worth knowing before touching anything:**

- There is one commit. The working tree holds a large uncommitted rewrite of the arena: the ten
  per-game `*Core.swift`/`*Stage.swift` pairs are deleted and replaced by a single gauntlet
  (`Course`, `Gauntlet*`, `Hazards`, `Sabotage`, `ArenaScene`, `CourseStage`), which are
  untracked. Almost every other engine file is modified.
- `.build/` (172 MB) and `build/` (160 MB) are **committed**: 5,464 tracked build products, and
  there is no `.gitignore`. Every build dirties the tree.

## 3. The game loop

The whole game is one value type, `Game`
([GameEngine.swift:5](../test/Engine/Rules/GameEngine.swift#L5)), and one entry point:

```swift
mutating func advance(_ input: HumanInput)
```

`advance` runs the rules forward until the next point where the human has to decide something or
tap to continue, then returns. It switches on `phase`; each phase accepts certain inputs and
**silently ignores the rest**. After each call the UI reads `phase`, `feed` (the lines to
present) and whatever other fields it needs straight off the struct.

| Phase | Input that moves it | What happens | Next |
|---|---|---|---|
| `roleReveal` | any | `startDay` | `breakfast` |
| `breakfast` | any | Winner set overnight → end. Otherwise `beginBrief`: pick the course, decide whether a bot traitor will use the hand, build the `MissionRun`. In the finale there is no mission and it goes straight to the table. | `missionBrief`, `roundTable`, or `gameOver` |
| `missionBrief` | any | `beginMission`: `run.plan()`. With no human seated the mission is resolved at once (dice, or `ArenaRunner.play` when `options.arena`). | `mission` or `missionResult` |
| `mission` | `.mission(MissionResult)`; any input if the human is out | `run.resolve`, then `finishMission`: public report logged, pot paid, sightings handed to the minds that saw them, feed built. | `missionResult` |
| `missionResult` | any | `enterRoundTable`: heat reset, team plan refreshed, bots take the `opening` (1 slot) and `accusations` (3 slots) rounds. With no living human the rest of the table and the vote run through at once. | `roundTable` (or onwards) |
| `roundTable` | `.say` or `.rebut` | Human's turn 1, then bots' `rebuttals` (2) and `openFloor` (1); human's turn 2, then `declarations` and `lockVotes`. `tableStep` is 1 or 2. | `roundTable`, then `voting` (or `finaleChoice` in the finale) |
| `voting` | `.vote(p)` with `p` in `choices` | `resolveVotes`. A tie on round 1 sets `candidates`, relocks bot votes and asks again (the human only votes again if not one of the tied); a second tie is decided by `rng.pick`. Then `banish`: snapshot, tallies, end check. | `voting` or `voteReveal` |
| `voteReveal` | any | `afterBanishment`: end, or (finale) another open floor and `finaleChoice`, or `enterNight`. | `night`, `finaleChoice`, `gameOver` |
| `night` | Whatever `nightChoice` asks for: `.murder(p)`, `.recruit(p)`, `.recruitAnswer(Bool)`, or any | `resolveNight`: murder/recruit applied, `.night` logged, tomorrow's `morning` beats prepared, `day += 1`, `startDay`. | `breakfast` |
| `finaleChoice` | `.finale(end:)` | Unanimous "end" finishes the game; otherwise banish again. | `finaleReveal` |
| `finaleReveal` | any | | `gameOver` or `voting` |
| `gameOver` | — | | — |

Rules that are easy to miss:

- **The night belongs to the traitors only if the company fell short** (`traitorsMayAct`,
  [GameEngine.swift:149](../test/Engine/Rules/GameEngine.swift#L149)). A won mission means no
  murder and no recruitment.
- **Recruitment** replaces the murder when one traitor is left, it has not been used, and five
  or more will be alive. The condition is written out three times
  ([:250](../test/Engine/Rules/GameEngine.swift#L250),
  [:336](../test/Engine/Rules/GameEngine.swift#L336),
  [:778](../test/Engine/Rules/GameEngine.swift#L778)). A human who refuses the offer is murdered.
- **The finale** begins on the morning four or fewer are alive (`startDay`). No missions, no
  nights, banished players leave without revealing, and the game ends on a unanimous vote to end
  or when two are left.
- **Bots lock their votes before the human chooses** (`lockVotes`), so nothing the human does on
  the voting screen can leak into them.
- **The win check** is written twice: after a banishment (`checkEnd`) and after the night
  ([:894](../test/Engine/Rules/GameEngine.swift#L894)).
- A rejected night input returns early and has to undo a counter it already bumped
  (`tally.nights -= 1`, four places in `resolveNight`).

`Game` has about 30 stored properties, all `var`, all readable and writable by anyone. They fall
into groups that the type does not distinguish:

| Group | Fields |
|---|---|
| Identity and setup | `seed`, `rng`, `players`, `minds`, `human`, `options`, `missionDeck` |
| Public record | `day`, `log`, `heat`, `pot`, `report`, `winner`, `finale` |
| Presentation | `phase`, `feed`, `morning` |
| Hidden truth | `sightings`, `sunkBy`, `teamPlan`, `mission` (a `MissionRun` with its own private fields) |
| Turn bookkeeping | `tableStep`, `voteRound`, `candidates`, `lockedVotes`, `lockedFinale`, `nightChoice`, `recruiter`, `partnerAdvice`, `recruitmentUsed` |
| Statistics | `history`, `tally` |

`Game` is `Codable`, and the encoded struct is the save format.

## 4. Engine, area by area

### Core

| File | Holds |
|---|---|
| [Models.swift](../test/Engine/Core/Models.swift) | `PlayerID` (= `Int`, the seat index), `Role`, `RolePreference`, `Voice`, `Personality` (eight 0…1 traits), `Player`, `Cast.bots` (the seven fixed characters), `SeatMask` (`UInt32` bit set of seats) |
| [GameState.swift](../test/Engine/Core/GameState.swift) | `Phase`, `Beat`/`BeatKind` (one line of the feed), `HumanInput`, `HumanSay`, `NightChoice`, `DaySnapshot`, `GameOptions` (sim-only switches), `Tally` (counters) |
| [Events.swift](../test/Engine/Core/Events.swift) | `MissionSpec`, `MissionKind` (five courses of the gauntlet and ten games, with their titles, icons, brief, controls, hand text and par), `MissionReport`, `Chip`/`ChipKind` (a citable piece of evidence), `Statement`/`StatementKind`, `Defence`, and `PublicEvent`, the log's element type |
| [TableView.swift](../test/Engine/Core/TableView.swift) | `Seat`, `TableView` (the public state handed to bots), `LogIndex` (the log pre-digested), `Chips.about` / `Chips.holds` (what evidence exists about a player, and whether a cited chip is true) |
| [Sightings.swift](../test/Engine/Core/Sightings.swift) | `SightingKind`, `Sighting` (who was seen doing what, and by whom), `SightingModel` (base rates used by the dice path) |
| [Random.swift](../test/Engine/Core/Random.swift) | `SeededRNG` (SplitMix64, `Codable`), `fork`, `derived`, and the free function `clamp` |
| [Rules.swift](../test/Engine/Core/Rules.swift) | `Rules.seats = 8`, `Rules.traitors = 2` |

`PublicEvent` is the heart of it: `.mission`, `.statement`, `.vote`, `.banished`, `.night`,
`.finaleVote`. Everything every bot believes is a function of `[PublicEvent]` plus its own
sightings and gut.

`Game.view()` builds a fresh `TableView` on every call, and `TableView.init` builds a fresh
`LogIndex` by walking the whole log. `view()` is called from most of the rule methods, often
inside loops.

### Rules

[GameEngine.swift](../test/Engine/Rules/GameEngine.swift) is the `Game` struct described in §3:
setup, queries, `advance`, and a private method per transition. It also:

- assembles the argument list for every bot decision (`botIntent`, `botVote`, and inline in
  `beginBrief`, `enterNight`, `enterFinaleChoice`), checking `options.randomFaithful` /
  `randomTraitors` in seven places;
- applies the social effect of each statement (`apply`: heat, grudges, tallies);
- has witnesses contradict false testimony on the spot (`contest`);
- writes most of the narrative text inline as string literals (whispers, vote lines, mission
  results, night secrets).

### AI

| File | Holds |
|---|---|
| [Belief.swift](../test/Engine/AI/Belief.swift) | `Tuning` (about 30 mutable static likelihood ratios and `Tuning.set(name, value)` for the sim), `Observer`, `EvidenceKind`, `Belief` (distribution over teams, with `reasons(for:)`), `Replay` (the inference engine), `Inference.compute` |
| [BotMind.swift](../test/Engine/AI/BotMind.swift) | `BotMind` (private notes: gut, seen, exposed, banked, own RNG), `Intent`, `Proposal`, `TablePhase`, `FaithfulBrain` |
| [TraitorPlanner.swift](../test/Engine/AI/TraitorPlanner.swift) | `TraitorBrain`: speak, vote, murder, recruit, whether to use the hand, finale |
| [TeamPlanner.swift](../test/Engine/AI/TeamPlanner.swift) | `Stance`, `TeamPlan` (stored on the game), `TeamPlanner.plan` and the partner's `whisper` |
| [Defences.swift](../test/Engine/AI/Defences.swift) | `DefenceOption`, `Defences.candidates` (what the record supports) and `choose` (which lands best) |
| [ListenerModel.swift](../test/Engine/AI/ListenerModel.swift) | `Listeners` (a model of every other mind at the table), `VoteSim.pBanish` (Monte Carlo of the coming vote) |

How it fits together:

- **`Replay`** enumerates every team of `Rules.traitors` from the seats other than the observer
  (21 hypotheses for a faithful at a table of eight) and keeps a log-likelihood per hypothesis
  per `EvidenceKind`. `feed(_ event:)` updates it one public event at a time; `belief()`
  normalises. It is a value, so a caller can copy it and feed it something hypothetical.
- **`Inference.compute(view:observer:)`** is the convenience that replays the entire log from
  scratch. It is called for every bot decision.
- **`FaithfulBrain`** computes its belief, generates scored `Proposal`s for the current
  `TablePhase`, and says the best. Its vote is a softmax over suspicion plus herd.
- **`TraitorBrain`** runs a *faithful mask*: the belief an honest player in its seat would hold.
  It says what the mask would say, and strays only where the `TeamPlan` needs it to, at a cost
  that falls with the `deceit` trait. Inventing a sighting is the one place a bot lies about
  what it saw.
- **`TeamPlanner`** models the table (`Listeners`), simulates the vote, picks a scapegoat, and
  gives each living traitor a `Stance` (`bus`, `redirect`, `distance`).
- **`Listeners` / `VoteSim`** are how a bot asks "how guilty do I look to each of them" and
  "what happens if this is said next". They are used by defences, by the team plan, and by the
  traitor's vote and murder.

The decision functions are free-standing statics with wide parameter lists
(`view, me, team, mind: inout, p, plan, known, phase, …`). `Game` is the only caller that knows
how to fill them in.

### Dialogue

| File | Holds |
|---|---|
| [Dialogue.swift](../test/Engine/Dialogue/Dialogue.swift) | `Dialogue.line` (statement kind + chip + voice → a spoken line, drawing on the game's RNG), `label` for chips and defence options as the human's buttons show them, `noticed` for what the human saw |
| [Host.swift](../test/Engine/Dialogue/Host.swift) | The host's fixed lines. None may draw randomness. |
| [Flavour.swift](../test/Engine/Dialogue/Flavour.swift) | Colour lines that are not logged. The signatures take no role, so they cannot leak one. |

### Missions

| File | Holds |
|---|---|
| [Missions.swift](../test/Engine/Missions/Missions.swift) | `MissionResult` (what a played mission hands back), `MissionRun` (one day's mission: plan, resolve, observe, report) |
| [MissionLedger.swift](../test/Engine/Missions/MissionLedger.swift) | `EventCode`, `MissionEvent`, `Zone`, `MissionLedger` (5 Hz position and sight tracks plus events) |
| [SightingDeriver.swift](../test/Engine/Missions/SightingDeriver.swift) | Ledger → `[Sighting]` and `neverAlone` |
| [MissionDeck.swift](../test/Engine/Missions/MissionDeck.swift) | The order of play: the ten games and one course of the gauntlet, shuffled |

See §6.

### Arena

| File | Holds |
|---|---|
| [ArenaTypes.swift](../test/Engine/Arena/ArenaTypes.swift) | `Vec2`, `ArenaSeat`, `ArenaSetup`, `ArenaInput`, `ArenaCue` (things for the screen and speaker to do), `ArenaGrid` (walls, line of sight, pathfinding) |
| [Course.swift](../test/Engine/Arena/Course.swift) | `Tile`, `Trap`, `Blueprint` (a course as ASCII art), `Mechanism`, `Course` (a blueprint laid out, with flow fields to hoard and vault) |
| [Courses.swift](../test/Engine/Arena/Courses.swift) | The five blueprints |
| [Hazards.swift](../test/Engine/Arena/Hazards.swift) | `Hazard`: one trap as a small state machine (`asleep`/`rest`/`warn`/`live`) with `hits`, `grazes`, `trip`, `ahead` |
| [Gauntlet.swift](../test/Engine/Arena/Gauntlet.swift) | `Gauntlet`, the simulation class: state, `step()`, end-of-round flow, sight, ledger writes |
| [GauntletBody.swift](../test/Engine/Arena/GauntletBody.swift) | `Runner`, `Bag`, and the extension that moves runners, resolves collisions, traps, gold |
| [GauntletBots.swift](../test/Engine/Arena/GauntletBots.swift) | `Bot`, `Errand`, and the extension that plays a seat: hauling, steering round traps, honest odd habits, a bot traitor's use of the hand |
| [Sabotage.swift](../test/Engine/Arena/Sabotage.swift) | The extension for the shadow's hand, blame accounting (`loss`, `sunkBy`), and the castle's own random misfires |
| [GauntletTuning.swift](../test/Engine/Arena/GauntletTuning.swift) | `Feel`: every constant of the mini-game, as `static let` |
| [ArenaRunner.swift](../test/Engine/Arena/ArenaRunner.swift) | `ArenaRunner`: countdown, fixed-step accumulator, buffered Dash press, `result()`. The lower two-thirds of the file is measurement and printing for the sim. |

`Gauntlet` is one class spread over four files. All of its state is `var` and internal, so the
SpriteKit layer reads it directly each frame.

**The other ten games** sit beside it:

| File | Holds |
|---|---|
| [ArenaGame.swift](../test/Engine/Arena/ArenaGame.swift) | `ArenaGame`, the protocol the runner and the screen hold a game by (step, press, shoot, clock, team total, goal, ledger, cues, and the private per-seat `tally`/`loss`/`acts`). `Gauntlet` conforms by extension. `ArenaGames.make` picks the class for a `MissionKind`. |
| [ArenaCore.swift](../test/Engine/Arena/ArenaCore.swift) | `ArenaCore`, the base class of the ten: actors, hold-to-use `Spot`s, `Prop`s for the stage, bot pacing, honest habits, and the shadow's hand as `Works` |
| [Games/](../test/Engine/Arena/Games) | One subclass per game: Bog, Lantern, Sheep, Ship, Céilí, Market, Kite, Maze, Hurley, Banquet |

How an `ArenaCore` game differs from the gauntlet:

- It steps at 30 Hz (`ArenaCore.tick`), not 60. `ArenaRunner` asks the game for `stepSeconds`.
- It always runs the whole clock. Only the gauntlet seals early.
- **Bots play to a share.** `shareOut()` turns `setup.form` into what each bot sets out to bring
  home (`pace` per bot, swung by `swing × form × head`), and the bots pace themselves to it. So
  the company's day is one roll, as the dice path assumes, by construction. `MissionSpec.par` for
  each game is what `ArenaRunner.par` measures, slips included.
- **The hand is the same in every game.** A game lists its `works` (the stack, a pen gate, the
  cart). `sabotage` takes `handCost` off the pile and logs `.sabotage`; `spring` does the visible
  thing and writes `.sprung` for everyone standing by; `slip()` springs something by itself
  `slipCount` times a game, waiting for somebody to be standing there. Céilí, Kite and Hurley
  have no button for it: standing on a cracked board on the beat, leaving a string caught on a
  sea stack, and putting a ball on the bell are the hand there.
- A human's button is `press()` (an edge) plus `ArenaInput.hold` (a level). A press by a traitor
  standing still within reach of a usable works is the hand; otherwise it is the game's own verb.

Note the name clash waiting to happen: the engine's `Feel` enum lives in `GauntletTuning.swift`,
and the UI has a file called `UI/Audio/Feel.swift` that declares `Haptics`.

### Staging

Presentation logic that is pure and so lives in the engine where it can be tested.

| File | Holds |
|---|---|
| [VoteScript.swift](../test/Engine/Staging/VoteScript.swift) | Rebuilds a vote from the feed's beats: slates reordered for suspense, the banishment held back, the running tally |
| [MorningScript.swift](../test/Engine/Staging/MorningScript.swift) | Who walks in to breakfast in what order, whose chair is empty, who reacts |
| [Place.swift](../test/Engine/Staging/Place.swift) | Which room the current moment is in, the scene key, and the title card |
| [Autopilot.swift](../test/Engine/Staging/Autopilot.swift) | Plays the human seat with fixed choices up to a `Stop`, and searches seeds for rare scenes |

`VoteScript` and `MorningScript` both reconstruct structure by pattern-matching `BeatKind`s in
`game.feed`, because the feed is the only channel the rules use to say what just happened.

### Simulator

[Simulator.swift](../test/Engine/Simulator.swift) is one 300-line function: argument parsing,
the game loop, statistics gathering (which re-derives "who named whom first" and similar from
the log a third time), and printing. It is part of the engine library and so is compiled into
the iOS app.

## 5. Who knows what

The design's central promise is that information only moves through defined channels.

```
                      ┌───────────────────────── Game (hidden truth) ─────────────────────────┐
                      │ players[].role   sightings   sunkBy   mission (MissionRun)   teamPlan │
                      └──────┬──────────────────┬──────────────────────────┬──────────────────┘
                             │ view()           │ finishMission            │ team, known()
                             ▼                  ▼                          ▼
   log: [PublicEvent] ─► TableView        BotMind.seen / .exposed     traitors only:
   heat, seats           + LogIndex       (own share only)            team, TeamPlan,
          │                    │                │                     partners' exposed
          │                    └───────┬────────┘
          │                            ▼
          │                  Observer ─► Replay ─► Belief
          │                            │
          ▼                            ▼
   feed: [Beat] ─► UI          FaithfulBrain / TraitorBrain ─► Intent ─► Dialogue.line ─► Statement ─► log
```

- A **faithful bot** gets the `TableView` and its own `BotMind`. That is all.
- A **traitor bot** additionally gets `team`, the shared `TeamPlan`, and `known`: everything the
  team's members know was seen of them (`minds[t].exposed`).
- The **human** gets the feed, including `.secret` beats addressed to them, plus
  `notebook(about:)` and `defenceOptions()`.
- A **sighting** is private until a witness says it at the table, and then it is only their
  word: listeners weigh it in the worlds where the speaker is faithful.
- The **mission report** carries the team total and nothing per player.

The same public log is interpreted in three separate places, each with its own copy of the
bookkeeping (who named whom first, declared votes, ballots, how hard each kind of statement
counts as an attack):

| Where | For what |
|---|---|
| `LogIndex.init` ([TableView.swift:90](../test/Engine/Core/TableView.swift#L90)) | Chips, standing, blame |
| `Replay.feed` / `hear` ([Belief.swift:244](../test/Engine/AI/Belief.swift#L244)) | Inference |
| `TraitorsSim.run` ([Simulator.swift:138](../test/Engine/Simulator.swift#L138)) | Calibration statistics |

A fourth table of per-statement weights lives in `Game.apply` for heat
([GameEngine.swift:509](../test/Engine/Rules/GameEngine.swift#L509)).

## 6. The mission pipeline

```
beginBrief           MissionRun(kind, alive, traitors, runner, traits, rng)
beginMission         run.plan()             coverage, runnerAttempt, form
                          │
        ┌─────────────────┴──────────────────┐
   dice path                             played path
   resolve(human: MissionResult(         ArenaSetup(run:) → ArenaRunner → Gauntlet.step() × N
     effort, sabotage))                  result(): MissionResult(teamTotal, sunkBy, ledger)
   teamTotal from a formula              resolve(human: result)
   observe(): sightings from             SightingDeriver.derive(ledger): sightings from
     SightingModel base rates              what the record shows
        └─────────────────┬──────────────────┘
finishMission        report() → log; sightings → minds[].seen / .exposed; feed
```

There are **two complete models of a mission** that must agree statistically:

- The **dice path** is used by headless games (unless `options.arena`), by `Autopilot`, and by
  the sim's `--seat` mode. `MissionRun.spread`, `handicap` and `sabotageCost` are tuned so its
  win rates match the gauntlet's.
- The **played path** is what the app does. `Tuning.sightLift` is measured from it.

`ArenaRunner.report` and the test `theDiceGiveTheCompanyTheOddsTheGauntletDoes` exist to keep
the two in line. Any change to gauntlet balance has to be followed by re-measuring the dice
constants and `sightLift`.

Inside the gauntlet, `Gauntlet.step()` runs at 60 Hz in a fixed order: act change → hazards →
castle misfires → crumbling floor → inputs (`think` for bots, stick for the human) → `move` →
`separate` → `settle` → bags → ledger sample every 12th step (5 Hz) → end-of-round `flow`.
`ArenaRunner.advance(dt, input:)` turns frame time into whole steps and holds a Dash press until
a step takes it.

A mechanism going off writes a `.sprung` event for everyone standing by it, whoever or whatever
worked it; the castle works mechanisms at random too, waiting for somebody to be standing there.
That is what keeps "was at the lever when it went" from being proof.

## 7. Randomness and determinism

Every random choice flows from `Game.seed` through `SeededRNG`. The streams:

| Stream | Used for |
|---|---|
| `game.rng` | Role deal, deck, dialogue wording, vote reveal order, tie-breaks |
| `minds[i].rng` (forked at setup) | That bot's choices: softmax picks, urgency jitter, whether to lie |
| `mission.rng` (forked in `beginBrief`) | Run order, `layoutSeed`, runner's nerve, the bots' form |
| `SeededRNG.derived(layoutSeed, n)` | Coverage (1), observation or ledger noticing (2), castle misfires (9) |
| `SeededRNG.derived(seed, day, …)` | Team plan vote simulations, `MorningScript` ordering |
| `SeededRNG.derived(mind.rng.state, …)` | A traitor's look-ahead when voting, without moving its own stream |
| `Gauntlet.rng` (from `setup.seed`) | Bag scatter, misfire targets; each `Bot` gets its own |

**The order of draws is an unwritten contract.** Moving a call that draws from `game.rng` or a
mind's stream, or adding one, changes every game from that seed onwards. Nothing checks this
beyond `sameSeedGivesSameGame`, which only compares a seed against itself in the same build.

Global mutable state that also affects outcomes: about 50 `static var` tuning values across
`Tuning`, `MissionRun`, `SightingDeriver`, `Gauntlet`, `Hazard` and `TraitorBrain`, all settable
by name through `Tuning.set` ([Belief.swift:44](../test/Engine/AI/Belief.swift#L44)).

## 8. Invariants the code relies on

Each of these is a property a refactor must keep. Where a test guards it, the test is named.

| Invariant | Guarded by |
|---|---|
| Same seed, same game | `sameSeedGivesSameGame` |
| A game encoded mid-way and decoded continues identically | `saveAndLoadMidGameContinuesIdentically`, `theTeamPlanSurvivesASave`, `theLedgerSurvivesASave` |
| Every game ends with a winner within the step limit | `allBotGamesTerminateWithAWinner`, `humanGamesTerminateInEveryRole` |
| Bots never read hidden roles; a faithful never suspects itself; beliefs sum to one | `faithfulBotsNeverSuspectThemselvesAndBeliefsAreNormalised` |
| Feeding the log in pieces gives the same belief as feeding it whole | `feedingTheLogInPiecesGivesTheSameBelief` |
| Look-ahead never moves a game stream | `lookingAheadNeverMovesTheGame` |
| Sightings stay private until spoken | `whatIsSeenStaysPrivateUntilSomeoneSaysIt` |
| What bots cite from the record is true; only traitors invent sightings | `whatBotsCiteFromTheRecordIsTrue`, `onlyTraitorsEverInventASighting` |
| A traitor is never first to name a partner, and vouches for one at most once a table | `aTraitorIsNeverTheFirstToNameAPartner`, `aTraitorVouchesForAPartnerAtMostOnceATable` |
| The night is the traitors' only after a loss; a win blocks recruitment too | `theNightIsOnlyTheTraitorsAfterALoss`, `groupWinBlocksRecruit`, and neighbours |
| The mission report holds no per-player numbers | `aMissionKeepsNoPerPlayerNumbers` |
| A faithful human cannot sink the day | `aFaithfulHumanCannotSinkTheDay` |
| Dice and gauntlet give the company the same odds | `theDiceGiveTheCompanyTheOddsTheGauntletDoes` |
| The gauntlet is deterministic; nobody ends in a wall | `everyCoursePlaysItselfOutTheSameWayTwice`, `nobodyEndsUpInAWallOrInsideAnyoneElse` |
| Every trap warns before it strikes; a dash clears two tiles and never three | `everyTrapWarnsBeforeItStrikes`, `aDashClearsTwoTilesAndNeverThree` |
| A press is never lost between frames | `aPressIsNeverLostBetweenFrames` |
| Standing by a mechanism reads the same whoever worked it | `standingByAMechanismReadsTheSameWhoeverWorkedIt` |
| The host's lines draw no randomness; colour names nobody still playing | `stagingColourIsTheSameEveryTimeAndNamesNobodyStillPlaying` |
| Bots lock votes before the human chooses | not tested |
| RNG draw order is stable across builds | not tested |

## 9. Tests

All 53 tests are in
[Tests/EngineTests/EngineTests.swift](../Tests/EngineTests/EngineTests.swift), using Swift
Testing and `@testable import TraitorsEngine`. By section:

| Section | Lines | Covers |
|---|---|---|
| Whole games | 41–335 | Termination, determinism, save/load, role preference, night and recruitment rules, mission outcomes |
| Beliefs | 337–383 | Team sizes, incremental feeding, reasons |
| Sightings and testimony | 384–528 | Privacy, calibration, testimony weighting, liars |
| Planning | 529–613 | Look-ahead purity, team plan, vouching, naming partners |
| The table | 614–721 | Chips hold, invented claims, human defence and notebook |
| The gauntlet | 722–1053 | Course validity, ledger, deriver, determinism, physics, traps, input, sabotage |
| Staging | 1054–1147 | `VoteScript`, colour lines |

The tests carry their own stand-in for the human (`autoInput`,
[EngineTests.swift:7](../Tests/EngineTests/EngineTests.swift#L7)), which is the third
implementation of "given a game, what does the human seat do next" alongside `Autopilot.input`
and `TraitorsSim.seatInput`.

Most tests are properties checked over a range of seeds by playing whole games and inspecting
`Game`'s fields. That makes them good at catching rule breaks and slow to localise them, and it
ties them to `Game`'s stored-property layout.

There are no UI tests and no tests of `GameStore`.

## 10. Tools

`swift run traitors-sim` ([Simulator.swift](../test/Engine/Simulator.swift)):

| Flag | Does |
|---|---|
| `--games N`, `--seed S` | Sample size and base seed |
| *(none)* | Smart vs smart, then random faithful, then random traitors |
| `--seat` | A scripted human in seat 0 under six lazy strategies |
| `--transcript` | One game's feed, printed |
| `--arena` | Games with every mission played out, then the course report |
| `--cores` | The course report only |
| `--trace course` | One gauntlet run in detail |
| `--form x` | Bags a head on each course at a given form |
| `--scenes` | Launch arguments that open the app on each rare scene |
| `--tune name=value` | Set a tuning value by name (repeatable) |

`Autopilot.scenes` prints app launch arguments of the form
`-autoplay 1 -seed N -role R -stopPhase P -stopDay D [-stopVoteRound 2] [-stopNight K]`.

## 11. App and UI

36 files under `test/App`, `test/UI` and `TraitorsApp.swift`. SwiftUI for everything except the
gauntlet, which is SpriteKit under a SwiftUI HUD.

### Ownership and the one way the game moves

```
TraitorsApp ── @State GameStore ──.environment──► every view
                   │  game: Game?          the single source of truth
                   │  send(_ input)        copy → advance → reassign → stats → save
                   │  told / concealed / shown / roleShown / spectating
                   ▼
RootView ── Title │ Tutorial │ GameView          two local bools; not persisted
                                 │  owns Stage (flood, dim), the curtain, the ambient bed
                                 ▼
                    switch game.phase ──► one screen per phase
```

[`GameStore.send`](../test/App/GameStore.swift#L51) is the only path that advances the game in a
release build: copy the struct, `advance`, reassign, record stats at game over, and write the
whole `Game` to `save-v8.json` synchronously. Because `Game` is replaced wholesale, every view
that reads `store.game` is invalidated on every input.

In DEBUG builds, launch arguments run `Autopilot.play` and assign the result straight to
`store.game`.

### Phase → screen

[`GameView.content`](../test/UI/Screens/GameView.swift#L63) is the router:

| Phase | Screen |
|---|---|
| `roleReveal` | `RoleCeremony` |
| `breakfast` | `BreakfastCeremony` (via `MorningScript`) |
| `missionBrief` | `MissionBriefView` |
| `mission`, `missionResult` | `MissionView` (one identity across both) |
| `roundTable`, `voting` round 1, `finaleChoice` | `TableScreen` |
| `voting` round 2, `voteReveal` | `VoteCeremony` (one identity across both; via `VoteScript`) |
| `night` | `NightView` |
| `finaleReveal` | `SceneView` (generic feed) |
| `gameOver` | `GameOverView`, behind `EndingCeremony` the first time |

Around the router: a header, a title-card curtain keyed on `Place.sceneKey`, and an ambient
sound bed chosen from `Place`.

### Ceremonies

Each ceremony derives a `[Moment]` script from the `Game` in `body`, keeps `@State shown`, and
uses `.stepClock` ([Stage.swift:39](../test/UI/Stage/Stage.swift#L39)) to reveal one moment at a
time with a `Cue` (sound + haptic). The script builders (`RoleCeremony.moments`,
`BreakfastCeremony.moments`, `VoteCeremony.moments`) are pure static functions that live inside
the view types.

**Concealment.** The engine has already banished or murdered a player by the time the ceremony
that announces it starts playing. `GameStore.concealed`
([GameStore.swift:83](../test/App/GameStore.swift#L83)) hides that by filtering the feed for
`.banish`/`.murder` beats until the ceremony calls `store.tell()`. `Avatar` asks the store what
it may show. `roleShown` decides which roles the human is entitled to see. These
information-hiding rules live in the store, next to persistence.

Screen state is reset by view identity. Five separate string keys take part: `sceneID` in the
store, the curtain key, the per-screen `.id(...)`, the `StepClock` task id, and `FeedList`'s id
(which is built from the first beat's *text*). `voteID` depends on `tally.roundTables`, a
simulator counter.

### What the UI takes from the engine

The UI reaches the engine at three depths.

1. **Through `GameStore.send`**, constructing all nine `HumanInput` cases from 20-odd call
   sites. Each view decides for itself which input is valid from `phase`, `tableStep`,
   `voteRound`, `nightChoice` and `choices`.
2. **By reading `Game` fields directly**: `phase`, `day`, `players`, `human`, `humanAlive`,
   `humanIsTraitor`, `alive`, `aliveTraitors`, `team`, `feed`, `winner`, `finale`, `pot`,
   `mission`, `report`, `tableStep`, `voteRound`, `choices`, `nightChoice`, `recruiter`,
   `partnerAdvice`, `history`, `tally.roundTables`, `seed`; and calling `view()`,
   `notebook(about:suspicious:)`, `defenceOptions()`, `revealedRole(_:)`.
3. **By holding the live `Gauntlet`** during a mission and reading about twenty of its stored
   properties every frame (below).

It never touches `log`, `minds`, `rng`, `heat`, `sightings`, `teamPlan`, `lockedVotes`,
`candidates`, `options` or `missionDeck`.

Places where the UI re-derives something the engine already knows:

| What | Where | Engine's own version |
|---|---|---|
| What the next phase will be, for button labels | [GameView.swift:197](../test/UI/Screens/GameView.swift#L197), [VoteCeremony.swift:145](../test/UI/Ceremonies/VoteCeremony.swift#L145), [BreakfastCeremony.swift:44](../test/UI/Ceremonies/BreakfastCeremony.swift#L44) | Private transition logic in `Game` |
| Running vote tally; where the revote starts | [VoteCeremony.swift:153](../test/UI/Ceremonies/VoteCeremony.swift#L153), [:68](../test/UI/Ceremonies/VoteCeremony.swift#L68) | `VoteScript.tally(shown:)`, `revoteStart` (used only by tests) |
| Who has just left | `GameStore.concealed` | `VoteScript.banished`, `MorningScript.victim` |
| Whether the hand can act here | [ArenaScene.swift:388](../test/UI/Missions/Arena/ArenaScene.swift#L388) | `Gauntlet.canSabotage` (stricter) |
| Whether the human has the hand | [MissionView.swift:119](../test/UI/Missions/MissionView.swift#L119) | `ArenaSetup.saboteurs` |
| Clock fraction and countdown digits | [ArenaScene.swift:416](../test/UI/Missions/Arena/ArenaScene.swift#L416), [:174](../test/UI/Missions/Arena/ArenaScene.swift#L174) | `Gauntlet.progress`, `ArenaRunner.countdown` |
| Cast order for the arena | [MissionView.swift:106](../test/UI/Missions/MissionView.swift#L106) | `ArenaSetup(run:)` sorts the same way independently |

Expensive engine calls made from view bodies: `defenceOptions()` twice per render of the
composer (each runs full inference), `view()` rebuilt per row in three screens, `notebook` twice
per player in the cast sheet.

Two behaviours to be aware of:

- The spectator's "Skip to the end" loops `store.send(.next)` up to 400 times
  ([GameView.swift:231](../test/UI/Screens/GameView.swift#L231)), which is up to 400 full saves.
- A spectator who skips a mission sends `.next`, so the engine settles it by dice and throws
  away the gauntlet run on screen; one who watches to the end sends the played result. The same
  mission can resolve two different ways.

### The arena on screen

`ArenaScene` hosts any `ArenaGame`. It asks `ArenaStages.make` for an `ArenaStage`
([ArenaStage.swift](../test/UI/Missions/Arena/ArenaStage.swift)): `CourseStage` for the gauntlet,
or a `CoreStage` subclass for the others. `CoreStage` draws the players and the game's `Prop`s
through a `project` function; `TopDownStage` fits a whole arena flat on one screen (Lantern,
Sheep, Céilí, Market, Maze, Banquet) and the side-on stages (Bog, Ship, Kite, Hurley) lay a
landscape behind it. The scene picks the controls from the kind: the stick, one `ActionButton`
labelled by `MissionKind.button`, or for Hurley a pulled-back strike. The HUD's row of tokens
is ordered by `tally`, so it shuffles as players overtake each other. What follows describes the
gauntlet's path through the same scene.

```
MissionView ── builds ArenaConfig(ArenaSetup(run:), cast colours, handVisible, spectating)
     │
     ▼
ArenaScene (SKScene) ── owns ArenaRunner ── owns Gauntlet  (a class: one shared mutable instance)
     │   update(_:)  each frame:
     │     pause / resume countdown / hit-stop      (UI-side)
     │     runner.advance(dt, input)                 → whole 60 Hz steps
     │     CourseStage.sync(alpha)                   reads Gauntlet state, interpolates
     │     drain core.cues → FX, sound, haptics      (and clears the engine's array)
     │     feed ArenaHUDModel                        → SwiftUI HUD
     ▼
onFinish(runner.result()) ──► store.send(.mission(result))
```

What `ArenaScene` and `CourseStage` read off the `Gauntlet` each frame: `runners` (with 16
fields of `Runner`), `hazards`, `bags`, `floor`, `dark`, `cues`, `timeLeft`, `totalTicks`,
`teamTotal`, `goal`, `won`, `sealing`, `human`, and the fields marked private in their own doc
comments: `acts`, `loss`, `sunkBy`. Plus `course` for static geometry, and the queries
`mechanism(near:)`, `vision(_:_:)`, `index(of:)`.

`CourseStage` assumes without checking that its node arrays line up index-for-index with
`core.hazards`, `core.runners`, `core.bags` and `core.dark`. The scene's logical width of 390
points is the same number as `Course.cols × Course.cell` by coincidence of two separate
constants. Fog-of-war (which runners the human can see) is decided in the renderer.

### Sound, haptics and settings

- `Soundscape.shared` owns the `AVAudioEngine`: two cross-faded bed nodes and eight sting nodes.
  `Synth` renders samples on detached tasks.
- There are two parallel stacks. Ceremonies use `Cue` → `Soundscape` + `Haptics`
  (`UI/Audio/Feel.swift`). The arena and buttons use `Feedback` → `ArenaSounds` (its own synth
  and cache) + cached haptic generators. `ArenaSynth.render` runs synchronously on the main
  thread the first time each sound is needed, mid-game.
- Everything is reached through statics (`Soundscape.shared`, `Feedback`, `Haptics`, `Senses`,
  `Cue.play()`), so there is no seam for a test to observe or silence them.
- `Settings` is a two-field value on the store; its `didSet` copies it into `Feedback.settings`.

### Persistence

| What | Where |
|---|---|
| The whole `Game`, `Stats`, `Settings` as JSON in Application Support | [GameStore.swift:133](../test/App/GameStore.swift#L133); synchronous; errors swallowed with `try?` |
| Save versioning | The file name. `save-v8.json` today; v1–v7 are deleted by name on every launch |
| Player name, ending-seen seed, per-course personal best | `@AppStorage` / `UserDefaults`, from three different views |
| Debug launch arguments | `UserDefaults`, read in `GameStore`, `TraitorsApp`, `Stage`, `MissionView` |

Not saved: navigation state, ceremony progress, a mission in progress (it restarts from the
countdown on the same `layoutSeed`).

`GameStore.init` reads and deletes files, reads `UserDefaults`, and may run autoplay, so it
cannot be constructed in a test without side effects.

### Dead code found in passing

Left over from the removed mini-games, verified unused by search: `Palette.moss`; a dozen
`Tokens.Hue` colours; `Toon.grass/green/panel/cloak`; `Props.star/flag/bell/strawKnight/cart`;
`FX.shake`; `Courtier.daze`; `Sprites.haze`; `ArenaHUDModel.seat(_:)`; `SeededRNG.cg`. `SceneView`
is routed only for `finaleReveal`, so its other label branches cannot run. Several files are
named for something they no longer hold (`MissionLeaderboard.swift` → `MissionResultCard`,
`Audio/Feel.swift` → `Haptics`, `NightCeremony.swift` → `NightView`; `SettingsToggles` lives in
`ArenaPauseView.swift`, `Letter` in `BreakfastCeremony.swift`).
