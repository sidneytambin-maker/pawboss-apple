import SwiftUI
import Charts
import PawBossCore

struct BusinessView: View {
    @EnvironmentObject private var store: BusinessStore
    @State private var priorities: Set<String> = []
    var body: some View {
        List {
            if let state = store.state, let economy = store.catalog?.economy {
                Section("Opening and Compliance") {
                    NavRow(title: "Readiness and Inspection Findings", icon: "checklist", destination: .readiness)
                    if !state.licence.registered { Act(title: "Register Business", icon: "doc.badge.plus", action: .register, confirmation: "Register the business for \(money(economy.registration))?") }
                    if !state.insured { Act(title: "Arrange Annual Insurance", icon: "shield.lefthalf.filled", action: .insure, confirmation: "Arrange one year's business insurance for \(money(economy.insurance))?") }
                    if !state.licence.applied || (!state.licenceValid && state.licence.validUntilDay != nil) { Act(title: "Apply for Day Care Licence", icon: "doc.text", action: .applyLicence, confirmation: "Submit your licence application for \(money(economy.licence))? The inspection is a separate cost.") }
                    if state.licence.inspectionDay == nil { Act(title: "Book Council Inspection", icon: "checkmark.seal", action: .requestInspection, confirmation: "Book an inspection for \(money(economy.inspection))? It takes place in two game days and the fee is not refunded after a failed inspection.") }
                    else { ValueRow(title: "Inspection booked", value: "Business day \((state.licence.inspectionDay ?? 0) + 1)") }
                    ValueRow(title: "Approved capacity", value: "\(state.licence.capacity) dogs; current care cover allows \(state.careCapacity)")
                    if let expiry = state.licence.insuranceUntilDay { ValueRow(title: "Insurance renewal", value: "Business day \(expiry + 1)") }
                    if let expiry = state.licence.validUntilDay { ValueRow(title: "Licence renewal", value: "Business day \(expiry + 1)") }
                }
                Section("Strategy") {
                    NavRow(title: "Service Prices", icon: "tag", destination: .pricing)
                    Act(title: "Start Local Campaign", icon: "megaphone", action: .market, confirmation: "Spend thirty-five pounds on a seven-day local introduction campaign?")
                    ForEach(["rest", "enrichment", "cleaning", "communication", "maintenance", "training"], id: \.self) { priority in
                        Toggle(priority.capitalized, isOn: Binding(get: { priorities.contains(priority) }, set: { if $0 { priorities.insert(priority) } else { priorities.remove(priority) } }))
                    }
                    Act(title: "Save Three Daily Priorities", icon: "checkmark", action: .priorities(priorities.sorted()))
                        .disabled(priorities.count > 3)
                }
                Section("Development") {
                    Act(title: "Apply for Planning", icon: "building.2", action: .applyPlanning, confirmation: "Commission a planning assessment and survey for two hundred pounds? A decision is due in seven days.")
                    Act(title: "Apply for Boarding Approval", icon: "moon.stars", action: .boardingApproval, confirmation: "Arrange a boarding-service assessment for two hundred and fifty pounds?")
                    NavRow(title: "Community Partners", icon: "person.3", destination: .community)
                }
            }
        }.listStyle(.plain).navigationTitle("Business")
            .onAppear { priorities = Set(store.state?.priorities ?? []) }
    }
}
struct FinanceView: View {
    @EnvironmentObject private var store: BusinessStore
    @State private var filter = "All"
    var body: some View {
        List {
            if let state = store.state, let engine = store.engine {
                Section("Business Bank") {
                    Text(money(state.cash)).font(.largeTitle.bold()).foregroundStyle(state.cash < 0 ? Color.pawCoral : Color.pawGreen)
                        .accessibilityLabel("Cash balance. \(money(state.cash))")
                    ValueRow(title: "Outstanding loan", value: money(state.loan.principal))
                    ValueRow(title: "Weekly contracted employment cost", value: money(engine.weeklyPayroll))
                    ValueRow(title: "Next monthly loan payment", value: money(engine.monthlyLoanPayment))
                    ValueRow(title: "Confirmed-booking forecast", value: "\(money(engine.monthlyForecast)) over four weeks, before new bookings, variable care supplies and new investment.")
                }
                NavRow(title: "Service Prices", icon: "tag", destination: .pricing)
                NavRow(title: "Loans and Repayments", icon: "building.columns", destination: .loans)
                NavRow(title: "Financial Reports", icon: "chart.xyaxis.line", destination: .reports)
                Section("Transactions") {
                    Picker("Show", selection: $filter) { ForEach(["All", "Income", "Expenses", "Investment", "Loans"], id: \.self) { Text($0) } }
                    ForEach(state.ledger.filter { filter == "All" || filter == "Income" && $0.kind == .income || filter == "Expenses" && [.expense, .refund].contains($0.kind) || filter == "Investment" && $0.kind == .investment || filter == "Loans" && [.borrowing, .principal].contains($0.kind) }.suffix(100).reversed()) { entry in
                        ValueRow(title: "Day \(entry.day + 1). \(entry.description)", value: "\(money(entry.amount)). Balance \(money(entry.balance)).")
                    }
                }
            }
        }.listStyle(.plain).navigationTitle("Finance")
    }
}
struct PricingView: View {
    @EnvironmentObject private var store: BusinessStore
    @State private var service: Service = .dayCare
    @State private var price = "35.00"
    var body: some View {
        Form {
            Picker("Service", selection: $service) { ForEach(Service.allCases) { Text($0.title).tag($0) } }
            ValueRow(title: "Suggested price", value: money(store.catalog?.economy.prices[service.rawValue] ?? 0))
            TextField("Price in pounds", text: $price).accessibilityHint("Enter pounds and pence. Existing agreed bookings keep their price.")
            Button("Save Price", systemImage: "checkmark") {
                guard let amount = MoneyInput.parse(price) else { store.errorMessage = "Enter a valid price in pounds and pence."; return }
                store.send(.setPrice(service, amount))
            }
            if let blocker = store.state?.serviceBlocker(service) { ValueRow(title: "Service readiness", value: blocker) }
            else { Label("Service ready", systemImage: "checkmark.circle") }
        }.navigationTitle("Pricing").onAppear { refresh() }.onChange(of: service) { _, _ in refresh() }
    }
    private func refresh() { price = MoneyInput.edit(store.state?.prices[service.rawValue] ?? 0) }
}
struct LoansView: View {
    @EnvironmentObject private var store: BusinessStore
    @State private var amount = "1000.00"
    @State private var confirmBorrow = false
    @State private var confirmRepay = false
    var body: some View {
        Form {
            if let state = store.state, let engine = store.engine {
                ValueRow(title: "Outstanding principal", value: money(state.loan.principal))
                ValueRow(title: "Interest rate", value: "\(engine.catalog.economy.loanAPRPercent)% APR, a fictional business-loan assumption")
                ValueRow(title: "Next monthly payment", value: money(engine.monthlyLoanPayment))
                ValueRow(title: "Interest paid", value: money(state.loan.interestPaid))
                TextField("Amount in pounds", text: $amount)
                Button("Take Business Loan", systemImage: "plus.circle") { confirmBorrow = true }
                Button("Repay Principal", systemImage: "minus.circle") { confirmRepay = true }
            }
        }.navigationTitle("Loans")
            .confirmationDialog("Borrow \(amount) pounds at \(store.catalog?.economy.loanAPRPercent ?? 34)% APR? Interest and principal are payable monthly.", isPresented: $confirmBorrow, titleVisibility: .visible) {
                Button("Confirm Loan") { submit(borrow: true) }; Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Repay \(amount) pounds from available cash?", isPresented: $confirmRepay, titleVisibility: .visible) {
                Button("Confirm Repayment") { submit(borrow: false) }; Button("Cancel", role: .cancel) {}
            }
    }
    private func submit(borrow: Bool) {
        guard let pence = MoneyInput.parse(amount) else { store.errorMessage = "Enter a valid amount in pounds and pence."; return }
        store.send(borrow ? .borrow(pence) : .repay(pence))
    }
}
struct ReportsView: View {
    @EnvironmentObject private var store: BusinessStore
    @State private var period = 30
    @State private var metric = "Revenue"
    var body: some View {
        List {
            Picker("Period", selection: $period) { Text("Last 7 days").tag(7); Text("Last 30 days").tag(30); Text("Last year").tag(365) }
            Picker("Chart", selection: $metric) { ForEach(["Revenue", "Expenses", "Profit", "Cash", "Attendance", "Welfare", "Customers", "Staff"], id: \.self) { Text($0) } }
            if let state = store.state {
                let reports = Array(state.reports.suffix(period))
                if reports.isEmpty { Text("Your first report appears after you complete a business day.") }
                else {
                    ValueRow(title: metric, value: summary(reports))
                    Chart(reports) { report in
                        LineMark(x: .value("Business day", report.day + 1), y: .value(metric, value(report)))
                            .foregroundStyle(Color.pawGreen).symbol(.circle)
                            .accessibilityLabel("Business day \(report.day + 1)")
                            .accessibilityValue(spoken(report))
                    }.frame(height: store.isWatch ? 130 : 220).accessibilityLabel("\(metric) trend").accessibilityValue(summary(reports)).accessibilityIdentifier("businessTrend")
                    Section {
                        ValueRow(title: "Care revenue", value: money(reports.reduce(0) { $0 + $1.revenue }))
                        ValueRow(title: "Operating costs and refunds", value: money(reports.reduce(0) { $0 + $1.expenses }))
                        ValueRow(title: "Operating result", value: money(reports.reduce(0) { $0 + $1.profit }))
                        ValueRow(title: "Cash movement", value: money(state.cashMovement(from: reports.first!.day, through: reports.last!.day)))
                        ValueRow(title: "Care days delivered", value: "\(reports.reduce(0) { $0 + $1.attendance })")
                        ValueRow(title: "Business explanation", value: reports.last?.explanation ?? "")
                    } header: { Text("Report Values").foregroundStyle(Color.primary) }
                    Section { ForEach(reports.reversed()) { report in ValueRow(title: "Day \(report.day + 1)", value: "\(metric): \(spoken(report)).") } } header: { Text("Individual Days").foregroundStyle(Color.primary) }
                }
            }
        }.listStyle(.plain).navigationTitle("Reports")
    }
    private func value(_ r: DayReport) -> Double {
        switch metric { case "Revenue": return Double(r.revenue) / 100; case "Expenses": return Double(r.expenses) / 100; case "Profit": return Double(r.profit) / 100; case "Cash": return Double(r.cash) / 100; case "Attendance": return Double(r.attendance); case "Welfare": return Double(r.welfare); case "Customers": return Double(r.customers); default: return Double(r.staff) }
    }
    private func spoken(_ r: DayReport) -> String { ["Revenue", "Expenses", "Profit", "Cash"].contains(metric) ? money(Pence((value(r) * 100).rounded())) : metric == "Welfare" ? (r.customers == 0 ? "No dogs registered" : "\(r.welfare) out of 100") : "\(Int(value(r)))" }
    private func summary(_ reports: [DayReport]) -> String {
        guard let first = reports.first, let last = reports.last else { return "No completed days" }
        let direction = value(last) > value(first) ? "Increased" : value(last) < value(first) ? "Decreased" : "Unchanged"
        return "\(direction) from \(spoken(first)) to \(spoken(last)) across \(reports.count) completed days."
    }
}
struct HistoryView: View {
    @EnvironmentObject private var store: BusinessStore
    var body: some View {
        List {
            if let state = store.state {
                Section("Milestones") {
                    if state.milestones.isEmpty { Text("Your business story is just beginning.") }
                    ForEach(state.milestones.keys.sorted(), id: \.self) { key in
                        Label("\(milestoneName(key)). Day \((state.milestones[key] ?? 0) + 1).", systemImage: "rosette").foregroundStyle(Color.pawGreen)
                    }
                }
                Section("Business History") { ForEach(state.history.reversed()) { ValueRow(title: "Day \($0.day + 1)", value: $0.text) } }
            }
        }.listStyle(.plain).navigationTitle("Your Business Story")
    }
    private func milestoneName(_ id: String) -> String {
        ["opening": "Open for business", "customer": "First customer", "firstCare": "First day of care", "inspection": "Inspection passed", "review": "Five-star care", "hire": "First colleague", "promotion": "A career grows", "100care": "One hundred care days", "profitMonth": "A sustainable month", "expansion": "Room to grow"][id] ?? "Business anniversary"
    }
}
struct CommunityView: View {
    @EnvironmentObject private var store: BusinessStore
    var body: some View {
        List {
            if let state = store.state {
                Text("Westmoor").font(.title2.bold())
                ValueRow(title: "Local conditions", value: "\(state.weather). Local day-care prices change as neighbouring businesses develop.")
                ForEach(["Competitor", "Supplier", "Vet", "Trainer", "Groomer", "Community"], id: \.self) { category in
                    Section(category) {
                        ForEach(state.world.filter { $0.category == category }) { business in
                            ValueRow(title: business.name, value: "\(business.detail) \(category == "Competitor" ? "Day-care price: \(money(business.price))." : "")")
                            if category != "Competitor" { Act(title: "Partner with \(business.name)", icon: "person.2", action: .community(business.id), confirmation: "Spend twenty-five pounds on a local introduction and partnership? It remains active for a month.") }
                        }
                    }
                }
            }
        }.listStyle(.plain).navigationTitle("Community and Market")
    }
}
struct AdviserView: View {
    @EnvironmentObject private var store: BusinessStore
    var body: some View {
        List {
            Text(store.engine?.adviser ?? "Create a business to begin your first opening.").fixedSize(horizontal: false, vertical: true)
            NavRow(title: "Readiness", icon: "checklist", destination: .readiness)
            NavRow(title: "Finance", icon: "sterlingsign.circle", destination: .finance)
            NavRow(title: "Dog Welfare", icon: "heart", destination: .dogs)
        }.listStyle(.plain).navigationTitle("Business Adviser")
    }
}
