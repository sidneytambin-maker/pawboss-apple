import Foundation

extension GameEngine {
    mutating func generateEnquiry(source: String) {
        let serial = state.identitySerial; state.identitySerial += 1
        let template = catalog.dogs[state.random(catalog.dogs.count)]
        let first = catalog.firstNames[serial % catalog.firstNames.count]
        let surname = catalog.surnames[(serial / catalog.firstNames.count) % catalog.surnames.count]
        let cycle = serial / (catalog.firstNames.count * catalog.surnames.count)
        let suffix = cycle == 0 ? "" : " \(catalog.firstNames[cycle % catalog.firstNames.count])"
        let customer = Customer(name: "\(first)\(suffix) \(surname)", communication: serial % 2 == 0 ? "Email" : "Collection handover", bookingHabit: serial % 3 == 0 ? "Three weekdays each week" : "Two weekdays each week")
        // A household surname distinguishes dogs with the same everyday name without conflating their records.
        var dog = Dog(name: "\(template.name) \(first)\(suffix) \(surname)", breed: template.breed, ageMonths: 12 + state.random(120), sex: serial % 2 == 0 ? "Female" : "Male", appearance: template.appearance, ownerID: customer.id,
            personality: template.personality, favouriteActivity: template.activity, diet: template.diet, health: template.health,
            carePlan: "Calm arrival, fresh water, \(template.activity.lowercased()), a quiet rest and an individual collection handover.", joinedDay: state.day)
        dog.confidence = 30 + state.random(50); dog.energy = 35 + state.random(50); dog.sociability = 30 + state.random(55)
        dog.vaccinationDueDay = state.day + 90 + state.random(180)
        if template.name == "Finn" {
            dog.medications.append(Medication(name: "Owner-prescribed medication", instructions: "Follow the written owner and vet care plan. Record one scheduled administration per game day.", dueDay: state.day))
        }
        let service: Service = serial % 3 == 0 ? .halfDay : .dayCare
        state.enquiries.append(Enquiry(customer: customer, dog: dog, service: service, requestedDay: state.day + 1, source: source, requirements: "\(template.health). \(template.diet)."))
    }
    mutating func decideEnquiry(_ id: UUID, _ decision: String) throws -> String {
        guard let i = state.enquiries.firstIndex(where: { $0.id == id && $0.isActionable }) else { throw GameError.invalid("This enquiry has already been handled. It has not been accepted again.") }
        switch decision {
        case "accept":
            let enquiry = state.enquiries[i]
            guard state.licenceValid && state.insured else { throw GameError.invalid("Complete insurance and council approval before accepting a customer.") }
            guard !state.dogs.contains(where: { $0.id == enquiry.dog.id }), !state.customers.contains(where: { $0.id == enquiry.customer.id }) else { throw GameError.invalid("This customer is already registered.") }
            state.customers.append(enquiry.customer); state.dogs.append(enquiry.dog)
            try book(enquiry.dog.id, service: enquiry.service, day: max(state.day, enquiry.requestedDay), quotedPrice: enquiry.quote)
            state.enquiries[i].status = .accepted
            state.customers[state.customers.count - 1].history.append(Memory(day: state.day, text: "First booking accepted following an enquiry from \(enquiry.source.lowercased())."))
            milestone("customer", "Your first customer. A new relationship begins.")
            return "\(enquiry.dog.name) accepted. Customer, dog and booking created once."
        case "decline": state.enquiries[i].status = .declined; return "Enquiry declined politely."
        case "information": state.enquiries[i].status = .informationRequested; state.enquiries[i].responseDay = state.day + 1; return "More information requested. The owner will reply on a later day."
        case "quote":
            guard state.enquiries[i].status != .quoted else { throw GameError.invalid("A quote has already been sent.") }
            let price = state.prices[state.enquiries[i].service.rawValue]!
            state.enquiries[i].quote = price; state.enquiries[i].status = .quoted
            return "Quote of \(money(price)) sent."
        case "wait": state.enquiries[i].status = .waiting; return "Enquiry added to the waiting list."
        default: throw GameError.invalid("Choose one of the available enquiry responses.")
        }
    }
    mutating func book(_ dogID: UUID, service: Service, day: Int, quotedPrice: Pence? = nil) throws {
        let d = try dogIndex(dogID)
        guard day >= state.day && day <= state.day + 90 else { throw GameError.invalid("Choose a booking within the next ninety game days.") }
        var future = state; future.day = day
        if let blocker = future.serviceBlocker(service) { throw GameError.invalid(blocker) }
        guard state.dogs[d].vaccinationDueDay >= day else { throw GameError.invalid("The vaccination record needs updating before this booking.") }
        let days = service == .holiday ? 3 : service == .overnight ? 2 : 1
        for date in day..<(day + days) {
            future.day = date
            guard future.licenceValid, future.insured else { throw GameError.invalid("Renew insurance and licensing to cover every requested day.") }
            let booked = state.bookings.filter { $0.day == date && $0.status != .cancelled }
            guard !booked.contains(where: { $0.dogID == dogID }) else { throw GameError.invalid("This dog already has a booking on that day.") }
            guard booked.count < future.careCapacity else { throw GameError.invalid("That day is at safe staffing or licence capacity. Change the date or improve cover.") }
            state.bookings.append(Booking(dogID: dogID, service: service, day: date, price: quotedPrice ?? state.prices[service.rawValue]!))
        }
    }
    mutating func checkIn(_ dogID: UUID) throws {
        let d = try dogIndex(dogID)
        guard state.isOpen, state.readiness().allSatisfy(\.complete) else { throw GameError.invalid("Open a ready, licensed site before checking dogs in.") }
        guard !state.dogs[d].present, let b = state.bookings.firstIndex(where: { $0.dogID == dogID && $0.day == state.day && $0.status == .expected }) else { throw GameError.invalid("There is no unstarted booking for this dog today.") }
        guard state.dogs.filter(\.present).count < state.careCapacity else { throw GameError.invalid("Today's care team is at safe capacity.") }
        if let blocker = state.serviceBlocker(state.bookings[b].service) { throw GameError.invalid(blocker) }
        guard state.dogs[d].vaccinationDueDay >= state.day else { throw GameError.invalid("Check the vaccination record with the owner before arrival.") }
        state.dogs[d].present = true; state.bookings[b].status = .checkedIn
        state.dogs[d].observations.append(Memory(day: state.day, text: "Arrival health check recorded. \(state.dogs[d].health)."))
    }
    mutating func care(_ dogID: UUID) throws {
        let d = try dogIndex(dogID)
        guard state.dogs[d].present else { throw GameError.invalid("Check this dog in before recording care.") }
        guard state.dogs[d].lastCareDay != state.day else { throw GameError.invalid("Today's routine is already recorded. Add an observation for anything new.") }
        let rest = state.priorities.contains("rest") && state.has("bed")
        let enrichment = state.priorities.contains("enrichment") && state.has("toys")
        let hygiene = state.cleanliness >= 60
        let staffing = state.dogs.filter(\.present).count <= state.careCapacity
        let water = state.has("water")
        let delta = (rest ? 3 : -4) + (enrichment ? 2 : -2) + (hygiene ? 1 : -8) + (staffing ? 1 : -12) + (water ? 1 : -15)
        state.dogs[d].welfare = bounded(state.dogs[d].welfare + delta)
        state.dogs[d].stress = bounded(state.dogs[d].stress + (rest && staffing ? -4 : 7))
        state.dogs[d].confidence = bounded(state.dogs[d].confidence + (delta > 0 ? 1 : -3))
        state.dogs[d].lastCareDay = state.day
        let note = rest && enrichment ? "Enjoyed \(state.dogs[d].favouriteActivity.lowercased()) and settled for a quiet rest." : rest ? "Rested quietly; more enrichment would help." : "Needed a quieter rest period during the day."
        state.dogs[d].observations.append(Memory(day: state.day, text: note))
        if let handler = state.staff.first(where: { $0.onDuty(day: state.day) && $0.role.caresForDogs }), state.dogs[d].attendedDays.count >= 3, !state.dogs[d].trustedStaff.contains(handler.id) { state.dogs[d].trustedStaff.append(handler.id) }
        if state.dogs[d].attendedDays.count >= 4 && delta > 0 {
            if let friend = state.dogs.first(where: { $0.id != dogID && $0.present && abs($0.energy - state.dogs[d].energy) < 20 && !state.dogs[d].friends.contains($0.id) }) {
                state.dogs[d].friends.append(friend.id)
                state.dogs[d].observations.append(Memory(day: state.day, text: "Growing comfortable playing with \(friend.name)."))
            }
        }
    }
    mutating func checkOut(_ dogID: UUID) throws {
        let d = try dogIndex(dogID)
        guard state.dogs[d].present, let b = state.bookings.firstIndex(where: { $0.dogID == dogID && $0.day == state.day && $0.status == .checkedIn }) else { throw GameError.invalid("This dog is not currently checked in.") }
        let c = try customerIndex(state.dogs[d].ownerID)
        let missedMedication = state.dogs[d].medications.contains { $0.dueDay <= state.day && !$0.givenDays.contains(state.day) }
        if state.dogs[d].lastCareDay != state.day { state.dogs[d].welfare = bounded(state.dogs[d].welfare - 18) }
        if missedMedication { state.dogs[d].welfare = bounded(state.dogs[d].welfare - 15); state.dogs[d].observations.append(Memory(day: state.day, text: "Scheduled medication was not recorded. Owner informed at collection.")) }
        state.dogs[d].present = false; state.dogs[d].attendedDays.append(state.day)
        state.bookings[b].status = .completed
        if !state.bookings[b].paid {
            let price = state.bookings[b].price
            post(price, "\(state.bookings[b].service.title): \(state.dogs[d].name)", kind: .income)
            state.bookings[b].paid = true
            post(-catalog.economy.dailySuppliesPerDog, "Care supplies: \(state.dogs[d].name)", kind: .expense)
            post(-max(1, price * 15 / 1000), "Card processing: \(state.dogs[d].name)", kind: .expense)
        }
        state.customers[c].visits += 1
        let poorCare = state.dogs[d].welfare < 60 || missedMedication
        state.customers[c].trust = bounded(state.customers[c].trust + (poorCare ? -16 : 3))
        if poorCare {
            let refund = state.bookings[b].price
            post(-refund, "Care guarantee refund: \(state.dogs[d].name)", kind: .refund); state.bookings[b].refunded = refund
            state.messages.append(Message(day: state.day, sender: state.customers[c].name, title: "Care concerns for \(state.dogs[d].name)", body: missedMedication ? "The medication record was missing today. Please explain how the care plan will be followed next time. The care guarantee refunded today's fee." : "My dog did not receive the expected standard of care today. Please review the rest, cleanliness and staffing records. The care guarantee refunded today's fee.", kind: .complaint, subjectID: state.customers[c].id))
            state.reputation = bounded(state.reputation - 4)
        } else if state.customers[c].visits % 4 == 0 {
            state.messages.append(Message(day: state.day, sender: state.customers[c].name, title: "A settled dog at collection", body: "\(state.dogs[d].name) \(state.dogs[d].observations.last?.text.lowercased() ?? "settled well today.") Thank you for the individual care.", kind: .review, subjectID: state.customers[c].id, rating: state.dogs[d].welfare >= 80 ? 5 : 4))
            state.reputation = bounded(state.reputation + 2)
            if state.dogs[d].welfare >= 80 { milestone("review", "Your first five-star review. Care that customers remember.") }
        }
        state.customers[c].history.append(Memory(day: state.day, text: "Collection handover: \(state.dogs[d].wellbeing.lowercased())."))
        milestone("firstCare", "Your first completed day of care. A small beginning with real meaning.")
    }
    mutating func staffAction(_ action: GameAction) throws -> String {
        let id: UUID
        switch action {
        case .hire(let value), .dismiss(let value), .promote(let value), .praise(let value): id = value
        case .train(let value, _), .staffRole(let value, _), .pay(let value, _), .rota(let value, _), .leave(let value, _): id = value
        default: throw GameError.invalid("Choose a staff action.")
        }
        guard let i = state.staff.firstIndex(where: { $0.id == id }) else { throw GameError.invalid("This staff member is no longer available.") }
        if case .hire = action {
            guard state.staff[i].joinedDay == nil else { throw GameError.invalid("This candidate has already been appointed.") }
            try spend(4500, "Recruitment checks for \(state.staff[i].name)")
            state.staff[i].joinedDay = state.day
            state.staff[i].history.append(Memory(day: state.day, text: "Joined as \(state.staff[i].role.title.lowercased())."))
            milestone("hire", "Your first employee. A team begins to grow.")
            return "\(state.staff[i].name) employed. Their agreed pay is now included in payroll."
        }
        guard state.staff[i].employed else { throw GameError.invalid("This person is not currently employed.") }
        switch action {
        case .dismiss:
            try spend(state.staff[i].hourlyPay * state.staff[i].hoursPerWeek, "Final agreed notice pay for \(state.staff[i].name)")
            state.staff[i].leftDay = state.day; state.staff[i].history.append(Memory(day: state.day, text: "Employment ended; notice pay settled."))
            return "Employment ended. Review upcoming bookings and cover."
        case .promote:
            guard state.staff[i].skill >= 65, state.staff[i].role != .manager else { throw GameError.invalid("Further experience or training is needed before the next promotion.") }
            state.staff[i].role = state.staff[i].role == .senior ? .manager : .senior
            state.staff[i].hourlyPay += 150; state.staff[i].morale = bounded(state.staff[i].morale + 8)
            state.staff[i].history.append(Memory(day: state.day, text: "Promoted to \(state.staff[i].role.title)."))
            milestone("promotion", "A career grows with your business. Your first promotion.")
            return "Promotion confirmed, with a pay rise of one pound fifty per hour."
        case .train(_, let course):
            guard Self.courses.contains(course), !state.staff[i].qualifications.contains(course) else { throw GameError.invalid("Choose a course this employee has not already completed.") }
            try spend(12000, "\(course) training for \(state.staff[i].name)")
            state.staff[i].qualifications.append(course); state.staff[i].skill = bounded(state.staff[i].skill + 7)
            state.staff[i].morale = bounded(state.staff[i].morale + 4)
            state.staff[i].history.append(Memory(day: state.day, text: "Completed \(course)."))
            return "Training completed and added to the staff record."
        case .staffRole(_, let role): state.staff[i].role = role; return "Staff role updated. Review pay and the rota."
        case .pay(_, let pay):
            guard (catalog.economy.minimumHourlyPay...5000).contains(pay) else { throw GameError.invalid("Choose an hourly rate of at least \(money(catalog.economy.minimumHourlyPay)), up to fifty pounds.") }
            state.staff[i].hourlyPay = pay; return "Hourly pay updated."
        case .rota(_, let days):
            guard Set(days).count == days.count, days.count <= 5, days.allSatisfy({ (0...6).contains($0) }) else { throw GameError.invalid("Choose up to five different working days.") }
            state.staff[i].workingWeekdays = days; return "Rota updated. Contracted weekly pay is unchanged."
        case .leave(_, let days):
            guard (1...14).contains(days) else { throw GameError.invalid("Choose one to fourteen days of leave.") }
            state.staff[i].absentUntilDay = state.day + days - 1; state.staff[i].stress = bounded(state.staff[i].stress - 10)
            return "Leave approved. Review cover for the affected days."
        case .praise:
            guard !state.staff[i].history.contains(where: { $0.day == state.day && $0.text == "Supportive check-in with the owner." }) else { throw GameError.invalid("You have already checked in with this colleague today.") }
            state.staff[i].morale = bounded(state.staff[i].morale + 2); state.staff[i].stress = bounded(state.staff[i].stress - 2)
            state.staff[i].history.append(Memory(day: state.day, text: "Supportive check-in with the owner.")); return "Supportive check-in recorded."
        default: throw GameError.invalid("Choose a staff action.")
        }
    }
    mutating func respond(_ id: UUID, choice: String) throws -> String {
        let m = try messageIndex(id)
        guard !state.messages[m].resolved else { throw GameError.invalid("This message has already been answered.") }
        let choices = ["Professional reply", "Apologise and improve", "Explain policy", "Request information", "Partial refund", "Full refund"]
        guard choices.contains(choice) else { throw GameError.invalid("Choose an available response.") }
        if let customerID = state.messages[m].subjectID, let c = state.customers.firstIndex(where: { $0.id == customerID }) {
            if choice.contains("refund") {
                let dogIDs = Set(state.dogs.filter { $0.ownerID == customerID }.map(\.id))
                guard let b = state.bookings.lastIndex(where: { dogIDs.contains($0.dogID) && $0.paid && $0.refunded < $0.price }) else { throw GameError.invalid("There is no unrefunded payment for this customer.") }
                let due = state.bookings[b].price - state.bookings[b].refunded
                let amount = choice == "Full refund" ? due : min(due, state.bookings[b].price / 2)
                try spend(amount, "Customer refund: \(state.customers[c].name)", kind: .refund); state.bookings[b].refunded += amount
            }
            state.customers[c].trust = bounded(state.customers[c].trust + (choice == "Explain policy" && state.messages[m].kind == .complaint ? -2 : 2))
            state.customers[c].history.append(Memory(day: state.day, text: "\(choice): \(state.messages[m].title)."))
        }
        state.messages[m].resolved = true; state.messages[m].read = true
        remember("\(choice) sent to \(state.messages[m].sender).")
        return "Response sent and recorded."
    }
}
public extension GameEngine {
    static var courses: [String] { ["Canine first aid", "Dog behaviour", "Medication records", "Puppy care", "Senior care", "Customer service", "Cleaning standards", "Leadership", "Overnight care", "Dog transport"] }
    var weeklyPayroll: Pence {
        state.staff.filter(\.employed).reduce(0) { sum, member in
            let wage = member.hourlyPay * member.hoursPerWeek
            let employerNI = max(0, wage - 9615) * 15 / 100
            let pension = max(0, wage - 12000) * 3 / 100
            return sum + wage + employerNI + pension
        }
    }
    var monthlyLoanPayment: Pence { state.loan.principal * catalog.economy.loanAPRPercent / 1200 + min(state.loan.principal, max(5000, state.loan.original / 36)) }
    var monthlyForecast: Pence {
        let weeklyBooked = state.bookings.filter { $0.day >= state.day && $0.day < state.day + 7 && $0.status != .cancelled }.reduce(0) { $0 + $1.price }
        return weeklyBooked * 4 - weeklyPayroll * 4 - catalog.economy.monthlyRent - catalog.economy.monthlyUtilities - catalog.economy.weeklyWaste * 4 - monthlyLoanPayment
    }
}
