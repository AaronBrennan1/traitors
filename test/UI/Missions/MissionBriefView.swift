import SwiftUI

/// Before each mission: which course it is, how the gauntlet is played, and for a traitor the shadow's hand.
struct MissionBriefView: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        if let game = store.game, let run = game.mission {
            let kind = run.kind
            let spec = kind.spec
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        hero(kind, day: game.day)

                        HStack(spacing: 8) {
                            fact("person.3.fill", "Goal", "\(run.teamGoal)", "\(spec.unit) between you")
                            fact("moon.stars.fill", "Make it", "Safe", "no murder tonight")
                            fact("hourglass", "Time", "\(Int(spec.seconds(day: game.day)))", "seconds")
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            SectionTitle(text: "How to play")
                            ForEach(Array((MissionKind.controls + [kind.twist]).enumerated()), id: \.offset) { _, line in
                                HStack(alignment: .firstTextBaseline, spacing: 9) {
                                    Image(systemName: "diamond.fill").font(.system(size: 6)).foregroundStyle(Palette.gold)
                                    Text(line).font(.serif(.subheadline)).foregroundStyle(Palette.parchment)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Text("Everyone runs at once and everything goes in one vault. Fill it to the goal between you and it seals: nobody is murdered tonight. Fall short and the traitors have their night.")
                                .font(.serif(.caption)).foregroundStyle(Palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 2)
                        }
                        .panel()

                        ForEach(game.feed.indices, id: \.self) { i in
                            if game.feed[i].kind == .secret { BeatRow(beat: game.feed[i]) }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
                BottomBar {
                    if !game.humanAlive, game.human != nil { SpectatorNote() }
                    Button(game.humanAlive ? "Begin the mission" : "Watch the mission") {
                        Feedback.play(.tap)
                        store.send(.next)
                    }
                    .buttonStyle(GoldButtonStyle())
                }
            }
        }
    }

    /// The mission's name on a card in its own light: the hour and weather of the stage to come.
    private func hero(_ kind: MissionKind, day: Int) -> some View {
        let tint = kind.tint
        return VStack(spacing: 10) {
            Image(systemName: kind.icon)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Palette.gold)
                .frame(width: 76, height: 76)
                .background(Palette.ink.opacity(0.75), in: Circle())
                .overlay(Circle().stroke(Palette.gold, lineWidth: 1.5))
                .overlay(Circle().stroke(Palette.gold.opacity(0.3), lineWidth: 1).padding(-5))
                .shadow(color: tint.opacity(0.6), radius: 18)
                .accessibilityHidden(true)
            Text(kind.title)
                .font(Tokens.TypeRole.display.font(.title)).foregroundStyle(Palette.parchment)
                .multilineTextAlignment(.center)
            HostLine(text: Host.missionIntro(day: day))
            Text(kind.brief)
                .font(.serif(.subheadline).italic()).foregroundStyle(Palette.parchment.opacity(0.82))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                Palette.panel
                LinearGradient(colors: [tint.opacity(0.55), tint.opacity(0.08)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Palette.gold.opacity(0.16), .clear], center: .top, startRadius: 0, endRadius: 220)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.sheet))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.sheet).stroke(Palette.gold.opacity(0.3), lineWidth: 1))
    }

    private func fact(_ icon: String, _ label: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.caption2).foregroundStyle(Palette.gold.opacity(0.8))
            Text(value).font(Tokens.TypeRole.numeral.font(.title3)).foregroundStyle(Palette.parchment)
            Text(label.uppercased()).font(.serif(.caption2, weight: .heavy)).tracking(1.5).foregroundStyle(Palette.gold)
            Text(unit).font(.serif(.caption2)).foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card).stroke(Palette.line))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value) \(unit)")
    }
}

extension MissionKind {
    /// The colour of each course's light, for the card that introduces it.
    var tint: Color {
        switch self {
        case .greatHall: return Color(red: 0.50, green: 0.30, blue: 0.16)
        case .cellars: return Color(red: 0.34, green: 0.22, blue: 0.16)
        case .armoury: return Color(red: 0.28, green: 0.32, blue: 0.40)
        case .battlements: return Color(red: 0.16, green: 0.22, blue: 0.40)
        case .crypt: return Color(red: 0.12, green: 0.30, blue: 0.26)
        }
    }
}
