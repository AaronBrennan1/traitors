import SwiftUI

/// What the top of a mini-game shows. The scene writes it; the view only reads.
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
        /// What the player did themselves. Only they are ever shown it.
        struct Own {
            let bags: Int
            let streak: Int
            let near: Int
            let best: Int
            let record: Bool
        }
        /// What a traitor's hand did.
        struct Hand {
            let uses: Int
            let cost: Int
            let sank: Bool
        }
        let teamTotal: Int
        let own: Own?
        /// Nil unless the player is a traitor.
        let hand: Hand?
    }

    let kind: MissionKind
    let title: String
    let unit: String
    let teamGoal: Int
    let seats: [Seat]
    /// The human is out of the game, or a bot is playing the seat.
    let watching: Bool
    /// What the shadow's hand does, for a traitor. Nil for everyone else.
    let handText: String?

    var seconds = 0
    var timeFraction = 1.0
    var urgent = false
    var teamTotal = 0
    /// Bags each seat has put in the vault, in the order of `seats`.
    var banked: [Int] = []
    /// 0...1 while the vault is sealing on a full pile.
    var sealing = 0.0
    var carry = 0
    var streak = 0
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

    init(config: ArenaConfig, core: Gauntlet) {
        kind = config.setup.kind
        title = kind.title
        unit = kind.spec.unit
        teamGoal = core.goal
        seats = config.cast.map { Seat(id: $0.id, name: $0.name, color: Color(uiColor: $0.color), isHuman: $0.isHuman && !config.spectating) }
        watching = config.spectating || !config.cast.contains { $0.isHuman }
        handText = config.handVisible ? MissionKind.hand : nil
        banked = Array(repeating: 0, count: config.cast.count)
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

/// What sits over the gauntlet: the clock, what the company has in the vault against its goal, and
/// who has put how much in. Only the pause button takes a touch; the rest lets the thumbs through.
struct ArenaHUDView: View {
    let model: ArenaHUDModel
    /// The status bar's height, in the view's own points.
    var topInset: CGFloat = 0
    @State private var toastShown = false
    @State private var cardShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var made: Bool { model.teamTotal >= model.teamGoal }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 7) {
                clockRow
                countRow
                goalBar
                pips
            }
            .padding(.horizontal, 12)
            .padding(.top, topInset + 6)
            .padding(.bottom, 22)
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
            Text("\(model.teamTotal)")
                .font(.system(size: 36, weight: .heavy, design: .serif)).monospacedDigit()
                .foregroundStyle(made ? Palette.faithful : Palette.gold)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.25), value: model.teamTotal)
            VStack(alignment: .leading, spacing: 0) {
                Text("of \(model.teamGoal) \(model.unit)").font(.system(size: 13, weight: .semibold, design: .serif)).foregroundStyle(Palette.parchment)
                HStack(spacing: 3) {
                    if made { Image(systemName: "checkmark.seal.fill").font(.system(size: 10)).foregroundStyle(Palette.faithful) }
                    Text(model.sealing > 0 ? "sealing the vault" : made ? "goal made" : model.watching ? "watching" : "between you all")
                        .font(.system(size: 11, weight: .medium, design: .serif)).foregroundStyle(made ? Palette.faithful : Palette.muted)
                }
            }
            Spacer(minLength: 6)
            if !model.watching { load }
        }
        .frame(height: 40)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The company has \(model.teamTotal) of \(model.teamGoal) \(model.unit)\(made ? ", goal made" : "")")
    }

    /// What the player has in their arms, and how many deliveries they have made without going down.
    private var load: some View {
        HStack(spacing: 5) {
            ForEach(0..<Feel.maxCarry, id: \.self) { i in
                Image(systemName: i < model.carry ? "bag.fill" : "bag").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(i < model.carry ? Palette.gold : Palette.muted.opacity(0.6))
            }
            if model.streak >= Feel.streakBonus {
                Text("x\(model.streak)").font(.system(size: 12, weight: .heavy, design: .serif)).foregroundStyle(Palette.parchment)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Palette.parchment.opacity(0.08), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Carrying \(model.carry) of \(Feel.maxCarry)")
    }

    /// Everyone's token with what they have put in the vault. It is for the player's eyes: the table never hears it.
    private var pips: some View {
        HStack(spacing: 0) {
            ForEach(Array(model.seats.enumerated()), id: \.element.id) { i, seat in
                HStack(spacing: 3) {
                    ArenaToken(seat: seat, size: 15)
                    Text("\(i < model.banked.count ? model.banked[i] : 0)")
                        .font(.system(size: 11, weight: .bold, design: .serif)).monospacedDigit()
                        .foregroundStyle(seat.isHuman ? Palette.gold : Palette.parchment.opacity(0.8))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 18)
        .accessibilityHidden(true)
    }

    /// How far the company is towards its goal.
    private var goalBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.parchment.opacity(0.14))
                Capsule().fill(made ? Palette.faithful.opacity(0.45) : Palette.gold.opacity(0.85))
                    .frame(width: max(5, geo.size.width * min(1, Double(model.teamTotal) / Double(max(model.teamGoal, 1)))))
                // The seal closing over a full vault.
                if model.sealing > 0 { Capsule().fill(Palette.faithful).frame(width: max(5, geo.size.width * model.sealing)) }
            }
        }
        .frame(height: 5)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: model.teamTotal)
        .accessibilityHidden(true)
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
            .padding(.top, topInset + 150)
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

    /// How the round ended, and then how the company did against its goal, what the player did
    /// themselves, and for a traitor what their hand cost.
    private var endCard: some View {
        ZStack {
            Palette.ink.opacity(0.72)
            VStack(spacing: 18) {
                Text(made ? "Sealed" : "Time")
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
        let teamMade = summary.teamTotal >= model.teamGoal
        return VStack(spacing: 14) {
            VStack(spacing: 4) {
                Label(teamMade ? "Goal made" : "Fell short", systemImage: teamMade ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .font(.serif(.caption, weight: .heavy)).textCase(.uppercase).tracking(2)
                    .foregroundStyle(teamMade ? Palette.faithful : Palette.blood)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(summary.teamTotal)").font(.system(size: 64, weight: .heavy, design: .serif)).monospacedDigit()
                        .foregroundStyle(teamMade ? Palette.faithful : Palette.parchment)
                    Text("of \(model.teamGoal) \(model.unit)").font(.serif(.headline)).foregroundStyle(Palette.muted)
                }
                Text(teamMade ? "Between you all. Nobody is murdered tonight."
                              : "Between you all. The traitors have their night.")
                    .font(.serif(.footnote)).foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let own = summary.own {
                Rectangle().fill(Palette.line).frame(height: 1)
                HStack(spacing: 0) {
                    stat("\(own.bags)", own.record ? "your best yet" : "your bags, best \(own.best)", gold: own.record)
                    stat("\(own.streak)", "in a row")
                    stat("\(own.near)", "near misses")
                }
            }
            if let hand = summary.hand {
                HStack {
                    Label("The Shadow's Hand", systemImage: "eye.slash.fill").font(.serif(.subheadline, weight: .semibold))
                    Spacer()
                    Text(hand.uses == 0 ? "Not used" : hand.sank ? "Sank the day" : "Cost them \(hand.cost)")
                        .font(.serif(.subheadline, weight: .bold))
                }
                .foregroundStyle(hand.uses > 0 ? Palette.blood : Palette.muted)
            }
            if !model.autoAdvance {
                Button("See the result") {
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

    private func stat(_ value: String, _ label: String, gold: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 24, weight: .heavy, design: .serif)).monospacedDigit()
                .foregroundStyle(gold ? Palette.gold : Palette.parchment)
            Text(label).font(.serif(.caption2)).foregroundStyle(gold ? Palette.gold : Palette.muted)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}
