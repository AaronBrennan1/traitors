import Foundation
import TraitorsCore
import TraitorsMinds
import TraitorsGauntlet

/// The whole game: state plus the rules that move it forward. `advance` runs until the next
/// point where the human has to decide something (or simply tap to continue).
public struct Game: Codable {
    public package(set) var seed: UInt64
    var rng: SeededRNG
    public package(set) var players: [Player]
    var minds: [BotMind]
    /// Seat of the human player. Nil in headless simulations, where all eight are bots.
    public package(set) var human: PlayerID?
    var options = GameOptions()

    public package(set) var day = 1
    public package(set) var phase: Phase = .roleReveal
    /// Everything said and done in front of the table.
    package private(set) var record = PublicRecord()
    /// The record's events, in order.
    package var log: [PublicEvent] { record.events }
    public package(set) var feed: [Beat] = []
    var morning: [Beat] = []
    var heat: [Double]

    var missionDeck: [MissionKind]
    public package(set) var mission: MissionRun?
    public package(set) var report: MissionReport?
    /// Private: the traitor whose hand cost the company today's mission, if one did.
    var sunkBy: PlayerID?
    public package(set) var pot = 0

    var recruitmentUsed = false
    public package(set) var finale = false
    private var tableStep = 0
    private var voteRound = 1
    private var candidates: [PlayerID] = []
    private var lockedVotes: [PlayerID: PlayerID] = [:]
    private var lockedFinale: [PlayerID: Bool] = [:]
    private var nightChoice: NightChoice = .none
    private var recruiter: PlayerID?
    private var partnerAdvice: PlayerID?
    /// What has just been resolved, for whoever is telling it. Cleared when the game moves on.
    public private(set) var outcome: Outcome?
    public package(set) var winner: Role?
    public package(set) var history: [DaySnapshot] = []
    public package(set) var tally = Tally()
    /// Private ledger of everything seen in missions and by whom. Bots only ever get their own share.
    var sightings: [Sighting] = []
    /// What the traitors have agreed for the current Round Table.
    var teamPlan: TeamPlan?

    // MARK: - Setup

    public init(seed: UInt64, humanName: String?, preference: RolePreference = .random, options: GameOptions = GameOptions()) {
        self.seed = seed
        self.options = options
        var rng = SeededRNG(seed: seed)
        var players: [Player] = []
        if let humanName {
            players.append(Player(id: 0, name: humanName, county: "", job: "You", isHuman: true, role: .faithful,
                                  personality: .average, voice: .plain, hue: 0.12))
            human = 0
        } else {
            players.append(Player(id: 0, name: "Tadhg", county: "Mayo", job: "Trawlerman", isHuman: false, role: .faithful,
                                  personality: Personality(perception: 0.74, logic: 0.74, aggression: 0.55, stubbornness: 0.5,
                                                           herd: 0.35, charisma: 0.65, deceit: 0.7, skill: 0.6),
                                  voice: .plain, hue: 0.66))
            human = nil
        }
        for (i, c) in Cast.bots.enumerated() {
            players.append(Player(id: i + 1, name: c.name, county: c.county, job: c.job, isHuman: false, role: .faithful,
                                  personality: c.personality, voice: c.voice, hue: c.hue))
        }
        let n = players.count
        var traitors: [PlayerID]
        switch (humanName != nil, preference) {
        case (true, .traitor): traitors = [0] + rng.shuffled(Array(1..<n)).prefix(Rules.traitors - 1)
        case (true, .faithful): traitors = Array(rng.shuffled(Array(1..<n)).prefix(Rules.traitors))
        default: traitors = Array(rng.shuffled(Array(0..<n)).prefix(Rules.traitors))
        }
        for t in traitors { players[t].role = .traitor }

        var minds: [BotMind] = []
        for p in players {
            var r = rng.fork()
            let spread = 0.12 + 0.3 * p.personality.stubbornness
            let gut = (0..<n).map { $0 == p.id ? 0 : r.gaussian() * spread }
            minds.append(BotMind(id: p.id, gut: gut, rng: r))
        }
        self.players = players
        self.minds = minds
        self.heat = Array(repeating: 0, count: n)
        self.missionDeck = MissionDeck.deal(rng: &rng)
        self.rng = rng
    }

    // MARK: - Queries

    public var alive: [PlayerID] { players.filter(\.alive).map(\.id) }
    public var aliveTraitors: [PlayerID] { players.filter { $0.alive && $0.role == .traitor }.map(\.id) }
    var aliveFaithful: [PlayerID] { players.filter { $0.alive && $0.role == .faithful }.map(\.id) }
    public var team: [PlayerID] { players.filter { $0.role == .traitor }.map(\.id) }
    var aliveBots: [PlayerID] { alive.filter { $0 != human } }
    public var humanAlive: Bool { human.map { players[$0].alive } ?? false }
    public var humanIsTraitor: Bool { human.map { players[$0].role == .traitor } ?? false }
    var names: [String] { players.map(\.name) }

