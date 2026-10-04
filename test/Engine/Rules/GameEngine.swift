import Foundation

/// The whole game: state plus the rules that move it forward. `advance` runs until the next
/// point where the human has to decide something (or simply tap to continue).
struct Game: Codable {
    static let shieldInPlay = 0.6

    /// Chance a bot traitor pulls off the side quest once they go for it.
    static func questOdds(_ p: Personality) -> Double {
        clamp(0.70 + 0.16 * p.skill + 0.13 * p.deceit, 0.5, 0.95)
    }

    var seed: UInt64
    var rng: SeededRNG
    var players: [Player]
    var minds: [BotMind]
    /// Seat of the human player. Nil in headless simulations, where all eight are bots.
    var human: PlayerID?
    var options = GameOptions()

    var day = 1
    var phase: Phase = .roleReveal
    var log: [PublicEvent] = []
    var feed: [Beat] = []
    var morning: [Beat] = []
    var heat: [Double]

    var missionDeck: [MissionKind]
    var mission: MissionRun?
    var report: MissionReport?
    var questBy: PlayerID?
    var shield: PlayerID?
    var shieldClaims: [PlayerID] = []
    var pot = 0

    var recruitmentUsed = false
    var finale = false
    var tableStep = 0
    var voteRound = 1
    var candidates: [PlayerID] = []
    var lockedVotes: [PlayerID: PlayerID] = [:]
    var lockedFinale: [PlayerID: Bool] = [:]
    var nightChoice: NightChoice = .none
    var recruiter: PlayerID?
    var partnerAdvice: PlayerID?
    var winner: Role?
    var history: [DaySnapshot] = []
    var tally = Tally()
    /// Private ledger of everything seen in missions and by whom. Bots only ever get their own share.
    var sightings: [Sighting] = []
    /// What the traitors have agreed for the current Round Table.
    var teamPlan: TeamPlan?

    // MARK: - Setup

