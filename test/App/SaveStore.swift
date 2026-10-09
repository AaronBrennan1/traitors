import Foundation
import TraitorsEngine

/// Somewhere to keep small named values between launches.
protocol SaveStore: AnyObject {
    func data(named name: String) -> Data?
    func write(_ data: Data, named name: String)
    func delete(_ name: String)
}

extension SaveStore {
    func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        data(named: name).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    func save<T: Encodable>(_ value: T, to name: String) {
        if let data = try? JSONEncoder().encode(value) { write(data, named: name) }
    }
}

/// JSON files in a folder: Application Support by default.
final class FileSaveStore: SaveStore {
    private let folder: URL

    init(folder: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.folder = folder ?? base.appendingPathComponent("Traitors", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true)
    }

    func data(named name: String) -> Data? { try? Data(contentsOf: folder.appendingPathComponent(name)) }
    func write(_ data: Data, named name: String) { try? data.write(to: folder.appendingPathComponent(name), options: .atomic) }
    func delete(_ name: String) { try? FileManager.default.removeItem(at: folder.appendingPathComponent(name)) }
}

/// Nothing leaves memory. For tests and previews.
final class MemorySaveStore: SaveStore {
    private(set) var files: [String: Data] = [:]
    /// How many times each name has been written, so a test can count saves.
    private(set) var writes: [String: Int] = [:]

    func data(named name: String) -> Data? { files[name] }
    func write(_ data: Data, named name: String) { files[name] = data; writes[name, default: 0] += 1 }
    func delete(_ name: String) { files[name] = nil }
}

/// A game on disk, with the version of the format it was written in. A save from any other
/// version is not read: `Game`'s encoded form changes with the rules.
struct SavedGame: Codable {
    static let current = 9
    static let file = "game.json"
    /// File names used before the version moved inside the file.
    static let legacy = ["save.json"] + (2...8).map { "save-v\($0).json" }

    var version = SavedGame.current
    var game: Game

    private struct Header: Decodable { var version: Int }

    static func read(from session: SaveStore) -> Game? {
        guard let data = session.data(named: file),
              let header = try? JSONDecoder().decode(Header.self, from: data), header.version == current else { return nil }
        return (try? JSONDecoder().decode(SavedGame.self, from: data))?.game
    }

    static func write(_ game: Game, to session: SaveStore) {
        session.save(SavedGame(game: game), to: file)
    }
}