    /// Role as publicly known: shown at a banishment, or faithful for anyone murdered.
    package func revealedRole(_ p: PlayerID) -> Role? {
        for event in log {
            if case .banished(_, let who, let role) = event, who == p { return role }
            if case .night(_, let victim, _) = event, victim == p { return .faithful }
        }
        return nil
    }

    public func view() -> TableView {
        let seats = players.map {
            Seat(id: $0.id, name: $0.name, alive: $0.alive, revealed: revealedRole($0.id), charisma: $0.personality.charisma)
        }
        return TableView(day: day, seats: seats, record: record, heat: heat, tuning: options.tuning.belief)
    }

    package func publicSuspicion() -> [Double] {
        Minds.publicSuspicion(at: view())
    }

    /// Evidence the human can cite about a player, including what they saw in today's mission.
    public func notebook(about p: PlayerID, suspicious: Bool) -> [Chip] {
        let mine = human.map { h in minds[h].seen.filter { $0.day == day } } ?? []
        return Chips.about(p, view: view(), suspicious: suspicious, sightings: mine)
    }

    /// The ways the human can answer whoever last pointed at them. Empty when nobody has.
    package func defenceOptions() -> [DefenceOption] {
        guard let me = human, players[me].alive, phase == .roundTable else { return [] }
        return Minds.defences(for: minds[me], traits: players[me].personality, at: view())
    }

    // MARK: - Minds

    /// How a seat is played. The only place the sim's switches are read.
    private func mindKind(of seat: PlayerID) -> MindKind {
        if players[seat].role == .traitor { return options.randomTraitors ? .random : .traitor }
        return options.randomFaithful ? .random : .faithful
    }

    /// The mind in a seat, with what it is entitled to know and nothing else.
    private func mind(for seat: PlayerID) -> any Mind {
        let traitor = players[seat].role == .traitor
        return Minds.make(mindKind(of: seat), notes: minds[seat], traits: players[seat].personality,
                          conspiracy: traitor ? Conspiracy(team: team, plan: teamPlan, known: known()) : nil)
    }

    /// Puts a question to the mind in a seat, and keeps what it has noted down in answering.
    private mutating func ask<T>(_ seat: PlayerID, _ question: (inout any Mind) -> T) -> T {
        var m = mind(for: seat)
        let answer = question(&m)
        minds[seat] = m.notes
        return answer
    }

    /// What the traitors as a team know was seen of them.
    private func known() -> [Sighting] {
        team.flatMap { minds[$0].exposed }
    }

    /// Whether a claimed sighting is something the speaker did not actually see.
    private func invented(_ chip: Chip?, by speaker: PlayerID) -> Bool {
        guard let chip, chip.isTestimony else { return false }
        return !sightings.contains { $0.day == chip.day && $0.subject == chip.subject && $0.kind == chip.sight && $0.witnesses.has(speaker) }
    }

    /// Whether a lone traitor would recruit tonight in place of a murder, with `left` still in the game by then.
    private func recruitNight(left: Int) -> Bool {
        aliveTraitors.count == 1 && !recruitmentUsed && left >= 5
    }

    /// Who has won as things stand, if anyone has.
    private var verdict: Role? {
        if aliveTraitors.isEmpty { return .faithful }
        return aliveTraitors.count >= aliveFaithful.count ? .traitor : nil
    }

    /// Whether tonight is the traitors'. A day the company won keeps them in.
    var traitorsMayAct: Bool { report?.groupWon != true }

    /// Who the human may pick right now (vote, murder, recruit).
    private var choices: [PlayerID] {
        guard let me = human else { return [] }
        switch phase {
        case .voting: return (candidates.isEmpty ? alive : candidates).filter { $0 != me }
        case .night:
            switch nightChoice {
            case .murder: return aliveFaithful
            case .recruit: return alive.filter { $0 != me }
            default: return []
            }
        default: return alive.filter { $0 != me }
        }
    }

    // MARK: - Prompt and answer

    /// What the game is waiting for.
    public var prompt: Prompt {
        switch phase {
        case .roleReveal: return .proceed(then: .breakfast)
        case .breakfast: return .proceed(then: winner != nil ? .ending : finale ? .fireOfTruth : .missionBrief)
        case .missionBrief: return .proceed(then: .mission)
        case .mission: return mission.map { .playMission($0) } ?? .proceed(then: .roundTable)
        case .missionResult: return .proceed(then: finale ? .fireOfTruth : .roundTable)
        case .roundTable: return .speak(turn: tableStep, targets: alive.filter { $0 != human }, defences: defenceOptions())
        case .voting: return .vote(round: voteRound, candidates: choices)
        case .voteReveal:
            if winner != nil || (finale && alive.count <= 2) { return .proceed(then: .ending) }
            return .proceed(then: finale ? .fireOfTruth : .night)
        case .night:
            switch nightChoice {
            case .murder: return .murder(candidates: choices, advice: partnerAdvice)
            case .recruit: return .recruit(candidates: choices)
            case .offer: return recruiter.map { .answerOffer(from: $0) } ?? .proceed(then: .morning)
            case .none: return .proceed(then: .morning)
            }
        case .finaleChoice: return .endOrBanish
        case .finaleReveal: return .proceed(then: winner != nil ? .ending : .vote)
        case .gameOver: return .over(winner: winner)
        }
    }

