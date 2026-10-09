# Architecture: how the code works today

This describes the code as it stands on 2026-10-06, after the refactor laid out in
[REFACTORING_PLAN.md](REFACTORING_PLAN.md). It is a map, not a wish list. What the plan set out to
do and did not is listed at the top of that file.

- [1. What this is](#1-what-this-is)
- [2. Layout and build targets](#2-layout-and-build-targets)
- [3. Game: prompt, answer, scene](#3-game-prompt-answer-scene)
- [4. The modules](#4-the-modules)
- [5. Who knows what](#5-who-knows-what)
- [6. The mission pipeline](#6-the-mission-pipeline)
- [7. Randomness, determinism and tuning](#7-randomness-determinism-and-tuning)
- [8. Invariants and the tests that guard them](#8-invariants-and-the-tests-that-guard-them)
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
  five courses) and ten games of their own. The same simulation runs on screen and headless.

## 2. Layout and build targets

```
Package.swift              Five library targets, the sim CLI, four test targets
Sources/
  TraitorsCore/            The vocabulary. Imports Foundation only.
  TraitorsMinds/           How a seat decides. Depends on Core.
  TraitorsGauntlet/        The eleven mini-games. Depends on Core.
  TraitorsEngine/          The rules and the telling. Depends on the three above.
    Rules/  Missions/  Dialogue/  Staging/
  TraitorsLab/             Simulator, measuring, scene finder. Not shipped.
Tools/Sim/main.swift       Calls TraitorsSim.run
Tests/                     CoreTests, MindsTests, GauntletTests, EngineTests (+ Golden/)
test/                      The app's sources (the Xcode target is also called "test")
  App/                     GameSession, SaveStore, Settings
  UI/                      SwiftUI + SpriteKit
AppTests/                  The app's unit tests (Xcode target AppTests)
test.xcodeproj             The iOS app. Links TraitorsEngine and TraitorsGauntlet from the package.
docs/baseline/             Simulator output recorded before the refactor
```

```
                 ┌──────────────────────────── App ────────────────────────────┐
                 │  GameSession   SaveStore   Effects   Screens / Ceremonies   │
                 └───────┬───────────────────────────────────────┬─────────────┘
                         │ Prompt, Answer, GameScene             │ ArenaSession
                         ▼                                       ▼
   Lab ───────────►  ┌──────────┐   MissionRun / MissionResult ┌──────────┐
   (sim, measuring,  │  Engine  │ ───────────────────────────► │ Gauntlet │
    scene finder)    └─┬──────┬─┘                              └────┬─────┘
                       │      │ Mind                                │
                       │      ▼                                     │
                       │  ┌───────┐                                │
                       │  │ Minds │                                │
                       │  └───┬───┘                                │
                       ▼      ▼                                     ▼
                 ┌──────────────────────────── Core ────────────────────────────┐
                 │ vocabulary · PublicRecord · SeededRNG · MissionLedger · Tuning │
                 └──────────────────────────────────────────────────────────────┘
```

**Access is the boundary.** `public` is what the app uses; `package` is what the targets use of
each other and what the lab uses; everything else is `internal` to its target. The app imports
only `TraitorsEngine` (41 files) and `TraitorsGauntlet` (18 files). `TraitorsEngine` re-exports
Core and Minds ([Exports.swift](../Sources/TraitorsEngine/Exports.swift)), so the app sees `Player`
or `DefenceOption` without naming those modules.

| Target | Lines | `public` declarations | Of which the app can write |
|---|---|---|---|
| Core | 1,425 | 71 | none |
| Minds | 1,458 | 8 | none |
| Gauntlet | 5,365 | 275 | `ArenaInput.move`, `.hold` |
| Engine | 2,331 | 136 | `Autopilot.Stop`'s four fields |

Every other public stored property is `public package(set)`: the app reads it and cannot change
it. The Gauntlet's surface is wide because each of the eleven stages draws straight from its
game's state (§11); it is read-only, and it is the surface worth narrowing next.

All targets set default actor isolation to `MainActor`, Swift language mode 5 and
`MemberImportVisibility` ([Package.swift](../Package.swift), project build settings).

## 3. Game: prompt, answer, scene

The whole game is one value type, [`Game`](../Sources/TraitorsEngine/Rules/Game.swift), with a
three-part interface:

```swift
public var prompt: Prompt { get }                       // what the game is waiting for
public mutating func advance(_ answer: Answer) throws   // an answer to it
public func scene(told: Bool) -> GameScene              // what the human may see
```

[`Prompt`](../Sources/TraitorsEngine/Rules/Prompt.swift) carries everything needed to answer it:

| Prompt | Answers it takes |
|---|---|
| `.proceed(then: Step)` | `.proceed`. `Step` says where the tap leads, for the button's label. |
| `.playMission(MissionRun)` | `.mission(MissionResult)`; `.proceed` too when the human is out and only watching |
| `.speak(turn:targets:defences:)` | `.say(kind, target:chip:)` about one of `targets`, `.rebut(i)` for one of `defences`, or `.say(.pass, …)` |
| `.vote(round:candidates:)` | `.vote(p)` for a candidate |
| `.murder(candidates:advice:)`, `.recruit(candidates:)` | `.murder(p)`, `.recruit(p)` |
| `.answerOffer(from:)` | `.offer(accept:)` |
| `.endOrBanish` | `.finale(end:)` |
| `.over(winner:)` | nothing |

An answer that does not fit **throws a `GameError` and changes nothing**. `advance` checks first
(`check`, which only reads) and then runs the rules forward to the next point where the human has
to decide something or tap to continue.

Anything that plays a seat is a [`SeatPolicy`](../Sources/TraitorsEngine/Rules/Prompt.swift):
`answer(_ prompt:, in game:) -> Answer`. There are three: `Autopilot.Seat` (the app's debug
autoplay and the scene finder), the lab's `LazySeat`, and the tests' `TestSeat`.
`Game.play(&seat, until:)` drives one.

**What just happened is data.** Where the rules resolve something they set
[`outcome`](../Sources/TraitorsEngine/Rules/Outcome.swift): `.mission(report, noticed:)`,
`.vote(VoteOutcome)` (ballots by round, who tied, whether the lot decided, who went, role,
winner), `.morning(MorningOutcome)`. It is cleared when the game moves on. The feed (`[Beat]`)
still says the same in words, and nothing reads structure back out of it.

**`GameScene` holds the concealment rules.** The rules run ahead of the telling: by the time a
banishment is being announced the player is already out. `scene(told: false)` shows them seated
and gives nothing away; the ceremony calls `GameSession.tell()` when it has said who went. Which
roles the human may see (their own, fellow traitors', revealed ones, everything once they are out
or the game is over) is decided here and tested in
[SceneTests](../Tests/EngineTests/SceneTests.swift).

The phases underneath are unchanged: `roleReveal`, `breakfast`, `missionBrief`, `mission`,
`missionResult`, `roundTable`, `voting`, `voteReveal`, `night`, `finaleChoice`, `finaleReveal`,
`gameOver`. `phase` is public and read-only; the app routes screens on it. Turn bookkeeping
(`tableStep`, `voteRound`, `candidates`, `lockedVotes`, `lockedFinale`, `nightChoice`,
`recruiter`, `partnerAdvice`) is `private`.

Rules that are easy to miss:

- **The night belongs to the traitors only if the company fell short** (`traitorsMayAct`).
- **Recruitment** replaces the murder when one traitor is left, it has not been used, and five or
  more will be alive (`recruitNight(left:)`, written once). A human who refuses is murdered.
- **The finale** begins on the morning four or fewer are alive. No missions, no nights, banished
  players leave without revealing, and the game ends on a unanimous vote to end or when two are
  left.
- **Bots lock their votes before the human chooses** (`lockVotes`).
- **The win check** is `verdict`, used after a banishment and after the night.

`Game` is `Codable`; the app saves it inside a versioned envelope (§11).

## 4. The modules

### Core

| File | Holds |
|---|---|
| [Models.swift](../Sources/TraitorsCore/Models.swift) | `PlayerID`, `Role`, `RolePreference`, `Voice`, `Personality`, `Player`, `Cast.bots`, `SeatMask` |
| [Events.swift](../Sources/TraitorsCore/Events.swift) | `MissionSpec`, `MissionKind`, `MissionReport`, `Chip`, `Statement`/`StatementKind`, `Defence`, `PublicEvent` |
| [StatementEffect.swift](../Sources/TraitorsCore/StatementEffect.swift) | **What each kind of statement means, once**: names the target, attack and push weights, declares a vote, flags, vouches, heat, grudge, and how inference reads it |
| [TableView.swift](../Sources/TraitorsCore/TableView.swift) | `PublicRecord` (events plus an index kept up to date as they arrive), `LogIndex`, `TableView` (record, seats, heat, belief tuning), `Chips` |
| [Sightings.swift](../Sources/TraitorsCore/Sightings.swift) | `SightingKind`, `Sighting`, `SightingModel` (the dice path's base rates) |
| [MissionLedger.swift](../Sources/TraitorsCore/MissionLedger.swift), [MissionResult.swift](../Sources/TraitorsCore/MissionResult.swift) | The 5 Hz record of a played mission, and what a mission hands back |
| [Tuning.swift](../Sources/TraitorsCore/Tuning.swift) | `Tuning` and its four groups (§7) |
| [Random.swift](../Sources/TraitorsCore/Random.swift), [Rules.swift](../Sources/TraitorsCore/Rules.swift) | `SeededRNG`, `clamp`; `Rules.seats = 8`, `Rules.traitors = 2` |

`PublicRecord.append` is the only way the log changes. `LogIndex`, `Replay.hear`, `Game.apply`
and the lab's statistics all read `StatementKind.effect` and carry no table of their own. The
record also keeps one mark per event (a hash chain) so that whoever has worked through part of a
record can tell later that this one carries on from the same beginning.

### Minds

The interface is [`Mind`](../Sources/TraitorsMinds/Mind.swift): `speak`, `vote`, `endTheGame`,
`useTheHand`, `murder`, `recruit`, `plan`, and three read-only questions (`knowsBetter`,
`suspect`, `opinion`). `Minds.make(kind, notes:traits:conspiracy:)` builds one of three:

| Mind | Knows | Does |
|---|---|---|
| `FaithfulMind` | The table and its own notes | Infers, says the best-scoring thing, votes by softmax over suspicion plus herd |
| `TraitorMind` | Also the `Conspiracy`: team, plan, what was seen of any of them | Runs a faithful mask and strays only where the plan needs it; plans, murders, recruits |
| `RandomMind` | Its seat (and team, if on one) | Says nothing and picks at random. The sim's control. |

`Game` asks `mind(for: seat)` one question at a time and keeps the notes it hands back.
`GameOptions.randomFaithful` / `randomTraitors` are read in one function, `mindKind(of:)`.

Internal to the module: `Replay` (exact inference over every team, fed one event at a time),
`Belief`, `Inference`, `Listeners` and `VoteSim` (a model of every other mind and of the coming
vote), `FaithfulBrain`, `TraitorBrain`. `TeamPlanner.whisper` and two numbers from `Defences` are
`package`.

**Minds carry their inference over.** [`Recall`](../Sources/TraitorsMinds/Belief.swift) keeps a
`Replay` per reading (the mind's own, an onlooker's, its model of each listener) inside `BotMind`,
and feeds it only the events that are new. It reuses a replay only when the record's mark says
the history is the same, the sightings it has used are unchanged, and the mind's hunches either
have not moved or can be worked in again exactly; otherwise it starts over. It is never saved
and never changes an answer: `RecallTests` checks it bit for bit against a from-scratch replay
at every step of whole games.

### Gauntlet

Everything is played through
[`ArenaSession`](../Sources/TraitorsGauntlet/ArenaSession.swift):

```swift
public init(_ setup: ArenaSetup)
public func advance(_ dt: Double, input: ArenaInput)   // whole steps, a long frame caught up
public func press();  public func shoot(_ v: Vec2)     // kept until a step can take them
public func finish()                                   // plays out the rest headless
public var stage, countdownNumber, clock, teamTotal, goal, won, tally, sealing
public var panel: PlayerPanel?        // the button, edge of sight, what is in hand, this frame
public func takeCues() -> [ArenaCue]  // what to show and sound since last asked
public var playerResult, ownHand      // how it went for the player; what their hand did
public func result() -> MissionResult
```

`ArenaGame` is the read-only face a stage is handed; `ArenaPlay` (package) is what the session
drives. `Gauntlet` and `ArenaCore` conform to both.

| File | Holds |
|---|---|
| [ArenaTypes.swift](../Sources/TraitorsGauntlet/ArenaTypes.swift) | `Vec2`, `ArenaSeat`, `ArenaSetup` (with its `Tuning`), `ArenaInput`, `ArenaCue`, `ArenaGrid` |
| [ArenaGame.swift](../Sources/TraitorsGauntlet/ArenaGame.swift) | The two protocols, `PlayerPanel`, `PlayerResult`, `HandSummary`, `ArenaGames.make` |
| [Course.swift](../Sources/TraitorsGauntlet/Course.swift), [Courses.swift](../Sources/TraitorsGauntlet/Courses.swift), [Hazards.swift](../Sources/TraitorsGauntlet/Hazards.swift) | The gauntlet's five courses and their traps |
| [Gauntlet.swift](../Sources/TraitorsGauntlet/Gauntlet.swift), `GauntletBody`, `GauntletBots`, `Sabotage`, `GauntletTuning` (`Feel`) | The gauntlet: one class over four files, 60 Hz |
| [ArenaCore.swift](../Sources/TraitorsGauntlet/ArenaCore.swift), [Games/](../Sources/TraitorsGauntlet/Games) | The base class of the other ten and one subclass each, 30 Hz |

How an `ArenaCore` game differs from the gauntlet: it always runs the whole clock; **bots play to
a share** (`shareOut()` turns `setup.form` into what each sets out to bring home), so the
company's day is one roll as the dice path assumes; and **the hand is the same in every game**
(a game lists its `works`; `sabotage` takes `handCost` off the pile; `spring` writes `.sprung`
for everyone standing by; the works also go by themselves `slipCount` times a game).

### Engine

| Area | Holds |
|---|---|
| [Rules/](../Sources/TraitorsEngine/Rules) | `Game`, `Prompt`/`Answer`/`SeatPolicy`, `Outcome`, `GameScene`, `GameState` (`Phase`, `Beat`, `GameOptions`, `Tally`) |
| [Missions/](../Sources/TraitorsEngine/Missions) | `MissionRun` (plan, resolve, observe, report), `SightingDeriver` (ledger → sightings), `MissionDeck`, and [ArenaBridge.swift](../Sources/TraitorsEngine/Missions/ArenaBridge.swift): `ArenaSetup(run:)`, the only place the rules and the mini-games meet |
| [Dialogue/](../Sources/TraitorsEngine/Dialogue) | `Dialogue.line` (draws on the game's RNG), `Host` (fixed lines, no randomness), `Flavour` (colour, takes no role) |
| [Staging/](../Sources/TraitorsEngine/Staging) | `VoteScript` (built from a `VoteOutcome`), `MorningScript`, `Place`, `Autopilot` |

### Lab

[Simulator.swift](../Sources/TraitorsLab/Simulator.swift) (`TraitorsSim.run`, `LazySeat`),
[ArenaMeasure.swift](../Sources/TraitorsLab/ArenaMeasure.swift) (`ArenaSession.sample`,
`winRate`, `par`, `trace`, `report`), [Scenes.swift](../Sources/TraitorsLab/Scenes.swift)
(`Autopilot.scenes`). The command line and the tests use it; the app does not link it.

## 5. Who knows what

```
                  ┌───────────────────────── Game (hidden truth) ─────────────────────────┐
                  │ players[].role   sightings   sunkBy   mission (MissionRun)   teamPlan │
                  └──────┬──────────────────┬──────────────────────────┬──────────────────┘
                         │ view()           │ finishMission            │ mind(for:) → Conspiracy
                         ▼                  ▼                          ▼
   PublicRecord ─► TableView          BotMind.seen / .exposed     traitors only:
   heat, seats                        (own share only)            team, plan, what was seen of them
          │                │                │
          │                └───────┬────────┘
          │                        ▼
          │                  Mind ─► Intent ─► Dialogue.line ─► Statement ─► PublicRecord
          ▼
   feed, outcome ─► GameScene ─► the human
```

- A **faithful mind** gets the `TableView` and its own notes. That is all.
- A **traitor mind** is built with the `Conspiracy`. Nobody else is.
- The **human** gets the `GameScene`, the `Prompt` (which carries their defence options), and
  `notebook(about:)`.
- A **sighting** is private until a witness says it at the table, and then it is only their word.
- The **mission report** carries the team total and nothing per player.

## 6. The mission pipeline

```
beginBrief           MissionRun(kind, alive, traitors, runner, traits, rng, tuning)
beginMission         run.plan()             coverage, runnerAttempt, form
                          │
        ┌─────────────────┴──────────────────┐
   dice path                             played path
   resolve(human: MissionResult(         ArenaSetup(run:) → ArenaSession → step × N
     effort, sabotage))                  result(): MissionResult(teamTotal, sunkBy, ledger)
   teamTotal from a formula              resolve(human: result)
   observe(): sightings from             SightingDeriver.derive(ledger): sightings from
     SightingModel base rates              what the record shows
        └─────────────────┬──────────────────┘
finishMission        report() → record; sightings → minds; feed; outcome = .mission
```

There are **two models of a mission** that must agree statistically. The dice path is used by
headless games (unless `options.arena`), `Autopilot` and the sim's `--seat` mode; the played path
is what the app does. Measured headless in a release build, a played round costs about 10 ms and
a whole dice game about 2 ms, so a game with every mission played out is roughly 18 times slower.
That is why the dice path stays. `theDiceGiveTheCompanyTheOddsTheGauntletDoes` keeps the two in
line; any change to a mini-game's balance means re-measuring `MissionTuning` and
`BeliefTuning.sightLift`.

**A mission resolves one way.** A spectator who skips calls `ArenaSession.finish()`, which plays
out the rest of the same round, and hands back that result. (Before, a skip fell back to dice.)

## 7. Randomness, determinism and tuning

Every random choice flows from `Game.seed` through `SeededRNG`:

| Stream | Used for |
|---|---|
| `game.rng` | Role deal, deck, dialogue wording, vote reveal order, tie-breaks, a random team's lots for the hand |
| `minds[i].rng` (forked at setup) | That seat's choices |
| `mission.rng` (forked in `beginBrief`) | Run order, `layoutSeed`, the bots' form |
| `SeededRNG.derived(…)` | Coverage, noticing, team-plan vote simulations, breakfast order, a traitor's look-ahead |
| The mini-game's own (from `setup.seed`) | Bag scatter, misfires; each bot gets its own |

**The order of draws is a contract, and it is now checked.** `GoldenTests` compares 370 whole
games and one round of each mini-game against [recordings](../Tests/EngineTests/Golden). The whole
refactor left them byte-identical, along with the simulator's output in all four modes
([docs/baseline](baseline)).

**Tuning is a value.** [`Tuning`](../Sources/TraitorsCore/Tuning.swift) has four groups:
`BeliefTuning` (likelihood ratios, how readily traitors act), `MissionTuning` (spread, handicap,
sabotage cost), `SightingTuning` (how a ledger is read) and `ArenaTuning` (how bots play the
mini-games). It rides on `GameOptions`, `MissionRun`, `ArenaSetup` and `TableView`, goes into the
save, and `set(name, value)` throws on an unknown name. There is no `static var` in `Sources/`.
`Feel` (the feel of the controls) stays as constants.

## 8. Invariants and the tests that guard them

| Invariant | Guarded by |
|---|---|
| Play is unchanged, draw for draw | `GoldenTests` |
| Same seed, same game; a save continues identically | `sameSeedGivesSameGame`, `saveAndLoadMidGameContinuesIdentically`, `theTeamPlanSurvivesASave`, `theLedgerSurvivesASave` |
| Every game ends with a winner | `allBotGamesTerminateWithAWinner`, `humanGamesTerminateInEveryRole` |
| An answer that does not fit is refused and nothing moves | `anAnswerThatDoesNotFitIsRefusedAndNothingMoves`, `refusingTheOfferIsTheEndOfYou` |
| A tap leads where the prompt says | `aTapSaysWhereItLeads` |
| What was resolved is handed over as data, and matches the record | `whatWasResolvedIsHandedOverAsData` |
| Nobody is shown gone, or shown a role, before they may be | `nobodyIsShownGoneBeforeTheSceneHasSaidSo`, `aRoleIsOnlyShownToSomeoneEntitledToIt` |
| The index kept as events arrive is the one built from scratch | `theIndexKeptAsEventsArriveIsTheOneBuiltFromScratch`, `aGamesIndexIsTheOneBuiltFromItsLog` |
| Each kind of statement means one thing | `everyKindOfStatementMeansOneThing` |
| Carried-over inference is exactly the from-scratch answer | `whatAMindCarriesOverIsExactlyWhatItWouldWorkOutAfresh`, `aRecallHandedADifferentHistoryStartsAgain`, `feedingTheLogInPiecesGivesTheSameBelief` |
| Bots never read hidden roles; beliefs are normalised | `faithfulBotsNeverSuspectThemselvesAndBeliefsAreNormalised`, `MindTests` |
| Look-ahead never moves a game stream | `lookingAheadNeverMovesTheGame` |
| Sightings stay private until spoken; only traitors invent one | `whatIsSeenStaysPrivateUntilSomeoneSaysIt`, `onlyTraitorsEverInventASighting`, `whatBotsCiteFromTheRecordIsTrue` |
| A traitor never opens on a partner, and vouches at most once a table | `aTraitorIsNeverTheFirstToNameAPartner`, `aTraitorVouchesForAPartnerAtMostOnceATable` |
| The night is the traitors' only after a loss | `theNightIsOnlyTheTraitorsAfterALoss`, `groupWinBlocksRecruit` |
| The report holds no per-player numbers; a faithful cannot sink the day | `aMissionKeepsNoPerPlayerNumbers`, `aFaithfulHumanCannotSinkTheDay` |
| Dice and mini-games give the company the same odds | `theDiceGiveTheCompanyTheOddsTheGauntletDoes` |
| A round plays the same way twice, at any frame rate, skipped or not | `everyCoursePlaysItselfOutTheSameWayTwice`, `aRoundSkippedPartWayIsStillARoundPlayed` |
| A press is never lost; traps warn; a dash clears two tiles | `aPressIsNeverLostBetweenFrames`, `everyTrapWarnsBeforeItStrikes`, `aDashClearsTwoTilesAndNeverThree` |
| The button shows the hand only where a press would be the hand | `theButtonOnlyShowsTheHandWhereAPressWouldBeTheHand` |
| A game is played by the tuning it was given | `aGameIsPlayedByTheNumbersItWasGiven`, `aTableWeighsEvidenceByItsOwnTuning` |
| Every demonstration still shows what it says: the player scores, or the hand goes off, at any frame rate | `everyDemonstrationShowsWhatItSaysItDoes`, `aDemonstrationPlaysTheSameHoweverTheFramesFall` |
| A session saves once per answer, and once for a skip to the end | `everyAnswerMovesTheGameAndSavesItOnce`, `skippingToTheEndIsOneSaveAndTheGameIsCountedOnce` |
| Bots lock votes before the human chooses | not tested |

## 9. Tests

| Target | Tests | Uses |
|---|---|---|
| `CoreTests` | 6 | Made-up logs. No game is played. |
| `MindsTests` | 11 | Hand-built tables; a mind is asked one question. |
| `GauntletTests` | 18 | Mini-games and the session by themselves. |
| `EngineTests` | 54 | Whole games: rules, prompts, scenes, the golden master. |
| `AppTests` (Xcode) | 12 | `GameSession`, saves, the ceremony scripts, the effects seam. |

```sh
swift test                                             # quick tier, debug: about 20 s
FULL=1 swift test -c release -Xswiftc -enable-testing  # everything: about 25 s
GOLDEN_RECORD=1 FULL=1 swift test -c release -Xswiftc -enable-testing --filter Golden   # re-record, deliberately
xcodebuild test -project test.xcodeproj -scheme test -destination 'platform=iOS Simulator,name=…'
```

Without `FULL` the sweeps and statistical guards are skipped (tags `.sweep`, `.balance`) and the
golden master checks a subset. Loops that wait on a game are capped and say which seed stuck
(`StepCap`).

## 10. Tools

`swift run traitors-sim`:

| Flag | Does |
|---|---|
| `--games N`, `--seed S` | Sample size and base seed |
| *(none)* | Smart vs smart, then random faithful, then random traitors |
| `--seat` | A scripted human in seat 0 under six lazy strategies |
| `--transcript` | One game's feed, printed |
| `--arena` | Games with every mission played out, then the course report |
| `--cores`, `--only a,b` | The course report only; restricted to some games |
| `--trace game`, `--form x` | One round in detail; what a player brings home at a given form |
| `--scenes` | Launch arguments that open the app on each rare scene |
| `--tune name=value` | Builds a `Tuning` for this run (repeatable). Nothing global is touched. |

## 11. App and UI

```
TraitorsApp ── @State GameSession ──.environment──► every view
                   │  game, prompt, scene     prompt and scene worked out once per answer
                   │  send(_ answer)          advance → refresh → stats → save
                   │  skipToEnd()             many answers, one save
                   │  tell()                  the scene has said who is gone
                   │  SaveStore, Effects      handed in; memory and a recorder in tests
                   ▼
RootView ── Title │ Tutorial │ GameView ──.environment(\.roster)──► leaf components
                                 ▼
                    switch game.phase ──► one screen per phase
```

[`GameSession`](../test/App/GameSession.swift) has no I/O of its own. It is built with a
[`SaveStore`](../test/App/SaveStore.swift) (`FileSaveStore` or `MemorySaveStore`) and an
[`Effects`](../test/UI/Audio/Effects.swift). Debug autoplay is applied by `TraitorsApp` after the
session exists, and does not overwrite the save.

**Screens read the prompt.** `TableScreen`, `NightView` and `VoteCeremony` switch on
`session.prompt` for what to offer; continue buttons take their label from `.proceed(then:)`.
No view reads turn bookkeeping.

**Ceremony scripts are values.** [`RoleTelling`, `BreakfastTelling`,
`VoteTelling`](../test/UI/Ceremonies/Tellings.swift) are `Equatable` structs: the moments in
order, how long each is held, and the `Cue` that goes with it. The views draw the moment they are
on. `VoteTelling.tally` and `revoteStart` are the engine's `VoteScript`'s own.

**Leaf components take values.** `Avatar`, `PlayerPicker` and `BeatRow` read a `Roster` (the
seats as the human may see them) from the environment, not the session.

**Sound and haptics are one seam.** `Effects` has a live implementation (the `Soundscape`, one
set of haptic generators, one cache of short sounds, nothing rendered on the main thread) and a
recording one. Views get it from the environment; SpriteKit and the button styles reach the same
instance through `Feedback.effects`.

**Saves.** `game.json` holds `{ version, game }`; a save from another version is not read.
Legacy `save*.json` files are deleted on launch. Stats and settings are separate files in the
same store. Player name, ending-seen seed and per-game personal bests are still in
`UserDefaults`.

### The arena on screen

```
MissionView ── ArenaConfig(ArenaSetup(run:), names and colours)
     ▼
ArenaScene (SKScene) ── owns ArenaSession
     │   update(_:)  each frame:
     │     pause / resume countdown / hit-stop       (UI-side)
     │     session.advance(dt, input)
     │     stage.sync(alpha)                         the stage reads session.game
     │     session.takeCues() → FX, sound, haptics
     │     session.clock / tally / panel → HUD, button, edge of sight
     ▼
onFinish(session.result()) ──► GameSession.send(.mission(result))
skip (spectator) ──► session.finish(), then the same
```

The scene asks the session for everything it used to work out or reach into the game for: the
countdown digit, the clock, whether the hand is in reach (the game's own answer), how far the
player can see, the end card's numbers, the hand's summary, where a trap is.

**The stages still draw from the game itself.** `ArenaStages.make` hands `session.game` to
`CourseStage` (the gauntlet) or a `CoreStage` subclass, which cast it to the concrete class and
read its runners, hazards, actors and props each frame. That access is read-only now, but it is
why the Gauntlet target has 275 public declarations, and `CourseStage` still assumes its node
arrays line up with the game's and still decides which runners the human can see.

### Phase → screen

### Instructions are shown, not written

How a game is played is never written out on screen. `MissionBriefView`, `ArenaPauseView` and `TutorialView` each show a
moving picture and one line of text (`MissionKind.gist`, `handGist`, `Vignette.line`).

- **A reel** is the real game with a script at the controls. `ArenaDemo` (TraitorsGauntlet, `Demo/`) builds a three-seat
  table, stages it from a `DemoPlan` and plays it with a `DemoDirector`, which `ArenaSession` asks once per step. Steps end
  when the game says something has happened, not after a time, so tuning moves a reel with it. `DemoPlans` holds one plan
  per game per reel (`play`, and `hand` for a traitor); `DemoCourses` holds a seventeen-row corridor for each course of the
  gauntlet so the whole run fits the picture.
- **On screen** `DemoScene` hosts the game's own stage from `ArenaStages.make` inside a rig it moves as a camera,
  `GhostThumbs` draws the game's own stick and button with fingertips on them, and `DemoReel` is the SwiftUI card. It makes
  no sound and writes nothing down. With Reduce Motion it stands on a poster frame and plays once when asked.
- **The long text** (`controls`, `twist`, `hand`, each `Vignette.spoken`) is kept as what VoiceOver reads for the picture.
- **To look at them:** `-demo all [-demoPage n]`, `-demo kiteRace [-demoReel hand]`, and `-autoplay 1 -tutorial 1 -tutorialPage n`.

| Phase | Screen |
|---|---|
| `roleReveal` | `RoleCeremony` |
| `breakfast` | `BreakfastCeremony` |
| `missionBrief` | `MissionBriefView` |
| `mission`, `missionResult` | `MissionView` |
| `roundTable`, `voting` round 1, `finaleChoice` | `TableScreen` |
| `voting` round 2, `voteReveal` | `VoteCeremony` |
| `night` | `NightView` |
| `finaleReveal` | `SceneView` |
| `gameOver` | `GameOverView`, behind `EndingCeremony` the first time |
