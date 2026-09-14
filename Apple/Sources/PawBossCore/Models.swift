import Foundation

public typealias Pence = Int
public func money(_ pence: Pence) -> String {
    (Double(pence) / 100).formatted(.currency(code: "GBP").locale(Locale(identifier: "en_GB")))
}
public func bounded(_ value: Int) -> Int { min(100, max(0, value)) }

public enum Service: String, Codable, CaseIterable, Identifiable {
    case dayCare, halfDay, overnight, holiday, pickup, dropoff, grooming, specialist
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .dayCare: return "Day care"
        case .halfDay: return "Half-day care"
        case .overnight: return "Overnight care"
        case .holiday: return "Holiday care"
        case .pickup: return "Pick-up"
        case .dropoff: return "Drop-off"
        case .grooming: return "Grooming"
        case .specialist: return "Specialist care"
        }
    }
}
public enum RoomUse: String, Codable, CaseIterable, Identifiable {
    case unassigned, reception, multipurpose, quiet, puppy, isolation, staff, grooming, boarding
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .unassigned: return "Not configured"
        case .multipurpose: return "Play and rest"
        case .staff: return "Staff room"
        default: return rawValue.capitalized
        }
    }
}
public enum Layer: String, Codable { case ground, boundary, building, furniture }
public struct ItemDefinition: Codable, Identifiable {
    public var id: String
    public var name: String
    public var detail: String
    public var price: Pence
    public var weeklyCost: Pence
    public var width: Int
    public var height: Int
    public var layer: Layer
    public var indoors: Bool
    public var outdoors: Bool
    public var welfare: Int
    public var lifespanDays: Int
    public var requiresInspection: Bool
}
public struct PlacedItem: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var definitionID: String
    public var row: Int
    public var column: Int
    public var condition = 100
    public var installedDay: Int
    public var readyDay: Int
}
public struct Area: Codable, Identifiable {
    public var id: String
    public var name: String
    public var rows: Int
    public var columns: Int
    public var purpose: RoomUse
    public var items: [PlacedItem] = []
    public init(id: String, name: String, rows: Int, columns: Int, purpose: RoomUse = .unassigned) {
        self.id = id; self.name = name; self.rows = rows; self.columns = columns; self.purpose = purpose
    }
    public var isOutdoor: Bool { id == "outdoor" }
    public func coordinate(row: Int, column: Int) -> String {
        "\(Character(UnicodeScalar(65 + column)!))\(row + 1)"
    }
}
public struct Memory: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var day: Int
    public var text: String
    public init(day: Int, text: String) { self.day = day; self.text = text }
}
public struct Medication: Codable, Identifiable {
    public var id = UUID()
    public var name: String
    public var instructions: String
    public var dueDay: Int
    public var givenDays: [Int] = []
}
public struct Dog: Codable, Identifiable {
    public var id = UUID()
    public var name: String
    public var breed: String
    public var ageMonths: Int
    public var sex: String
    public var appearance: String
    public var ownerID: UUID
    public var personality: String
    public var favouriteActivity: String
    public var diet: String
    public var health: String
    public var carePlan: String
    public var energy = 60
    public var confidence = 45
    public var sociability = 55
    public var stress = 25
    public var welfare = 75
    public var vaccinationDueDay = 180
    public var medications: [Medication] = []
    public var friends: [UUID] = []
    public var trustedStaff: [UUID] = []
    public var attendedDays: [Int] = []
    public var observations: [Memory] = []
    public var present = false
    public var lastCareDay: Int?
    public var joinedDay: Int
    public var wellbeing: String {
        welfare < 45 ? "Needs urgent care" : stress > 55 ? "Needs reassurance" : welfare >= 75 ? "Doing well" : "Settling in"
    }
    public var summary: String { "\(name). \(breed). Age \(ageMonths / 12). \(present ? "Attending today. " : "")\(wellbeing)." }
}
public struct Customer: Codable, Identifiable {
    public var id = UUID()
    public var name: String
    public var communication: String
    public var bookingHabit: String
    public var trust = 40
    public var visits = 0
    public var history: [Memory] = []
    public var relationship: String {
        trust < 25 ? "Needs reassurance" : trust < 50 ? "Getting to know you" : trust < 75 ? "Growing confidence" : "Loyal advocate"
    }
}
public enum EnquiryStatus: String, Codable { case pending, informationRequested, quoted, accepted, declined, waiting }
public struct Enquiry: Codable, Identifiable {
    public var id = UUID()
    public var customer: Customer
    public var dog: Dog
    public var service: Service
    public var requestedDay: Int
    public var source: String
    public var requirements: String
    public var status: EnquiryStatus = .pending
    public var responseDay: Int?
    public var quote: Pence?
    public var isActionable: Bool { [.pending, .quoted, .waiting].contains(status) }
}
public enum BookingStatus: String, Codable { case expected, checkedIn, completed, cancelled }
public struct Booking: Codable, Identifiable {
    public var id = UUID()
    public var dogID: UUID
    public var service: Service
    public var day: Int
    public var price: Pence
    public var status: BookingStatus = .expected
    public var paid = false
    public var refunded: Pence = 0
}
public enum StaffRole: String, Codable, CaseIterable, Identifiable {
    case handler, senior, reception, cleaner, trainer, groomer, manager
    public var id: String { rawValue }
    public var title: String {
        switch self { case .handler: return "Dog care assistant"; case .senior: return "Senior handler"; default: return rawValue.capitalized }
    }
    public var caresForDogs: Bool { [.handler, .senior, .trainer, .manager].contains(self) }
}
public struct StaffMember: Codable, Identifiable {
    public var id = UUID()
    public var name: String
    public var age: Int
    public var role: StaffRole
    public var hourlyPay: Pence
    public var hoursPerWeek: Int
    public var skill: Int
    public var strength: String
    public var development: String
    public var qualifications: [String]
    public var morale = 70
    public var stress = 20
    public var joinedDay: Int?
    public var leftDay: Int?
    public var absentUntilDay: Int?
    public var workingWeekdays: [Int] = [0, 1, 2, 3, 4]
    public var history: [Memory] = []
    public var employed: Bool { joinedDay != nil && leftDay == nil }
    public func onDuty(day: Int) -> Bool {
        employed && (absentUntilDay ?? -1) < day && workingWeekdays.contains(day % 7)
    }
    public var wellbeing: String { stress > 65 ? "Overstretched" : morale < 40 ? "Needs support" : "Settled" }
}
public enum MessageKind: String, Codable, CaseIterable { case message, complaint, review, referral, staff, inspection, report, community }
public struct Message: Codable, Identifiable {
    public var id = UUID()
    public var day: Int
    public var sender: String
    public var title: String
    public var body: String
    public var kind: MessageKind
    public var subjectID: UUID?
    public var read = false
    public var archived = false
    public var resolved = false
    public var rating: Int?
}
public enum LedgerKind: String, Codable { case income, expense, investment, borrowing, principal, refund }
public struct LedgerEntry: Codable, Identifiable {
    public var id = UUID()
    public var day: Int
    public var description: String
    public var amount: Pence
    public var kind: LedgerKind
    public var balance: Pence
}
public struct DayReport: Codable, Identifiable {
    public var id: Int { day }
    public var day: Int
    public var revenue: Pence
    public var expenses: Pence
    public var profit: Pence
    public var cash: Pence
    public var attendance: Int
    public var welfare: Int
    public var customers: Int
    public var staff: Int
    public var explanation: String
}
public struct Licence: Codable {
    public var registered = false
    public var insuranceUntilDay: Int?
    public var applied = false
    public var inspectionDay: Int?
    public var validUntilDay: Int?
    public var capacity = 6
    public var boarding = false
    public var result = "Not inspected"
    public var findings: [String] = []
}
public struct Loan: Codable {
    public var principal: Pence = 0
    public var original: Pence = 0
    public var interestPaid: Pence = 0
    public var nextPaymentDay: Int?
}
public struct WorldBusiness: Codable, Identifiable {
    public var id: String
    public var name: String
    public var category: String
    public var detail: String
    public var price: Pence
    public var reputation: Int
}
public struct Receipt: Codable, Identifiable {
    public var id: UUID
    public var applied: Bool
    public var message: String
    public var revision: Int
}
public struct BusinessState: Codable, Identifiable {
    public var schemaVersion = 1
    public var id = UUID()
    public var revision = 0
    public var name: String
    public var owner: String
    public var ownerTitle: String
    public var startDate: Date
    public var day = 0
    public var cash: Pence
    public var loan = Loan()
    public var isOpen = false
    public var ownerOnDuty = true
    public var cleanliness = 85
    public var reputation = 0
    public var weather = "Mild"
    public var priorities: [String] = ["rest", "enrichment", "cleaning"]
    public var marketingUntilDay: Int?
    public var planningReadyDay: Int?
    public var licence = Licence()
    public var areas: [Area]
    public var prices: [String: Pence]
    public var dogs: [Dog] = []
    public var customers: [Customer] = []
    public var enquiries: [Enquiry] = []
    public var bookings: [Booking] = []
    public var staff: [StaffMember]
    public var messages: [Message] = []
    public var ledger: [LedgerEntry] = []
    public var reports: [DayReport] = []
    public var history: [Memory] = []
    public var milestones: [String: Int] = [:]
    public var world: [WorldBusiness]
    public var eventLastDays: [String: Int] = [:]
    public var receipts: [Receipt] = []
    public var generator: UInt64
    public var identitySerial = 0
    public var week: Int { day / 7 + 1 }
    public var date: Date { Calendar.pawBoss.date(byAdding: .day, value: day, to: startDate)! }
    public var dateText: String {
        var style = Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide).year().locale(Locale(identifier: "en_GB"))
        style.timeZone = Calendar.pawBoss.timeZone
        return date.formatted(style)
    }
    public func cashMovement(from firstDay: Int, through lastDay: Int) -> Pence {
        ledger.filter { $0.day >= firstDay && $0.day <= lastDay }.reduce(0) { $0 + $1.amount }
    }
    public var ageText: String { day < 365 ? "\(day) days in business" : "\(day / 365) years in business" }
    public var pendingEnquiries: [Enquiry] { enquiries.filter(\.isActionable) }
    public var todayBookings: [Booking] { bookings.filter { $0.day == day && $0.status != .cancelled } }
    public var expectedRevenue: Pence { todayBookings.reduce(0) { $0 + $1.price } }
    public var welfare: Int { dogs.isEmpty ? 0 : dogs.reduce(0) { $0 + $1.welfare } / dogs.count }
    public var profit: Pence { reports.reduce(0) { $0 + $1.profit } }
    public mutating func random(_ upper: Int) -> Int {
        generator = generator &* 6364136223846793005 &+ 1442695040888963407
        return Int((generator >> 33) % UInt64(max(1, upper)))
    }
}
public extension Calendar {
    static var pawBoss: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; c.firstWeekday = 2; return c }
}
