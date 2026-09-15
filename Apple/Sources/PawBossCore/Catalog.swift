import Foundation

public struct DogTemplate: Codable {
    public var name: String; public var breed: String; public var appearance: String
    public var personality: String; public var activity: String; public var diet: String; public var health: String
}
public struct EventTemplate: Codable, Identifiable {
    public var id: String; public var title: String; public var body: String
    public var condition: String; public var cooldown: Int; public var cost: Pence
    public var welfare: Int; public var stress: Int; public var reputation: Int
}
public struct Economy: Codable {
    public var initialCash: Pence; public var minimumHourlyPay: Pence
    public var registration: Pence; public var insurance: Pence; public var licence: Pence; public var inspection: Pence
    public var monthlyRent: Pence; public var monthlyUtilities: Pence; public var weeklyWaste: Pence
    public var dailySuppliesPerDog: Pence; public var loanAPRPercent: Int
    public var prices: [String: Pence]
}
public struct Catalog: Codable {
    public var economy: Economy
    public var items: [ItemDefinition]
    public var dogs: [DogTemplate]
    public var firstNames: [String]
    public var surnames: [String]
    public var world: [WorldBusiness]
    public var events: [EventTemplate]
    public static func bundled() throws -> Catalog {
        guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json") else { throw GameError.invalid("PawBoss content is missing.") }
        let result = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
        guard result.items.count >= 15, !result.dogs.isEmpty, !result.firstNames.isEmpty,
              Set(result.items.map(\.id)).count == result.items.count,
              Service.allCases.allSatisfy({ result.economy.prices[$0.rawValue, default: 0] > 0 }),
              result.items.allSatisfy({ $0.price >= 0 && $0.width > 0 && $0.height > 0 && $0.lifespanDays > 0 }),
              result.world.allSatisfy({ $0.terms?.valid ?? true }),
              Set(result.world.map(\.id)).count == result.world.count
        else { throw GameError.invalid("PawBoss content could not be validated.") }
        return result
    }
    public func item(_ id: String) throws -> ItemDefinition {
        guard let value = items.first(where: { $0.id == id }) else { throw GameError.invalid("That item is no longer available.") }
        return value
    }
    public func newBusiness(name: String, owner: String, title: String, seed: UInt64 = UInt64.random(in: 1...UInt64.max)) throws -> BusinessState {
        guard [name, owner, title].allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 70 }) else {
            throw GameError.invalid("Enter a business name, your name and your job title, each up to 70 characters.")
        }
        let start = Calendar.pawBoss.date(from: DateComponents(year: 2026, month: 9, day: 14))!
        var state = BusinessState(name: name, owner: owner, ownerTitle: title, startDate: start,
            cash: economy.initialCash,
            areas: [Area(id: "outdoor", name: "Outdoor area", rows: 10, columns: 10),
                    Area(id: "room1", name: "Room one", rows: 4, columns: 4),
                    Area(id: "room2", name: "Room two", rows: 4, columns: 4)],
            prices: economy.prices, staff: [], world: world, generator: seed)
        for index in 0..<8 {
            let roles = StaffRole.allCases
            let role = roles[index % roles.count]
            state.staff.append(StaffMember(name: "\(firstNames[(index + 11) % firstNames.count]) \(surnames[(index + 7) % surnames.count])",
                age: 23 + index * 3, role: role, hourlyPay: economy.minimumHourlyPay + Pence(index) * 65,
                hoursPerWeek: [.cleaner, .reception].contains(role) ? 15 : 25, skill: 52 + index * 5,
                strength: index % 2 == 0 ? "Patient with nervous dogs" : "Clear, reassuring customer communication",
                development: index % 2 == 0 ? "Would like to develop leadership skills" : "Would like more behaviour training",
                qualifications: role == .trainer ? ["Dog behaviour", "Canine first aid"] : ["Canine first aid"]))
        }
        state.history.append(Memory(day: 0, text: "\(owner) founded \(name) with \(money(economy.initialCash)) of savings and no loan."))
        state.messages.append(Message(day: 0, sender: "Westmoor Business Adviser", title: "Your first opening",
            body: "Your two rooms and outdoor plot are ready to inspect. Furnish play and rest space, secure the boundary, then arrange insurance and a council inspection. Your savings are enough for a careful opening; borrowing is optional.", kind: .message))
        return state
    }
}
public enum GameError: LocalizedError, Equatable {
    case invalid(String)
    public var errorDescription: String? { switch self { case .invalid(let text): return text } }
}
