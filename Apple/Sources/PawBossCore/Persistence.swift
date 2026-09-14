import Foundation
import CryptoKit

public struct SaveEnvelope: Codable {
    public var version: Int = 2
    public var business: BusinessState
    public var checksum: String?
    public init(business: BusinessState) { self.business = business }
    enum CodingKeys: String, CodingKey { case version, business, checksum }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(version, forKey: .version)
        try values.encode(business, forKey: .business)
        if version >= 2 { try values.encode(Self.digest(business), forKey: .checksum) }
    }
    public static func digest(_ business: BusinessState) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return SHA256.hash(data: try encoder.encode(business)).map { String(format: "%02x", $0) }.joined()
    }
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
        guard [1, 2].contains(envelope.version), envelope.business.schemaVersion == 1 else { throw GameError.invalid("This save needs a newer version of PawBoss. It has not been changed.") }
        if envelope.version == 2 {
            guard envelope.checksum == (try SaveEnvelope.digest(envelope.business)) else { throw GameError.invalid("This save's integrity check failed. The previous backup has been preserved.") }
        }
        // Version 1 has the same business schema. The next successful save adds
        // the version 2 checksum without changing identities or replay receipts.
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
