import SwiftUI

/// A player's cloak-coloured token. Shows a role mark only when the viewer is entitled to it.
struct Avatar: View {
    @Environment(GameStore.self) private var store
    /// As passed in. What is drawn is `player`, which keeps someone seated until their going has been told.
    let subject: Player
    var size: CGFloat = 44
    var role: Role? = nil
    var selected = false
    /// Hood up, as in the turret.
    var hooded = false

    init(player: Player, size: CGFloat = 44, role: Role? = nil, selected: Bool = false, hooded: Bool = false) {
        subject = player
        self.size = size
        self.role = role
        self.selected = selected
        self.hooded = hooded
    }

    private var player: Player { store.shown(subject) }

    var body: some View {
        Portrait(name: player.name, cloak: Palette.cloak(for: player), size: size, hooded: hooded, human: player.isHuman)
        .saturation(player.alive ? 1 : 0.15)
        .opacity(player.alive ? 1 : 0.55)
        .overlay {
            Circle().stroke(ring, lineWidth: selected ? 3 : (player.isHuman || role != nil ? 2 : 1))
        }
        .overlay(alignment: .bottomTrailing) {
            if !player.alive {
                Image(systemName: player.fate == .murdered ? "xmark" : "door.left.hand.open")
                    .font(.system(size: size * 0.24, weight: .bold))
                    .foregroundStyle(Palette.parchment)
                    .padding(size * 0.07)
                    .background(Palette.ink, in: Circle())
            }
        }
        .accessibilityLabel(player.name)
        .accessibilityValue(player.alive ? "" : player.fate == .murdered ? "Murdered" : "Banished")
    }

    private var ring: Color {
        if selected { return Palette.gold }
        if let role { return Palette.role(role) }
        return player.isHuman ? Palette.gold.opacity(0.8) : Palette.line
    }
}

/// A grid of players to choose one from.
struct PlayerPicker: View {
    @Environment(GameStore.self) private var store
    let ids: [PlayerID]
    @Binding var selection: PlayerID?

    var body: some View {
        if let game = store.game {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 10) {
                ForEach(ids, id: \.self) { id in
                    Button {
                        selection = selection == id ? nil : id
                    } label: {
                        VStack(spacing: 4) {
                            Avatar(player: game.players[id], size: 50, role: store.roleShown(id), selected: selection == id)
                            Text(game.players[id].name)
                                .font(.serif(.caption, weight: selection == id ? .bold : .regular))
                                .foregroundStyle(selection == id ? Palette.gold : Palette.parchment)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct BeatRow: View {
    @Environment(GameStore.self) private var store
    let beat: Beat

    var body: some View {
        if let game = store.game {
            switch beat.kind {
            case .narration:
                Text(beat.text)
                    .font(.serif(.subheadline).italic())
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            case .host:
                HostLine(text: beat.text)
            case .speech:
                HStack(alignment: .top, spacing: 10) {
                    if let s = beat.speaker {
                        Avatar(player: game.players[s], size: 36, role: store.roleShown(s))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        if let s = beat.speaker {
                            Text(game.players[s].isHuman ? "You" : game.players[s].name)
                                .font(.serif(.caption, weight: .bold))
                                .foregroundStyle(Palette.gold)
                        }
                        Text(beat.text)
                            .font(.serif(.subheadline))
                            .foregroundStyle(Palette.parchment)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .panel()
            case .vote:
                // Drawn as they were at the vote, so the rows don't give away the banishment below.
                HStack(spacing: 10) {
                    if let s = beat.speaker { Avatar(player: seated(game.players[s]), size: 30) }
                    Text(beat.text)
                        .font(.serif(.subheadline))
                        .foregroundStyle(Palette.parchment)
                    Spacer(minLength: 0)
                    if let t = beat.target { Avatar(player: seated(game.players[t]), size: 30) }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
            case .banish, .murder:
                let tint = beat.role.map(Palette.role) ?? Palette.muted
                VStack(spacing: 10) {
                    if let t = beat.target { Avatar(player: game.players[t], size: 64, role: beat.role) }
                    Text(beat.text)
                        .font(.serif(.headline))
                        .foregroundStyle(Palette.parchment)
                        .multilineTextAlignment(.center)
                    if beat.kind == .banish, let role = beat.role {
                        Text(role == .traitor ? "TRAITOR" : "FAITHFUL")
                            .font(.serif(.caption, weight: .heavy))
                            .tracking(3)
                            .foregroundStyle(tint)
                    }
                }
                .frame(maxWidth: .infinity)
                .panel(stroke: (beat.kind == .murder ? Palette.blood : tint).opacity(0.7), fill: Palette.panelHi)
            case .secret:
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "eye.slash.fill").foregroundStyle(Palette.blood)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("FOR YOUR EYES ONLY")
                            .font(.serif(.caption2, weight: .heavy))
                            .tracking(1.5)
                            .foregroundStyle(Palette.blood)
                        Text(beat.text)
                            .font(.serif(.subheadline))
                            .foregroundStyle(Palette.parchment)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .panel(stroke: Palette.blood.opacity(0.6), fill: Palette.blood.opacity(0.10))
            case .result:
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(Palette.gold).padding(.top, 7)
                    Text(beat.text)
                        .font(.serif(.subheadline))
                        .foregroundStyle(Palette.parchment)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Something the host says to the room.
struct HostLine: View {
    let text: String

    var body: some View {
        VStack(spacing: 5) {
            Text(Host.name.uppercased())
                .font(.serif(.caption2, weight: .heavy))
                .tracking(2)
                .foregroundStyle(Palette.gold)
            Text(text)
                .font(.serif(.body).italic())
                .foregroundStyle(Palette.parchment)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Palette.ink.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.gold.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// A player as they looked while still at the table.
func seated(_ p: Player) -> Player {
    var q = p
    q.alive = true
    return q
}

/// Shows beats one at a time so a scene plays out instead of landing all at once. Tap to skip ahead.
struct FeedList: View {
    let beats: [Beat]
    var pace: Double = 0.75
    @Binding var settled: Bool
    @State private var shown = 0
    @Environment(\.curtainUp) private var curtainUp

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(0..<min(shown, beats.count), id: \.self) { i in
                        BeatRow(beat: beats[i])
                            .id(i)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    Color.clear.frame(height: 4).id(-1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .contentShape(Rectangle())
            .onTapGesture { reveal(beats.count, proxy) }
            .onChange(of: beats.first?.text) { shown = 0; settled = beats.isEmpty }
            .onChange(of: beats.count) { old, new in
                if new < old { shown = 0 }
                settled = shown >= new
            }
            .task(id: "\(beats.first?.text ?? "")|\(beats.count)|\(curtainUp)") {
                settled = shown >= beats.count
                // Nothing is said while the title card is still down.
                guard curtainUp else { return }
                while shown < beats.count {
                    try? await Task.sleep(for: .seconds(shown == 0 ? 0.15 : pace))
                    if Task.isCancelled { return }
                    reveal(shown + 1, proxy)
                }
            }
        }
    }

    private func reveal(_ n: Int, _ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            shown = min(n, beats.count)
            proxy.scrollTo(-1, anchor: .bottom)
        }
        settled = shown >= beats.count
    }
}

struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.serif(.caption, weight: .heavy))
            .tracking(2)
            .foregroundStyle(Palette.gold)
    }
}

/// What only a traitor is told about a mission.
struct QuestBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "eye.slash.fill").foregroundStyle(Palette.blood)
            Text(text)
                .font(.serif(.footnote))
                .foregroundStyle(Palette.parchment)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.blood.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.blood.opacity(0.5), lineWidth: 1))
    }
}
