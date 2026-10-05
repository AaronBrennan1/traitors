import SwiftUI

/// Routes the current phase to its screen, under a persistent header.
struct GameView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    var onExit: () -> Void
    @State private var showCast = false
    @State private var stage = Stage()
    /// The scene the title card last lifted on.
    @State private var lifted: String?

    var body: some View {
        if let game = store.game {
            let place = Place.of(game)
            let key = "\(game.seed)-\(Place.sceneKey(game))"
            let card = Place.card(game)
            // Worked out from the game itself, so the card is already down on the frame the scene changes.
            let down = card != nil && lifted != key && !Senses.settledCeremonies
            ZStack {
                CastleBackdrop(place: place, paused: game.phase == .mission)
                VStack(spacing: 0) {
                    // A mini-game takes the whole screen; its own pause menu is the way out.
                    if game.phase != .roleReveal, game.phase != .gameOver, game.phase != .mission {
                        HeaderBar(game: game, onCast: { showCast = true }, onExit: onExit)
                    }
                    content(game)
                }
                .environment(\.curtainUp, !down)
                if let card {
                    PhaseCurtain(title: card.title, subtitle: card.subtitle)
                        .opacity(down ? 1 : 0)
                        .allowsHitTesting(down)
                        .animation(down ? nil : .easeOut(duration: 0.7), value: down)
                        .onTapGesture { lifted = key }
                        .accessibilityHidden(!down)
                }
            }
            .environment(stage)
            .sheet(isPresented: $showCast) { CastSheet() }
            .task(id: key) {
                guard down else { lifted = key; return }
                Cue.curtain.play()
                try? await Task.sleep(for: .seconds(1.9))
                if !Task.isCancelled { lifted = key }
            }
            .task(id: "\(place.rawValue)-\(game.phase == .mission)") {
                // The gauntlet has a pulse of its own in place of the room.
                Soundscape.shared.setBed(game.phase == .mission ? .gauntlet : place.bed, level: game.phase == .mission ? 0.8 : 1)
            }
            .onChange(of: game.phase) { stage.clear() }
            .onChange(of: scenePhase) {
                if scenePhase == .active { Soundscape.shared.resume() } else { Soundscape.shared.suspend() }
            }
            .onChange(of: store.settings.sound) { Soundscape.shared.resume() }
            .onAppear { Soundscape.shared.warmUp() }
            .onDisappear { Soundscape.shared.setBed(nil) }
        }
    }

    @ViewBuilder
    private func content(_ game: Game) -> some View {
        switch game.phase {
        case .roleReveal:
            RoleCeremony()
        case .missionBrief:
            MissionBriefView().id("brief-\(game.day)")
        case .breakfast:
            BreakfastCeremony().id("breakfast-\(game.day)")
        case .voteReveal:
            VoteCeremony().id(voteID(game))
        case .voting where game.voteRound == 2:
            // The first round is turned over before anyone votes again, and the scene carries on from there.
            VoteCeremony().id(voteID(game))
        case .finaleReveal:
            SceneView().id("\(game.phase.rawValue)-\(game.day)-\(game.alive.count)")
        case .mission, .missionResult:
            MissionView(onExit: onExit).id("mission-\(game.day)")
        case .roundTable, .voting, .finaleChoice:
            TableScreen().id("table-\(game.day)-\(game.alive.count)")
        case .night:
            NightView().id("night-\(game.day)")
        case .gameOver:
            GameOverView(onExit: onExit)
        }
    }

    /// The same for a revote and the reveal that follows it; different for each banishment of a finale.
    private func voteID(_ game: Game) -> String {
        "vote-\(game.day)-\(game.tally.roundTables - (game.phase == .voteReveal ? 1 : 0))"
    }
}

