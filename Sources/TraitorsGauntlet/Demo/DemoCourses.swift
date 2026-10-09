import Foundation
import TraitorsCore

/// A short stretch of each course of the gauntlet, for its demonstration: seventeen rows from
/// hoard to vault, so the whole run is in the picture at once, with the one thing that course is
/// known for in the middle of it. The traps are the course's own and keep their own time.
enum DemoCourses {
    /// The middle of a tile, counting columns from the left and rows from the top of the drawing.
    static func point(_ col: Double, _ row: Double) -> Vec2 {
        Vec2((col + 0.5) * Course.cell, (16 - row + 0.5) * Course.cell)
    }

    static func course(_ kind: MissionKind) -> Course { Course(kind, blueprint(kind)) }

    static func blueprint(_ kind: MissionKind) -> Blueprint {
        switch kind {
        case .cellars: return cellars
        case .armoury: return armoury
        case .battlements: return battlements
        case .crypt: return crypt
        default: return greatHall
        }
    }

    /// Two of the hall's blades, a beat apart.
    private static let greatHall = Blueprint(rows: [
        "#############",
        "#VVVVVVVVVVV#",
        "#VVVVVVVVVVV#",
        "#...........#",
        "#...........#",
        "#1.........1#",
        "#...........#",
        "#...........#",
        "#2.........2#",
        "#...........#",
        "#...........#",
        "#.....B.....#",
        "#...........#",
        "#...........#",
        "#HHHHHHHHHHH#",
        "#HHHHHHHHHHH#",
        "#############",
    ], traps: [
        Trap(kind: .blade, mark: "1", period: 2.4),
        Trap(kind: .blade, mark: "2", period: 2.4, offset: 0.8),
    ])

    /// The short lane on the left with a barrel coming down it, and the long way round on the right.
    private static let cellars = Blueprint(rows: [
        "#############",
        "#VVVVVVVVVVV#",
        "#VVVVVVVVVVV#",
        "#...........#",
        "#.1.#.......#",
        "#...#.......#",
        "#...####....#",
        "#...#.......#",
        "#...#...#####",
        "#...#.......#",
        "#.1.#.......#",
        "#.....B.....#",
        "#...........#",
        "#...........#",
        "#HHHHHHHHHHH#",
        "#HHHHHHHHHHH#",
        "#############",
    ], traps: [
        Trap(kind: .barrel, mark: "1", period: 3.6, offset: 1.5),
    ])

    /// A plate in the middle of the floor, the darts two paces on, and a bed of spikes to one side.
    private static let armoury = Blueprint(rows: [
        "#############",
        "#VVVVVVVVVVV#",
        "#VVVVVVVVVVV#",
        "#...........#",
        "#...........#",
        "#3.........3#",
        "#...........#",
        "#.....x.....#",
        "#...........#",
        "#.4.........#",
        "#...4.......#",
        "#.....B.....#",
        "#...........#",
        "#...........#",
        "#HHHHHHHHHHH#",
        "#HHHHHHHHHHH#",
        "#############",
    ], traps: [
        Trap(kind: .darts, mark: "3", plate: "x"),
        Trap(kind: .spikes, mark: "4", period: 2.6, offset: 0.4),
    ])

    /// Open edges and one gust across the whole walk.
    private static let battlements = Blueprint(rows: [
        "#############",
        "#VVVVVVVVVVV#",
        "#VVVVVVVVVVV#",
        "#...........#",
        " ........... ",
        " 1.......... ",
        " ........... ",
        " ..........1 ",
        " ........... ",
        "#...........#",
        " ........... ",
        "#.....B.....#",
        "#...........#",
        "#...........#",
        "#HHHHHHHHHHH#",
        "#HHHHHHHHHHH#",
        "#############",
    ], traps: [
        Trap(kind: .gust, mark: "1", period: 5, offset: 3.4, push: Vec2(120, 0)),
    ])

    /// Two grates of flame, and no seeing further than the candles let you.
    private static let crypt = Blueprint(rows: [
        "#############",
        "#VVVVVVVVVVV#",
        "#VVVVVVVVVVV#",
        "#...........#",
        "#...........*",
        "#1.....1....#",
        "#...........#",
        "#...........#",
        "#....2....2.#",
        "#...........#",
        "*...........#",
        "#.....B.....#",
        "#...........#",
        "#...........#",
        "#HHHHHHHHHHH#",
        "#HHHHHHHHHHH#",
        "#############",
    ], traps: [
        Trap(kind: .flame, mark: "1", period: 3),
        Trap(kind: .flame, mark: "2", period: 3, offset: 1.5),
    ], vision: 110)
}
