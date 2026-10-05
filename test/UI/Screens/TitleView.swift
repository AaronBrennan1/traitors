import SwiftUI

struct TitleView: View {
    @Environment(GameStore.self) private var store
    /// Called to enter the castle; `true` when the game has only just been set up.
    var onPlay: (Bool) -> Void
    @State private var showSetup = false
    @State private var showRules = false
    @State private var showSettings = false

    var body: some View {
        ZStack {
            CastleBackground()
            VStack(spacing: 0) {
                Spacer()
                Image(systemName: "theatermasks.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(Palette.gold)
                    .padding(.bottom, 18)
                Text("THE TRAITORS")
                    .font(.system(size: 38, weight: .heavy, design: .serif))
                    .tracking(4)
                    .foregroundStyle(Palette.parchment)
                Text("IRELAND")
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .tracking(12)
                    .foregroundStyle(Palette.gold)
                    .padding(.top, 4)
                Text("Eight players. Two traitors. One castle.")
                    .font(.serif(.subheadline).italic())
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 16)
                Spacer()

                if store.stats.played > 0 {
                    HStack(spacing: 0) {
                        stat("Played", "\(store.stats.played)")
                        stat("Won as faithful", "\(store.stats.wonAsFaithful)/\(store.stats.asFaithful)")
                        stat("Won as traitor", "\(store.stats.wonAsTraitor)/\(store.stats.asTraitor)")
                    }
                    .padding(.vertical, 10)
                    .background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 16)
                }

                VStack(spacing: 10) {
                    if store.hasSave {
                        Button("Continue game") { onPlay(false) }.buttonStyle(GoldButtonStyle())
                        Button("New game") { showSetup = true }.buttonStyle(GhostButtonStyle())
                    } else {
                        Button("New game") { showSetup = true }.buttonStyle(GoldButtonStyle())
                    }
                    Button("How to play") { showRules = true }.buttonStyle(GhostButtonStyle())
                }
                Text("A fan-made game. Not affiliated with the television programme.")
                    .font(.serif(.caption2))
                    .foregroundStyle(Palette.muted.opacity(0.7))
                    .padding(.top, 14)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .sheet(isPresented: $showSetup) {
            SetupView { name, pref in
                store.newGame(name: name, preference: pref)
                showSetup = false
                onPlay(true)
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showRules) { TutorialView(finishLabel: "Done") { showRules = false } }
        .overlay(alignment: .topTrailing) {
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill").font(.headline).foregroundStyle(Palette.muted)
                    .frame(width: 44, height: 44)
            }
            .padding(.trailing, 12)
            .accessibilityLabel("Settings")
        }
        .sheet(isPresented: $showSettings) {
            ZStack {
                CastleBackground()
                VStack(alignment: .leading, spacing: 14) {
                    Text("Settings").font(.serif(.title2, weight: .bold)).foregroundStyle(Palette.parchment)
                    SettingsToggles().panel()
                    Spacer()
                }
                .padding(20)
                .padding(.top, 10)
            }
            .presentationDetents([.height(250)])
            .presentationDragIndicator(.visible)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.serif(.headline, weight: .bold)).foregroundStyle(Palette.parchment)
            Text(label).font(.serif(.caption2)).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity)
    }
}

struct SetupView: View {
    var onStart: (String, RolePreference) -> Void
    @AppStorage("playerName") private var name = ""
    @State private var preference: RolePreference = .random

    var body: some View {
        ZStack {
            CastleBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Take your seat")
                        .font(.serif(.largeTitle, weight: .bold))
                        .foregroundStyle(Palette.parchment)
                        .padding(.top, 24)

                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(text: "Your name")
                        TextField("Your name", text: $name)
                            .font(.serif(.title3))
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(text: "Your role")
                        ForEach(RolePreference.allCases, id: \.self) { pref in
                            Button { preference = pref } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: icon(pref))
                                        .font(.title3)
                                        .foregroundStyle(tint(pref))
                                        .frame(width: 30)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(title(pref)).font(.serif(.headline)).foregroundStyle(Palette.parchment)
                                        Text(blurb(pref)).font(.serif(.caption)).foregroundStyle(Palette.muted)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer()
                                    Image(systemName: preference == pref ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(preference == pref ? Palette.gold : Palette.muted)
                                }
                                .panel(stroke: preference == pref ? Palette.gold.opacity(0.7) : Palette.line)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(text: "Your seven rivals")
                        ForEach(Array(Cast.bots.enumerated()), id: \.offset) { _, c in
                            HStack(spacing: 10) {
                                Circle().fill(Palette.cloak(c.hue)).frame(width: 28, height: 28)
                                    .overlay(Text(String(c.name.prefix(1))).font(.serif(.caption, weight: .bold)).foregroundStyle(.white))
                                Text(c.name).font(.serif(.subheadline, weight: .semibold)).foregroundStyle(Palette.parchment)
                                Text("\(c.job), \(c.county)").font(.serif(.caption)).foregroundStyle(Palette.muted)
                                Spacer()
                            }
                        }
                    }
                    .panel()

                    Button("Enter the castle") { onStart(name, preference) }
                        .buttonStyle(GoldButtonStyle())
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func title(_ p: RolePreference) -> String {
        switch p {
        case .random: return "Let fate decide"
        case .faithful: return "Faithful"
        case .traitor: return "Traitor"
        }
    }
    private func blurb(_ p: RolePreference) -> String {
        switch p {
        case .random: return "One chance in four of being a traitor."
        case .faithful: return "Find both traitors before they outnumber you."
        case .traitor: return "Lie by day, spoil the company's win unseen, and murder by night."
        }
    }
    private func icon(_ p: RolePreference) -> String {
        switch p {
        case .random: return "dice.fill"
        case .faithful: return "shield.lefthalf.filled"
        case .traitor: return "theatermasks.fill"
        }
    }
    private func tint(_ p: RolePreference) -> Color {
        switch p {
        case .random: return Palette.gold
        case .faithful: return Palette.faithful
        case .traitor: return Palette.blood
        }
    }
}