    /// Applies an answer to the current prompt and runs the rules forward to the next point where
    /// the human has to decide something or tap to continue. An answer that does not fit the
    /// prompt throws and changes nothing.
    public mutating func advance(_ answer: Answer) throws {
        try check(answer)
        // A tied vote keeps its first round until the second is in.
        if phase != .voting { outcome = nil }
        switch (phase, answer) {
        case (.roleReveal, _):
            startDay()
        case (.breakfast, _):
            if winner != nil { phase = .gameOver } else { beginBrief() }
        case (.missionBrief, _):
            beginMission()
        case (.mission, .mission(let result)):
            mission?.resolve(human: result)
            finishMission()
        case (.mission, _):
            // A human who is out only watches, so the day moves on without them.
            mission?.resolve(human: nil)
            finishMission()
        case (.missionResult, _):
            enterRoundTable()
        case (.roundTable, .say(let kind, let target, let chip)):
            humanSay(kind, target, chip)
        case (.roundTable, .rebut(let choice)):
            humanRebut(choice)
        case (.voting, .vote(let target)):
            resolveVotes(humanVote: target)
        case (.voteReveal, _):
            afterBanishment()
        case (.night, _):
            resolveNight(answer)
        case (.finaleChoice, .finale(let end)):
            resolveFinale(humanEnd: end)
        case (.finaleReveal, _):
            if winner != nil { phase = .gameOver } else { feed = []; enterVoting() }
        default:
            break
        }
    }

    /// Whether `answer` fits what the game is asking. Reads only; throws the reason when it does not.
    private func check(_ answer: Answer) throws {
        func among(_ p: PlayerID, _ offered: [PlayerID]) throws {
            if !offered.contains(p) { throw GameError.notACandidate(p) }
        }
        switch (phase, answer) {
        case (.gameOver, _):
            throw GameError.gameOver
        case (.roleReveal, .proceed), (.breakfast, .proceed), (.missionBrief, .proceed), (.missionResult, .proceed),
             (.voteReveal, .proceed), (.finaleReveal, .proceed):
            break
        case (.mission, .mission):
            break
        case (.mission, .proceed) where mission?.human == nil:
            break
        case (.roundTable, .say(let kind, let target, _)):
            guard kind != .pass else { break }
            guard let target, target != human, players.indices.contains(target), players[target].alive else {
                throw GameError.notACandidate(target)
            }
        case (.roundTable, .rebut(let choice)):
            if !defenceOptions().indices.contains(choice) { throw GameError.noSuchDefence(choice) }
        case (.voting, .vote(let target)):
            try among(target, choices)
        case (.night, .murder(let target)) where nightChoice == .murder:
            try among(target, choices)
        case (.night, .recruit(let target)) where nightChoice == .recruit:
            try among(target, choices)
        case (.night, .offer) where nightChoice == .offer:
            break
        case (.night, .proceed) where nightChoice == .none:
            break
        case (.finaleChoice, .finale):
            break
        default:
            throw GameError.notAskedFor
        }
    }

    /// Plays a game with no human input to the end. Only valid when no living human is seated.
    mutating func runToEnd(limit: Int = 500) {
        var steps = 0
        while phase != .gameOver, steps < limit {
            guard (try? advance(.proceed)) != nil else { break }
            steps += 1
        }
    }

    // MARK: - Day

    private mutating func startDay() {
        heat = Array(repeating: 0, count: players.count)
        sunkBy = nil
        mission = nil
        report = nil
        partnerAdvice = nil
        teamPlan = nil
        if day == 1 {
            feed = [Beat(kind: .host, text: Host.firstBreakfast(players: players.count, traitors: team.count))]
            phase = .breakfast
            return
        }
        feed = morning
        morning = []
        if winner == nil, alive.count <= 4 {
            finale = true
        }
        phase = .breakfast
    }

