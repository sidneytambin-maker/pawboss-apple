import Foundation

extension GameEngine {
    mutating func simulateDay() throws {
        let day = state.day
        if state.isOpen {
            let expected = state.todayBookings.filter { $0.status == .expected }.map(\.dogID)
            for id in expected {
                do { try checkIn(id) }
                catch {
                    if let b = state.bookings.firstIndex(where: { $0.dogID == id && $0.day == day && $0.status == .expected }) { state.bookings[b].status = .cancelled }
                    let dog = state.dogs[try dogIndex(id)]
                    state.messages.append(Message(day: day, sender: "Daily care team", title: "Booking could not safely go ahead", body: "\(dog.name): \(error.localizedDescription) No fee was charged.", kind: .message, subjectID: dog.ownerID))
                }
            }
            let present = state.dogs.filter(\.present).map(\.id)
            for id in present {
                if state.dogs[try dogIndex(id)].lastCareDay != day { try care(id) }
                try checkOut(id)
            }
        } else {
            for b in state.bookings.indices where state.bookings[b].day == day && state.bookings[b].status == .expected {
                state.bookings[b].status = .cancelled
                let d = try dogIndex(state.bookings[b].dogID)
                let c = try customerIndex(state.dogs[d].ownerID)
                state.customers[c].trust = bounded(state.customers[c].trust - 5)
                state.customers[c].history.append(Memory(day: day, text: "Booking cancelled because the business was closed. No fee charged."))
            }
        }
        let attendance = state.bookings.filter { $0.day == day && $0.status == .completed }.count
        state.cleanliness = bounded(state.cleanliness - attendance * 2 - (state.weather == "Heavy rain" ? attendance : 0) + (state.priorities.contains("cleaning") ? 8 : 0) + (attendance > 0 ? state.cleaningEquipmentSupport : 0))
        if attendance > 0 && state.priorities.contains("cleaning") { post(-300 - Pence(attendance) * 40, "Daily cleaning and laundry", kind: .expense) }
        for i in state.staff.indices where state.staff[i].employed {
            let onDuty = state.staff[i].onDuty(day: day)
            let pressure = attendance >= max(1, state.careCapacity) ? 4 : -2
            let breakSupport = attendance < state.careCapacity ? state.teamEquipmentSupport : 0
            state.staff[i].stress = bounded(state.staff[i].stress + (onDuty ? pressure - breakSupport : -4))
            state.staff[i].morale = bounded(state.staff[i].morale + (state.staff[i].stress > 65 ? -3 : attendance > 0 ? 1 : 0))
            if onDuty && attendance > 0 && day % 7 == 6 { state.staff[i].skill = bounded(state.staff[i].skill + 1) }
            if onDuty && attendance > 0 && state.priorities.contains("training") && day % 3 == 0 {
                state.staff[i].skill = bounded(state.staff[i].skill + 1)
                state.staff[i].history.append(Memory(day: day, text: "Supervised practice strengthened everyday care skills."))
            }
            if state.staff[i].stress > 80 && state.random(8) == 0 {
                state.staff[i].absentUntilDay = day + 2
                state.messages.append(Message(day: day, sender: state.staff[i].name, title: "Sickness absence", body: "I need two days away to recover. Please review the rota and care cover.", kind: .staff, subjectID: state.staff[i].id))
            }
        }
        for a in state.areas.indices {
            for i in state.areas[a].items.indices where state.areas[a].items[i].readyDay <= day {
                let definition = try catalog.item(state.areas[a].items[i].definitionID)
                if day > state.areas[a].items[i].installedDay && day % max(1, definition.lifespanDays / 100) == 0 {
                    state.areas[a].items[i].condition = max(0, state.areas[a].items[i].condition - (attendance > 4 ? 2 : 1))
                }
                if state.priorities.contains("maintenance") && state.areas[a].items[i].condition < 90 && state.cash >= 150 {
                    post(-150, "Routine maintenance: \(definition.name)", kind: .expense)
                    state.areas[a].items[i].condition = min(100, state.areas[a].items[i].condition + 5)
                }
            }
        }
        if (day + 1) % 7 == 0 {
            let payroll = payrollForWeek(ending: day)
            if payroll > 0 { post(-payroll, "Weekly wages, employer contributions and pension", kind: .expense) }
            post(-catalog.economy.weeklyWaste, "Weekly commercial waste collection", kind: .expense)
            let facilityCost = try state.areas.flatMap(\.items).filter { $0.readyDay <= day }.reduce(0) { $0 + (try catalog.item($1.definitionID).weeklyCost) }
            if facilityCost > 0 { post(-facilityCost, "Facilities running costs", kind: .expense) }
        }
        if (day + 1) % 30 == 0 {
            let inflation = Pence(100 + (day / 365) * 3)
            post(-catalog.economy.monthlyRent * inflation / 100, "Monthly premises rent", kind: .expense)
            let winter = [11, 12, 1, 2].contains(Calendar.pawBoss.component(.month, from: state.date))
            post(-catalog.economy.monthlyUtilities * (winter ? 125 : 100) * inflation / 10000, "Monthly utilities and administration\(winter ? ", including winter heating" : "")", kind: .expense)
        }
        if let due = state.loan.nextPaymentDay, due <= day, state.loan.principal > 0 {
            let interest = state.loan.principal * Pence(catalog.economy.loanAPRPercent) / 1200
            post(-interest, "Monthly loan interest", kind: .expense); state.loan.interestPaid += interest
            let principal = min(state.loan.principal, max(5000, state.loan.original / 36))
            post(-principal, "Monthly loan principal repayment", kind: .principal)
            state.loan.principal -= principal; state.loan.nextPaymentDay = state.loan.principal == 0 ? nil : day + 30
        }
        chooseEvent(attendance: attendance)
        let entries = state.ledger.filter { $0.day == day }
        let revenue = entries.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount }
        let expenses = -entries.filter { [.expense, .refund].contains($0.kind) }.reduce(0) { $0 + $1.amount }
        let explanation = attendance == 0 ? "No dogs attended; no care income was invented. Premises and employment commitments still apply." : "\(attendance) dogs attended. Care quality shaped customer trust; supplies, wages and facilities shaped the cost of providing that care."
        state.reports.append(DayReport(day: day, revenue: revenue, expenses: expenses, profit: revenue - expenses, cash: state.cash, attendance: attendance, welfare: state.welfare, customers: state.customers.count, staff: state.staff.filter(\.employed).count, explanation: explanation))
        if state.dogs.reduce(0, { $0 + $1.attendedDays.count }) >= 100 { milestone("100care", "One hundred days of individual dog care. Look how far you have come.") }
        if (day + 1) % 30 == 0 {
            let profit = state.reports.suffix(30).reduce(0) { $0 + $1.profit }
            if profit > 0 { milestone("profitMonth", "Your first profitable month. Care and careful planning are working together.") }
            state.messages.append(Message(day: day, sender: "Monthly review", title: "Month \((day + 1) / 30) review", body: "Operating result: \(money(profit)). Cash: \(money(state.cash)). \(adviser)", kind: .report))
        }
        if (day + 1) % 365 == 0 { milestone("year-\((day + 1) / 365)", "\(state.name) celebrates \((day + 1) / 365) years in business.") }
        state.day += 1
        if state.day % 7 == 0 && state.priorities.contains("communication") {
            for c in state.customers.indices where state.customers[c].visits > 0 {
                state.customers[c].trust = bounded(state.customers[c].trust + 1)
                state.customers[c].history.append(Memory(day: state.day, text: "Received a clear weekly care update."))
            }
        }
        state.weather = ["Mild", "Mild", "Cloudy", "Heavy rain", "Warm sunshine", "Cold snap"][state.random(6)]
        if state.day % 30 == 0 { for i in state.dogs.indices { state.dogs[i].ageMonths += 1 } }
        completeConstruction()
        if state.licence.inspectionDay == state.day { inspect() }
        if !state.licenceValid || !state.insured {
            state.isOpen = false
            if state.licence.validUntilDay == state.day - 1 || state.licence.insuranceUntilDay == state.day - 1 {
                state.messages.append(Message(day: state.day, sender: "Business records", title: "Renewal needed before reopening", body: "Insurance or licensing has expired. Arrange renewal to protect your customers and business.", kind: .inspection))
            }
        }
        for i in state.enquiries.indices where state.enquiries[i].status == .informationRequested && (state.enquiries[i].responseDay ?? Int.max) <= state.day {
            state.enquiries[i].status = .pending; state.enquiries[i].requirements += " Owner confirmed the care information and requested a calm introductory day."
        }
        let activeCampaign = (state.marketingUntilDay ?? -1) >= state.day
        let referrals = state.customers.contains { $0.trust >= 75 }
        let localPartner = state.eventLastDays.contains { $0.key.hasPrefix("partner-") && $0.value > state.day - 30 }
        let sensiblePrice = state.prices[Service.dayCare.rawValue, default: 3500] <= catalog.economy.prices[Service.dayCare.rawValue, default: 3500] * Pence(140 + state.reputation) / 100
        if state.pendingEnquiries.count < 12 && sensiblePrice && (activeCampaign || (referrals && state.random(3) == 0) || (localPartner && state.random(4) == 0)) {
            generateEnquiry(source: activeCampaign ? "Local introduction campaign" : referrals ? "Customer recommendation" : "Community partner")
        }
        if state.day % 7 == 0 {
            for i in state.world.indices where state.world[i].category == "Competitor" {
                state.world[i].price = max(2000, state.world[i].price + Pence(state.random(201)) - 100)
                state.world[i].reputation = bounded(state.world[i].reputation + state.random(5) - 2)
            }
            state.messages.append(Message(day: state.day, sender: "Weekly briefing", title: "Welcome to Week \(state.week)", body: adviser, kind: .report))
            scheduleReturningCustomers()
        }
        if state.cash < 0 {
            state.messages.append(Message(day: state.day, sender: "Business bank", title: "Cash shortfall", body: "The balance is \(money(state.cash)). Committed bills remain payable. Review pricing, future bookings, staffing and optional borrowing before further purchases.", kind: .message))
        }
    }
    func payrollForWeek(ending day: Int) -> Pence {
        state.staff.reduce(0) { total, member in
            guard let joined = member.joinedDay else { return total }
            let end = min(day, (member.leftDay ?? (day + 1)) - 1)
            let paidDays = max(0, end - max(day - 6, joined) + 1)
            let wage = member.hourlyPay * Pence(member.hoursPerWeek) * Pence(paidDays) / 7
            return total + wage + max(0, wage - 9615) * 15 / 100 + max(0, wage - 12000) * 3 / 100
        }
    }
    mutating func inspect() {
        state.licence.inspectionDay = nil
        let checks = state.readiness().filter { $0.id != "licence" }
        state.licence.findings = checks.map { "\($0.title): \($0.complete ? "meets the standard" : $0.help)" }
        if checks.allSatisfy(\.complete) {
            state.licence.validUntilDay = state.day + 364
            state.licence.result = state.welfare >= 85 && state.customers.count >= 5 ? "Excellent" : "Good"
            milestone("inspection", "Your first inspection passed. Prepared, safe and ready to care.")
        } else { state.licence.result = "Requires improvement"; state.isOpen = false }
        state.messages.append(Message(day: state.day, sender: "Westmoor council", title: "Inspection: \(state.licence.result)", body: state.licence.findings.joined(separator: "\n"), kind: .inspection))
        remember("Council inspection: \(state.licence.result).")
    }
    mutating func completeConstruction() {
        for item in state.areas.flatMap(\.items) where item.definitionID == "extension" && item.readyDay == state.day {
            let areaID = "room-\(item.id.uuidString)"
            if !state.areas.contains(where: { $0.id == areaID }) {
                state.areas.append(Area(id: areaID, name: "Care building \(state.areas.count - 2)", rows: 4, columns: 4))
                remember("A new care building completed. Its room is ready to configure.")
            }
        }
    }
    mutating func scheduleReturningCustomers() {
        for dog in state.dogs where dog.welfare >= 60 {
            guard let customer = state.customers.first(where: { $0.id == dog.ownerID && $0.trust >= 35 && $0.visits > 0 }) else { continue }
            for offset in CustomerSchedule.offsets(for: customer.bookingHabit) {
                var candidate = self
                do { try candidate.book(dog.id, service: CustomerSchedule.service(for: customer.bookingHabit), day: state.day + offset); self = candidate }
                catch { /* An unsafe or duplicate returning booking is not added. */ }
            }
        }
    }
    mutating func chooseEvent(attendance: Int) {
        guard attendance > 0 else { return }
        let candidates = catalog.events.filter { event in
            guard state.day - state.eventLastDays[event.id, default: -1000] >= event.cooldown else { return false }
            switch event.condition {
            case "rain": return state.weather == "Heavy rain"
            case "heat": return state.weather == "Warm sunshine" && !state.careHas(["shade", "coolmat", "fan", "canopy"])
            case "rainPrepared": return state.weather == "Heavy rain" && state.cleaningEquipmentSupport >= 2
            case "seniorCare": return state.dogs.contains { $0.ageMonths >= 96 && $0.attendedDays.last == state.day } && state.careHas(["orthobed", "quietden"]) && state.priorities.contains("rest")
            case "enrichment": return state.priorities.contains("enrichment") && state.careHas(["snuffle", "puzzle", "garden", "trainingkit"]) && state.welfare >= 75
            case "reserve": return state.day >= 28 && state.cash >= 300000 && state.loan.principal == 0
            case "loyal": return state.customers.contains { $0.visits >= 10 && $0.trust >= 75 }
            case "teamPrepared": return state.staff.contains { $0.employed && $0.skill >= 70 && $0.stress < 40 }
            case "tightMargin": return state.reports.suffix(7).filter { $0.attendance > 0 }.count >= 3 && state.reports.suffix(7).reduce(0, { $0 + $1.profit }) < 0
            case "coldPrepared": return state.weather == "Cold snap" && state.careHas(["blankets"]) && state.priorities.contains("rest")
            case "worn": return state.areas.flatMap(\.items).contains { $0.condition < 45 }
            case "stress": return state.staff.contains { $0.employed && $0.stress > 65 }
            case "settled": return state.customers.count >= 3 && state.welfare > 70
            case "established": return state.day >= 90
            default: return false
            }
        }
        guard !candidates.isEmpty, state.random(4) == 0 else { return }
        let event = candidates[state.random(candidates.count)]
        state.eventLastDays[event.id] = state.day
        if event.cost > 0 { post(-event.cost, event.title, kind: .expense) }
        for d in state.dogs.indices where state.dogs[d].attendedDays.last == state.day { state.dogs[d].welfare = bounded(state.dogs[d].welfare + event.welfare) }
        for s in state.staff.indices where state.staff[s].onDuty(day: state.day) { state.staff[s].stress = bounded(state.staff[s].stress + event.stress) }
        state.reputation = bounded(state.reputation + event.reputation)
        state.messages.append(Message(day: state.day, sender: "Westmoor daily news", title: event.title, body: event.body, kind: .community))
        remember(event.title)
    }
}
public extension GameEngine {
    var adviser: String {
        if state.cash < 100000 { return "Cash is tight. New investment would leave less room for wages and rent. Review confirmed bookings before adding commitments." }
        if !state.licenceValid { return "A careful opening starts with the readiness checklist. Essential equipment is enough; larger facilities can wait until customers need them." }
        if state.welfare > 0 && state.welfare < 65 { return "Care quality needs attention. Review rest, water, cleaning and medication before accepting more dogs. Customer confidence depends on consistent care." }
        if state.staff.contains(where: { $0.employed && $0.stress > 65 }) { return "The team is stretched. More cover would cost money but could protect wellbeing, continuity and the quality of each dog's day." }
        if state.pendingEnquiries.isEmpty && state.customers.count < 4 { return "The site is ready for more relationships. A modest campaign or community partnership can introduce you to local dog owners." }
        if state.bookings.filter({ $0.day >= state.day && $0.status == .expected }).count >= state.careCapacity * 3 { return "Bookings are building. Holding some capacity in reserve helps the team manage illness, new arrivals and dogs who need more reassurance." }
        return "Your next decision is a balance: preserve a cash reserve, invest in reliable care, and let customer trust grow through consistent experience. Growth adds responsibility as well as opportunity."
    }
}
