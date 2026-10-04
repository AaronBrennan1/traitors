import SwiftUI

/// A swipeable walkthrough of how the game works. Shown before every new game and from the title screen.
struct TutorialView: View {
    /// Label on the last page's button.
    var finishLabel = "Take your seat"
    var onDone: () -> Void
    @State private var page = 0

    private struct Page {
        let title: String
        let lines: [String]
    }

    private let pages: [Page] = [
        Page(title: "The aim", lines: [
            "Eight players sit down in the castle. Two of them are secretly traitors.",
            "The faithful win by banishing every traitor.",
            "The traitors win by surviving to the end, or once there are as many of them as faithful.",
        ]),
        Page(title: "A day in the castle", lines: [
            "Breakfast shows who was murdered in the night.",
            "Then everyone plays the day's mission, and the scores go up on the board.",
            "At the Round Table you talk, vote, and banish one player. Then night falls.",
        ]),
        Page(title: "Missions", lines: [
            "Each mission is a short game everyone plays at once: stacking turf across a bog, keeping the castle lanterns lit, herding sheep, cooking for the banquet.",
            "What you bring home counts for you and for the team. The pot depends on what everyone manages between them.",
            "Every mission has a par. Beat it, because the table is told exactly who fell short.",
        ]),
        Page(title: "The secret side quest", lines: [
            "A traitor is given the Shadow's Task, hidden in the very same game: a sod to sink in a bog pool, a lantern to keep dark, a letter to slip into a basket.",
            "If a traitor finishes the side quest, the traitors may murder that night. If nobody does, nobody dies.",
            "It costs a little time, but the real risk is being seen. You can only see so far, and so can everyone else: wait for the fog, the crowd or an empty room.",
        ]),
        Page(title: "Reading the board", lines: [
            "A red flag means under par. It proves little: plenty of faithful are simply bad at games.",
            "What people saw matters more. You are told what you noticed in each mission, and can say it at the table.",
            "It is only your word, though, and a traitor can invent a sighting. Anyone who was watching can call the lie.",
        ]),
        Page(title: "The shield", lines: [
            "Some days, one of the three best scorers is secretly given the shield and cannot be murdered that night.",
            "If nobody dies because the side quest went undone, breakfast says so, and names anyone who was never out of sight. A murder the shield blocked passes without a word.",
        ]),
        Page(title: "The Round Table", lines: [
            "You speak twice. Accuse or defend someone with a piece of real evidence, or put a question to another player.",
            "Then everyone votes and the banished player reveals their role.",
            "The others notice when your words and your vote don't match.",
        ]),
        Page(title: "Night and the finale", lines: [
            "Once per game a lone traitor recruits instead of murdering. The knock could come at your door.",
            "With four or fewer left there are no more missions or murders, and banished players stop revealing their role.",
            "The game only ends when everyone still standing votes to end it.",
        ]),
    ]

    var body: some View {
        ZStack {
            CastleBackground()
            VStack(spacing: 0) {
                HStack {
                    Text("How to play").font(.serif(.headline, weight: .bold)).foregroundStyle(Palette.gold)
                    Spacer()
                    Button("Skip", action: onDone).font(.serif(.headline)).foregroundStyle(Palette.muted)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)

                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { i in
                        ScrollView {
                            VStack(spacing: 18) {
                                illustration(i)
                                    .frame(maxWidth: .infinity, minHeight: 150)
                                    .panel(fill: Palette.panel.opacity(0.7))
                                Text(pages[i].title)
                                    .font(.serif(.title, weight: .bold)).foregroundStyle(Palette.parchment)
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(pages[i].lines, id: \.self) { line in
                                        HStack(alignment: .top, spacing: 10) {
                                            Image(systemName: "circle.fill").font(.system(size: 5))
                                                .foregroundStyle(Palette.gold).padding(.top, 8)
                                            Text(line).font(.serif(.body)).foregroundStyle(Palette.parchment)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                            .padding(.bottom, 50)
                        }
                        .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                Button(page == pages.count - 1 ? finishLabel : "Next") {
                    if page == pages.count - 1 { onDone() } else { withAnimation { page += 1 } }
                }
                .buttonStyle(GoldButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
    }

    @ViewBuilder
    private func illustration(_ i: Int) -> some View {
        switch i {
        case 0:
            HStack(spacing: 8) {
                ForEach(0..<8, id: \.self) { n in
                    Image(systemName: n == 2 || n == 5 ? "theatermasks.fill" : "shield.lefthalf.filled")
                        .font(.title2)
                        .foregroundStyle(n == 2 || n == 5 ? Palette.blood : Palette.faithful)
                }
            }
        case 1:
            HStack(spacing: 6) {
                step("cup.and.saucer.fill", "Breakfast")
                arrow
                step("flag.checkered", "Mission")
                arrow
                step("person.3.fill", "Round Table")
                arrow
                step("moon.stars.fill", "Night")
            }
        case 2:
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 14) {
                ForEach(MissionKind.allCases, id: \.self) { k in
                    Image(systemName: k.icon).font(.title2).foregroundStyle(Palette.gold)
                }
            }
            .frame(maxWidth: 260)
        case 3:
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    Image(systemName: "circle.fill").foregroundStyle(Palette.gold)
                    Image(systemName: "circle.fill").foregroundStyle(Palette.gold)
                    Image(systemName: "flame.fill").foregroundStyle(Palette.blood)
                    Image(systemName: "circle.fill").foregroundStyle(Palette.gold)
                }
                .font(.title2)
                QuestBanner(text: "seen only by traitors, hidden inside the mission.")
            }
        case 4:
            MissionLeaderboard(report: Self.sampleReport, players: Self.samplePlayers)
        case 5:
            Image(systemName: "shield.fill").font(.system(size: 64)).foregroundStyle(Palette.gold)
        case 6:
            HStack(spacing: 22) {
                step("exclamationmark.bubble.fill", "Accuse")
                step("hand.raised.fill", "Defend")
                step("questionmark.bubble.fill", "Question")
                step("pencil.and.list.clipboard", "Vote")
            }
        default:
            HStack(spacing: 26) {
                step("door.left.hand.open", "Recruit")
                step("flame.fill", "Fire of Truth")
                step("checkmark.seal.fill", "End it")
            }
        }
    }

    private var arrow: some View {
        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted)
    }

    private func step(_ icon: String, _ label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title2).foregroundStyle(Palette.gold)
            Text(label).font(.serif(.caption2, weight: .bold)).foregroundStyle(Palette.parchment)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private static let samplePlayers: [Player] = Cast.bots.prefix(4).enumerated().map { i, c in
        Player(id: i, name: c.name, county: c.county, job: c.job, isHuman: false, role: .faithful,
               personality: c.personality, voice: c.voice, hue: c.hue)
    }

    private static let sampleReport: MissionReport = {
        let counts = [9, 7, 6, 3]
        let units = counts.enumerated().map { i, c in
            MissionUnit(players: [i], count: c, anomalous: c < 6, innocentRate: 0.3, questRate: 0.4, detail: "")
        }
        return MissionReport(kind: .bogRelay, day: 1, steps: 10, par: 6, units: units, scores: [:], potEarned: 0, lines: [])
    }()
}