    private mutating func beginBrief() {
        if finale {
            feed = [Beat(kind: .host, text: Host.noMission(left: alive.count))]
            enterRoundTable(keepFeed: true)
            return
        }
        let kind = missionDeck[(day - 1) % missionDeck.count]
        let v = view()
        let ts = aliveTraitors
        let botTs = ts.filter { $0 != human }
        // A lone traitor recruits at night in place of a murder, and has to earn that night the same way.
        let recruitTonight = recruitNight(left: alive.count - 1)
        let night = recruitTonight ? "recruit" : "murder"
        var runner: PlayerID?
        var whisper: String?
        let humanOnTeam = humanAlive && humanIsTraitor

        if let first = botTs.first, mindKind(of: first) == .random {
            // A team playing at random draws lots for the hand.
            runner = rng.chance(0.5) ? rng.pick(botTs) : nil
        } else if let (cand, suspicion) = Minds.leastSuspected(of: botTs, at: v) {
            let mustKill = aliveFaithful.count - 2 <= ts.count
            var go = ask(cand) { $0.useTheHand(at: v, mustKill: mustKill) }
            if humanOnTeam, let me = human {
                if suspicion(cand) > suspicion(me) + 0.05 {
                    go = false
                    whisper = "\(players[cand].name) whispers: \"Too many eyes on me. If anyone spoils the day it has to be you.\""
                } else if go {
                    whisper = "\(players[cand].name) whispers: \"Leave the dirty work to me. Keep your hands clean.\""
                } else {
                    whisper = "\(players[cand].name) whispers: \"I'm lying low today. If they look like making their goal, it is on you.\""
                }
            }
            if go { runner = cand }
        } else if humanOnTeam {
            whisper = recruitTonight
                ? "You are alone now. Tonight you may recruit, but only if the company falls short."
                : "You are the only traitor left. If the company makes its goal, there is no night for you."
        }

        let run = MissionRun(kind: kind, day: day, alive: alive, human: humanAlive ? human : nil, traitors: ts,
                             runner: runner, traits: players.map(\.personality), quirkSeed: seed, rng: rng.fork(), tuning: options.tuning)
        mission = run
        feed = [Beat(kind: .narration, text: kind.brief),
                Beat(kind: .host, text: Host.missionRule(goal: run.teamGoal, unit: kind.spec.unit))]
        if humanOnTeam {
            feed.append(Beat(kind: .secret, text: "\(kind.hand) Keep the company short of its goal and the traitors may \(night) tonight."))
            if let whisper { feed.append(Beat(kind: .secret, text: whisper)) }
        }
        phase = .missionBrief
    }

    private mutating func beginMission() {
        guard var run = mission else { return }
        run.plan()
        mission = run
        if human == nil {
            run.resolve(human: options.arena ? ArenaSession.play(run) : nil)
            mission = run
            finishMission()
        } else {
            // A human who is out still gets to watch the others play.
            phase = .mission
        }
    }

    private mutating func finishMission() {
        guard let run = mission else { return }
        let r = run.report()
        report = r
        record.append(.mission(r))
        pot += r.potEarned
        sunkBy = run.sunkBy
        if run.runnerAttempt || run.humanAttempt { tally.sabotageAttempts += 1 }
        if sunkBy != nil { tally.daysSunk += 1 }
        if r.groupWon { tally.groupWins += 1 }

        // Everyone takes away what they saw, and knows who was looking at them.
        sightings += run.sightings
        for s in run.sightings {
            minds[s.subject].exposed.append(s)
            for w in s.witnesses.seats { minds[w].seen.append(s) }
        }

        let tally = "\(r.kind.title): \(r.teamTotal) \(r.kind.spec.unit) between you, and the goal was \(r.teamGoal)."
        feed = [Beat(kind: .result, text: tally + (r.groupWon ? " The company made it." : " The company fell short.")),
                Beat(kind: .result, text: "\(r.potEarned) added to the pot."),
                Beat(kind: .host, text: r.groupWon ? Host.missionWon : Host.missionLost)]
        var noticed: [Sighting] = []
        if humanAlive, let me = human {
            let v = view()
            noticed = run.sightings.filter { $0.witnesses.has(me) }
            for s in noticed {
                feed.append(Beat(kind: .secret, target: s.subject, text: Dialogue.noticed(s, view: v)))
            }
        }
        outcome = .mission(r, noticed: noticed)
        if humanAlive, humanIsTraitor {
            let recruitTonight = recruitNight(left: alive.count - 1)
            let night = recruitTonight ? "recruit" : "murder"
            if r.groupWon {
                feed.append(Beat(kind: .secret, text: "The company made its goal. There will be no \(night) tonight."))
            } else if let by = sunkBy {
                let who = by == human ? "Your hand" : "\(players[by].name)'s hand"
                feed.append(Beat(kind: .secret, text: "\(who) cost them the day. The traitors may \(night) tonight."))
            } else {
                feed.append(Beat(kind: .secret, text: "The company fell short without any help. The traitors may \(night) tonight."))
            }
        }
        phase = .missionResult
    }

    // MARK: - Round Table

    private mutating func enterRoundTable(keepFeed: Bool = false) {
        if !keepFeed { feed = [] }
        feed.append(Beat(kind: .host, text: finale ? Host.fireLit : Host.roundTable(day: day)))
        heat = Array(repeating: 0, count: players.count)
        tableStep = 1
        if tally.roundTables == 0 {
            let v = view()
            let tops = Set(aliveBots.filter { players[$0].role == .faithful }.compactMap { mind(for: $0).suspect(at: v) })
            tally.firstTableSplit = tops.count >= 2
        }
        refreshPlan()
        if let plan = teamPlan, humanAlive, humanIsTraitor, let me = human,
           let partner = aliveTraitors.first(where: { $0 != me }),
           let text = TeamPlanner.whisper(plan, from: partner, to: me, view: view()) {
            feed.append(Beat(kind: .secret, text: text))
        }
        let called = round(.opening, 1)
        let accused = round(.accusations, 3)
        if !called, !accused {
            feed.append(Beat(kind: .narration, text: "Nobody is ready to name a name. Eyes move around the table."))
        }
        if humanAlive {
            phase = .roundTable
        } else {
            secondHalf()
            closeTable()
        }
    }

