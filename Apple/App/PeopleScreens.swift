import SwiftUI
import PawBossCore

struct CustomersView: View {
    @EnvironmentObject private var store: BusinessStore
    @State private var search = ""
    var body: some View {
        List {
            if let state = store.state {
                if state.customers.isEmpty { Text("Customers join when you accept a dog enquiry.") }
                ForEach(state.customers.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }.sorted { $0.name < $1.name }) { customer in
                    NavRow(title: customer.name, icon: "person.crop.circle", destination: .customer(customer.id), detail: customer.relationship)
                        .accessibilityActions {
                            if let dog = state.dogs.first(where: { $0.ownerID == customer.id }) {
                                Button("View Dog") { store.navigate(.dog(dog.id)) }
                                Button("Send Care Update") { store.send(.contactOwner(dog.id)) }
                            }
                        }
                }
                NavRow(title: "Waiting List and Enquiries", icon: "clock", destination: .enquiries)
            }
        }.listStyle(.plain).searchable(text: $search, prompt: "Customer name").navigationTitle("Customers")
    }
}
struct CustomerDetailView: View {
    @EnvironmentObject private var store: BusinessStore
    let id: UUID
    var customer: Customer? { store.state?.customers.first { $0.id == id } }
    var body: some View {
        List {
            if let c = customer, let state = store.state {
                ValueRow(title: "Relationship", value: c.relationship)
                ValueRow(title: "Preferred communication", value: c.communication)
                ValueRow(title: "Booking habit", value: c.bookingHabit)
                ValueRow(title: "Completed visits", value: "\(c.visits)")
                Section("Dogs") { ForEach(state.dogs.filter { $0.ownerID == id }) { dog in
                    NavRow(title: dog.name, icon: "dog", destination: .dog(dog.id), detail: dog.wellbeing)
                    Act(title: "Share \(dog.name)'s Update", icon: "paperplane", action: .contactOwner(dog.id))
                } }
                Section("Messages and Reviews") { ForEach(state.messages.filter { $0.subjectID == id }) { message in
                    NavRow(title: message.title, icon: "envelope", destination: .message(message.id), detail: message.resolved ? "Answered" : "Awaiting response")
                } }
                Section("Relationship History") { ForEach(c.history.reversed()) { ValueRow(title: "Day \($0.day + 1)", value: $0.text) } }
            }
        }.listStyle(.plain).navigationTitle(customer?.name ?? "Customer")
    }
}
struct InboxView: View {
    @EnvironmentObject private var store: BusinessStore
    let onlyAlerts: Bool
    @State private var filter = "All"
    @State private var search = ""
    var body: some View {
        List {
            Picker("Show", selection: $filter) { ForEach(["All", "Unread", "Complaints", "Reviews", "Archived"], id: \.self) { Text($0) } }
            if let state = store.state {
                let messages = state.messages.filter { m in
                    (filter == "Archived" ? m.archived : !m.archived) &&
                    (search.isEmpty || m.title.localizedCaseInsensitiveContains(search) || m.sender.localizedCaseInsensitiveContains(search)) &&
                    (filter != "Unread" || !m.read) && (filter != "Complaints" || m.kind == .complaint) &&
                    (filter != "Reviews" || m.kind == .review) && (!onlyAlerts || (!m.resolved && [.complaint, .inspection, .staff].contains(m.kind)))
                }
                if messages.isEmpty { Text("No messages in this view.") }
                ForEach(messages.reversed()) { message in
                    NavRow(title: message.title, icon: message.read ? "envelope.open" : "envelope.badge", destination: .message(message.id), detail: "\(message.sender). \(message.read ? "Read" : "Unread").")
                        .accessibilityActions {
                            Button("Mark Read") { store.send(.readMessage(message.id)) }
                            if !message.archived { Button("Archive") { store.send(.archiveMessage(message.id)) } }
                        }
                }
            }
        }.listStyle(.plain).searchable(text: $search, prompt: "Messages").navigationTitle(onlyAlerts ? "Alerts" : "Inbox")
    }
}
struct MessageDetailView: View {
    @EnvironmentObject private var store: BusinessStore
    let id: UUID
    @State private var response = "Professional reply"
    var body: some View {
        List {
            if let message = store.state?.messages.first(where: { $0.id == id }) {
                ValueRow(title: "From", value: message.sender)
                Text(message.title).font(.headline)
                ForEach(Array(message.body.components(separatedBy: "\n").enumerated()), id: \.offset) { _, text in Text(text).fixedSize(horizontal: false, vertical: true) }
                if let rating = message.rating { ValueRow(title: "Review", value: "\(rating) out of 5 stars") }
                if message.kind == .inspection { NavRow(title: "Inspection Findings", icon: "checkmark.seal", destination: .readiness) }
                if message.kind == .report { NavRow(title: "Business Reports", icon: "chart.bar", destination: .reports) }
                if !message.resolved && [.message, .complaint, .review, .referral].contains(message.kind) {
                    Picker("Response", selection: $response) {
                        ForEach(["Professional reply", "Apologise and improve", "Explain policy", "Request information", "Partial refund", "Full refund"], id: \.self) { Text($0) }
                    }
                    Act(title: "Send Response", icon: "paperplane", action: .respond(id, response), confirmation: response.contains("refund") ? "Issue the selected refund against this customer's most recent unrefunded payment?" : nil)
                }
                if !message.read { Act(title: "Mark Read", icon: "envelope.open", action: .readMessage(id)) }
                if !message.archived { Act(title: "Archive", icon: "archivebox", action: .archiveMessage(id)) }
                if message.resolved { Label("Response recorded", systemImage: "checkmark.circle") }
            }
        }.listStyle(.plain).navigationTitle("Message")
    }
}
struct StaffListView: View {
    @EnvironmentObject private var store: BusinessStore
    let recruitment: Bool
    var body: some View {
        List {
            if let state = store.state {
                if !recruitment {
                    ValueRow(title: state.owner, value: "\(state.ownerTitle). \(state.ownerOnDuty ? "Providing care cover" : "Off care duty"). Owner salary: none.")
                    Toggle("Owner provides care cover", isOn: Binding(get: { store.state?.ownerOnDuty ?? false }, set: { store.send(.ownerCover($0)) }))
                    NavRow(title: "Recruitment", icon: "person.badge.plus", destination: .recruitment)
                }
                ForEach(state.staff.filter { recruitment ? $0.joinedDay == nil : $0.employed }) { member in
                    NavRow(title: member.name, icon: "person.crop.circle", destination: .employee(member.id), detail: "\(member.role.title). Age \(member.age). \(member.wellbeing).")
                        .accessibilityActions {
                            if member.employed {
                                Button("Review Pay") { store.navigate(.staffTask(member.id, .pay)) }
                                Button("Training") { store.navigate(.staffTask(member.id, .training)) }
                                Button("Change Role") { store.navigate(.staffTask(member.id, .role)) }
                                Button("View Rota") { store.navigate(.staffTask(member.id, .rota)) }
                                Button("Supportive Check-in") { store.send(.praise(member.id)) }
                            }
                        }
                }
            }
        }.listStyle(.plain).navigationTitle(recruitment ? "Recruitment" : "Staff")
    }
}
struct StaffDetailView: View {
    @EnvironmentObject private var store: BusinessStore
    let id: UUID
    @State private var wage = ""
    @State private var role: StaffRole = .handler
    @State private var course = "Dog behaviour"
    @State private var leaveDays = 1
    @State private var days: Set<Int> = []
    private var member: StaffMember? { store.state?.staff.first { $0.id == id } }
    var body: some View {
        List {
            if let member {
                ValueRow(title: "Role and experience", value: "\(member.role.title). Age \(member.age). \(member.qualifications.joined(separator: ", ")).")
                ValueRow(title: "Strength", value: member.strength)
                ValueRow(title: "Development", value: member.development)
                ValueRow(title: "Pay", value: "\(money(member.hourlyPay)) per hour. \(member.hoursPerWeek) contracted hours per week.")
                ValueRow(title: "Wellbeing", value: member.wellbeing)
                if member.joinedDay == nil {
                    Act(title: "Employ \(member.name)", icon: "person.badge.plus", action: .hire(id), confirmation: "Employ \(member.name) at \(money(member.hourlyPay)) per hour for \(member.hoursPerWeek) hours weekly, plus employer costs and a forty-five-pound recruitment check?")
                } else if member.employed {
                    Section("Pay and Responsibility") {
                        TextField("Hourly pay in pounds", text: $wage).accessibilityHint("Enter pounds and pence, for example 14.50.")
                        Button("Save Pay", systemImage: "checkmark") {
                            if let pence = MoneyInput.parse(wage) { store.send(.pay(id, pence)) } else { store.errorMessage = "Enter a valid amount in pounds and pence." }
                        }
                        Picker("Role", selection: $role) { ForEach(StaffRole.allCases) { Text($0.title).tag($0) } }
                        Act(title: "Update Role", icon: "person.badge.key", action: .staffRole(id, role))
                        Act(title: "Promote", icon: "star", action: .promote(id), confirmation: "Promote this colleague and increase hourly pay by one pound fifty?")
                    }
                    Section("Development") {
                        Picker("Training course", selection: $course) { ForEach(GameEngine.courses, id: \.self) { Text($0) } }
                        Act(title: "Arrange Training", icon: "graduationcap", action: .train(id, course), confirmation: "Invest one hundred and twenty pounds in this course?")
                        Act(title: "Supportive Check-in", icon: "bubble.left.and.bubble.right", action: .praise(id))
                    }
                    Section("Rota and Leave") {
                        ForEach(0..<7) { day in
                            Toggle(["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][day], isOn: Binding(get: { days.contains(day) }, set: { if $0 { days.insert(day) } else { days.remove(day) } }))
                        }
                        Act(title: "Save Rota", icon: "calendar", action: .rota(id, days.sorted()))
                        Picker("Leave length", selection: $leaveDays) { ForEach(1..<15) { Text("\($0) days").tag($0) } }
                        Act(title: "Approve Leave", icon: "calendar.badge.checkmark", action: .leave(id, leaveDays), confirmation: "Approve this leave and review care cover for the affected bookings?")
                        Act(title: "End Employment", icon: "person.badge.minus", action: .dismiss(id), confirmation: "End employment and settle one week's agreed notice pay? Review care capacity afterwards.", destructive: true)
                    }
                }
                Section("Career History") { ForEach(member.history.reversed()) { ValueRow(title: "Day \($0.day + 1)", value: $0.text) } }
            }
        }.listStyle(.plain).navigationTitle(member?.name ?? "Staff Profile")
            .onAppear {
                if let member { wage = MoneyInput.edit(member.hourlyPay); role = member.role; days = Set(member.workingWeekdays) }
            }
    }
}
enum MoneyInput {
    static func parse(_ text: String) -> Pence? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.range(of: "^[0-9]{1,7}(\\.[0-9]{1,2})?$", options: .regularExpression) != nil,
              let decimal = Decimal(string: clean, locale: Locale(identifier: "en_GB")) else { return nil }
        return NSDecimalNumber(decimal: decimal * 100).intValue
    }
    static func edit(_ pence: Pence) -> String { String(format: "%.2f", Double(pence) / 100) }
}
