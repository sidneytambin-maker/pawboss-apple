import Foundation

public enum GameAction: Codable, Equatable {
    case register, insure, applyLicence, requestInspection, open, close, nextDay, market, clean, maintain, applyPlanning, expandLand, boardingApproval
    case configureRoom(String, RoomUse)
    case floorRoom(String)
    case buildBoundary
    case build(String, String, Int, Int)
    case move(UUID, String, Int, Int)
    case remove(UUID, String)
    case decideEnquiry(UUID, String)
    case book(UUID, Service, Int)
    case cancelBooking(UUID)
    case checkIn(UUID), checkOut(UUID), care(UUID), medication(UUID, UUID), observation(UUID, String), carePlan(UUID, String), contactOwner(UUID)
    case vaccination(UUID, stateDay: Int, note: String)
    case hire(UUID), dismiss(UUID), promote(UUID), train(UUID, String), staffRole(UUID, StaffRole), pay(UUID, Pence), rota(UUID, [Int]), leave(UUID, Int), praise(UUID)
    case setPrice(Service, Pence), borrow(Pence), repay(Pence)
    case respond(UUID, String), archiveMessage(UUID), readMessage(UUID)
    case ownerCover(Bool), priorities([String]), community(String)
}
public struct GameCommand: Codable, Identifiable {
    public var id: UUID
    public var businessID: UUID
    public var day: Int
    public var action: GameAction
    public init(id: UUID = UUID(), businessID: UUID, day: Int, action: GameAction) {
        self.id = id; self.businessID = businessID; self.day = day; self.action = action
    }
}
public struct GameEngine {
    public var state: BusinessState
    public let catalog: Catalog
    public init(state: BusinessState, catalog: Catalog) throws {
        self.state = state; self.catalog = catalog; try validate()
    }
    public mutating func perform(_ action: GameAction) -> Receipt {
        apply(GameCommand(businessID: state.id, day: state.day, action: action))
    }
    @discardableResult public mutating func apply(_ command: GameCommand) -> Receipt {
        if let previous = state.receipts.first(where: { $0.id == command.id }) { return previous }
        guard command.businessID == state.id else { return Receipt(id: command.id, applied: false, message: "This action belongs to a different business. Refresh the Watch before trying again.", revision: state.revision) }
        var candidate = self
        let receipt: Receipt
        do {
            guard command.day == state.day else { throw GameError.invalid("The business day has changed. Review today's information and try again.") }
            let message = try candidate.execute(command.action)
            candidate.state.revision += 1
            try candidate.validate()
            receipt = Receipt(id: command.id, applied: true, message: message, revision: candidate.state.revision)
            self = candidate
        } catch {
            state.revision += 1
            receipt = Receipt(id: command.id, applied: false, message: error.localizedDescription, revision: state.revision)
        }
        // Receipts and the transaction share one atomic save. Retain IDs for safe replay after long offline periods.
        state.receipts.append(receipt)
        return receipt
    }
    public func validate() throws {
        guard state.schemaVersion == 1, (0...365000).contains(state.day), state.revision >= 0, (-999_999_999_999...999_999_999_999).contains(state.cash),
              state.loan.principal >= 0, !state.name.isEmpty,
              Set(state.dogs.map(\.id)).count == state.dogs.count,
              Set(state.customers.map(\.id)).count == state.customers.count,
              Set(state.staff.map(\.id)).count == state.staff.count,
              Set(state.bookings.map(\.id)).count == state.bookings.count,
              Set(state.enquiries.map(\.id)).count == state.enquiries.count,
              state.dogs.allSatisfy({ dog in state.customers.contains { $0.id == dog.ownerID } }),
              state.bookings.allSatisfy({ booking in state.dogs.contains { $0.id == booking.dogID } && (0...1000000).contains(booking.price) && booking.refunded >= 0 && booking.refunded <= booking.price }),
              Service.allCases.allSatisfy({ (1...1000000).contains(state.prices[$0.rawValue, default: 0]) }),
              state.staff.allSatisfy({ (0...1000000).contains($0.hourlyPay) && (0...60).contains($0.hoursPerWeek) && $0.workingWeekdays.allSatisfy { (0...6).contains($0) } }),
              Set(state.areas.map(\.id)).count == state.areas.count,
              state.areas.allSatisfy({ (1...26).contains($0.rows) && (1...26).contains($0.columns) }),
              Set(state.receipts.map(\.id)).count == state.receipts.count,
              state.ledger.last.map({ $0.balance == state.cash }) ?? (state.cash == catalog.economy.initialCash)
        else { throw GameError.invalid("The business records did not pass validation. Your previous save has been kept.") }
        var balance = catalog.economy.initialCash
        for entry in state.ledger {
            let next = balance.addingReportingOverflow(entry.amount)
            guard !next.overflow, next.partialValue == entry.balance else { throw GameError.invalid("The bank history does not reconcile. Your previous save has been kept.") }
            balance = next.partialValue
        }
        for area in state.areas {
            guard Set(area.items.map(\.id)).count == area.items.count else { throw GameError.invalid("The premises contain duplicate object identities.") }
            for item in area.items {
                let definition = try catalog.item(item.definitionID)
                guard (0...100).contains(item.condition), item.row >= 0, item.column >= 0,
                      item.row <= area.rows - definition.height, item.column <= area.columns - definition.width else { throw GameError.invalid("A premises object is outside its valid area.") }
            }
        }
    }
    mutating func post(_ amount: Pence, _ detail: String, kind: LedgerKind) {
        state.cash += amount
        state.ledger.append(LedgerEntry(day: state.day, description: detail, amount: amount, kind: kind, balance: state.cash))
    }
    mutating func spend(_ amount: Pence, _ detail: String, kind: LedgerKind = .expense) throws {
        guard amount >= 0, state.cash >= amount else { throw GameError.invalid("This costs \(money(amount)); available cash is \(money(state.cash)). Review Finance before spending.") }
        post(-amount, detail, kind: kind)
    }
    mutating func remember(_ text: String) { state.history.append(Memory(day: state.day, text: text)) }
    mutating func milestone(_ key: String, _ text: String) {
        guard state.milestones[key] == nil else { return }
        state.milestones[key] = state.day; remember(text)
        state.messages.append(Message(day: state.day, sender: "Your business story", title: text, body: "A lasting part of \(state.name)'s history.", kind: .report))
    }
    mutating func execute(_ action: GameAction) throws -> String {
        switch action {
        case .register:
            guard !state.licence.registered else { throw GameError.invalid("Your business is already registered.") }
            try spend(catalog.economy.registration, "Business registration")
            state.licence.registered = true; remember("\(state.name) registered with Westmoor council.")
            return "Business registered."
        case .insure:
            guard !state.insured else { throw GameError.invalid("Your annual insurance is already in force.") }
            try spend(catalog.economy.insurance, "Annual business insurance")
            state.licence.insuranceUntilDay = state.day + 364; return "Business insurance arranged for one year."
        case .applyLicence:
            guard state.licence.registered else { throw GameError.invalid("Register the business first.") }
            guard !state.licence.applied || (!state.licenceValid && state.licence.validUntilDay != nil) else { throw GameError.invalid("Your licence application is already on record. Book an inspection next.") }
            try spend(catalog.economy.licence, "Day care licence application")
            state.licence.validUntilDay = nil
            state.licence.applied = true; return "Licence application submitted. You can now book an inspection."
        case .requestInspection:
            guard state.licence.applied else { throw GameError.invalid("Apply for a licence before booking an inspection.") }
            guard state.licence.validUntilDay == nil || state.licenceValid else { throw GameError.invalid("Your previous licence has expired. Submit a renewal application before booking the inspection.") }
            guard state.licence.inspectionDay == nil else { throw GameError.invalid("Your inspection is already booked.") }
            try spend(catalog.economy.inspection, "Council inspection booking")
            state.licence.inspectionDay = state.day + 2; return "Inspection booked in two business days. Check your readiness before then."
        case .open:
            guard !state.isOpen else { throw GameError.invalid("The business is already open.") }
            let blockers = state.readiness().filter { !$0.complete }
            guard blockers.isEmpty else { throw GameError.invalid("Before opening: \(blockers.map(\.title).joined(separator: ", ")).") }
            state.isOpen = true; milestone("opening", "Open for business. Your first day of care awaits.")
            return "Business open."
        case .close:
            guard !state.dogs.contains(where: \.present) else { throw GameError.invalid("Check out the dogs before closing the site.") }
            state.isOpen = false; return "Business closed. Existing bookings are kept."
        case .configureRoom(let id, let purpose):
            guard !state.isOpen, let i = state.areas.firstIndex(where: { $0.id == id && !$0.isOutdoor }) else { throw GameError.invalid("Close the site and choose an indoor room before changing its use.") }
            state.areas[i].purpose = purpose; return "\(state.areas[i].name) set to \(purpose.title.lowercased())."
        case .floorRoom(let id): try floorRoom(id); return "Washable flooring installed."
        case .buildBoundary: try buildBoundary(); return "Missing perimeter fencing installed. Existing gates kept."
        case .build(let item, let area, let row, let col): try build(itemID: item, areaID: area, row: row, column: col); return "\(try catalog.item(item).name) installed."
        case .move(let id, let area, let row, let col):
            guard let item = state.areas.first(where: { $0.id == area })?.items.first(where: { $0.id == id }) else { throw GameError.invalid("This item is no longer here.") }
            try build(itemID: item.definitionID, areaID: area, row: row, column: col, movingID: id); return "Item moved."
        case .remove(let id, let area):
            guard !state.isOpen else { throw GameError.invalid("Close the site before removing equipment.") }
            guard let a = state.areas.firstIndex(where: { $0.id == area }), let i = state.areas[a].items.firstIndex(where: { $0.id == id }) else { throw GameError.invalid("This item has already been removed.") }
            let item = state.areas[a].items[i]
            guard item.definitionID != "extension" else { throw GameError.invalid("Care buildings cannot be demolished while their rooms form part of the licensed site.") }
            let value = try catalog.item(item.definitionID).price * item.condition / 400
            state.areas[a].items.remove(at: i); post(value, "Equipment resale", kind: .investment)
            return "Item removed. \(money(value)) resale value received."
        case .clean:
            guard state.cleanliness < 100 else { throw GameError.invalid("The site is already clean.") }
            try spend(1200, "Additional deep cleaning supplies"); state.cleanliness = 100; return "Deep cleaning completed."
        case .maintain:
            let worn = state.areas.flatMap(\.items).filter { $0.condition < 90 }
            guard !worn.isEmpty else { throw GameError.invalid("No maintenance is currently due.") }
            let cost = try maintenanceQuote
            try spend(cost, "Preventative premises maintenance")
            for a in state.areas.indices { for i in state.areas[a].items.indices where state.areas[a].items[i].condition < 90 { state.areas[a].items[i].condition = 100 } }
            return "Premises maintenance completed."
        case .applyPlanning:
            guard state.licenceValid, state.customers.count >= 4, state.welfare >= 65 else { throw GameError.invalid("Planning requires council approval, at least four customers and stable dog welfare.") }
            guard state.planningReadyDay == nil else { throw GameError.invalid("Planning approval is already arranged.") }
            try spend(20000, "Planning application and site survey"); state.planningReadyDay = state.day + 7
            return "Planning assessment arranged. A decision is due in seven days."
        case .expandLand:
            guard (state.planningReadyDay ?? Int.max) <= state.day, state.cash >= 600000, let a = state.areas.firstIndex(where: \.isOutdoor), state.areas[a].rows < 20, !state.isOpen else { throw GameError.invalid("Expansion needs planning approval, a closed site and at least \(money(600000)) cash including a reserve.") }
            try spend(350000, "Additional land and utility connections", kind: .investment)
            let old = state.areas[a].rows; state.areas[a].rows += 5; state.areas[a].columns += 5
            for i in state.areas[a].items.indices where ["fence", "gate"].contains(state.areas[a].items[i].definitionID) {
                if state.areas[a].items[i].row == old - 1 { state.areas[a].items[i].row += 5 }
                if state.areas[a].items[i].column == old - 1 { state.areas[a].items[i].column += 5 }
            }
            state.licence.validUntilDay = nil; state.licence.capacity += 6
            milestone("expansion", "Your site has grown. Prepare the enlarged boundary and a new inspection.")
            return "Land purchased. Fill the new boundary gaps and arrange a new inspection."
        case .boardingApproval:
            guard state.licenceValid, state.hasRoom(.boarding), state.staff.contains(where: { $0.employed && $0.qualifications.contains("Overnight care") }) else { throw GameError.invalid("A licensed site, boarding room and overnight-trained employee are required.") }
            guard !state.licence.boarding else { throw GameError.invalid("Boarding is already approved.") }
            try spend(25000, "Boarding service assessment"); state.licence.boarding = true; return "Boarding service approved."
        case .market:
            guard state.licence.registered else { throw GameError.invalid("Register your business before advertising.") }
            guard (state.marketingUntilDay ?? -1) < state.day else { throw GameError.invalid("Your current campaign is still running.") }
            try spend(3500, "Seven-day local introduction campaign"); state.marketingUntilDay = state.day + 6
            return "Local campaign started. Enquiries arrive over the coming days."
        case .nextDay: try simulateDay(); return "\(state.dateText). Welcome to Week \(state.week)."
        case .decideEnquiry(let id, let decision): return try decideEnquiry(id, decision)
        case .book(let id, let service, let day): try book(id, service: service, day: day); return "Booking confirmed."
        case .cancelBooking(let id):
            guard let b = state.bookings.firstIndex(where: { $0.id == id && $0.status == .expected }) else { throw GameError.invalid("Only an upcoming booking can be cancelled.") }
            state.bookings[b].status = .cancelled; return "Booking cancelled."
        case .checkIn(let id): try checkIn(id); return "Dog checked in."
        case .checkOut(let id): try checkOut(id); return "Dog checked out. Payment and handover recorded."
        case .care(let id): try care(id); return "Care routine recorded."
        case .medication(let dogID, let medicationID):
            let d = try dogIndex(dogID)
            guard state.dogs[d].present else { throw GameError.invalid("Check this dog in before recording medication.") }
            guard let m = state.dogs[d].medications.firstIndex(where: { $0.id == medicationID }), state.dogs[d].medications[m].dueDay <= state.day else { throw GameError.invalid("No medication is due.") }
            guard !state.dogs[d].medications[m].givenDays.contains(state.day) else { throw GameError.invalid("Today's medication is already recorded. It has not been given again.") }
            state.dogs[d].medications[m].givenDays.append(state.day)
            state.dogs[d].observations.append(Memory(day: state.day, text: "Medication recorded according to the owner's instructions."))
            return "Medication recorded once for today."
        case .observation(let id, let text):
            let d = try dogIndex(id); try validText(text)
            state.dogs[d].observations.append(Memory(day: state.day, text: text)); return "Observation saved."
        case .carePlan(let id, let text):
            let d = try dogIndex(id); try validText(text); state.dogs[d].carePlan = text; return "Care plan updated."
        case .vaccination(let id, let stateDay, let note):
            let d = try dogIndex(id); try validText(note)
            guard stateDay > state.day && stateDay <= state.day + 366 else { throw GameError.invalid("Choose a review date within the next year.") }
            state.dogs[d].vaccinationDueDay = stateDay
            state.dogs[d].observations.append(Memory(day: state.day, text: "Owner vaccination record reviewed: \(note)"))
            return "Vaccination record updated."
        case .contactOwner(let id):
            let d = try dogIndex(id); let c = try customerIndex(state.dogs[d].ownerID)
            let note = "Shared \(state.dogs[d].name)'s latest care and wellbeing update."
            guard !state.customers[c].history.contains(where: { $0.day == state.day && $0.text == note }) else { throw GameError.invalid("Today's care update has already been shared.") }
            state.customers[c].history.append(Memory(day: state.day, text: note)); state.customers[c].trust = bounded(state.customers[c].trust + 1)
            return "Care update sent to \(state.customers[c].name)."
        case .hire, .dismiss, .promote, .train, .staffRole, .pay, .rota, .leave, .praise:
            return try staffAction(action)
        case .setPrice(let service, let price):
            guard (100...50000).contains(price) else { throw GameError.invalid("Choose a price from one to five hundred pounds.") }
            state.prices[service.rawValue] = price; return "\(service.title) price updated. Existing quotes and bookings keep their agreed price."
        case .borrow(let amount):
            guard amount >= 10000, amount <= 1000000 - state.loan.principal else { throw GameError.invalid("Borrow from one hundred pounds, up to a total outstanding loan of ten thousand pounds.") }
            state.loan.principal += amount; state.loan.original += amount
            if state.loan.nextPaymentDay == nil { state.loan.nextPaymentDay = state.day + 30 }
            post(amount, "Business loan drawn at \(catalog.economy.loanAPRPercent)% APR", kind: .borrowing)
            return "Loan received. Monthly interest and principal repayments are shown in Finance."
        case .repay(let amount):
            guard amount > 0 && amount <= state.loan.principal else { throw GameError.invalid("Choose an amount no higher than the outstanding loan.") }
            try spend(amount, "Additional loan principal repayment", kind: .principal); state.loan.principal -= amount; return "Loan repayment recorded."
        case .respond(let id, let choice): return try respond(id, choice: choice)
        case .archiveMessage(let id):
            let m = try messageIndex(id); state.messages[m].archived = true; return "Message archived."
        case .readMessage(let id):
            let m = try messageIndex(id); state.messages[m].read = true; return "Message marked as read."
        case .ownerCover(let enabled): state.ownerOnDuty = enabled; return enabled ? "Owner care cover on." : "Owner care cover off. Review today's staffing capacity."
        case .priorities(let choices):
            guard choices.count <= 3, Set(choices).count == choices.count, choices.allSatisfy({ ["rest", "enrichment", "cleaning", "communication", "maintenance", "training"].contains($0) }) else { throw GameError.invalid("Choose up to three different daily priorities.") }
            state.priorities = choices; return "Daily priorities saved."
        case .community(let id):
            guard state.world.contains(where: { $0.id == id }) else { throw GameError.invalid("This local partner is not available.") }
            guard state.eventLastDays["partner-\(id)", default: -30] <= state.day - 30 else { throw GameError.invalid("Your recent partnership is still active. Review it next month.") }
            try spend(2500, "Community partnership with \(state.world.first { $0.id == id }!.name)")
            state.eventLastDays["partner-\(id)"] = state.day; remember("Built a local partnership with \(state.world.first { $0.id == id }!.name).")
            return "Partnership arranged. The local community will hear about your business."
        }
    }
    func dogIndex(_ id: UUID) throws -> Int {
        guard let i = state.dogs.firstIndex(where: { $0.id == id }) else { throw GameError.invalid("This dog record is no longer available.") }; return i
    }
    func customerIndex(_ id: UUID) throws -> Int {
        guard let i = state.customers.firstIndex(where: { $0.id == id }) else { throw GameError.invalid("This customer record is no longer available.") }; return i
    }
    func messageIndex(_ id: UUID) throws -> Int {
        guard let i = state.messages.firstIndex(where: { $0.id == id }) else { throw GameError.invalid("This message is no longer available.") }; return i
    }
    func validText(_ text: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 2000 else { throw GameError.invalid("Enter a note between one and two thousand characters.") }
    }
}