    init(seed: UInt64, humanName: String?, preference: RolePreference = .random, options: GameOptions = GameOptions()) {
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

    var alive: [PlayerID] { players.filter(\.alive).map(\.id) }
    var aliveTraitors: [PlayerID] { players.filter { $0.alive && $0.role == .traitor }.map(\.id) }
    var aliveFaithful: [PlayerID] { players.filter { $0.alive && $0.role == .faithful }.map(\.id) }
    var team: [PlayerID] { players.filter { $0.role == .traitor }.map(\.id) }
    var aliveBots: [PlayerID] { alive.filter { $0 != human } }
    var humanAlive: Bool { human.map { players[$0].alive } ?? false }
    var humanIsTraitor: Bool { human.map { players[$0].role == .traitor } ?? false }
    var names: [String] { players.map(\.name) }

    /// Role as publicly known: shown at a banishment, or faithful for anyone murdered.
    func revealedRole(_ p: PlayerID) -> Role? {
        for event in log {
            if case .banished(_, let who, let role) = event, who == p { return role }
            if case .night(_, let victim, _) = event, victim == p { return .faithful }
        }
        return nil
    }

    func view() -> TableView {
        let seats = players.map {
            Seat(id: $0.id, name: $0.name, alive: $0.alive, revealed: revealedRole($0.id), charisma: $0.personality.charisma)
        }
        return TableView(day: day, seats: seats, log: log, heat: heat)
    }

    func publicSuspicion() -> [Double] {
        TraitorBrain.publicBelief(view()).marginals(count: players.count)
    }

    /// Evidence the human can cite about a player, including what they saw in today's mission.
    func notebook(about p: PlayerID, suspicious: Bool) -> [Chip] {
        let mine = human.map { h in minds[h].seen.filter { $0.day == day } } ?? []
        return Chips.about(p, view: view(), noticed: nil, suspicious: suspicious, sightings: mine)
    }

    /// The ways the human can answer whoever last pointed at them. Empty when nobody has.
    func defenceOptions() -> [DefenceOption] {
        guard let me = human, players[me].alive, phase == .roundTable else { return [] }
        let v = view()
        guard let accuser = v.index.accuser(of: me, day: day) else { return [] }
        let belief = Inference.compute(view: v, observer: FaithfulBrain.observer(minds[me], players[me].personality))
        return Defences.candidates(me: me, accuser: accuser, view: v, belief: belief, mind: minds[me], p: players[me].personality)
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

    /// Who the human may pick right now (vote, murder, recruit).
    var choices: [PlayerID] {
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

    // MARK: - Advance

    mutating func advance(_ input: HumanInput) {
        switch phase {
        case .roleReveal:
            startDay()
        case .breakfast:
            if winner != nil { phase = .gameOver } else { beginBrief() }
        case .missionBrief:
            beginMission()
        case .mission:
            guard var run = mission else { break }
            if case .mission(let result) = input {
                run.resolve(human: result)
            } else if run.human == nil {
                // A human who is out only watches, so anything moves the day on.
                run.resolve(human: nil)
            } else {
                break
            }
            mission = run
            finishMission()
        case .missionResult:
            enterRoundTable()
        case .roundTable:
            if case .say(let kind, let target, let chip) = input { humanSay(kind, target, chip) }
            if case .rebut(let choice) = input { humanRebut(choice) }
        case .voting:
            if case .vote(let target) = input, choices.contains(target) { resolveVotes(humanVote: target) }
        case .voteReveal:
            afterBanishment()
        case .night:
            resolveNight(input)
        case .finaleChoice:
            if case .finale(let end) = input { resolveFinale(humanEnd: end) }
        case .finaleReveal:
            if winner != nil { phase = .gameOver } else { feed = []; enterVoting() }
        case .gameOver:
            break
        }
    }

    /// Plays a game with no human input to the end. Only valid when no living human is seated.
    mutating func runToEnd(limit: Int = 500) {
        var steps = 0
        while phase != .gameOver, steps < limit {
            advance(.next)
            steps += 1
        }
    }

    // MARK: - Day

    private mutating func startDay() {
        heat = Array(repeating: 0, count: players.count)
        shieldClaims = []
        questBy = nil
        shield = nil
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
        let recruitTonight = ts.count == 1 && !recruitmentUsed && alive.count - 1 >= 5
        var runner: PlayerID?
        var whisper: String?
        let humanOnTeam = humanAlive && humanIsTraitor

        if recruitTonight {
            if humanOnTeam { whisper = "You are alone now. Tonight you recruit, so there is no need for the side quest today." }
        } else if options.randomTraitors {
            runner = botTs.isEmpty || !rng.chance(0.5) ? nil : rng.pick(botTs)
        } else if !botTs.isEmpty {
            let pub = TraitorBrain.publicBelief(v)
            let cand = botTs.min { pub.marginal($0) < pub.marginal($1) }!
            let mustKill = aliveFaithful.count - 2 <= ts.count
            var go = TraitorBrain.willAttempt(view: v, me: cand, team: team, mind: &minds[cand], p: players[cand].personality,
                                              mustKill: mustKill, known: known())
            if humanOnTeam, let me = human {
                if pub.marginal(cand) > pub.marginal(me) + 0.05 {
                    go = false
                    whisper = "\(players[cand].name) whispers: \"Too many eyes on me. The side quest has to be you today.\""
                } else if go {
                    whisper = "\(players[cand].name) whispers: \"Leave the side quest to me. Keep your hands clean.\""
                } else {
                    whisper = "\(players[cand].name) whispers: \"I'm lying low today. If you want a murder tonight, it's on you.\""
                }
            }
            if go { runner = cand }
        } else if humanOnTeam {
            whisper = "You are the only traitor left. If you want a murder tonight, the side quest is yours to do."
        }

        let cautious = runner.map { 0.2 + 0.6 * (1 - players[$0].personality.deceit) } ?? 0
        // With fewer left to watch, the task is longer.
        let questSteps = alive.count <= 6 ? 2 : 1
        let odds = (runner.map { Self.questOdds(players[$0].personality) } ?? 0) * (questSteps > 1 ? 0.88 : 1)
        mission = MissionRun(kind: kind, day: day, alive: alive, human: humanAlive ? human : nil, traitors: ts,
                             runner: runner, caution: cautious, questOdds: odds, questOpen: !recruitTonight,
                             traits: players.map(\.personality), quirkSeed: seed, rng: rng.fork(),
                             questSteps: questSteps)
        feed = [Beat(kind: .narration, text: kind.brief)]
        if humanOnTeam {
            if !recruitTonight {
                feed.append(Beat(kind: .secret, text: "The Shadow's Task. \(kind.questText(steps: questSteps)) Complete it and the traitors may murder tonight."))
            }
            if let whisper { feed.append(Beat(kind: .secret, text: whisper)) }
        }
        phase = .missionBrief
    }

    private mutating func beginMission() {
        guard var run = mission else { return }
        run.plan()
        mission = run
        if human == nil {
            run.resolve(human: options.arena ? ArenaRunner.play(run) : nil)
            mission = run
            finishMission()
        } else {
            // A human who is out still gets to watch the others play.
            phase = .mission
        }
    }

    private mutating func finishMission() {
        guard let run = mission else { return }
        let r = run.report(names: names)
        report = r
        log.append(.mission(r))
        pot += r.potEarned
        questBy = run.questCompletedBy
        if run.runnerAttempt || (run.questCompletedBy != nil && run.questCompletedBy == human) { tally.questAttempts += 1 }
        if questBy != nil { tally.questsDone += 1 }

        // Everyone takes away what they saw, and knows who was looking at them.
        sightings += run.sightings
        for s in run.sightings {
            minds[s.subject].exposed.append(s)
            for w in s.witnesses.seats { minds[w].seen.append(s) }
        }

        // Each bot only registers the slips it happened to spot.
        for b in aliveBots {
            let perception = players[b].personality.perception
            for (u, unit) in r.units.enumerated() where unit.anomalous {
                if unit.players.contains(b) || minds[b].rng.chance(0.5 + 0.5 * perception) {
                    minds[b].noticed.insert(r.day * 100 + u)
                }
            }
        }

        let ranked = alive.sorted { (r.scores[$0] ?? 0, Double($0)) > (r.scores[$1] ?? 0, Double($1)) }
        let top = Array(ranked.prefix(3))
        // The shield is not in play every day, which keeps a quiet night ambiguous without making murders rare.
        shield = top.isEmpty || !rng.chance(Self.shieldInPlay) ? nil : rng.pick(top)

        feed = [Beat(kind: .result, text: "\(r.kind.title): \(r.potEarned) added to the pot.")]
        feed += r.lines.map { Beat(kind: .result, text: $0) }
        if humanAlive, let me = human {
            let v = view()
            for s in run.sightings where s.witnesses.has(me) {
                feed.append(Beat(kind: .secret, target: s.subject, text: Dialogue.noticed(s, view: v)))
            }
        }
        if humanAlive, shield == human {
            feed.append(Beat(kind: .secret, text: "You were among the best today and hold the shield. You cannot be murdered tonight. Nobody else knows."))
        }
        if humanAlive, humanIsTraitor {
            let recruitTonight = aliveTraitors.count == 1 && !recruitmentUsed && alive.count - 1 >= 5
            if !recruitTonight {
                if let by = questBy {
                    let who = by == human ? "You" : players[by].name
                    feed.append(Beat(kind: .secret, text: "\(who) completed the side quest. The traitors may murder tonight."))
                } else {
                    feed.append(Beat(kind: .secret, text: "The side quest was not completed. There will be no murder tonight."))
                }
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
        if tally.roundTables == 0, !options.randomFaithful {
            let v = view()
            var tops: Set<PlayerID> = []
            for b in aliveBots where players[b].role == .faithful {
                let belief = Inference.compute(view: v, observer: FaithfulBrain.observer(minds[b], players[b].personality))
                if let t = FaithfulBrain.topSuspect(v, belief, me: b) { tops.insert(t) }
            }
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
        guard !aliveTraitors.isEmpty, !options.randomTraitors else { teamPlan = nil; return }
        if let old = teamPlan, old.day == day, old.asOf == log.count { return }
        var plan = TeamPlanner.plan(view: view(), team: team, known: known(), seed: seed)
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
        let p = players[b].personality
        if players[b].role == .traitor {
            if options.randomTraitors { return nil }
            return TraitorBrain.speak(view: v, me: b, team: team, mind: &minds[b], p: p, replyTo: replyTo,
                                      plan: teamPlan, phase: phase, known: known())
        }
        if options.randomFaithful { return nil }
        return FaithfulBrain.speak(view: v, mind: &minds[b], p: p, replyTo: replyTo, phase: phase)
    }

    private mutating func botVote(_ b: PlayerID, pool: [PlayerID], sticky: PlayerID?) -> PlayerID {
        let v = view()
        let p = players[b].personality
        let random = players[b].role == .traitor ? options.randomTraitors : options.randomFaithful
        if random {
            let others = pool.filter { $0 != b }
            return others.isEmpty ? b : minds[b].rng.pick(others)
        }
        if players[b].role == .traitor {
            return TraitorBrain.intent(view: v, me: b, team: team, mind: &minds[b], p: p, candidates: pool, sticky: sticky,
                                       plan: teamPlan, known: known())
        }
        return FaithfulBrain.intent(view: v, mind: &minds[b], p: p, candidates: pool, sticky: sticky)
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
        guard let chip, chip.isTestimony, let claim = chip.sight else { return }
        for c in aliveBots where c != speaker && c != chip.subject {
            // A traitor does not expose a partner's lie.
            if players[c].role == .traitor, players[speaker].role == .traitor { continue }
            if players[c].role == .traitor ? options.randomTraitors : options.randomFaithful { continue }
            guard let mine = minds[c].seen.first(where: { $0.subject == chip.subject && $0.day == chip.day && $0.clashes(with: claim) })
            else { continue }
            tally.challenges += 1
            if invented(chip, by: speaker) { tally.liesCaught += 1 }
            say(c, Intent(kind: .challenge, target: speaker,
                          chip: Chip(kind: .caughtLie, subject: speaker, day: chip.day, other: chip.subject, sight: mine.kind, strength: 1.3)))
            if speaker != human, players[speaker].alive, let reply = botIntent(speaker, replyTo: c) { say(speaker, reply) }
            return
        }
    }

    private mutating func apply(_ s: Statement, view v: TableView, credibility: Double = 0) {
        log.append(.statement(s))
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
                minds[b].gut[s.speaker] = max(-1.5, minds[b].gut[s.speaker] - Defences.soothe(credibility))
            }
        }
        if s.kind == .vouch, players[s.speaker].role == .traitor, teamPlan?.vouched.contains(s.speaker) == false {
            teamPlan?.vouched.append(s.speaker)
        }
        guard let t = s.target else { return }
        switch s.kind {
        case .accuse, .callout, .challenge:
            if s.kind == .callout { tally.callouts += 1 }
            heat[t] += (s.kind == .challenge ? 1.2 : s.kind == .callout ? 0.8 : 1) * weight
            // Being accused breeds a grudge in proportion to stubbornness.
            if t != human {
                let g = minds[t].gut[s.speaker] + 0.35 * players[t].personality.stubbornness
                minds[t].gut[s.speaker] = min(g, 1.5)
            }
        case .defend: heat[t] = max(0, heat[t] - 0.6 * weight)
        case .vouch: heat[t] = max(0, heat[t] - 0.9 * weight)
        case .doubt: heat[t] += 0.25 * weight
        case .selfDefend: heat[t] += 0.4 * weight
        case .answer, .declare: heat[t] += 0.5 * weight
        default: break
        }
        // Pointing at a mission slip makes others see it who had missed it.
        if let key = s.chip?.noticeKey {
            let p = clamp(0.45 + 0.35 * v.standing(s.speaker), 0, 0.95)
            for b in aliveBots where b != s.speaker && !minds[b].noticed.contains(key) {
                if minds[b].rng.chance(p) { minds[b].noticed.insert(key) }
            }
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
            log.append(.statement(Statement(day: day, speaker: me, kind: .question, target: t, chip: nil, text: text)))
            feed.append(Beat(kind: .speech, speaker: me, target: t, text: text))
            let name = botVote(t, pool: alive, sticky: view().index.declared(day: day, by: t))
            let noticed: Set<Int>? = players[t].role == .traitor ? nil : minds[t].noticed
            say(t, Intent(kind: .answer, target: name, chip: FaithfulBrain.bestChip(name, view(), noticed, suspicious: true)))
        case .claimShield:
            shieldClaims.append(me)
            let text = Dialogue.line(kind: .claimShield, target: nil, chip: nil, voice: .plain, view: v, rng: &rng)
            log.append(.statement(Statement(day: day, speaker: me, kind: .claimShield, target: nil, chip: nil, text: text)))
            feed.append(Beat(kind: .speech, speaker: me, text: text))
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
        for voter in rng.shuffled(Array(votes.keys).sorted()) {
            let target = votes[voter]!
            counts[target] += 1
            log.append(.vote(day: day, round: voteRound, voter: voter, target: target))
            feed.append(Beat(kind: .vote, speaker: voter, target: target, text: "\(players[voter].name) votes for \(players[target].name)."))
        }
        let pool = candidates.isEmpty ? alive : candidates
        let most = pool.map { counts[$0] }.max() ?? 0
        let tied = pool.filter { counts[$0] == most }
        if voteRound == 1, most == votes.count, votes.count > 2 { tally.unanimous += 1 }

        if tied.count > 1, voteRound == 1 {
            voteRound = 2
            candidates = tied
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
        }
        banish(out)
    }

    private mutating func banish(_ p: PlayerID) {
        players[p].alive = false
        players[p].fate = .banished
        players[p].fateDay = day
        let role = players[p].role
        log.append(.banished(day: day, player: p, role: finale ? nil : role))
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
                let belief = Inference.compute(view: v, observer: FaithfulBrain.observer(minds[b], players[b].personality))
                ofHuman[b] = belief.marginal(me)
                let chip = FaithfulBrain.bestChip(me, v, minds[b].noticed, suspicious: true,
                                                  sightings: minds[b].seen.filter { $0.day == day }, belief: belief)
                if chip?.kind != .gut { whyHuman[b] = chip }
            }
        }
        history.append(DaySnapshot(day: day, publicSuspicion: publicSuspicion(), ofHuman: ofHuman, whyHuman: whyHuman))
    }

    private mutating func checkEnd() {
        if aliveTraitors.isEmpty {
            winner = .faithful
            feed.append(Beat(kind: .host, text: Host.allBanished))
        } else if aliveTraitors.count >= aliveFaithful.count {
            winner = .traitor
            feed.append(Beat(kind: .host, text: Host.outvoted))
        }
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
            let random = players[b].role == .traitor ? options.randomTraitors : options.randomFaithful
            if random {
                lockedFinale[b] = minds[b].rng.chance(0.5)
            } else if players[b].role == .traitor {
                lockedFinale[b] = TraitorBrain.finaleEnd(view: v)
            } else {
                lockedFinale[b] = FaithfulBrain.finaleEnd(view: v, mind: minds[b], p: players[b].personality)
            }
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
            log.append(.finaleVote(day: day, voter: voter, end: end))
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
        if ts.count == 1, !recruitmentUsed, alive.count >= 5 {
            recruiter = ts[0]
            if ts[0] == human {
                nightChoice = .recruit
                feed.append(Beat(kind: .secret, text: "You are the last traitor. Choose someone to recruit. There is no murder tonight."))
            } else {
                var mind = minds[ts[0]]
                let others = alive.filter { $0 != ts[0] }
                var pick = mind.rng.pick(others)
                if !options.randomTraitors, let chosen = TraitorBrain.recruit(view: view(), me: ts[0], mind: &mind) {
                    pick = chosen
                }
                minds[ts[0]] = mind
                partnerAdvice = pick
                if pick == human, humanAlive {
                    nightChoice = .offer
                    feed.append(Beat(kind: .secret, text: "A cloaked figure is waiting in your room. It is \(players[ts[0]].name). \"Join me as a traitor, or you will not see the morning.\""))
                }
            }
        } else if questBy != nil, !ts.isEmpty {
            let lead = ts.first { $0 != human } ?? ts[0]
            if lead != human {
                var mind = minds[lead]
                if options.randomTraitors {
                    partnerAdvice = mind.rng.pick(aliveFaithful)
                } else {
                    partnerAdvice = TraitorBrain.murder(view: view(), me: lead, team: team, mind: &mind,
                                                        p: players[lead].personality, shieldClaims: shieldClaims, known: known())
                }
                minds[lead] = mind
            }
            if humanOnTeam {
                nightChoice = .murder
                var text = "The traitors meet in the turret. Choose who to murder."
                if let advice = partnerAdvice { text += " \(players[lead].name) suggests \(players[advice].name)." }
                feed.append(Beat(kind: .secret, text: text))
            }
        } else if humanOnTeam {
            feed.append(Beat(kind: .secret, text: "The side quest was not completed. The traitors cannot murder tonight."))
        }
        phase = .night
        if human == nil { resolveNight(.next) }
    }

    private mutating func resolveNight(_ input: HumanInput) {
        tally.nights += 1
        var victim: PlayerID?
        var recruitNight = false
        var secret: Beat?

        if let r = recruiter {
            recruitNight = true
            recruitmentUsed = true
            var recruit: PlayerID?
            switch (nightChoice, input) {
            case (.recruit, .recruit(let pick)) where choices.contains(pick):
                recruit = pick
            case (.recruit, _):
                tally.nights -= 1
                return
            case (.offer, .recruitAnswer(let yes)):
                if yes { recruit = human } else { victim = human }
            case (.offer, _):
                tally.nights -= 1
                return
            default:
                recruit = partnerAdvice
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
        } else if questBy != nil, !aliveTraitors.isEmpty {
            var target = partnerAdvice
            if nightChoice == .murder {
                guard case .murder(let pick) = input, choices.contains(pick) else {
                    tally.nights -= 1
                    return
                }
                target = pick
            }
            if let target {
                if target == shield {
                    tally.shieldBlocks += 1
                    if humanAlive, humanIsTraitor {
                        secret = Beat(kind: .secret, text: "\(players[target].name) held the shield. The murder failed.")
                    }
                } else {
                    victim = target
                }
            }
        }

        if let victim {
            players[victim].alive = false
            players[victim].fate = .murdered
            players[victim].fateDay = day
            tally.murders += 1
        }
        log.append(.night(day: day, victim: victim, recruitNight: recruitNight))

        morning = []
        if let victim {
            let text = victim == human
                ? "You do not come down to breakfast. You were murdered in the night."
                : "\(players[victim].name) does not come down to breakfast. Murdered in the night."
            morning.append(Beat(kind: .murder, target: victim, text: text, role: .faithful))
        } else {
            morning.append(Beat(kind: .host, text: Host.noMurder))
            if !recruitNight, questBy == nil, let run = mission, run.questOpen {
                // The shadow's task went undone, and whoever was watched all day could not have tried it.
                let watched = run.neverAlone.filter { players[$0].alive }.prefix(3).map { players[$0].name }
                var text = "Word at breakfast is that the shadow's task went undone yesterday."
                if !watched.isEmpty {
                    let list = watched.count > 1 ? watched.dropLast().joined(separator: ", ") + " and " + watched.last! : watched[0]
                    text += " \(list) \(watched.count > 1 ? "were" : "was") never out of sight. Who was?"
                }
                morning.append(Beat(kind: .narration, text: text))
            }
        }
        if let secret { morning.append(secret) }

        if aliveTraitors.count >= aliveFaithful.count {
            winner = .traitor
            morning.append(Beat(kind: .host, text: Host.outvoted))
        }
        nightChoice = .none
        day += 1
        startDay()
    }
}