    /// The traitors take stock of the table as it now stands.
    private mutating func refreshPlan() {
        guard let first = aliveTraitors.first, mindKind(of: first) != .random else { teamPlan = nil; return }
        if let old = teamPlan, old.day == day, old.asOf == log.count { return }
        let v = view(), seed = seed
        guard var plan = ask(first, { $0.plan(at: v, seed: seed) }) else { teamPlan = nil; return }
        if let old = teamPlan, old.day == day { plan.vouched = old.vouched }
        teamPlan = plan
    }

    private mutating func secondHalf() {
        let answered = round(.rebuttals, 2)
        let open = round(.openFloor, 1)
        if !answered, !open {
            feed.append(Beat(kind: .narration, text: "Nobody is ready to name a name. Eyes move around the table."))
        }
    }

    private mutating func closeTable() {
        declarations()
        if finale { enterFinaleChoice() } else { enterVoting() }
    }

    private mutating func botIntent(_ b: PlayerID, replyTo: PlayerID?, phase: TablePhase = .openFloor) -> Intent? {
        let v = view()
        return ask(b) { $0.speak(at: v, phase: phase, replyTo: replyTo) }
    }

    private mutating func botVote(_ b: PlayerID, pool: [PlayerID], sticky: PlayerID?) -> PlayerID {
        let v = view()
        return ask(b) { $0.vote(at: v, among: pool, declared: sticky) }
    }

    /// One beat of the table. The bots keenest to speak in this phase take the floor, and
    /// anyone they point at gets a right of reply. Returns whether anything was said.
    @discardableResult
    private mutating func round(_ phase: TablePhase, _ slots: Int) -> Bool {
        refreshPlan()
        let said = view().index.statements(day: day)
        var eager: [(PlayerID, Double)] = []
        for b in aliveBots {
            let spoken = said.filter { $0.speaker == b }.count
            eager.append((b, phase.urgency(heat: heat[b], spoken: spoken, p: players[b].personality,
                                           jitter: minds[b].rng.range(0, 0.6))))
        }
        // A couple more than there are slots, since not everyone keen to speak has something to say.
        let speakers = eager.sorted { $0.1 > $1.1 }.prefix(slots + 2).map(\.0)
        var replied: Set<PlayerID> = []
        var spoke = 0
        for b in speakers where spoke < slots {
            guard let intent = botIntent(b, replyTo: nil, phase: phase) else { continue }
            say(b, intent)
            spoke += 1
            if intent.kind == .accuse || intent.kind == .callout, let t = intent.target, t != human, players[t].alive, !replied.contains(t) {
                replied.insert(t)
                if let reply = botIntent(t, replyTo: b) { say(t, reply) }
            }
        }
        return spoke > 0
    }

    private mutating func say(_ speaker: PlayerID, _ intent: Intent) {
        let v = view()
        let text = Dialogue.line(kind: intent.kind, target: intent.target, chip: intent.chip,
                                 voice: players[speaker].voice, view: v, rng: &rng, defence: intent.defence)
        apply(Statement(day: day, speaker: speaker, kind: intent.kind, target: intent.target, chip: intent.chip,
                        text: text, defence: intent.defence), view: v, credibility: intent.credibility)
        contest(speaker, intent.chip)
    }

    /// Anyone who was there and knows a claimed sighting to be false says so at once.
    private mutating func contest(_ speaker: PlayerID, _ chip: Chip?) {
        guard let chip, chip.isTestimony else { return }
        for c in aliveBots where c != speaker && c != chip.subject {
            guard let mine = mind(for: c).knowsBetter(than: chip, saidBy: speaker) else { continue }
            tally.challenges += 1
            if invented(chip, by: speaker) { tally.liesCaught += 1 }
            say(c, Intent(kind: .challenge, target: speaker,
                          chip: Chip(kind: .caughtLie, subject: speaker, day: chip.day, other: chip.subject, sight: mine.kind, strength: 1.3)))
            if speaker != human, players[speaker].alive, let reply = botIntent(speaker, replyTo: c) { say(speaker, reply) }
            return
        }
    }

