import Foundation

public enum Soundscape: String, CaseIterable {
    case office, care, outdoors, rain
    public static func outdoors(weather: String) -> Soundscape { weather.lowercased().contains("rain") ? .rain : .outdoors }
}
public enum AudioMix {
    public static let categories = ["Music", "Ambience", "Dogs", "Customers", "Office", "Gameplay"]
    public static let defaults = Dictionary(uniqueKeysWithValues: categories.map { ($0, 0.5) })
    public static func gain(_ category: String, volumes: [String: Double]) -> Double {
        let value = volumes[category] ?? 0.5
        return value.isFinite ? min(1, max(0, value)) : 0.5
    }
    public static func migrated(_ volumes: [String: Double], version: Int) -> [String: Double] {
        let old = ["Music": 0.15, "Ambience": 0.15, "Dogs": 0.25, "Customers": 0.3, "Office": 0.25, "Gameplay": 0.35]
        return Dictionary(uniqueKeysWithValues: categories.map { category in
            let value = volumes[category]
            return (category, version < 2 && (value == nil || value == old[category]) ? 0.5 : gain(category, volumes: volumes))
        })
    }
}
public struct MusicRotation {
    private var remaining: [String] = []
    private var previous: String?
    public init() {}
    public mutating func next(from tracks: [String]) -> String? {
        let unique = Array(Set(tracks)).sorted()
        guard !unique.isEmpty else { return nil }
        remaining.removeAll { !unique.contains($0) }
        if remaining.isEmpty { remaining = unique.shuffled() }
        if remaining.count > 1, remaining.last == previous { remaining.swapAt(0, remaining.count - 1) }
        let next = remaining.removeLast(); previous = next; return next
    }
}
public struct AppPreferences: Codable {
    public var appearance = "System"
    public var reduceMotion = false
    public var adviser = true
    public var haptics = true
    public var volumes = AudioMix.defaults
    public var audioDefaultsVersion = 2
    public var notifications = ["Enquiries": true, "Medication": true, "Vaccinations": true, "Inspections": true, "Staff": true, "Messages": true, "Reports": true, "Anniversaries": true]
    public var notificationEnabled = false
    public init() {}
    private enum CodingKeys: String, CodingKey { case appearance, reduceMotion, adviser, haptics, volumes, audioDefaultsVersion, notifications, notificationEnabled }
    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        appearance = try values.decodeIfPresent(String.self, forKey: .appearance) ?? appearance
        reduceMotion = try values.decodeIfPresent(Bool.self, forKey: .reduceMotion) ?? reduceMotion
        adviser = try values.decodeIfPresent(Bool.self, forKey: .adviser) ?? adviser
        haptics = try values.decodeIfPresent(Bool.self, forKey: .haptics) ?? haptics
        notifications = try values.decodeIfPresent([String: Bool].self, forKey: .notifications) ?? notifications
        notificationEnabled = try values.decodeIfPresent(Bool.self, forKey: .notificationEnabled) ?? notificationEnabled
        let old = try values.decodeIfPresent([String: Double].self, forKey: .volumes) ?? [:]
        let version = try values.decodeIfPresent(Int.self, forKey: .audioDefaultsVersion) ?? 1
        volumes = AudioMix.migrated(old, version: version)
    }
}