struct HeaderBar: View {
    @Environment(GameStore.self) private var store
    let game: Game
    var onCast: () -> Void
    var onExit: () -> Void
    @State private var confirmQuit = false

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button { confirmQuit = true } label: {
                    Image(systemName: "chevron.left").font(.headline).foregroundStyle(Palette.muted)
                        .frame(width: 36, height: 36)
                }
                Spacer()
                VStack(spacing: 1) {
                    Text(game.finale ? "The Finale" : "Day \(game.day)")
                        .font(.serif(.headline, weight: .bold)).foregroundStyle(Palette.parchment)
                    Text(phaseName).font(.serif(.caption)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Text("€\(game.pot.formatted())")
                    .font(.serif(.subheadline, weight: .semibold)).foregroundStyle(Palette.gold)
                    .frame(minWidth: 36, alignment: .trailing)
            }
            Button(action: onCast) {
                HStack(spacing: 5) {
                    ForEach(game.players.indices, id: \.self) { i in
                        // Don't show tonight's banishment in the header before the votes have played out.
                        // Avatar and roleShown both hold back anything the scene on screen has not told yet.
                        Avatar(player: game.players[i], size: 29, role: store.roleShown(i))
                    }
                    Spacer(minLength: 4)
                    roleTag
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .background(Palette.ink.opacity(0.55))
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
        .confirmationDialog("Leave the castle?", isPresented: $confirmQuit, titleVisibility: .visible) {
            Button("Save and return to title") { onExit() }
            Button("Abandon this game", role: .destructive) { store.abandon(); onExit() }
            Button("Stay", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var roleTag: some View {
        if let me = game.human {
            let role = game.players[me].role
            let dead = store.spectating
            Text(dead ? "WATCHING" : role == .traitor ? "TRAITOR" : "FAITHFUL")
                .font(.serif(.caption2, weight: .heavy))
                .tracking(1)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(dead ? Palette.muted : Palette.role(role))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .overlay(Capsule().stroke((dead ? Palette.muted : Palette.role(role)).opacity(0.6)))
        }
    }

    private var phaseName: String {
        switch game.phase {
        case .roleReveal: return ""
        case .breakfast: return "Breakfast"
        case .missionBrief, .mission, .missionResult: return game.mission?.kind.title ?? "Mission"
        case .roundTable: return "Round Table"
        case .voting: return "The Vote"
        case .voteReveal: return "Banishment"
        case .night: return "Night"
        case .finaleChoice, .finaleReveal: return "Fire of Truth"
        case .gameOver: return ""
        }
    }
}

/// A scene that plays out as a list of beats and waits for a tap to move on.
struct SceneView: View {
    @Environment(GameStore.self) private var store
    @State private var settled = false

    var body: some View {
        if let game = store.game {
            VStack(spacing: 0) {
                FeedList(beats: game.feed, pace: game.phase == .voteReveal ? 1.0 : 0.7, settled: $settled)
                BottomBar {
                    if store.spectating, game.phase != .gameOver, game.winner == nil {
                        SpectatorNote()
                    }
                    Button(label(game)) { store.send(.next) }
                        .buttonStyle(GoldButtonStyle())
                        .opacity(settled ? 1 : 0.45)
                }
            }
        }
    }

    private func label(_ game: Game) -> String {
        switch game.phase {
        case .breakfast: return game.winner != nil ? "See how it ended" : game.finale ? "To the Fire of Truth" : "To the mission"
        case .voteReveal:
            if game.winner != nil || (game.finale && game.alive.count <= 2) { return "See how it ended" }
            return game.finale ? "Continue" : "Nightfall"
        case .finaleReveal: return game.winner != nil ? "See how it ended" : "To the vote"
        default: return "Continue"
        }
    }
}

struct BottomBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 10) { content }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(Palette.ink.opacity(0.7))
            .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }
}

/// Shown once the human is out: roles are open and the rest can be fast-forwarded.
struct SpectatorNote: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        HStack {
            Text("You are out. Roles are revealed while you watch.")
                .font(.serif(.caption)).foregroundStyle(Palette.muted)
            Spacer()
            Button("Skip to the end") {
                var guardCount = 0
                while let g = store.game, g.phase != .gameOver, guardCount < 400 {
                    store.send(.next)
                    guardCount += 1
                }
            }
            .font(.serif(.caption, weight: .bold))
        }
    }
}

/// Everyone at a glance, with the public evidence about each of them.
struct CastSheet: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            CastleBackground()
            if let game = store.game {
                let view = game.view()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Notebook").font(.serif(.largeTitle, weight: .bold)).foregroundStyle(Palette.parchment)
                            Spacer()
                            Button("Done") { dismiss() }.font(.serif(.headline))
                        }
                        .padding(.top, 24)
                        ForEach(game.players.indices, id: \.self) { i in
                            let p = store.shown(game.players[i])
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 10) {
                                    Avatar(player: p, size: 40, role: store.roleShown(i))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(p.isHuman ? "\(p.name) (you)" : p.name)
                                            .font(.serif(.headline)).foregroundStyle(Palette.parchment)
                                        Text(status(p)).font(.serif(.caption)).foregroundStyle(Palette.muted)
                                    }
                                    Spacer()
                                    if let role = store.roleShown(i) {
                                        Text(role == .traitor ? "Traitor" : "Faithful")
                                            .font(.serif(.caption, weight: .bold)).foregroundStyle(Palette.role(role))
                                    }
                                }
                                let against = game.notebook(about: i, suspicious: true).filter { $0.kind != .gut }
                                let inFavour = game.notebook(about: i, suspicious: false).filter { $0.kind != .gut }
                                ForEach(Array(against.enumerated()), id: \.offset) { _, chip in
                                    evidence(Dialogue.label(chip, view: view), Palette.blood, "exclamationmark.triangle.fill")
                                }
                                ForEach(Array(inFavour.enumerated()), id: \.offset) { _, chip in
                                    evidence(Dialogue.label(chip, view: view), Palette.faithful, "checkmark.seal.fill")
                                }
                            }
                            .panel()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private func evidence(_ text: String, _ tint: Color, _ icon: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).font(.caption).foregroundStyle(tint).padding(.top, 2)
            Text(text).font(.serif(.footnote)).foregroundStyle(Palette.parchment)
        }
    }

    private func status(_ p: Player) -> String {
        if p.alive { return p.isHuman ? "Still in the game" : "\(p.job), \(p.county)" }
        return "\(p.fate == .murdered ? "Murdered" : "Banished") on day \(p.fateDay ?? 0)"
    }
}