    private mutating func apply(_ s: Statement, view v: TableView, credibility: Double = 0) {
        record.append(.statement(s))
        feed.append(Beat(kind: .speech, speaker: s.speaker, target: s.target, text: s.text))
        if s.chip?.isTestimony == true {
            tally.testimony += 1
            if invented(s.chip, by: s.speaker) { tally.liesTold += 1 }
        }
        let weight = v.voice(s.speaker)
        if let d = s.defence {
            tally.defences[d.rawValue, default: 0] += 1
            // A defence that stands up cools the table and softens what each listener privately thinks.
            heat[s.speaker] = max(0, heat[s.speaker] - Defences.relief(credibility) * weight)
            for b in aliveBots where b != s.speaker {
                minds[b].gut[s.speaker] = max(-1.5, minds[b].gut[s.speaker] - Defences.soothe(credibility, persuasion: options.tuning.belief.persuasion))
            }
        }
        if s.kind == .vouch, players[s.speaker].role == .traitor, teamPlan?.vouched.contains(s.speaker) == false {
            teamPlan?.vouched.append(s.speaker)
        }
        guard let t = s.target else { return }
        let effect = s.kind.effect
        if s.kind == .callout { tally.callouts += 1 }
        if effect.heat > 0 {
            heat[t] += effect.heat * weight
        } else if effect.heat < 0 {
            heat[t] = max(0, heat[t] + effect.heat * weight)
        }
        // Being accused breeds a grudge in proportion to stubbornness.
        if effect.grudge, t != human {
            let g = minds[t].gut[s.speaker] + 0.35 * players[t].personality.stubbornness
            minds[t].gut[s.speaker] = min(g, 1.5)
        }
    }

    private mutating func humanSay(_ kind: HumanSay, _ target: PlayerID?, _ chip: Chip?) {
        guard let me = human else { return }
        let v = view()
        let valid = target.map { $0 != me && players[$0].alive } ?? false
        switch kind {
        case .accuse where valid, .defend where valid:
            let k: StatementKind = kind == .accuse ? .accuse : .defend
            let text = Dialogue.line(kind: k, target: target, chip: chip, voice: .plain, view: v, rng: &rng)
            apply(Statement(day: day, speaker: me, kind: k, target: target, chip: chip, text: text), view: v)
            contest(me, chip)
            if k == .accuse, let t = target, players[t].alive, let reply = botIntent(t, replyTo: me) { say(t, reply) }
        case .question where valid:
            let t = target!
            let text = Dialogue.line(kind: .question, target: t, chip: nil, voice: .plain, view: v, rng: &rng)
            record.append(.statement(Statement(day: day, speaker: me, kind: .question, target: t, chip: nil, text: text)))
            feed.append(Beat(kind: .speech, speaker: me, target: t, text: text))
            let name = botVote(t, pool: alive, sticky: view().index.declared(day: day, by: t))
            say(t, Intent(kind: .answer, target: name, chip: Minds.bestChip(about: name, at: view(), suspicious: true)))
        default:
            feed.append(Beat(kind: .narration, text: "You say nothing and watch."))
        }
        endHumanTurn()
    }

    /// The human answers whoever last pointed at them, in place of their turn.
    private mutating func humanRebut(_ choice: Int) {
        guard let me = human else { return }
        let options = defenceOptions()
        if options.indices.contains(choice) {
            let o = options[choice]
            let v = view()
            let text = Dialogue.line(kind: .selfDefend, target: o.target, chip: o.chip, voice: .plain, view: v, rng: &rng, defence: o.defence)
            apply(Statement(day: day, speaker: me, kind: .selfDefend, target: o.target, chip: o.chip, text: text, defence: o.defence),
                  view: v, credibility: o.credibility)
        } else {
            feed.append(Beat(kind: .narration, text: "You say nothing and watch."))
        }
        endHumanTurn()
    }

    private mutating func endHumanTurn() {
        if tableStep == 1 {
            tableStep = 2
            secondHalf()
        } else {
            closeTable()
        }
    }

    private mutating func declarations() {
        feed.append(Beat(kind: .host, text: Host.declarations))
        refreshPlan()
        for b in rng.shuffled(aliveBots) {
            let target = botVote(b, pool: alive, sticky: view().index.declared(day: day, by: b))
            guard target != b else { continue }
            say(b, Intent(kind: .declare, target: target, chip: nil))
        }
    }

    // MARK: - Voting

    private mutating func enterVoting() {
        voteRound = 1
        candidates = []
        lockVotes()
        if humanAlive {
            phase = .voting
        } else {
            resolveVotes(humanVote: nil)
        }
    }

    /// Bots commit before the human chooses, so nothing the human does can leak into their votes.
    private mutating func lockVotes() {
        lockedVotes = [:]
        refreshPlan()
        let pool = candidates.isEmpty ? alive : candidates
        for b in aliveBots where !(voteRound == 2 && candidates.contains(b)) {
            let sticky = voteRound == 1 ? view().index.declared(day: day, by: b) : nil
            let t = botVote(b, pool: pool, sticky: sticky)
            if t != b { lockedVotes[b] = t }
        }
    }

