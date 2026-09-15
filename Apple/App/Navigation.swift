import SwiftUI
import PawBossCore

struct RootView: View {
    @EnvironmentObject private var store: BusinessStore
    @State private var watchSection: Destination = .today
    @State private var menu = false
    var body: some View {
        NavigationStack(path: $store.path) {
            Group {
                if store.isWatch {
                    Group {
                        if store.state != nil { DestinationView(destination: watchSection) }
                        else { WaitingView() }
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Menu", systemImage: "line.3.horizontal") { menu = true }
                                .accessibilityLabel("Menu")
                                .accessibilityIdentifier("watchMenu")
                                .accessibilityHint("Choose a business section.")
                        }
                    }
                } else if store.inBusiness && store.state != nil {
                    TabView(selection: $store.tab) {
                        TodayView().tabItem { Label("Today", systemImage: "sun.max.fill") }.tag(0)
                        OfficeView().tabItem { Label("Office", systemImage: "building.2.fill") }.tag(1)
                        DogsView().tabItem { Label("Dogs", systemImage: "dog.fill") }.tag(2)
                        PremisesView().tabItem { Label("Premises", systemImage: "square.grid.3x3.fill") }.tag(3)
                        MoreView().tabItem { Label("More", systemImage: "ellipsis") }.tag(4)
                    }
                } else { WelcomeView() }
            }
            .navigationDestination(for: Destination.self) { DestinationView(destination: $0) }
            .sheet(isPresented: $menu) {
                NavigationStack {
                    List {
                        ForEach(watchSections, id: \.0) { section in
                            Button(section.1, systemImage: section.2) { watchSection = section.0; store.path = []; menu = false }
                        }
                    }.navigationTitle("Menu")
                }
            }
        }
    }
    private var watchSections: [(Destination, String, String)] {
        [(.today, "Today", "sun.max"), (.office, "Office", "building.2"), (.dogs, "Dogs", "dog"), (.customers, "Customers", "person.2"), (.staff, "Staff", "person.badge.key"), (.finance, "Finance", "sterlingsign.circle"), (.alerts, "Alerts", "bell"), (.more, "More", "ellipsis")]
    }
}
struct DestinationView: View {
    let destination: Destination
    var body: some View {
        switch destination {
        case .today: TodayView()
        case .office: OfficeView()
        case .dogs: DogsView()
        case .premises: PremisesView()
        case .more: MoreView()
        case .customers: CustomersView()
        case .staff: StaffListView(recruitment: false)
        case .recruitment: StaffListView(recruitment: true)
        case .finance: FinanceView()
        case .pricing: PricingView()
        case .loans: LoansView()
        case .business: BusinessView()
        case .readiness: ReadinessView()
        case .enquiries: EnquiriesView()
        case .inbox: InboxView(onlyAlerts: false)
        case .alerts: InboxView(onlyAlerts: true)
        case .bookings: BookingsView()
        case .reports: ReportsView()
        case .history: HistoryView()
        case .community: CommunityView()
        case .adviser: AdviserView()
        case .settings: SettingsView()
        case .help: HelpView()
        case .about: AboutView()
        case .dog(let id): DogDetailView(id: id)
        case .customer(let id): CustomerDetailView(id: id)
        case .employee(let id): StaffDetailView(id: id)
        case .enquiry(let id): EnquiryDetailView(id: id)
        case .message(let id): MessageDetailView(id: id)
        case .booking(let id): BookingDetailView(id: id)
        case .area(let id): AreaView(id: id)
        case .dogTask(let id, let task): DogTaskView(id: id, task: task)
        case .staffTask(let id, let task): StaffTaskView(id: id, task: task)
        }
    }
}
struct NavRow: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let title: String
    let icon: String
    let destination: Destination
    var detail: String = ""
    var body: some View {
        NavigationLink(value: destination) {
            HStack(alignment: .top, spacing: 12) {
                if !textSize.isAccessibilitySize {
                    Image(systemName: icon).font(.body).foregroundStyle(Color.pawGreen).frame(width: 24).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    if !detail.isEmpty { Text(detail).font(.subheadline).foregroundStyle(.primary) }
                }
            }.padding(.vertical, 5)
        }.accessibilityLabel(detail.isEmpty ? title : "\(title). \(detail)")
    }
}
struct ValueRow: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline).foregroundStyle(Color.primary)
            Text(value).font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, 3).accessibilityElement(children: .ignore).accessibilityLabel("\(title). \(value)")
            .accessibilityAddTraits(.isStaticText)
    }
}
struct Act: View {
    @EnvironmentObject private var store: BusinessStore
    let title: String
    let icon: String
    let action: GameAction
    var confirmation: String? = nil
    var destructive = false
    @State private var showingConfirmation = false
    var body: some View {
        Button(role: destructive ? .destructive : nil) {
            if confirmation != nil { showingConfirmation = true } else { store.send(action) }
        } label: { Label(title, systemImage: icon).fixedSize(horizontal: false, vertical: true) }
        .confirmationDialog(confirmation ?? title, isPresented: $showingConfirmation, titleVisibility: .visible) {
            Button(title, role: destructive ? .destructive : nil) { store.send(action) }
            Button("Cancel", role: .cancel) {}
        }
    }
}
struct WaitingView: View {
    @EnvironmentObject private var store: BusinessStore
    var body: some View {
        List {
            Text("PawBoss").font(.title2.bold()).accessibilityAddTraits(.isHeader)
            Text("Waiting for your business from iPhone.")
            Button("Refresh Sync", systemImage: "arrow.triangle.2.circlepath") { store.refreshSync() }
            Text(store.syncStatus).font(.footnote)
            NavRow(title: "Help", icon: "questionmark.circle", destination: .help)
        }
    }
}
struct WelcomeView: View {
    @EnvironmentObject private var store: BusinessStore
    @State private var newBusiness = false
    @State private var confirmNew = false
    @AccessibilityFocusState private var titleFocused: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PawBoss").font(.largeTitle.bold())
                    Text("A Dog Day Care Simulation").font(.headline)
                }.accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader).accessibilityFocused($titleFocused)
                    .padding(.horizontal, 24)
                Image("Welcome").resizable().scaledToFit().accessibilityHidden(true)
                VStack(spacing: 14) {
                    Button("New Business", systemImage: "plus.circle.fill") {
                        if store.state != nil { confirmNew = true } else { newBusiness = true }
                    }.buttonStyle(.borderedProminent).disabled(store.recoveryNeeded)
                    Button("Continue", systemImage: "arrow.right.circle") { store.tab = 1; store.inBusiness = true }
                        .buttonStyle(.bordered).disabled(store.state == nil || store.recoveryNeeded)
                    if store.recoveryNeeded { Button("Recover Previous Backup", systemImage: "arrow.counterclockwise") { store.recover() } }
                    NavigationLink("How to Play", value: Destination.help)
                    NavigationLink("Settings", value: Destination.settings)
                }.frame(maxWidth: .infinity).controlSize(.large).padding(.horizontal, 24)
            }.padding(.vertical, 20)
        }
        .task { titleFocused = true }
        .sheet(isPresented: $newBusiness) { NewBusinessView() }
        .confirmationDialog("Start a new business? Your current progress will become the previous local backup.", isPresented: $confirmNew, titleVisibility: .visible) {
            Button("Start New Business", role: .destructive) { newBusiness = true }
            Button("Cancel", role: .cancel) {}
        }
    }
}
struct NewBusinessView: View {
    @EnvironmentObject private var store: BusinessStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var owner = ""
    @State private var title = "Owner"
    var body: some View {
        NavigationStack {
            Form {
                TextField("Business name", text: $name).accessibilityIdentifier("businessName")
                TextField("Your name", text: $owner).accessibilityIdentifier("ownerName")
                Picker("Your job title", selection: $title) { ForEach(["Owner", "Founder", "Owner-operator", "Director"], id: \.self) { Text($0) } }
                ValueRow(title: "Starting savings", value: money(store.catalog?.economy.initialCash ?? 750000))
                ValueRow(title: "Starting loan", value: "None")
                Button("Create Business", systemImage: "checkmark.circle") {
                    store.startBusiness(name: name, owner: owner, title: title)
                    if store.inBusiness { dismiss() }
                }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || owner.trimmingCharacters(in: .whitespaces).isEmpty)
            }.navigationTitle("New Business")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
