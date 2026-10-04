import SwiftUI

/// The first night: the host's welcome, the others introducing themselves, then blindfolds on
/// while she walks the circle and chooses her traitors.
struct RoleCeremony: View {
    @Environment(GameStore.self) private var store
    @Environment(Stage.self) private var stage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0

    enum Moment {
        case welcome(String)
        case meet(PlayerID)
        case blindfold, circling, footstep(Int)
        /// A hand on the shoulder, or the steps going by.
        case touch
        case done, reveal
        /// Traitors only: hoods down in the turret.
        case turret
    }

    var body: some View {
        if let game = store.game, let me = game.human {
            let role = game.players[me].role
            let moments = Self.moments(game, role)
            let settled = shown >= moments.count
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 20) {
                        if shown > 0 { scene(game, role, moments, moments[shown - 1]).id(shown).transition(.opacity) }
                    }
                    .padding(.horizontal, 26)
                    .padding(.vertical, 30)
                    .frame(maxWidth: .infinity)
                }
                .defaultScrollAnchor(.center)
                .contentShape(Rectangle())
                .onTapGesture { shown = moments.count }
                .accessibilityAction(named: "Skip to my role") { shown = moments.count }

                met(game, moments)
                VStack(spacing: 8) {
                    if settled {
                        Button("Go down to breakfast") { store.send(.next) }
                            .buttonStyle(GoldButtonStyle(tint: Palette.role(role)))
                    } else {
                        Text("Tap to skip. Make sure nobody else can see your screen.")
                            .font(.serif(.caption)).foregroundStyle(Palette.muted)
                            .frame(minHeight: 50)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .stepClock($shown, count: moments.count, key: "role", hold: { hold(moments, $0) }, cue: { cue(moments[$0], role) })
            .onChange(of: shown, initial: true) {
                // Dark for as long as the blindfold is on.
                var dark = false
                if shown > 0 {
                    switch moments[shown - 1] {
                    case .blindfold, .circling, .footstep, .touch: dark = true
                    default: break
                    }
                }
                withAnimation(.easeInOut(duration: reduceMotion ? 0.3 : 0.9)) { stage.dim = dark ? 1 : 0 }
            }
        }
    }

    static func moments(_ game: Game, _ role: Role) -> [Moment] {
        var out: [Moment] = Host.welcome.map { .welcome($0) }
        out += game.players.indices.filter { !game.players[$0].isHuman }.map { .meet($0) }
        out += [.blindfold, .circling, .footstep(1), .footstep(2), .footstep(3), .touch, .done, .reveal]
        if role == .traitor { out.append(.turret) }
        return out
    }

    private func hold(_ moments: [Moment], _ i: Int) -> Double {
        if i == 0 { return 0.7 }
        switch moments[i] {
        case .welcome: return 2.8
        case .meet: return 2.4
        case .blindfold: return 2.6
        case .circling: return 2.6
        case .footstep: return 1.2
        case .touch: return 1.8
        case .done: return 2.6
        case .reveal: return 2.4
        case .turret: return 3.4
        }
    }

    private func cue(_ moment: Moment, _ role: Role) {
        switch moment {
        case .meet: Cue.door.play()
        case .blindfold: Cue.snuff.play()
        case .footstep: Cue.footstep.play()
        case .touch: (role == .traitor ? Cue.shoulder : Cue.footstep).play()
        case .done: Cue.bell.play()
        case .reveal: Cue.declare(role).play()
        case .turret: Cue.boom.play()
        default: break
        }
    }

    @ViewBuilder
    private func scene(_ game: Game, _ role: Role, _ moments: [Moment], _ moment: Moment) -> some View {
        switch moment {
        case .welcome(let text):
            HostLine(text: text)
        case .meet(let p):
            let player = game.players[p]
            VStack(spacing: 10) {
                Avatar(player: player, size: 120)
                Text(player.name).font(.serif(.title, weight: .bold)).foregroundStyle(Palette.parchment)
                Text("\(player.job), \(player.county)").font(.serif(.subheadline)).foregroundStyle(Palette.gold)
                Text("“\(Flavour.introduction(player.voice))”")
                    .font(.serif(.body).italic()).foregroundStyle(Palette.parchment)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        case .blindfold:
            HostLine(text: Host.blindfolds)
        case .circling:
            HostLine(text: Host.circling)
        case .footstep(let n):
            Text(["Footsteps, behind the chairs.", "Closer.", "Right behind you."][min(n, 3) - 1])
                .font(.serif(.title3).italic()).foregroundStyle(Palette.muted)
        case .touch:
            Text(role == .traitor ? "A hand rests on your shoulder." : "The footsteps pass you by.")
                .font(.serif(.title2, weight: .semibold)).foregroundStyle(Palette.parchment)
                .multilineTextAlignment(.center)
        case .done:
            HostLine(text: Host.chosen)
        case .reveal:
            reveal(game, role, partnerShown: role != .traitor)
        case .turret:
            reveal(game, role, partnerShown: true)
        }
    }

    private func reveal(_ game: Game, _ role: Role, partnerShown: Bool) -> some View {
        VStack(spacing: 14) {
            Text("You are a").font(.serif(.title3)).foregroundStyle(Palette.muted)
            Image(systemName: role == .traitor ? "theatermasks.fill" : "shield.lefthalf.filled")
                .font(.system(.largeTitle)).imageScale(.large).scaleEffect(1.6).padding(.vertical, 12)
                .foregroundStyle(Palette.role(role))
                .accessibilityHidden(true)
            Text(role == .traitor ? "TRAITOR" : "FAITHFUL")
                .font(.serif(.largeTitle, weight: .heavy)).tracking(5)
                .foregroundStyle(Palette.role(role))
                .minimumScaleFactor(0.5).lineLimit(1)
            if role == .traitor {
                let partners = game.team.filter { $0 != game.human }
                if partnerShown { HostLine(text: Host.turret) }
                HStack(spacing: 18) {
                    ForEach(partners, id: \.self) { p in
                        VStack(spacing: 6) {
                            Avatar(player: game.players[p], size: 84, role: partnerShown ? .traitor : nil, hooded: !partnerShown)
                            Text(partnerShown ? game.players[p].name : "A hooded figure")
                                .font(.serif(.headline)).foregroundStyle(Palette.parchment)
                        }
                    }
                }
                if partnerShown {
                    Text("Each day, one of you must finish the secret side quest hidden inside the mission to earn a murder that night. It costs time, so mind your score. Do not get caught.")
                        .font(.serif(.subheadline)).foregroundStyle(Palette.parchment)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Two of the seven around you are traitors. Beat par in the missions, watch who falls short, weigh the votes, and banish them both.")
                    .font(.serif(.body)).foregroundStyle(Palette.parchment)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Everyone met so far, along the bottom.
    @ViewBuilder
    private func met(_ game: Game, _ moments: [Moment]) -> some View {
        let seen: [PlayerID] = moments.prefix(shown).compactMap { if case .meet(let p) = $0 { return p } else { return nil } }
        HStack(spacing: 6) {
            ForEach(seen, id: \.self) { p in
                Avatar(player: game.players[p], size: 36).transition(.scale.combined(with: .opacity))
            }
        }
        .frame(height: 40)
        .padding(.bottom, 8)
        .accessibilityHidden(true)
    }
}