    private mutating func resolveVotes(humanVote: PlayerID?) {
        var votes = lockedVotes
        if let me = human, let humanVote, players[me].alive { votes[me] = humanVote }
        // A living human has just read the discussion; a spectator sees it together with the votes.
        if voteRound == 1, humanAlive { feed = [] }
        var counts = Array(repeating: 0, count: players.count)
        var result = voteRound == 2 ? outcome?.vote ?? VoteOutcome() : VoteOutcome()
        result.rounds.append([])
        for voter in rng.shuffled(Array(votes.keys).sorted()) {
            let target = votes[voter]!
            counts[target] += 1
            result.rounds[result.rounds.count - 1].append(Ballot(voter: voter, target: target))
            record.append(.vote(day: day, round: voteRound, voter: voter, target: target))
            feed.append(Beat(kind: .vote, speaker: voter, target: target, text: "\(players[voter].name) votes for \(players[target].name)."))
        }
        let pool = candidates.isEmpty ? alive : candidates
        let most = pool.map { counts[$0] }.max() ?? 0
        let tied = pool.filter { counts[$0] == most }
        if voteRound == 1, most == votes.count, votes.count > 2 { tally.unanimous += 1 }

        if tied.count > 1, voteRound == 1 {
            voteRound = 2
            candidates = tied
            result.tied = tied
            outcome = .vote(result)
            let list = tied.map { players[$0].name }.joined(separator: " and ")
            feed.append(Beat(kind: .host, text: Host.tie(list)))
            lockVotes()
            if let me = human, players[me].alive, !tied.contains(me) {
                phase = .voting
            } else {
                resolveVotes(humanVote: nil)
            }
            return
        }
        var out = tied[0]
        if tied.count > 1 {
            out = rng.pick(tied)
            feed.append(Beat(kind: .host, text: Host.fate))
            result.byFate = true
        }
        banish(out)
        result.banished = out
        result.role = finale ? nil : players[out].role
        result.winner = winner
        outcome = .vote(result)
    }

    private mutating func banish(_ p: PlayerID) {
        players[p].alive = false
        players[p].fate = .banished
        players[p].fateDay = day
        let role = players[p].role
        record.append(.banished(day: day, player: p, role: finale ? nil : role))
        if finale {
            feed.append(Beat(kind: .banish, target: p, text: "\(players[p].name) is banished and leaves without a word."))
        } else {
            let line = role == .traitor ? "\"I am a traitor.\"" : "\"I am a faithful.\""
            feed.append(Beat(kind: .banish, target: p, text: "\(players[p].name) is banished. \(line)", role: role))
        }
        if role == .traitor, !aliveTraitors.isEmpty {
            // Did the partners left at the table have their names on this?
            tally.partnerDown += aliveTraitors.count
            for case .vote(day, voteRound, let voter, p) in log where aliveTraitors.contains(voter) { tally.busVotes += 1 }
        }
        if tally.firstBanishedTraitor == nil { tally.firstBanishedTraitor = role == .traitor }
        if role == .traitor { tally.banishedTraitors += 1 } else { tally.banishedFaithful += 1 }
        tally.roundTables += 1
        snapshot()
        if !finale { checkEnd() }
        phase = .voteReveal
    }

    private mutating func snapshot() {
        let v = view()
        var ofHuman = Array(repeating: -1.0, count: players.count)
        var whyHuman: [Chip?] = Array(repeating: nil, count: players.count)
        if let me = human {
            for b in aliveBots where players[b].role == .faithful {
                guard let held = mind(for: b).opinion(of: me, at: v) else { continue }
                ofHuman[b] = held.suspicion
                whyHuman[b] = held.why
            }
        }
        history.append(DaySnapshot(day: day, publicSuspicion: publicSuspicion(), ofHuman: ofHuman, whyHuman: whyHuman))
    }

    private mutating func checkEnd() {
        guard let won = verdict else { return }
        winner = won
        feed.append(Beat(kind: .host, text: won == .faithful ? Host.allBanished : Host.outvoted))
    }

    private mutating func afterBanishment() {
        if winner != nil {
            phase = .gameOver
        } else if finale {
            if alive.count <= 2 {
                finishFinale()
                phase = .gameOver
            } else {
                feed = []
                round(.openFloor, 2)
                enterFinaleChoice()
            }
        } else {
            enterNight()
        }
    }

    // MARK: - Finale

    private mutating func enterFinaleChoice() {
        lockedFinale = [:]
        let v = view()
        for b in aliveBots {
            lockedFinale[b] = ask(b) { $0.endTheGame(at: v) }
        }
        if humanAlive {
            feed.append(Beat(kind: .host, text: Host.finaleChoice))
            phase = .finaleChoice
        } else {
            resolveFinale(humanEnd: nil)
        }
    }

    private mutating func resolveFinale(humanEnd: Bool?) {
        var votes = lockedFinale
        if let me = human, let humanEnd, players[me].alive { votes[me] = humanEnd }
        feed = []
        for voter in votes.keys.sorted() {
            let end = votes[voter]!
            record.append(.finaleVote(day: day, voter: voter, end: end))
            feed.append(Beat(kind: .vote, speaker: voter, text: "\(players[voter].name): \(end ? "End the game." : "Banish again.")"))
        }
        if votes.values.allSatisfy({ $0 }) {
            finishFinale()
        } else {
            feed.append(Beat(kind: .host, text: Host.notUnanimous))
        }
        phase = .finaleReveal
    }

