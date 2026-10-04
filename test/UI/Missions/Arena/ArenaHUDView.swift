import SwiftUI

/// What the scores along the top of a mini-game show. The scene writes it; the view only reads.
@Observable
final class ArenaHUDModel {
    struct Seat: Identifiable {
        let id: PlayerID
        let name: String
        let color: Color
        let isHuman: Bool
    }

    /// How the round came out, for the card at the end.
    struct Summary {
        let count: Int
        let teamTotal: Int
        /// Nil unless a traitor was on the side quest.
        let quest: Bool?
    }

    let kind: MissionKind
    let title: String
    let unit: String
    let steps: Int
    let par: Int
    let teamGoal: Int
    let seats: [Seat]
    /// The human is out of the game, or a bot is playing the seat.
    let watching: Bool
    /// Zero unless a traitor is on the side quest.
    let questGoal: Int
    let questText: String?

    var seconds = 0
    var timeFraction = 1.0
    var urgent = false
    var count = 0
    var teamTotal = 0
    var questProgress = 0
    var counts: [PlayerID: Int] = [:]
    var order: [PlayerID]
    var meterLabel: String?
    var meterValue = 1.0
    var toast = ""
    var toastCount = 0
    /// The number on screen before the start and after a pause.
    var countdown: String?
    var paused = false
    var canPause = false
    var ended = false
    var summary: Summary?
    /// Set by the button on the end card.
    var proceed = false
    /// Nobody is at the controls, so the round hands itself back.
    let autoAdvance: Bool

    init(config: ArenaConfig, core: ArenaCore) {
        kind = config.setup.kind
        title = kind.title
        unit = core.spec.unit
        steps = core.spec.steps
        par = core.spec.par
        teamGoal = core.teamGoal
        seats = config.cast.map { Seat(id: $0.id, name: $0.name, color: Color(uiColor: $0.color), isHuman: $0.isHuman && !config.spectating) }
        watching = config.spectating || !config.cast.contains { $0.isHuman }
        questGoal = config.questVisible ? core.questGoal : 0
        questText = config.questVisible ? kind.questText(steps: config.setup.questSteps) : nil
        order = config.cast.map(\.id)
        autoAdvance = config.setup.autopilot || watching
    }

    func seat(_ id: PlayerID) -> Seat? { seats.first { $0.id == id } }

    func pause() {
        guard canPause, !paused, !ended else { return }
        paused = true
        Feedback.play(.pause)
    }
}

/// A player's token at arena size: their cloak colour and their initial.
struct ArenaToken: View {
    let seat: ArenaHUDModel.Seat
    var size: CGFloat = 20

    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [seat.color, seat.color.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                Text(String(seat.name.prefix(1)))
                    .font(.system(size: size * 0.52, weight: .bold, design: .serif))
                    .foregroundStyle(seat.isHuman ? Palette.ink.opacity(0.85) : .white.opacity(0.92))
            }
            .overlay { Circle().stroke(seat.isHuman ? Palette.gold : Palette.ink.opacity(0.6), lineWidth: seat.isHuman ? 1.5 : 1) }
    }
}

