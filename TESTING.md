# Testing

> **Status, 2026-10-06.** This report was measured before the refactor in
> [docs/REFACTORING_PLAN.md](docs/REFACTORING_PLAN.md), and its numbers, file names and line
> links describe the code as it was then. Since then: the one test file is five targets
> (`CoreTests`, `MindsTests`, `GauntletTests`, `EngineTests`, and `AppTests` in the Xcode
> project); the engine is in `Sources/`; `swift test` is a quick tier (about 20 s) and
> `FULL=1 swift test -c release -Xswiftc -enable-testing` runs everything (about 25 s).
> Recommendations 1, 5, 18 and 19 are done, and 3 in part (loops are capped; there are no time
> limits). Of the five items under "Needs a main-code change", three are done: saves take
> their store as a parameter, the visibility rules are in the engine, and tuning is a value.
> Marking engine types `nonisolated` and having the simulator return its summary are not.
> There is also a golden master.
> [docs/ARCHITECTURE.md §8–9](docs/ARCHITECTURE.md#8-invariants-and-the-tests-that-guard-them)
> has the current list of tests and how to run them. The findings below about tests that can
> pass empty (2), seeds missing from failure messages (4) and thin end-state invariants (7)
> still stand.

What the test suite covers today, where it is thin, and what to do about it, in priority order.

Measured on 2026-10-05 against the working tree (Swift 6.4, macOS, debug build with coverage on).

## At a glance

| | |
|---|---|
| Test target | `EngineTests` (SwiftPM), one file: [Tests/EngineTests/EngineTests.swift](Tests/EngineTests/EngineTests.swift), 1,147 lines |
| Framework | Swift Testing (`@Test`, `#expect`), no XCTest |
| Tests | 53 free functions, 0 suites, 0 tags, 0 parameterised tests |
| Result | 53 passed, 0 failed |
| Wall time | 6 min 36 s for the test run, 6 min 43 s including the build |
| Engine coverage | 80.0% of lines (4,663 / 5,826), 82.2% of functions (980 / 1,192) |
| Engine coverage without `Simulator.swift` | 89.5% of lines |
| App and UI coverage | none: `test/App` and `test/UI` are not in the package and the Xcode project has no test target |
| CI | none runs the tests; the Xcode Cloud manifest lists only the app target |

The suite is strong on engine rules, belief inference and the gauntlet physics. It has three structural weaknesses: it is slow and serial, several tests can pass without checking anything, and nothing outside `test/Engine` is tested at all.

## How to run

```sh
swift test                                   # everything
swift test --filter aDashClearsTwoTiles      # one test, by name substring
swift test --enable-code-coverage            # writes the coverage JSON
swift test --show-codecov-path               # prints where that JSON is
swift run traitors-sim --games 2000          # balance numbers, not pass/fail
```

The package compiles `test/Engine` only (see [Package.swift](Package.swift)). Tests use `@testable import TraitorsEngine`, so they reach internal types directly.

## How the tests are built

Almost every test uses one of four techniques.

| Technique | What it does | Examples |
|---|---|---|
| Seed sweep | Plays whole games across a range of seeds and checks a rule on every one | `allBotGamesTerminateWithAWinner`, `onlyTraitorsEverInventASighting` |
| Forced branch | Plays to a mission, then hands in a made-up `MissionResult` to force a win or a loss | `murderFollowsAGroupLoss`, `groupWinBlocksRecruit` |
| Hand-built fixture | Builds a small log, ledger or course by hand and checks an exact outcome | the belief tests, `sightingsComeFromWhatTheRecordShows`, `aDashClearsTwoTilesAndNeverThree` |
| Statistical guard | Runs thousands of trials on a fixed seed and checks a rate against a tolerance | `theDiceGiveTheCompanyTheOddsTheGauntletDoes`, `sightingsAreAsTellingAsTheTableAssumes` |

Shared helpers, all at file scope:

| Helper | Purpose |
|---|---|
| `autoInput(_:)` | Plays the human seat with fixed choices: pass, vote for the first choice, accept recruitment, never end the finale |
| `play(seed:name:preference:)` | Plays a game to the end with `autoInput`, capped at 600 steps |
| `playToMission`, `playThroughNight`, `night(_:in:)` | Stop at a mission, play on through the following night, read that night from the log |
| `loneTraitorMissions()` | Searches seeds 1...200 for games with one traitor left and the recruitment unused |
| `quietTable(won:)`, `says(...)` | Build a one-mission log and a statement for the belief tests |
| `stillLedger`, `derived` | Build a ledger of eight players standing still and derive sightings from it |
| `gapRun(tiles:)`, `clears(tiles:dashAt:)` | Build a corridor with a drop across it and test whether a dash clears it |

## Inventory

Times are the gap between one test finishing and the next, which is accurate because the tests run one at a time (see finding 1). Tests under 0.2 s are shown as "fast".

### Game flow and rules (16 tests)

| Test | What it proves | Time |
|---|---|---|
| [allBotGamesTerminateWithAWinner](Tests/EngineTests/EngineTests.swift#L41) | 200 all-bot games reach `gameOver` with a winner | 19 s |
| [humanGamesTerminateInEveryRole](Tests/EngineTests/EngineTests.swift#L50) | 120 seeds in every role preference all finish | 33 s |
| [sameSeedGivesSameGame](Tests/EngineTests/EngineTests.swift#L61) | Seed 77 played twice gives the same log and winner | fast |
| [rolePreferenceIsHonoured](Tests/EngineTests/EngineTests.swift#L71) | The human gets the role asked for; the team is the right size | fast |
| [saveAndLoadMidGameContinuesIdentically](Tests/EngineTests/EngineTests.swift#L80) | A game saved at step 14 and restored ends with the same winner and log length | fast |
| [faithfulBotsNeverSuspectThemselvesAndBeliefsAreNormalised](Tests/EngineTests/EngineTests.swift#L97) | Beliefs sum to 1; marginals sum to the team size; self-suspicion is 0 | fast |
| [theNightIsOnlyTheTraitorsAfterALoss](Tests/EngineTests/EngineTests.swift#L111) | Over 150 games, traitors act at night exactly when the day was lost | 15 s |
| [aWinKeepsTheTraitorsInWhateverTheirHandDid](Tests/EngineTests/EngineTests.swift#L164) | A forced win gives a quiet night, even with sabotage reported | 0.7 s |
| [murderFollowsAGroupLoss](Tests/EngineTests/EngineTests.swift#L180) | A forced loss gives a murder or a recruitment | 0.9 s |
| [groupWinBlocksRecruit](Tests/EngineTests/EngineTests.swift#L216) | A lone traitor cannot recruit after a win and does after a loss | 10 s |
| [theHandIsOpenOnARecruitDay](Tests/EngineTests/EngineTests.swift#L247) | A lone traitor with the recruitment unused still attempts sabotage | 15 s |
| [aFaithfulHumanCannotSinkTheDay](Tests/EngineTests/EngineTests.swift#L263) | Sabotage reported by a faithful human is ignored | fast |
| [aMissionKeepsNoPerPlayerNumbers](Tests/EngineTests/EngineTests.swift#L276) | The report has only team fields and no feed text names a player | fast |
| [theDiceGiveTheCompanyTheOddsTheGauntletDoes](Tests/EngineTests/EngineTests.swift#L292) | The abstract mission model gives win rates of about 0.75, 0.28 and 0.13 | 6 s |
| [theHandCostsTheCompanyItsDayMoreOftenThanNot](Tests/EngineTests/EngineTests.swift#L306) | Sabotage takes the real gauntlet win rate from above half to below it | **197 s** |
| [aHumanWhoIsOutWatchesTheMissionAndAnyInputMovesOn](Tests/EngineTests/EngineTests.swift#L316) | A dead human's mission resolves on any input | 6 s |

### Beliefs (3 tests)

| Test | What it proves | Time |
|---|---|---|
| [beliefsWorkForAnyTeamSize](Tests/EngineTests/EngineTests.swift#L340) | Inference stays normalised for teams of 1, 2 and 3 | fast |
| [feedingTheLogInPiecesGivesTheSameBelief](Tests/EngineTests/EngineTests.swift#L355) | Incremental replay equals a one-shot computation to 1e-12 | fast |
| [theTopSuspectAlwaysComesWithReasons](Tests/EngineTests/EngineTests.swift#L371) | A strong top suspect always has at least one stated reason | 0.5 s |

### Sightings and testimony (7 tests)

| Test | What it proves | Time |
|---|---|---|
| [whatIsSeenStaysPrivateUntilSomeoneSaysIt](Tests/EngineTests/EngineTests.swift#L387) | Nobody witnesses themselves; reports carry no witnesses; honest sightings do not contradict | 4 s |
| [sightingsAreAsTellingAsTheTableAssumes](Tests/EngineTests/EngineTests.swift#L408) | Measured sighting likelihood ratios are within 20% of `Tuning.sight` | 0.3 s |
| [aLostDayMakesWhatWasSeenCountForMore](Tests/EngineTests/EngineTests.swift#L441) | A sighting weighs more after a loss; a quiet night adds nothing | fast |
| [testimonyOnlyCountsWhereTheSpeakerIsFaithful](Tests/EngineTests/EngineTests.swift#L467) | Testimony raises suspicion of the subject but lowers the witness-and-subject pair | fast |
| [hearingWhatYouAlreadySawChangesNothingAboutThem](Tests/EngineTests/EngineTests.swift#L480) | Testimony matching your own sighting is not counted twice | fast |
| [aWitnessWhoKnowsBetterSuspectsTheLiar](Tests/EngineTests/EngineTests.swift#L497) | A contradicted claim puts the speaker above 0.8 | fast |
| [aSightingBeforeARecruitNightCountsAgainstWhoeverWasSeenAndNobodyElse](Tests/EngineTests/EngineTests.swift#L510) | A sighting on a recruit day does not leak onto who was recruited | fast |

### Planning (4 tests)

| Test | What it proves | Time |
|---|---|---|
| [lookingAheadNeverMovesTheGame](Tests/EngineTests/EngineTests.swift#L532) | Vote simulation and team planning are repeatable and leave the game untouched | fast |
| [theTeamPlanSurvivesASave](Tests/EngineTests/EngineTests.swift#L552) | The plan and sightings round-trip through JSON | fast |
| [aTraitorVouchesForAPartnerAtMostOnceATable](Tests/EngineTests/EngineTests.swift#L563) | Over 80 games, no traitor defends a partner twice at one table | 8 s |
| [aTraitorIsNeverTheFirstToNameAPartner](Tests/EngineTests/EngineTests.swift#L588) | Over 80 games, traitors only accuse a partner a faithful named first | 8 s |

### The table (5 tests)

| Test | What it proves | Time |
|---|---|---|
| [whatBotsCiteFromTheRecordIsTrue](Tests/EngineTests/EngineTests.swift#L617) | Every chip a bot cites holds against the record | 3 s |
| [aMadeUpClaimFromTheRecordDoesNotHold](Tests/EngineTests/EngineTests.swift#L634) | `Chips.holds` rejects a false voting claim and accepts a true one | fast |
| [onlyTraitorsEverInventASighting](Tests/EngineTests/EngineTests.swift#L650) | Over 100 games, every invented sighting comes from a traitor | 10 s |
| [theHumanCanAnswerAChargeButNeverHasTo](Tests/EngineTests/EngineTests.swift#L672) | Rebutting or passing both spend the human's turn | 7 s |
| [theHumanIsToldWhatTheySawAndCanCiteIt](Tests/EngineTests/EngineTests.swift#L701) | The human's sightings appear in the notebook and can be cited | 0.4 s |

### The gauntlet (14 tests)

| Test | What it proves | Time |
|---|---|---|
| [everyCourseIsWellMade](Tests/EngineTests/EngineTests.swift#L725) | Goals are sane, rows are the right width, the vault is reachable, each course has its mechanisms | fast |
| [theDeckOpensInTheGreatHall](Tests/EngineTests/EngineTests.swift#L750) | The deck starts in the Great Hall and holds every course once | fast |
| [theLedgerSurvivesASave](Tests/EngineTests/EngineTests.swift#L759) | A real ledger round-trips through JSON | 0.8 s |
| [sightingsComeFromWhatTheRecordShows](Tests/EngineTests/EngineTests.swift#L785) | Each ledger pattern gives exactly the expected sighting | fast |
| [aPlayedOutMissionIsSettledFromItsRecord](Tests/EngineTests/EngineTests.swift#L812) | A faithful cannot be blamed; sightings come from the ledger; the pot is 3,200 | fast |
| [breakfastOnlyAsksWhoWasOutOfSightAfterALostDay](Tests/EngineTests/EngineTests.swift#L839) | The "never out of sight" clue never follows a win | 8 s |
| [everyCoursePlaysItselfOutTheSameWayTwice](Tests/EngineTests/EngineTests.swift#L859) | Each course is deterministic and independent of frame rate | 13 s |
| [nobodyEndsUpInAWallOrInsideAnyoneElse](Tests/EngineTests/EngineTests.swift#L878) | On every tick: no runner in a wall, out of bounds, too fast or overlapping | 5 s |
| [aDashClearsTwoTilesAndNeverThree](Tests/EngineTests/EngineTests.swift#L934) | Dash distance is between two and three tiles | fast |
| [everyTrapWarnsBeforeItStrikes](Tests/EngineTests/EngineTests.swift#L943) | Every trap warns for at least 0.4 s before going live | fast |
| [aPressIsNeverLostBetweenFrames](Tests/EngineTests/EngineTests.swift#L968) | A press on a short frame or during cooldown is buffered | fast |
| [onlyTheSeatWithTheHandEverUsesIt](Tests/EngineTests/EngineTests.swift#L989) | Only the saboteur's seat logs sabotage | 21 s |
| [standingByAMechanismReadsTheSameWhoeverWorkedIt](Tests/EngineTests/EngineTests.swift#L1012) | A sprung mechanism records the same bystanders whoever sprang it | fast |
| [aFullVaultSealsUnlessItIsSpilled](Tests/EngineTests/EngineTests.swift#L1037) | The vault seals at goal, resets on a spill, then ends the game early | fast |

### Staging (4 tests)

| Test | What it proves | Time |
|---|---|---|
| [stagingKeepsEverySlateAndHoldsTheResultBack](Tests/EngineTests/EngineTests.swift#L1057) | Slates are reordered so the result stays open until the last one | fast |
| [stagingSplitsATieIntoTwoRoundsAndStartsTheCountAgain](Tests/EngineTests/EngineTests.swift#L1080) | A tie gives two rounds and the count restarts | fast |
| [stagingReadsRealGamesWithoutLosingAnyone](Tests/EngineTests/EngineTests.swift#L1099) | Over 50 games, the vote and morning scripts account for every player and beat | 5 s |
| [stagingColourIsTheSameEveryTimeAndNamesNobodyStillPlaying](Tests/EngineTests/EngineTests.swift#L1132) | Flavour lines are repeatable and never name a bot | fast |

## Coverage

Line coverage per file in `test/Engine`, lowest first. Files at 97% or above are grouped.

| File | Lines covered | % |
|---|---|---|
| Simulator.swift | 0 / 613 | 0.0 |
| Staging/Autopilot.swift | 22 / 100 | 22.0 |
| Arena/ArenaRunner.swift | 77 / 196 | 39.3 |
| Staging/Place.swift | 13 / 32 | 40.6 |
| Arena/ArenaTypes.swift | 65 / 135 | 48.1 |
| Dialogue/Flavour.swift | 41 / 67 | 61.2 |
| Core/Events.swift | 63 / 81 | 77.8 |
| Dialogue/Host.swift | 22 / 27 | 81.5 |
| Dialogue/Dialogue.swift | 284 / 347 | 81.8 |
| AI/Belief.swift | 392 / 443 | 88.5 |
| Arena/Hazards.swift | 170 / 179 | 95.0 |
| AI/BotMind.swift | 172 / 181 | 95.0 |
| Missions/Missions.swift | 126 / 132 | 95.5 |
| Rules/GameEngine.swift | 833 / 870 | 95.7 |
| Missions/MissionLedger.swift | 51 / 53 | 96.2 |
| Staging/VoteScript.swift | 89 / 92 | 96.7 |
| 19 other files | | 97.0 to 100 |

What the uncovered lines are:

| Area | Uncovered | Why it matters |
|---|---|---|
| `TraitorsSim.run` and its summary | All of [Simulator.swift](test/Engine/Simulator.swift) | Balance decisions are read off this output; an argument-parsing or tallying bug would go unnoticed |
| `GameOptions` | `randomFaithful`, `randomTraitors` and `arena` are never set by a test | These are whole branches of [GameEngine.swift](test/Engine/Rules/GameEngine.swift) (bot intent, votes, finale, night, `ArenaRunner.play(run)`) |
| Human `.question` | [GameEngine.swift:538-544](test/Engine/Rules/GameEngine.swift#L538-L544) | A player action that no test sends |
| Human refuses recruitment | [GameEngine.swift:837-840](test/Engine/Rules/GameEngine.swift#L837-L840) | `autoInput` always accepts, so the refuse-and-be-murdered path never runs |
| Wrong input for the phase | [GameEngine.swift:183-185](test/Engine/Rules/GameEngine.swift#L183-L185), [833-835](test/Engine/Rules/GameEngine.swift#L833-L835), [857-860](test/Engine/Rules/GameEngine.swift#L857-L860), [561-563](test/Engine/Rules/GameEngine.swift#L561-L563) | The engine is meant to ignore a bad input and stay put; nothing checks it does |
| `Autopilot.play` and `Autopilot.scenes` | [Autopilot.swift](test/Engine/Staging/Autopilot.swift) | The debug launch arguments and `--scenes` depend on them |
| `Place.sceneKey`, `Place.card`, several `Place.of` cases | [Place.swift](test/Engine/Staging/Place.swift) | Decides which room the UI shows |
| `Dialogue.label` for chips and defence options | [Dialogue.swift:80-118](test/Engine/Dialogue/Dialogue.swift#L80-L118) | Text on the human's buttons |
| `Tuning.set` | [Belief.swift:44-85](test/Engine/AI/Belief.swift#L44-L85) | Used by `--tune`; it writes global state |
| `Grid.path`, `Grid.nearestOpen`, `Grid.open` | [ArenaTypes.swift:129-214](test/Engine/Arena/ArenaTypes.swift#L129-L214) | Not reached by any game in the suite, so possibly dead code; check for callers before writing tests |
| `ArenaRunner.par`, `trace`, `report` | [ArenaRunner.swift:121-216](test/Engine/Arena/ArenaRunner.swift#L121-L216) | Simulator-only tooling |
| `icon` and `twist` strings, `Flavour.introduction`, `Flavour.turretAdvice` | Events.swift, Flavour.swift | UI-facing text, low risk |

Line coverage overstates how well some of these files are checked. `GameEngine.swift` is at 95.7% mostly because whole games run through it, not because each rule has an assertion.

## Findings

### 1. The suite is serial and one test is half of it

The package sets `.defaultIsolation(MainActor.self)`, so every test runs on the main actor, one at a time. The run used 101% CPU. Of 396 s, `theHandCostsTheCompanyItsDayMoreOftenThanNot` takes 197 s: it plays 240 full gauntlet games.

That test is also the weakest statistically. With 24 games per rate, the standard error is about 0.10, so `alone > 0.5` and `against < 0.5` pass or fail on a few games either way.

### 2. Several tests can pass without checking anything

| Test | How it can pass empty |
|---|---|
| `aWinKeepsTheTraitorsInWhateverTheirHandDid` | The night checks are inside `if let n = night(1, in:)` with no count of how often it was true |
| `murderFollowsAGroupLoss` | Same pattern |
| `theTopSuspectAlwaysComesWithReasons` | `guard ... else { continue }` with no count of suspects checked |
| `aMadeUpClaimFromTheRecordDoesNotHold` | `guard let b = ... else { return }` on a single seed; if seed 6 stops banishing a faithful, the test checks nothing |
| `theHandIsOpenOnARecruitDay` | Only checks a count is above 3; it asserts nothing about any single game |

Other tests already do this properly, with a counter and a floor at the end (`#expect(lies > 0)`, `#expect(blocked > 0 && recruited > 0)`).

### 3. A hang hangs the suite

`play` caps a game at 600 steps, but the file has 16 loops with no cap: 10 of the form `while game.phase != .gameOver { game.advance(.next) }` and 6 that wait for another phase. If a rule change stops a game reaching that phase, those tests spin forever. No test has a `.timeLimit`.

### 4. Seed loops hide which seed failed

Each sweep is one test with a `for seed in` loop. A failure in `allBotGamesTerminateWithAWinner` does not say which seed, because the `#expect` has no message. Tests that do add `"seed \(seed)"` are fine; about half do not.

### 5. Determinism and save/load are checked at one point each

| Test | What it covers | What it misses |
|---|---|---|
| `sameSeedGivesSameGame` | Seed 77, human traitor, log and winner | Other seeds and roles; the rest of the game state |
| `saveAndLoadMidGameContinuesIdentically` | Seed 9, saved at step 14, winner and log count | Saves in other phases (night, voting, finale, mid-table); log contents |
| `theTeamPlanSurvivesASave` | Plan and sightings at the first round table | |

Save and load is the feature most exposed to this gap: the app saves after every input, in every phase.

There is also no check that today's save format still decodes after a change. [GameStore.swift](test/App/GameStore.swift) deletes saves `v1` to `v6` and reads `save-v7.json`; nothing fails if a change breaks v7 without a version bump.

### 6. Human input is barely varied

`autoInput` always passes at the table, votes for the first choice, accepts recruitment and never ends the finale. Every `HumanInput` case is sent at least once, but with one fixed choice each. A human who questions, defends another player, refuses recruitment, votes to end the game, or sends the wrong input for the phase is untested. Of the four `HumanSay` kinds, only `.pass` and `.accuse` are used. Two tests add accusing with a chip and rebutting.

`autoInput` also duplicates `Autopilot.input(for:)` in the engine with different choices, and only one test uses the engine's version.

### 7. End-state and whole-game invariants are thin

`allBotGamesTerminateWithAWinner` checks only that there is a winner. Nothing checks, for example:

- the winner matches who is left (faithful win means no traitor alive)
- nobody speaks, votes or is murdered after they are out
- every vote round has one slate per living voter
- the pot never goes down and equals the sum of the mission reports
- the traitor count never exceeds the starting team plus one recruit

### 8. Nothing outside the engine is tested

`test/App` and `test/UI` are compiled only by the Xcode project, which has no test target. The logic most worth testing there is in `GameStore`: `concealed`, `roleShown` and `spectating` decide what the player is allowed to see, and `record` updates the stats.

`Persistence` writes to the real Application Support folder with no way to redirect it, so testing `GameStore` end to end needs a change to main code. That is out of scope here and listed under "Needs a main-code change" below.

### 9. Structure and upkeep

- One 1,147-line file with 53 free functions. Filtering is by name substring only; there are no suites or tags to run "the fast ones" or "the gauntlet ones".
- The loop that tracks roles through a recruitment is written out three times (`aTraitorVouches...`, `aTraitorIsNeverTheFirst...`, `onlyTraitorsEverInventASighting`).
- Magic numbers: `potEarned == 3200`, `MissionKind.allCases.count == 5`, win rates `0.75 / 0.28 / 0.13`. These are deliberate tripwires for tuning changes but are not labelled as such, so a failure reads like a bug.
- `aMissionKeepsNoPerPlayerNumbers` compares `Mirror` field labels. Adding any field to `MissionReport` or `MissionResult` fails it. That is the intent (a privacy guard), and worth a comment saying so.
- `Tuning.set` writes global state. Any future test that calls it will affect every later test in the process.

### 10. Repository and CI

- `.build/` and `build/` are tracked in git and there is no `.gitignore`. Every `swift test` leaves hundreds of modified files in `git status`.
- No CI runs `swift test`. The Xcode Cloud manifest builds the app target only.
- The test file has 575 changed lines not yet committed, alongside the gauntlet rewrite it tests.

## Recommendations

None of these touch `test/Engine`, `test/App` or `test/UI`.

### Do first

| # | Change | Fixes | Effort |
|---|---|---|---|
| 1 | Tag the slow statistical tests (`.tags(.balance)`) and cut `theHandCostsTheCompanyItsDayMoreOftenThanNot` to a smoke check in the default run. Run the full version in a release build (`swift test -c release`) on a schedule. | Finding 1; takes the default run from about 6.5 min to about 3.5 min before any other change | Small |
| 2 | Add a counter and a final `#expect(count > N)` to the five tests in finding 2 | Finding 2 | Small |
| 3 | Replace bare `while phase != .gameOver` loops with one bounded helper that fails with the seed and phase when the cap is hit, and add `.timeLimit(.minutes(2))` to the sweeps | Finding 3 | Small |
| 4 | Add `"seed \(seed)"` to every `#expect` inside a seed loop, or move the sweeps to `@Test(arguments: 1...200)` so each seed reports on its own | Finding 4 | Small |
| 5 | Add `.gitignore` for `.build/` and `build/` and untrack them (`git rm -r --cached`) | Finding 10 | Small, but it rewrites the index, so do it as its own commit |

### Do next: new tests that close real gaps

| # | Test to add | Covers |
|---|---|---|
| 6 | **Save at every step.** For about 20 seeds and each role, encode and decode the game after every `advance`, continue from the decoded copy, and compare the full sorted-key JSON of both games at the end | Finding 5 |
| 7 | **Determinism across seeds.** Same as `sameSeedGivesSameGame` for about 20 seeds and all roles, comparing the whole encoded `Game` | Finding 5 |
| 8 | **Wrong input is ignored.** In each phase, send every `HumanInput` that does not belong, plus out-of-range targets (dead player, self, index past the end), and expect the encoded game to be unchanged | Uncovered engine lines 183-185, 833-835, 857-860, 561-563 |
| 9 | **A second human policy.** A helper that questions, defends, refuses recruitment and votes to end the finale; run the termination sweep with it | Finding 6; lines 538-544 and 837-840 |
| 10 | **Refusing recruitment.** Reach a night with `nightChoice == .offer`, send `.recruitAnswer(false)`, expect the human murdered and the recruitment spent | Line 837-840 |
| 11 | **Whole-game invariants.** One sweep that checks the five invariants in finding 7 after every step | Finding 7 |
| 12 | **Game options.** Run the termination sweep with `randomFaithful`, `randomTraitors` and `arena` each switched on (a few seeds for `arena`, which is slow) | The `GameOptions` branches |
| 13 | **Autopilot and Place.** `Autopilot.play` stops where its `Stop` says for each phase; `Place.of` returns a value for every phase reached; `Autopilot.scenes` finds each wanted scene in a known seed range | Autopilot.swift, Place.swift |
| 14 | **Simulator smoke test.** `TraitorsSim.run(arguments: ["sim", "--games", "5"])` completes, and again with `--arena`, `--form 0` and `--scenes` | Simulator.swift from 0% to most of it. It prints to stdout; the test only checks it does not trap |
| 15 | **Button labels.** `Dialogue.label` for every `Chip.Kind` and every defence option is non-empty and contains no unfilled `{O}` placeholder | Dialogue.swift 80-118 |
| 16 | **Save fixture.** Commit one encoded v7 `Game` as a test resource and assert it still decodes and plays to the end. When it fails, bump `Persistence.saveFile` | Finding 5 |
| 17 | **Large seeds.** Add a few seeds near `UInt64.max / 2` to the termination sweep. The app draws from `1...UInt64.max / 2` | Seeds above 280 are never used today |

### Structure

| # | Change | Why |
|---|---|---|
| 18 | Split the file along its existing `MARK`s into `GameFlowTests`, `BeliefTests`, `SightingTests`, `PlanningTests`, `TableTests`, `GauntletTests`, `StagingTests`, with helpers in `Support.swift`, each wrapped in a `@Suite` | Lets you run one area; makes the file readable |
| 19 | Tags: `.sweep` (plays many games), `.balance` (statistical), `.fast` (everything else) | A sub-10-second inner loop |
| 20 | Pull the role-tracking loop into one helper, for example `rolesOverTime(game)` | Removes three copies |
| 21 | Name the tripwire constants and comment them as "fails when tuning changes; update deliberately" | Finding 9 |
| 22 | Add a CI job that runs `swift test --skip-tags balance` on every push and the full suite nightly | Finding 10 |

### Needs a main-code change (out of scope for now)

| Change | What it unlocks |
|---|---|
| Let `Persistence` take its folder as a parameter | Testing `GameStore` save, load, stats and abandon without touching the real Application Support folder |
| Move `GameStore`'s visibility rules (`concealed`, `roleShown`, `spectating`) into the engine package, or add an Xcode unit-test target for the app | Testing what the player is allowed to see |
| Make `Tuning` an instance passed in, not global statics | Tests that vary tuning without affecting each other, and running suites in parallel |
| Mark pure engine types `nonisolated` | Tests off the main actor, so the sweeps can run in parallel across cores |
| Have `TraitorsSim.run` return its summary as a value | Asserting on simulator numbers instead of only checking it does not crash |

## Targets

| Measure | Now | After "Do first" | After "Do next" |
|---|---|---|---|
| Default run time | 6 min 36 s | about 3.5 min | about 4 min, or under 10 s with `.fast` only |
| Engine line coverage | 80.0% | 80.0% | about 92% (estimate) |
| Tests that can pass empty | 5 | 0 | 0 |
| Uncapped game loops | 16 | 0 | 0 |
| `HumanSay` kinds exercised | 2 of 4 | 2 of 4 | 4 of 4, plus invalid inputs |
