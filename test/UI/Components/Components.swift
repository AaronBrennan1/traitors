import SwiftUI
import TraitorsEngine

/// Everyone in the game as the human may see them right now: a value handed down the view tree,
/// so the small components know who is who without knowing where the game is kept.
struct Roster {
    var seats: [GameScene.Seat] = []
    /// Players the game has sent out whose going the screen has not told yet.
    var concealed: Set<PlayerID> = []

    init() {}

    init(_ scene: GameScene?) {
        seats = scene?.seats ?? []
        concealed = scene?.concealed ?? []
    }

    func player(_ id: PlayerID) -> Player? { seats.indices.contains(id) ? seats[id].player : nil }
    /// The role the human may see for a player, if any.
    func role(_ id: PlayerID) -> Role? { seats.indices.contains(id) ? seats[id].role : nil }
    /// A player as the screen may show them: still seated if their going has not been told.
    func shown(_ p: Player) -> Player { concealed.contains(p.id) ? p.seated : p }
}

private struct RosterKey: EnvironmentKey {
    static let defaultValue = Roster()
}

extension EnvironmentValues {
    var roster: Roster {
        get { self[RosterKey.self] }
        set { self[RosterKey.self] = newValue }
    }
}

/// A player's cloak-coloured token. Shows a role mark only when the viewer is entitled to it.
struct Avatar: View {
    @Environment(\.roster) private var roster
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

    private var player: Player { roster.shown(subject) }

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
    @Environment(\.roster) private var roster
    let ids: [PlayerID]
    @Binding var selection: PlayerID?

    var body: some View {
        Group {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 10) {
                ForEach(ids.filter { roster.player($0) != nil }, id: \.self) { id in
                    let player = roster.player(id)!
                    Button {
                        selection = selection == id ? nil : id
                    } label: {
                        VStack(spacing: 4) {
                            Avatar(player: player, size: 50, role: roster.role(id), selected: selection == id)
                            Text(player.name)
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
    @Environment(\.roster) private var roster
    let beat: Beat

    var body: some View {
        Group {
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
                    if let s = beat.speaker, let speaker = roster.player(s) {
                        Avatar(player: speaker, size: 36, role: roster.role(s))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        if let s = beat.speaker, let speaker = roster.player(s) {
                            Text(speaker.isHuman ? "You" : speaker.name)
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
                    if let s = beat.speaker, let speaker = roster.player(s) { Avatar(player: speaker.seated, size: 30) }
                    Text(beat.text)
                        .font(.serif(.subheadline))
                        .foregroundStyle(Palette.parchment)
                    Spacer(minLength: 0)
                    if let t = beat.target, let target = roster.player(t) { Avatar(player: target.seated, size: 30) }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
            case .banish, .murder:
                let tint = beat.role.map(Palette.role) ?? Palette.muted
                VStack(spacing: 10) {
                    if let t = beat.target, let target = roster.player(t) { Avatar(player: target, size: 64, role: beat.role) }
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
