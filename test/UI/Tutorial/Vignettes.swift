import SwiftUI
import SpriteKit
import TraitorsEngine
import TraitorsGauntlet

/// One scene of the walkthrough: a few seconds of moving picture and the one line that goes under it.
struct Vignette: Identifiable {
    let id: Int
    /// The one line.
    let line: String
    /// What the scene shows, said in full, for VoiceOver.
    let spoken: String
    var duration = 5.5
    /// The moment that says it all, for anyone who would rather nothing moved.
    let poster: Double

    static let all: [Vignette] = [
        Vignette(id: 0, line: "Eight sit down. Two are secretly traitors.",
                 spoken: "Eight players sit down in the castle. Two of them are secretly traitors. The faithful win by banishing every traitor. The traitors win by surviving to the end, or once there are as many of them as faithful.",
                 poster: 3.0),
        Vignette(id: 1, line: "Breakfast. Mission. Round Table. Night.",
                 spoken: "Breakfast shows who was murdered in the night. Then everyone plays the day's mission together, and wins or loses it together. At the Round Table you talk, vote, and banish one player. Then night falls.",
                 poster: 2.6),
        Vignette(id: 2, line: "Reach the goal together and the night is safe.",
                 spoken: "Every day is a different game, and everyone plays at once. It all counts towards one goal. Make it between you and there is no murder that night. Fall short and the traitors have their night.",
                 duration: 6.4, poster: 5.6),
        Vignette(id: 3, line: "Traitors spoil it in secret. Unless they are seen.",
                 spoken: "A traitor plays the same game with one thing more. Every game has something that can be made to go wrong. Stand still beside it and tap the button, and the team loses some of what it had. Nothing on the screen says whose hand it was, but anyone close by sees who was standing there, and can say so at the table. It is only their word, and a traitor can invent a sighting.",
                 poster: 4.2),
        Vignette(id: 4, line: "Talk it out. Vote. Banish one.",
                 spoken: "At the Round Table you speak twice. Accuse or defend someone with a piece of real evidence, or put a question to another player. Then everyone votes and the banished player reveals their role. The others notice when your words and your vote do not match.",
                 poster: 3.4),
        Vignette(id: 5, line: "Banish every traitor before the night takes you.",
                 spoken: "Each night the traitors murder one of the faithful, unless the company made its goal. Once in a game a lone traitor recruits instead. With four or fewer left there are no more missions or murders, and the game only ends when everyone still standing votes to end it.",
                 poster: 5.0),
    ]
}

/// 0 before `from`, 1 after `to`, and eased in between.
private func ease(_ t: Double, _ from: Double, _ to: Double) -> Double {
    let k = min(max((t - from) / max(to - from, 0.001), 0), 1)
    return k * k * (3 - 2 * k)
}

/// Springs past 1 on the way in, for something that lands.
private func land(_ t: Double, _ at: Double, over: Double = 0.42) -> Double {
    let k = min(max((t - at) / over, 0), 1)
    return k == 0 ? 0 : 1 + 0.22 * sin(k * .pi) * (1 - k)
}

/// A game's reel with nothing round it, for a scene that wants the picture alone.
private struct DemoPicture: View {
    let kind: MissionKind
    var reel: ArenaDemo.Reel = .play
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var scene: DemoScene?

    var body: some View {
        ZStack {
            Palette.ink
            if let scene { SpriteView(scene: scene) }
        }
        .onAppear { show() }
        .onChange(of: kind) { show() }
        .onChange(of: scenePhase) { _, phase in scene?.playing = phase == .active }
        .onDisappear { scene = nil }
    }

    private func show() {
        if let scene { scene.load(kind: kind, reel: reel) } else { scene = DemoScene(kind: kind, reel: reel, still: reduceMotion) }
    }
}

/// The scenes of the walkthrough. Each is drawn from nothing but how many seconds in it is, so
/// it can be paused, shown as a still, or started again, and always looks the same at the same moment.
struct VignetteView: View {
    let index: Int
    /// Seconds into the scene.
    let t: Double