/// The scores over a mini-game: the clock, your count against par, the team's haul, the traitor's
/// quest and everyone's standing. Only the pause button takes a touch; the rest lets the thumbs through.
struct ArenaHUDView: View {
    let model: ArenaHUDModel
    /// The status bar's height, in the view's own points.
    var topInset: CGFloat = 0
    @State private var toastShown = false
    @State private var cardShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var atPar: Bool { model.count >= model.par }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 7) {
                clockRow
                countRow
                standings
                if let label = model.meterLabel { meter(label) }
            }
            .padding(.horizontal, 12)
            .padding(.top, topInset + 6)
            .padding(.bottom, 26)
            .background {
                LinearGradient(stops: [.init(color: Palette.ink.opacity(0.94), location: 0), .init(color: Palette.ink.opacity(0.80), location: 0.7),
                                       .init(color: Palette.ink.opacity(0), location: 1)], startPoint: .top, endPoint: .bottom)
            }
            .allowsHitTesting(false)
            .dynamicTypeSize(.medium)

            HStack {
                pauseButton
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.top, topInset)

            toast
            if let number = model.countdown { countdownCard(number) }
            if model.ended { endCard }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: model.toastCount) {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.3, bounce: 0.35)) { toastShown = true }
            Task {
                let mine = model.toastCount
                try? await Task.sleep(for: .seconds(1.8))
                if mine == model.toastCount { withAnimation(.easeOut(duration: 0.4)) { toastShown = false } }
            }
        }
    }

    // MARK: Rows

    private var clockRow: some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: 30, height: 30)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.parchment.opacity(0.14))
                    Capsule().fill(model.urgent ? Palette.blood : Palette.gold)
                        .frame(width: max(model.urgent ? 8 : 6, geo.size.width * model.timeFraction))
                }
            }
            .frame(height: model.urgent ? 8 : 6)
            .animation(.linear(duration: 0.2), value: model.timeFraction)
            HStack(spacing: 3) {
                Image(systemName: "hourglass").font(.system(size: 11, weight: .semibold))
                Text("\(model.seconds)").font(.system(size: 19, weight: .bold, design: .serif)).monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
            }
            .foregroundStyle(model.urgent ? Palette.blood : Palette.parchment)
            .frame(width: 52, alignment: .trailing)
        }
        .frame(height: 30)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time, \(model.seconds) seconds")
    }

    private var countRow: some View {
        HStack(alignment: .center, spacing: 8) {
            if model.watching {
                Text("Watching").font(.system(size: 24, weight: .heavy, design: .serif)).foregroundStyle(Palette.parchment)
                Text("par \(model.par)").font(.system(size: 12, weight: .medium, design: .serif)).foregroundStyle(Palette.muted)
            } else {
                Text("\(model.count)")
                    .font(.system(size: 36, weight: .heavy, design: .serif)).monospacedDigit()
                    .foregroundStyle(atPar ? Palette.faithful : Palette.gold)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.25), value: model.count)
                VStack(alignment: .leading, spacing: 0) {
                    Text("of \(model.steps) \(model.unit)").font(.system(size: 13, weight: .semibold, design: .serif)).foregroundStyle(Palette.parchment)
                    HStack(spacing: 3) {
                        if atPar { Image(systemName: "checkmark.seal.fill").font(.system(size: 10)).foregroundStyle(Palette.faithful) }
                        Text(atPar ? "par \(model.par) made" : "par \(model.par)")
                            .font(.system(size: 11, weight: .medium, design: .serif)).foregroundStyle(atPar ? Palette.faithful : Palette.muted)
                    }
                }
            }
            Spacer(minLength: 6)
            if model.questGoal > 0 { quest }
            team
        }
        .frame(height: 40)
    }

    private var quest: some View {
        HStack(spacing: 4) {
            Image(systemName: "eye.slash.fill").font(.system(size: 11))
            ForEach(0..<model.questGoal, id: \.self) { i in
                Image(systemName: i < model.questProgress ? "diamond.fill" : "diamond").font(.system(size: 10, weight: .bold))
            }
        }
        .foregroundStyle(Palette.blood)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Palette.blood.opacity(0.14), in: Capsule())
        .overlay(Capsule().stroke(Palette.blood.opacity(0.5), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Side quest, \(model.questProgress) of \(model.questGoal)")
    }

    private var team: some View {
        let made = model.teamTotal >= model.teamGoal
        return VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 4) {
                Text("TEAM").font(.system(size: 9, weight: .heavy, design: .serif)).tracking(1.5).foregroundStyle(Palette.gold)
                if made { Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(Palette.faithful) }
            }
            Text("\(model.teamTotal)/\(model.teamGoal)")
                .font(.system(size: 15, weight: .bold, design: .serif)).monospacedDigit()
                .foregroundStyle(made ? Palette.faithful : Palette.parchment)
                .contentTransition(.numericText())
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.parchment.opacity(0.14))
                Capsule().fill(made ? Palette.faithful : Palette.gold.opacity(0.8))
                    .frame(width: 58 * min(1, Double(model.teamTotal) / Double(max(model.teamGoal, 1))))
            }
            .frame(width: 58, height: 3)
        }
        .animation(.easeOut(duration: 0.25), value: model.teamTotal)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Team, \(model.teamTotal) of \(model.teamGoal)")
    }

    /// Everyone's count, kept in score order.
    private var standings: some View {
        HStack(spacing: 0) {
            ForEach(model.order, id: \.self) { id in
                if let seat = model.seat(id) {
                    let n = model.counts[id] ?? 0
                    HStack(spacing: 3) {
                        ArenaToken(seat: seat, size: 19)
                        Text("\(n)").font(.system(size: 13, weight: .bold, design: .serif)).monospacedDigit()
                            .foregroundStyle(n >= model.par ? Palette.faithful : Palette.parchment)
                            .overlay(alignment: .bottom) {
                                if n >= model.par { Rectangle().fill(Palette.faithful).frame(height: 1.5).offset(y: 2) }
                            }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                    .background {
                        if seat.isHuman {
                            Capsule().fill(Palette.gold.opacity(0.18)).overlay(Capsule().stroke(Palette.gold.opacity(0.8), lineWidth: 1))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(seat.isHuman ? "You" : seat.name), \(n)\(n >= model.par ? ", par made" : "")")
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: Tokens.Motion.standard), value: model.order)
    }

    private func meter(_ label: String) -> some View {
        let low = model.meterValue < 0.25
        return HStack(spacing: 8) {
            Text(label).font(.system(size: 10, weight: .heavy, design: .serif)).tracking(1.2)
                .foregroundStyle(low ? Palette.blood : Palette.parchment)
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.parchment.opacity(0.14))
                Capsule().fill(low ? Palette.blood : Palette.faithful).frame(width: max(4, 120 * model.meterValue))
            }
            .frame(width: 120, height: 6)
            if low { Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(Palette.blood) }
            Spacer()
        }
        .padding(.top, 2)
        .animation(.linear(duration: 0.15), value: model.meterValue)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(Int(model.meterValue * 100)) percent")
    }

    // MARK: Over the top

    private var pauseButton: some View {
        Button { model.pause() } label: {
            Image(systemName: "pause.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Palette.parchment)
                .frame(width: 30, height: 30)
                .background(Palette.parchment.opacity(0.12), in: Circle())
                .overlay(Circle().stroke(Palette.parchment.opacity(0.25), lineWidth: 1))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .opacity(model.canPause ? 1 : 0.35)
        .disabled(!model.canPause)
        .accessibilityLabel("Pause")
    }

    private var toast: some View {
        Text(model.toast)
            .font(.system(size: 19, weight: .bold, design: .serif))
            .foregroundStyle(Palette.gold)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Palette.ink.opacity(0.82), in: Capsule())
            .overlay(Capsule().stroke(Palette.gold.opacity(0.5), lineWidth: 1))
            .padding(.top, topInset + 172)
            .scaleEffect(toastShown ? 1 : 0.85)
            .opacity(toastShown ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(!toastShown)
    }

    private func countdownCard(_ number: String) -> some View {
        ZStack {
            Palette.ink.opacity(0.62)
            VStack(spacing: 6) {
                Text(model.title.uppercased())
                    .font(.system(size: 17, weight: .heavy, design: .serif)).tracking(3)
                    .foregroundStyle(Palette.gold)
                Text(number)
                    .font(.system(size: 110, weight: .heavy, design: .serif))
                    .foregroundStyle(Palette.parchment)
                    .shadow(color: Palette.gold.opacity(0.35), radius: 18)
                    .id(number)
                    .transition(reduceMotion ? .opacity : .scale(scale: 1.5).combined(with: .opacity))
                if model.watching {
                    Text("You are watching this one").font(.serif(.footnote)).foregroundStyle(Palette.muted)
                }
            }
            .animation(.easeOut(duration: 0.2), value: number)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .transition(.opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(model.title). Starting in \(number)")
    }

    /// "Time", and then how you did: your count against par, the team's haul, and for a traitor the quest.
    private var endCard: some View {
        ZStack {
            Palette.ink.opacity(0.72)
            VStack(spacing: 18) {
                Text("Time")
                    .font(.system(size: cardShown ? 30 : 64, weight: .heavy, design: .serif)).tracking(2)
                    .foregroundStyle(cardShown ? Palette.gold : Palette.parchment)
                    .shadow(color: Palette.gold.opacity(0.35), radius: 18)
                if cardShown, let summary = model.summary { resultCard(summary) }
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: 440)
        }
        .ignoresSafeArea()
        .allowsHitTesting(cardShown && !model.autoAdvance)
        .transition(.opacity)
        .task {
            try? await Task.sleep(for: .seconds(0.9))
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.45, bounce: 0.2)) { cardShown = true }
        }
    }

    private func resultCard(_ summary: ArenaHUDModel.Summary) -> some View {
        let full = summary.count >= model.steps, made = summary.count >= model.par
        let teamMade = summary.teamTotal >= model.teamGoal
        return VStack(spacing: 14) {
            if !model.watching {
                VStack(spacing: 4) {
                    Label(full ? "Full haul" : made ? "Par made" : "Under par",
                          systemImage: full ? "crown.fill" : made ? "checkmark.seal.fill" : "flag.fill")
                        .font(.serif(.caption, weight: .heavy)).textCase(.uppercase).tracking(2)
                        .foregroundStyle(made ? Palette.faithful : Palette.blood)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(summary.count)").font(.system(size: 64, weight: .heavy, design: .serif)).monospacedDigit()
                            .foregroundStyle(made ? Palette.faithful : Palette.parchment)
                        Text("of \(model.steps) \(model.unit)").font(.serif(.headline)).foregroundStyle(Palette.muted)
                    }
                    Text(made ? "Par was \(model.par)." : "Par was \(model.par). The whole table will see it.")
                        .font(.serif(.footnote)).foregroundStyle(Palette.muted)
                }
                Rectangle().fill(Palette.line).frame(height: 1)
            }
            HStack {
                Label("Team", systemImage: "person.3.fill").font(.serif(.subheadline, weight: .semibold)).foregroundStyle(Palette.gold)
                Spacer()
                if teamMade { Image(systemName: "checkmark").font(.caption.weight(.heavy)).foregroundStyle(Palette.faithful) }
                Text("\(summary.teamTotal) of \(model.teamGoal)").font(.serif(.subheadline, weight: .bold)).monospacedDigit()
                    .foregroundStyle(teamMade ? Palette.faithful : Palette.parchment)
            }
            if let quest = summary.quest {
                HStack {
                    Label("Side quest", systemImage: "eye.slash.fill").font(.serif(.subheadline, weight: .semibold))
                    Spacer()
                    Text(quest ? "Done" : "Not done").font(.serif(.subheadline, weight: .bold))
                }
                .foregroundStyle(quest ? Palette.blood : Palette.muted)
            }
            if !model.autoAdvance {
                Button("See the scoreboard") {
                    Feedback.play(.tap)
                    model.proceed = true
                }
                .buttonStyle(GoldButtonStyle())
                .padding(.top, 4)
            }
        }
        .padding(18)
        .background(Palette.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: Tokens.Radius.sheet))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.sheet).stroke(Palette.gold.opacity(0.4), lineWidth: 1))
        .transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
    }
}
