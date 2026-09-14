import Foundation

public struct SaveEnvelope: Codable {
    public var version: Int = 1
    public var business: BusinessState
    public init(business: BusinessState) { self.business = business }
}
public protocol BusinessRepository {
    func load() throws -> BusinessState?
    func save(_ state: BusinessState) throws
}
public struct FileBusinessRepository: BusinessRepository {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public var url: URL { directory.appendingPathComponent("business.json") }
    public var backupURL: URL { directory.appendingPathComponent("business.previous.json") }
    public func load() throws -> BusinessState? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Self.decode(Data(contentsOf: url))
    }
    public static func decode(_ data: Data) throws -> BusinessState {
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(SaveEnvelope.self, from: data)
        guard envelope.version == 1, envelope.business.schemaVersion == 1 else { throw GameError.invalid("This save needs a newer version of PawBoss. It has not been changed.") }
        let catalog = try Catalog.bundled()
        _ = try GameEngine(state: envelope.business, catalog: catalog)
        return envelope.business
    }
    public func save(_ state: BusinessState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(SaveEnvelope(business: state))
        _ = try Self.decode(data)
        if FileManager.default.fileExists(atPath: url.path) {
            let previous = try Data(contentsOf: url)
            // Never replace the last good backup with unreadable data.
            _ = try Self.decode(previous)
            try previous.write(to: backupURL, options: .atomic)
        }
        try data.write(to: url, options: .atomic)
    }
    public func recoverBackup() throws -> BusinessState {
        let recovered = try Self.decode(Data(contentsOf: backupURL))
        if FileManager.default.fileExists(atPath: url.path) {
            let quarantine = directory.appendingPathComponent("unreadable-\(UUID().uuidString).json")
            try FileManager.default.copyItem(at: url, to: quarantine)
        }
        try JSONEncoder().encode(SaveEnvelope(business: recovered)).write(to: url, options: .atomic)
        return recovered
    }
}
public struct WatchOutbox: Codable {
    public private(set) var pending: [GameCommand] = []
    public private(set) var results: [Receipt] = []
    public init() {}
    public mutating func enqueue(_ command: GameCommand) {
        guard !pending.contains(where: { $0.id == command.id }), !results.contains(where: { $0.id == command.id }) else { return }
        pending.append(command)
    }
    public mutating func receive(_ receipt: Receipt) {
        guard pending.contains(where: { $0.id == receipt.id }) else { return }
        pending.removeAll { $0.id == receipt.id }
        results.removeAll { $0.id == receipt.id }; results.append(receipt)
        if results.count > 100 { results.removeFirst(results.count - 100) }
    }
}
