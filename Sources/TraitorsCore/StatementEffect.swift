import Foundation

/// What a kind of statement means, said once. The index of the record, the inference, the
/// table's mood and the lab's statistics all read this and carry no table of their own.
package struct StatementEffect {
    /// How a listener takes it as evidence about speaker and target.
    package enum Reading: String {
        case accuse
        /// Pointing back at an accuser while defending oneself.
        case rebuttal
        /// Naming someone under less than full conviction: a declared vote, an answer when asked.
        case soft
        case doubt
        case defend
        case vouch

        /// The heading the lab's statistics file it under.
        package var family: String { self == .rebuttal ? Reading.soft.rawValue : rawValue }
    }

    /// Points the finger at its target, for "who named them first".
    package var names = false
    /// How hard it counts as going after the target, over the whole game.
    package var attack = 0.0
    /// How hard it counts as pushing for the target's banishment at today's table.
    package var push = 0.0
    /// Commits the speaker to a vote for the target.
    package var declares = false
    /// An accusation, callout or doubt on the record.
    package var flags = false
    /// Stakes the speaker's own name on the target.
    package var vouches = false
    /// What it does to the table's mood towards the target, per unit of the speaker's voice.
    /// Negative cools it.
    package var heat = 0.0
    /// The target takes it personally.
    package var grudge = false
    package var reading: Reading? = nil
}

extension StatementKind {
    package var effect: StatementEffect {
        switch self {
        case .accuse:
            return StatementEffect(names: true, attack: 1, push: 1, flags: true, heat: 1, grudge: true, reading: .accuse)
        case .callout:
            return StatementEffect(names: true, attack: 1, push: 1, flags: true, heat: 0.8, grudge: true, reading: .accuse)
        case .challenge:
            return StatementEffect(names: true, attack: 1, push: 1, flags: true, heat: 1.2, grudge: true, reading: .accuse)
        case .selfDefend:
            return StatementEffect(names: true, attack: 0.5, push: 0.5, heat: 0.4, reading: .rebuttal)
        case .answer, .declare:
            return StatementEffect(names: true, attack: 0.5, push: 0.5, declares: true, heat: 0.5, reading: .soft)
        case .doubt:
            return StatementEffect(attack: 0.25, flags: true, heat: 0.25, reading: .doubt)
        case .defend:
            return StatementEffect(heat: -0.6, reading: .defend)
        case .vouch:
            return StatementEffect(vouches: true, heat: -0.9, reading: .vouch)
        case .question, .pass:
            return StatementEffect()
        }
    }
}
