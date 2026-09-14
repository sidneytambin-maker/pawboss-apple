import SwiftUI
import PawBossCore

struct TodayView: View {
    @EnvironmentObject private var store: BusinessStore
    var body: some View {
        List {
            if let state = store.state {
                VStack(alignment: .leading, spacing: 8) {
                    Text(state.name).font(.title2.bold())
                    Text(state.dateText).font(.headline)
                    Text("Week \(state.week) · \(state.ageText)").foregroundStyle(.secondary)
                    Label(state.isOpen ? "Open for care" : "Site closed", systemImage: state.isOpen ? "door.left.hand.open" : "door.left.hand.closed")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(state.isOpen ? Color.pawGreen : Color.secondary)
                }.padding(.vertical, 10).accessibilityElement(children: .combine)
                Section {
                    NavRow(title: "Dogs attending", icon: "dog.fill", destination: .dogs, detail: "\(state.dogs.filter(\.present).count) checked in; \(state.todayBookings.count) booked")
                    NavRow(title: "Arrivals and collections", icon: "person.and.background.dotted", destination: .bookings, detail: "\(state.todayBookings.filter { $0.status == .expected }.count) expected; \(state.dogs.filter(\.present).count) to collect")
                    NavRow(title: "Care team", icon: "person.2.fill", destination: .staff, detail: "\(state.staff.filter { $0.onDuty(day: state.day) }.count) employees on duty\(state.ownerOnDuty ? ", plus you" : "")")
                    ForEach(state.dogs.filter { $0.present && ($0.welfare < 60 || $0.medications.contains { $0.dueDay <= state.day && !$0.givenDays.contains(state.day) }) }) { dog in
                        NavRow(title: dog.name, icon: "heart.text.square", destination: .dog(dog.id), detail: "Care record needs attention")
                    }
                } header: {
                    Text("Today's Care").foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading).background(.background)
                        .accessibilityIdentifier("todayCareHeading")
                }
                Section {
                    NavRow(title: "Cash available", icon: "sterlingsign.circle.fill", destination: .finance, detail: money(state.cash))
                    ValueRow(title: "Booked care value today", value: money(state.expectedRevenue))
                    NavRow(title: "Enquiries", icon: "envelope.badge", destination: .enquiries, detail: "\(state.pendingEnquiries.count) waiting")
                    NavRow(title: "Messages", icon: "tray.fill", destination: .inbox, detail: "\(state.messages.filter { !$0.read && !$0.archived }.count) unread")
                    ValueRow(title: "Weather", value: state.weather)
                    if !state.licenceValid { NavRow(title: "Opening readiness", icon: "checklist", destination: .readiness, detail: "\(state.readiness().filter(\.complete).count) of \(state.readiness().count) ready") }
                    if state.areas.flatMap(\.items).contains(where: { $0.condition < 60 }) { NavRow(title: "Maintenance due", icon: "wrench.adjustable", destination: .premises) }
                    if let inspection = state.licence.inspectionDay { NavRow(title: "Council inspection", icon: "checkmark.seal", destination: .readiness, detail: "In \(inspection - state.day) game days") }
                } header: {
                    Text("Business Pulse").foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading).background(.background)
                        .accessibilityIdentifier("businessPulseHeading")
                }
                Section {
                    if state.isOpen { Act(title: "Close Site", icon: "door.left.hand.closed", action: .close) }
                    else { Act(title: "Open for Care", icon: "door.left.hand.open", action: .open) }
                    Act(title: "Complete Day", icon: "sun.horizon", action: .nextDay,
                        confirmation: "Complete today's scheduled care and collections, pay due commitments, then move to tomorrow? Unrecorded medication remains a missed-care record.")
                }
            }
        }.listStyle(.plain).navigationTitle("Today")
    }
}
struct OfficeView: View {
    @EnvironmentObject private var store: BusinessStore
    var body: some View {
        List {
            Section("Communication") {
                NavRow(title: "Inbox", icon: "tray.full", destination: .inbox)
                NavRow(title: "Enquiries and Quotes", icon: "envelope.open", destination: .enquiries)
            }
            Section("People") {
                NavRow(title: "Customers and Relationships", icon: "person.2", destination: .customers)
                NavRow(title: "Bookings", icon: "calendar", destination: .bookings)
                NavRow(title: "Staff and Recruitment", icon: "person.badge.key", destination: .staff)
            }
            Section("Business") {
                NavRow(title: "Finance", icon: "sterlingsign.circle", destination: .finance)
                NavRow(title: "Licensing, Strategy and Marketing", icon: "briefcase", destination: .business)
                NavRow(title: "Reports", icon: "chart.xyaxis.line", destination: .reports)
                if store.preferences.adviser { NavRow(title: "Business Adviser", icon: "lightbulb", destination: .adviser) }
            }
        }.listStyle(.plain).navigationTitle("Office")
    }
}
struct MoreView: View {
    @EnvironmentObject private var store: BusinessStore
    var body: some View {
        List {
            NavRow(title: "Community and Market", icon: "building.2.crop.circle", destination: .community)
            NavRow(title: "Reports", icon: "chart.bar", destination: .reports)
            NavRow(title: "History and Milestones", icon: "clock.arrow.circlepath", destination: .history)
            NavRow(title: "Business Adviser", icon: "lightbulb", destination: .adviser)
            if store.isWatch { NavRow(title: "Premises", icon: "square.grid.3x3", destination: .premises) }
            NavRow(title: "How to Play", icon: "questionmark.circle", destination: .help)
            NavRow(title: "Settings and Sync", icon: "gearshape", destination: .settings)
            NavRow(title: "About PawBoss", icon: "info.circle", destination: .about)
            if !store.isWatch { Button("Main Menu", systemImage: "house") { store.inBusiness = false; store.path = [] } }
        }.listStyle(.plain).navigationTitle("More")
    }
}
struct ReadinessView: View {
    @EnvironmentObject private var store: BusinessStore
    var body: some View {
        List {
            if let state = store.state {
                ForEach(state.readiness()) { check in
                    VStack(alignment: .leading, spacing: 6) {
                        Label(check.title, systemImage: check.complete ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(check.complete ? Color.pawGreen : Color.primary)
                        if !check.complete { Text(check.help).font(.subheadline).foregroundStyle(.secondary) }
                    }.accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(check.title). \(check.complete ? "Complete" : "Not complete")")
                        .accessibilityHint(check.complete ? "" : check.help)
                }
                NavRow(title: "Business Setup", icon: "briefcase", destination: .business)
                NavRow(title: "Premises", icon: "square.grid.3x3", destination: .premises)
                Section("Last Inspection") {
                    Text(state.licence.result)
                    ForEach(state.licence.findings, id: \.self) { Text($0) }
                }
            }
        }.listStyle(.plain).navigationTitle("Readiness")
    }
}