    private static let seats: [(name: String, cloak: Color, human: Bool)] =
        [("You", Tokens.Hue.youCloak.color, true)] + Cast.bots.map { ($0.name, Palette.cloak($0.hue), false) }
    /// The two who are not what they seem, and the one the table turns on.
    private static let traitors: Set<Int> = [3, 6]
    private static let accused = 3

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                switch index {
                case 0: gathering(size)
                case 1: day(size)
                case 2: mission(size)
                case 3: hand(size)
                case 4: table(size)
                default: night(size)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .accessibilityHidden(true)
    }

    // MARK: - The table, which three of the scenes share

    private func seat(_ i: Int, _ size: CGSize) -> CGPoint {
        let a = Double(i) / 8 * 2 * .pi - .pi / 2
        return CGPoint(x: size.width * (0.5 + 0.36 * cos(a)), y: size.height * (0.5 + 0.31 * sin(a)))
    }

    /// The room: dark, with the table in the middle of it and a candle on the table.
    private func room(_ size: CGSize, light: Double = 1, wash: Color = .clear) -> some View {
        ZStack {
            Palette.panel
            RadialGradient(colors: [Tokens.Hue.ember.color.opacity(0.30 * light), .clear], center: .center, startRadius: 0, endRadius: size.width * 0.62)
            Ellipse()
                .fill(LinearGradient(colors: [Tokens.Hue.wood.color.opacity(0.9), Tokens.Hue.woodDark.color], startPoint: .top, endPoint: .bottom))
                .overlay(Ellipse().strokeBorder(Palette.gold.opacity(0.35), lineWidth: 1.5))
                .frame(width: size.width * 0.44, height: size.height * 0.30)
                .shadow(color: .black.opacity(0.5), radius: 12, y: 8)
            Image(systemName: "flame.fill")
                .font(.system(size: size.width * 0.07))
                .foregroundStyle(Tokens.Hue.ember.color.opacity(0.35 + 0.65 * light))
                .shadow(color: Tokens.Hue.ember.color.opacity(light), radius: 12)
                .scaleEffect(1 + 0.05 * sin(t * 9))
            wash
        }
    }

    /// One player at the table. `hood` is how far the hood is up, 0...1.
    private func face(_ i: Int, _ size: CGSize, show: Double = 1, hood: Double = 0, ring: Color? = nil, gone: Double = 0) -> some View {
        let s = Self.seats[i]
        let d = size.width * 0.17
        return ZStack {
            Portrait(name: s.name, cloak: s.cloak, size: d, human: s.human).opacity(1 - hood)
            Portrait(name: s.name, cloak: s.cloak, size: d, hooded: true, human: s.human).opacity(hood)
        }
        .overlay(Circle().strokeBorder(ring ?? (s.human ? Palette.gold : .clear), lineWidth: 2.5).padding(-4))
        .shadow(color: (ring ?? .clear).opacity(0.8), radius: 10)
        .saturation(1 - 0.9 * gone)
        .opacity(min(show, 1) * (1 - 0.7 * gone))
        .scaleEffect(max(show, 0.001) * (1 - 0.12 * gone))
        .position(seat(i, size))
    }

    // MARK: - Eight sit down. Two are secretly traitors.

    private func gathering(_ size: CGSize) -> some View {
        // The light dips while the two show themselves, and comes back when they have hidden again.
        let reveal = ease(t, 2.3, 2.8) - ease(t, 4.1, 4.7)
        return ZStack {
            room(size, light: 1 - 0.7 * reveal, wash: Palette.blood.opacity(0.10 * reveal))
            ForEach(0..<8, id: \.self) { i in
                let mine = Self.traitors.contains(i)
                face(i, size, show: land(t, 0.25 + 0.14 * Double(i)), hood: mine ? reveal : 0,
                     ring: mine && reveal > 0.05 ? Palette.blood.opacity(reveal) : nil)
            }
        }
    }