    private mutating func finishFinale() {
        winner = aliveTraitors.isEmpty ? .faithful : .traitor
        let left = aliveTraitors.map { players[$0].name }.joined(separator: " and ")
        feed.append(Beat(kind: .host, text: winner == .faithful ? Host.endFaithful : Host.endTraitors(left, count: aliveTraitors.count)))
    }

    // MARK: - Night

    private mutating func enterNight() {
        feed = [Beat(kind: .narration, text: Host.nightfall)]
        nightChoice = .none
        recruiter = nil
        partnerAdvice = nil
        let ts = aliveTraitors
        let humanOnTeam = humanAlive && humanIsTraitor
        if !traitorsMayAct {
            // The company won the day: nobody leaves their room.
            tally.quietNights += 1
            if humanOnTeam {
                feed.append(Beat(kind: .secret, text: "The company made its goal. The turret stays dark tonight."))
            }
        } else if recruitNight(left: alive.count) {
            recruiter = ts[0]
            if ts[0] == human {
                nightChoice = .recruit
                feed.append(Beat(kind: .secret, text: "You are the last traitor. Choose someone to recruit. There is no murder tonight."))
            } else {
                let v = view()
                let pick = ask(ts[0]) { $0.recruit(at: v) }
                partnerAdvice = pick
                if pick == human, humanAlive {
                    nightChoice = .offer
                    feed.append(Beat(kind: .secret, text: "A cloaked figure is waiting in your room. It is \(players[ts[0]].name). \"Join me as a traitor, or you will not see the morning.\""))
                }
            }
        } else if !ts.isEmpty {
            let lead = ts.first { $0 != human } ?? ts[0]
            if lead != human {
                let v = view()
                partnerAdvice = ask(lead) { $0.murder(at: v) }
            }
            if humanOnTeam {
                nightChoice = .murder
                var text = "The traitors meet in the turret. Choose who to murder."
                if let advice = partnerAdvice { text += " \(players[lead].name) suggests \(players[advice].name)." }
                feed.append(Beat(kind: .secret, text: text))
            }
        }
        phase = .night
        if human == nil { resolveNight(.proceed) }
    }

    /// `answer` has already been checked against what the night asks of the human.
    private mutating func resolveNight(_ answer: Answer) {
        tally.nights += 1
        var victim: PlayerID?
        var recruitNight = false
        var secret: Beat?

        if let r = recruiter {
            recruitNight = true
            recruitmentUsed = true
            var recruit = partnerAdvice
            switch answer {
            case .recruit(let pick): recruit = pick
            case .offer(let accept):
                recruit = accept ? human : nil
                if !accept { victim = human }
            default: break
            }
            if let recruit {
                players[recruit].role = .traitor
                players[recruit].wasRecruited = true
                tally.recruited = true
                if recruit == human {
                    secret = Beat(kind: .secret, text: "You are a traitor now. \(players[r].name) is your partner.")
                } else if r == human {
                    secret = Beat(kind: .secret, text: "\(players[recruit].name) accepted. You have a partner again.")
                }
            }
        } else if traitorsMayAct, !aliveTraitors.isEmpty {
            victim = partnerAdvice
            if case .murder(let pick) = answer { victim = pick }
        }

        if let victim {
            players[victim].alive = false
            players[victim].fate = .murdered
            players[victim].fateDay = day
            tally.murders += 1
        }
        record.append(.night(day: day, victim: victim, recruitNight: recruitNight))

        morning = []
        if let victim {
            let text = victim == human
                ? "You do not come down to breakfast. You were murdered in the night."
                : "\(players[victim].name) does not come down to breakfast. Murdered in the night."
            morning.append(Beat(kind: .murder, target: victim, text: text, role: .faithful))
        } else {
            morning.append(Beat(kind: .host, text: traitorsMayAct ? Host.noMurder : Host.quietNight))
        }
        var cleared: [PlayerID] = []
        if traitorsMayAct, !finale, let run = mission, run.done {
            // The traitors had their night because the gold came up short. Whoever was watched all
            // day had no chance to see to that.
            cleared = Array(run.neverAlone.filter { players[$0].alive }.prefix(3))
            let watched = cleared.map { players[$0].name }
            if !watched.isEmpty {
                let list = watched.count > 1 ? watched.dropLast().joined(separator: ", ") + " and " + watched.last! : watched[0]
                morning.append(Beat(kind: .narration, text: "The company fell short yesterday, and somebody may have seen to it. \(list) \(watched.count > 1 ? "were" : "was") never out of sight. Who was?"))
            }
        }
        if let secret { morning.append(secret) }

        if verdict == .traitor {
            winner = .traitor
            morning.append(Beat(kind: .host, text: Host.outvoted))
        }
        let told = MorningOutcome(victim: victim, traitorsHadTheNight: traitorsMayAct, recruitNight: recruitNight, neverOutOfSight: cleared)
        nightChoice = .none
        day += 1
        startDay()
        outcome = .morning(told)
    }
}
