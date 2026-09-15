import Foundation

public struct DailyPrioritySlots {
    public static let choices = ["rest", "enrichment", "cleaning", "communication", "maintenance", "training"]
    public private(set) var slots: [String]
    public init(_ saved: [String]) {
        var unique: [String] = []
        for value in saved where Self.choices.contains(value) && !unique.contains(value) { unique.append(value) }
        slots = Array((unique + ["","",""]).prefix(3))
    }
    public var selected: [String] { slots.filter { !$0.isEmpty } }
    public mutating func select(_ value: String, at index: Int) {
        guard slots.indices.contains(index), value.isEmpty || Self.choices.contains(value) else { return }
        if !value.isEmpty, let other = slots.firstIndex(of: value), other != index { slots.swapAt(index, other) }
        else { slots[index] = value }
    }
    public static func explanation(_ choice: String) -> String {
        switch choice {
        case "rest": return "Quiet rest supports welfare and settling."
        case "enrichment": return "Individual activities support confidence and welfare."
        case "cleaning": return "Protects hygiene, with daily cleaning supply costs."
        case "communication": return "Weekly care updates build customer trust."
        case "maintenance": return "Small paid repairs reduce wear and disruption."
        case "training": return "Supervised practice develops staff skills over time."
        default: return "No priority in this slot."
        }
    }
}
public struct OpeningStage: Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    public var complete: Bool
}
public extension BusinessState {
    var openingStages: [OpeningStage] {
        let checks = readiness()
        func complete(_ ids: [String]) -> Bool { ids.allSatisfy { id in checks.contains { $0.id == id && $0.complete } } }
        return [
            .init(id:"registration", title:"Make it your business", detail:"Register your business and keep your starting savings in view.", complete:licence.registered),
            .init(id:"space", title:"Create a place to play and rest", detail:"Choose a care room and give it a cleanable floor.", complete:complete(["rooms","floor"])),
            .init(id:"boundary", title:"Make the grounds secure", detail:"A complete fence and a lockable gate keep arrivals safe.", complete:secureBoundary),
            .init(id:"essentials", title:"Prepare everyday care", detail:"Water, rest, enrichment and cleaning come before optional upgrades.", complete:complete(["water","rest","hygiene","staffing"])),
            .init(id:"approval", title:"Arrange insurance and inspection", detail:"The council checks your actual premises. Approval takes game time.", complete:insured && licenceValid),
            .init(id:"opening", title:"Welcome your first customers", detail:"Open safely, then introduce your business to local dog owners.", complete:milestones["opening"] != nil)
        ]
    }
}
public struct PartnerTerms: Codable, Equatable {
    public var fee: Pence
    public var supplyDiscount: Int
    public var trainingDiscount: Int
    public var careSupport: Int
    public var referrals: Int
    public var reliability: Int
    public var advantage: String
    public var tradeoff: String
    public var valid: Bool {
        (0...100000).contains(fee) && (0...25).contains(supplyDiscount) && (0...30).contains(trainingDiscount) &&
        (0...1).contains(careSupport) && (0...2).contains(referrals) && (0...100).contains(reliability)
    }
}
public struct PartnerContract: Codable, Equatable {
    public var providerID: String
    public var startDay: Int
    public var terms: PartnerTerms
    public var endDay: Int { startDay + 30 }
}
public extension BusinessState {
    func activePartner(_ category: String) -> PartnerContract? {
        guard let contract = partnerContracts?[category], contract.startDay <= day, day < contract.endDay else { return nil }
        return contract
    }
    var supplyDiscount: Int { activePartner("Supplier")?.terms.supplyDiscount ?? 0 }
    var trainingDiscount: Int { activePartner("Trainer")?.terms.trainingDiscount ?? 0 }
    var partnerCareSupport: Int { min(1, (activePartner("Vet")?.terms.careSupport ?? 0) + (activePartner("Community")?.terms.careSupport ?? 0)) }
    var partnerReferralStrength: Int {
        min(3, ["Vet","Supplier","Trainer","Groomer","Community"].compactMap { activePartner($0)?.terms.referrals }.reduce(0,+))
    }
}
public extension GameEngine {
    var trainingPrice: Pence { 12000 * Pence(100 - state.trainingDiscount) / 100 }
}
extension GameEngine {
    mutating func choosePartner(_ id: String) throws -> String {
        guard let provider = state.world.first(where: { $0.id == id }), let terms = provider.terms, provider.category != "Competitor" else { throw GameError.invalid("Choose an available community provider.") }
        guard state.activePartner(provider.category)?.providerID != id else { throw GameError.invalid("This agreement is already active. It can be renewed after it expires.") }
        try spend(terms.fee, "30-day agreement: \(provider.name)")
        if state.partnerContracts == nil { state.partnerContracts = [:] }
        state.partnerContracts?[provider.category] = PartnerContract(providerID:id, startDay:state.day, terms:terms)
        for previous in state.world where previous.category == provider.category { state.eventLastDays.removeValue(forKey:"partner-\(previous.id)") }
        state.eventLastDays["partner-\(id)"] = state.day
        remember("Chose \(provider.name) for 30 days at \(money(terms.fee)). \(terms.advantage) \(terms.tradeoff)")
        return "\(provider.name) selected for 30 days. No automatic renewal; the previous provider in this category is replaced."
    }
    mutating func partnerDailyConsequences(attendance: Int) {
        guard attendance > 0 else { return }
        if state.day % 7 == 0, let supplier = state.activePartner("Supplier"), state.random(100) >= supplier.terms.reliability {
            let cost: Pence = 800 + Pence(attendance) * 100
            post(-cost, "Retail top-up after delayed supplier delivery", kind:.expense)
            state.messages.append(Message(day:state.day, sender:"Supply records", title:"A delivery needed a backup plan", body:"Your supplier's delivery was late. A \(money(cost)) local top-up kept care supplied. Compare reliability as well as discounts; a reserve prevents this from becoming a welfare problem.", kind:.message))
        }
    }
}
