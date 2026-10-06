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
            "Then everyone plays the day's mission together, and wins or loses it together.",
            "At the Round Table you talk, vote, and banish one player. Then night falls.",
        ]),
        Page(title: "Missions", lines: [
            "Every day is a different game. One day you are stacking turf across a bog, the next herding sheep, diving a wreck, dancing a céilí or running gold through the castle's traps. Each plays its own way, and the card before it says how.",
            "Everyone plays at once. The row of tokens along the top shows who has brought home what, and it shuffles as people overtake one another.",
            "It all counts towards one goal. Make it between you and there is no murder that night. Fall short and the traitors have their night.",
        ]),
        Page(title: "The shadow's hand", lines: [
            "A traitor plays the same game with one thing more. Every game has something that can be made to go wrong: a stack that slumps, a gate that bursts, a cart that tips. Stand still beside it and tap the button, and the team loses some of what it had.",
            "The traitors only get their night if the company falls short, so the hand is how they see to it.",
            "Nothing on the screen says whose hand it was. But these things go by themselves now and then too, and anyone close by sees who was standing there when it went.",
        ]),
        Page(title: "What you saw", lines: [
            "The mission does not say who did how much. What people saw is the evidence: you are told what you noticed, and can say it at the table.",
            "It is only your word, though, and a traitor can invent a sighting. Anyone who was watching can call the lie.",
            "After a day the company lost, breakfast names anyone who was never out of sight. Whoever spoiled the run, it was not them.",
        ]),
        Page(title: "The Round Table", lines: [
            "You speak twice. Accuse or defend someone with a piece of real evidence, or put a question to another player.",
            "Then everyone votes and the banished player reveals their role.",
            "The others notice when your words and your vote don't match.",
        ]),
        Page(title: "Night and the finale", lines: [
            "Once per game a lone traitor recruits instead of murdering, on a night that is theirs. The knock could come at your door.",
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
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 14) {
                ForEach(MissionKind.games + [.greatHall], id: \.self) { k in
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
                QuestBanner(text: "Known only to traitors: what can be made to go wrong, marked in red.")
            }
        case 4:
            HStack(spacing: 22) {
                step("eye.fill", "Seen")
                step("bubble.left.fill", "Said")
                step("moon.stars.fill", "The night")
            }
        case 5:
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
}