    // MARK: - Breakfast. Mission. Round Table. Night.

    private func day(_ size: CGSize) -> some View {
        let icons = ["cup.and.saucer.fill", "flag.checkered", "person.3.fill", "moon.stars.fill"]
        // Dawn, noon, dusk, night: the sky behind turns as the day goes round.
        let skies: [Color] = [Color(red: 0.86, green: 0.58, blue: 0.42), Color(red: 0.40, green: 0.58, blue: 0.72),
                              Color(red: 0.62, green: 0.36, blue: 0.40), Color(red: 0.10, green: 0.13, blue: 0.26)]
        let go = min(max((t - 0.5) / 4.2, 0), 1) * 3
        let at = min(Int(go), 2), mix = go - Double(at)
        func spot(_ k: Double) -> CGPoint {
            // An arc across the picture, the way the sun goes.
            let x = 0.15 + 0.2333 * k
            return CGPoint(x: size.width * x, y: size.height * (0.6 - 0.2 * sin(k / 3 * .pi)))
        }
        return ZStack {
            Palette.panel
            LinearGradient(colors: [skies[at].opacity(0.55), .clear], startPoint: .top, endPoint: .bottom).opacity(1 - mix)
            LinearGradient(colors: [skies[at + 1].opacity(0.55), .clear], startPoint: .top, endPoint: .bottom).opacity(mix)
            Circle().fill(RadialGradient(colors: [skies[min(at + (mix > 0.5 ? 1 : 0), 3)].opacity(0.55), .clear], center: .center, startRadius: 0, endRadius: size.width * 0.3))
                .frame(width: size.width * 0.6, height: size.width * 0.6)
                .position(spot(go))
            // The road between them, and how much of it the day has travelled.
            Path { p in
                p.move(to: spot(0))
                for k in stride(from: 0.1, through: 3.001, by: 0.1) { p.addLine(to: spot(k)) }
            }
            .stroke(Palette.parchment.opacity(0.18), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 7]))
            Path { p in
                p.move(to: spot(0))
                for k in stride(from: 0.05, through: max(go, 0.05), by: 0.05) { p.addLine(to: spot(k)) }
            }
            .stroke(Palette.gold, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            ForEach(0..<4, id: \.self) { i in
                let lit = ease(go, Double(i) - 0.35, Double(i))
                let now = max(0, 1 - abs(go - Double(i)) * 2.2)
                Image(systemName: icons[i])
                    .font(.system(size: size.width * 0.09, weight: .semibold))
                    .foregroundStyle(lit > 0.5 ? Palette.ink : Palette.gold.opacity(0.6))
                    .frame(width: size.width * 0.2, height: size.width * 0.2)
                    .background(Circle().fill(Palette.gold.opacity(lit)))
                    .background(Circle().fill(Palette.ink.opacity(0.8)))
                    .overlay(Circle().strokeBorder(Palette.gold.opacity(0.7), lineWidth: 1.5))
                    .shadow(color: Palette.gold.opacity(0.7 * now), radius: 14)
                    .scaleEffect(land(t, 0.1 + 0.1 * Double(i)) * (1 + 0.16 * now))
                    .position(spot(Double(i)))
            }
        }
    }

    // MARK: - Reach the goal together and the night is safe.

    private func mission(_ size: CGSize) -> some View {
        // Three days' games, cut together, and one bar they all fill.
        let cuts: [MissionKind] = [.sheepRoundUp, .marketDay, .greatHall]
        let shot = min(Int(t / 1.9), cuts.count - 1)
        let dip = 1 - min(abs(t - 1.9), abs(t - 3.8), 0.14) / 0.14
        let fill = ease(t, 0.4, 5.0)
        let safe = land(t, 5.2)
        return ZStack {
            DemoPicture(kind: cuts[shot])
            Palette.ink.opacity(dip)
            VStack(spacing: 10) {
                Spacer()
                ZStack {
                    Image(systemName: "moon.stars.fill").foregroundStyle(Palette.parchment.opacity(0.5 * (1 - min(safe, 1))))
                    Image(systemName: "checkmark.shield.fill").foregroundStyle(Palette.faithful)
                        .scaleEffect(max(safe, 0.001)).opacity(min(safe, 1))
                        .shadow(color: Palette.faithful.opacity(0.8), radius: 12)
                }
                .font(.system(size: size.width * 0.12))
                GeometryReader { bar in
                    Capsule().fill(Palette.parchment.opacity(0.2))
                        .overlay(alignment: .leading) {
                            Capsule().fill(fill >= 1 ? Palette.faithful : Palette.gold).frame(width: bar.size.width * fill)
                        }
                }
                .frame(height: 7)
                .padding(.horizontal, size.width * 0.12)
            }
            .padding(.bottom, size.height * 0.05)
            .frame(maxWidth: .infinity)
            .background(LinearGradient(colors: [.clear, Palette.ink.opacity(0.9)], startPoint: UnitPoint(x: 0.5, y: 0.6), endPoint: .bottom))
        }
    }

    // MARK: - Traitors spoil it in secret. Unless they are seen.

    private func hand(_ size: CGSize) -> some View {
        let seen = land(t, 3.3)
        let from = CGPoint(x: size.width * 0.80, y: size.height * 0.22), to = CGPoint(x: size.width * 0.52, y: size.height * 0.66)
        let sight = ease(t, 3.5, 4.1)
        return ZStack {
            DemoPicture(kind: .marketDay, reel: .hand)
            Palette.blood.opacity(0.10)
            // Somebody was looking.
            Path { p in
                p.move(to: from)
                p.addLine(to: CGPoint(x: from.x + (to.x - from.x) * sight, y: from.y + (to.y - from.y) * sight))
            }
            .stroke(Palette.parchment.opacity(0.85), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 6]))
            ZStack(alignment: .bottomTrailing) {
                Portrait(name: Self.seats[1].name, cloak: Self.seats[1].cloak, size: size.width * 0.2)
                    .overlay(Circle().strokeBorder(Palette.parchment, lineWidth: 2))
                Image(systemName: "eye.fill")
                    .font(.system(size: size.width * 0.055, weight: .bold)).foregroundStyle(Palette.ink)
                    .padding(5).background(Palette.parchment, in: Circle())
                    .offset(x: 6, y: 6)
            }
            .shadow(color: .black.opacity(0.6), radius: 8, y: 4)
            .scaleEffect(max(seen, 0.001)).opacity(min(seen, 1))
            .position(from)
        }
    }

    // MARK: - Talk it out. Vote. Banish one.

    private func table(_ size: CGSize) -> some View {
        let talk: [(seat: Int, icon: String, at: Double)] = [(1, "exclamationmark.bubble.fill", 0.4), (5, "hand.raised.fill", 0.9),
                                                             (7, "questionmark.bubble.fill", 1.4)]
        let out = ease(t, 4.0, 4.6)
        let target = seat(Self.accused, size)
        let voters = (0..<8).filter { $0 != Self.accused }
        let cast = voters.enumerated().filter { t >= 2.2 + 0.2 * Double($0.offset) + 0.45 }.count
        return ZStack {
            room(size, wash: Palette.blood.opacity(0.08 * out))
            ForEach(0..<8, id: \.self) { i in
                let it = i == Self.accused
                face(i, size, hood: it ? out : 0, ring: it && cast > 0 ? Palette.blood.opacity(min(1, Double(cast) / 4)) : nil, gone: it ? out * 0.6 : 0)
            }
            // What is said: an accusation, a defence, a question.
            ForEach(talk.indices, id: \.self) { k in
                let p = seat(talk[k].seat, size)
                let up = land(t, talk[k].at) * (1 - ease(t, 1.9, 2.2))
                Image(systemName: talk[k].icon)
                    .font(.system(size: size.width * 0.085)).foregroundStyle(Palette.parchment)
                    .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
                    .scaleEffect(max(up, 0.001)).opacity(min(up, 1))
                    .position(x: p.x + size.width * 0.07, y: p.y - size.width * 0.12)
            }
            // The votes, one from every seat, all to the one place.
            ForEach(voters.indices, id: \.self) { k in
                let from = seat(voters[k], size)
                let go = ease(t, 2.2 + 0.2 * Double(k), 2.65 + 0.2 * Double(k))
                RoundedRectangle(cornerRadius: 2).fill(Palette.parchment)
                    .frame(width: size.width * 0.045, height: size.width * 0.06)
                    .rotationEffect(.degrees(go * 200 + Double(k) * 30))
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
                    .opacity(go > 0 && go < 1 ? 1 : 0)
                    .position(x: from.x + (target.x - from.x) * go, y: from.y + (target.y - from.y) * go - sin(go * .pi) * size.height * 0.07)
            }
            Text("\(cast)")
                .font(Tokens.TypeRole.numeral.font(.title3)).foregroundStyle(Palette.parchment)
                .frame(width: size.width * 0.1, height: size.width * 0.1)
                .background(Palette.blood, in: Circle())
                .scaleEffect(cast > 0 ? 1 : 0.001).opacity(cast > 0 ? 1 - out : 0)
                .position(x: target.x + size.width * 0.09, y: target.y - size.width * 0.09)
            Image(systemName: "door.left.hand.open")
                .font(.system(size: size.width * 0.07, weight: .bold)).foregroundStyle(Palette.parchment)
                .padding(6).background(Palette.blood, in: Circle())
                .scaleEffect(max(land(t, 4.3), 0.001)).opacity(min(land(t, 4.3), 1))
                .position(x: target.x + size.width * 0.09, y: target.y - size.width * 0.09)
        }
    }

    // MARK: - Banish every traitor before the night takes you.

    private func night(_ size: CGSize) -> some View {
        let dark = ease(t, 0.2, 0.9) - ease(t, 2.2, 2.9)
        let murdered = 5
        let taken = ease(t, 1.2, 1.7)
        let first = ease(t, 3.1, 3.6), second = ease(t, 3.9, 4.4)
        let won = land(t, 4.8)
        return ZStack {
            room(size, light: 1 - 0.75 * dark, wash: Color(red: 0.05, green: 0.08, blue: 0.22).opacity(0.55 * dark))
            Image(systemName: "moon.stars.fill")
                .font(.system(size: size.width * 0.1)).foregroundStyle(Palette.parchment.opacity(0.85))
                .opacity(dark).position(x: size.width * 0.15, y: size.height * (0.13 + 0.03 * (1 - dark)))
            ForEach(0..<8, id: \.self) { i in
                let mine = Self.traitors.contains(i)
                let caught = i == Self.accused ? first : (mine ? second : 0)
                face(i, size, hood: caught, ring: caught > 0.05 ? Palette.blood.opacity(caught) : nil,
                     gone: i == murdered ? taken : caught * ease(t, i == Self.accused ? 3.5 : 4.3, i == Self.accused ? 3.9 : 4.7))
            }
            // The one the night took.
            Image(systemName: "xmark")
                .font(.system(size: size.width * 0.09, weight: .heavy)).foregroundStyle(Palette.blood)
                .scaleEffect(max(land(t, 1.5), 0.001)).opacity(min(land(t, 1.5), 1))
                .position(seat(murdered, size))
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: size.width * 0.24)).foregroundStyle(Palette.faithful)
                .background(Circle().fill(Palette.ink).padding(8))
                .shadow(color: Palette.faithful.opacity(0.8), radius: 18)
                .scaleEffect(max(won, 0.001)).opacity(min(won, 1))
        }
    }
}
