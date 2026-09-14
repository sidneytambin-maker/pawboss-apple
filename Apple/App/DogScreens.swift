import SwiftUI
import PawBossCore

struct DogsView: View {
    @EnvironmentObject private var store: BusinessStore
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var search = ""
    @State private var filter = "All Dogs"
    var body: some View {
        List {
            Picker("Show", selection: $filter) { ForEach(["All Dogs", "Dogs Today", "Welfare", "Medication"], id: \.self) { Text($0) } }
            if let state = store.state {
                let dogs = state.dogs.filter { dog in
                    (search.isEmpty || dog.name.localizedCaseInsensitiveContains(search) || dog.breed.localizedCaseInsensitiveContains(search)) &&
                    (filter == "All Dogs" || filter == "Dogs Today" && state.todayBookings.contains { $0.dogID == dog.id } || filter == "Welfare" && dog.welfare < 65 || filter == "Medication" && !dog.medications.isEmpty)
                }.sorted { $0.name < $1.name }
                if dogs.isEmpty { Text(state.dogs.isEmpty ? "Your first dog will arrive through an accepted enquiry." : "No dogs match this view.").foregroundStyle(.secondary) }
                ForEach(dogs) { dog in
                    NavigationLink(value: Destination.dog(dog.id)) {
                        HStack(alignment: .top, spacing: 12) {
                            if !textSize.isAccessibilitySize {
                                Image(systemName: "dog.fill").font(.title2).foregroundStyle(Color.pawGreen).frame(width: 34).accessibilityHidden(true)
                            }
                            VStack(alignment: .leading, spacing: 5) {
                                Text(dog.name).font(.headline)
                                Text(dog.breed).font(.subheadline).foregroundStyle(.primary)
                                Label(dog.wellbeing, systemImage: dog.welfare < 60 ? "exclamationmark.circle" : "heart.fill").font(.caption.weight(.medium)).foregroundStyle(dog.welfare < 60 ? Color.pawCoral : Color.pawGreen)
                            }
                        }.padding(.vertical, 7)
                    }.accessibilityElement(children: .ignore).accessibilityLabel(dog.summary)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { store.navigate(.dog(dog.id)) }
                        .accessibilityIdentifier("dog-row-\(dog.id.uuidString)")
                        .accessibilityActions {
                            if dog.present {
                                Button("Check Out") { store.send(.checkOut(dog.id)) }
                                Button("Record Care Routine") { store.send(.care(dog.id)) }
                            } else if state.todayBookings.contains(where: { $0.dogID == dog.id && $0.status == .expected }) {
                                Button("Check In") { store.send(.checkIn(dog.id)) }
                            }
                            Button("Add Observation") { store.navigate(.dogTask(dog.id, .observation)) }
                            Button("View Care Plan") { store.navigate(.dogTask(dog.id, .carePlan)) }
                            if !dog.medications.isEmpty { Button("Record Medication") { store.navigate(.dogTask(dog.id, .medication)) } }
                            if let booking = state.todayBookings.first(where: { $0.dogID == dog.id }) {
                                Button("View Booking") { store.navigate(.booking(booking.id)) }
                            }
                            Button("View Owner") { store.navigate(.customer(dog.ownerID)) }
                            Button("Contact Owner") { store.send(.contactOwner(dog.id)) }
                        }
                }
                NavRow(title: "New Dog Enquiries", icon: "envelope.open", destination: .enquiries)
            }
        }.listStyle(.plain).searchable(text: $search, prompt: "Dog name or breed").navigationTitle("Dogs")
    }
}
struct DogDetailView: View {
    @EnvironmentObject private var store: BusinessStore
    let id: UUID
    @State private var edit: String?
    @State private var booking = false
    private var dog: Dog? { store.state?.dogs.first { $0.id == id } }
    var body: some View {
        List {
            if let dog, let state = store.state {
                Section {
                    ValueRow(title: "Profile", value: "\(dog.breed). \(dog.ageMonths / 12) years, \(dog.ageMonths % 12) months. \(dog.sex). \(dog.appearance).")
                    ValueRow(title: "Today", value: dog.present ? "Checked in. \(dog.wellbeing)." : dog.wellbeing)
                    if dog.present {
                        Act(title: "Record Care Routine", icon: "heart.text.square", action: .care(id))
                        Act(title: "Check Out", icon: "door.left.hand.open", action: .checkOut(id))
                    } else if state.todayBookings.contains(where: { $0.dogID == id && $0.status == .expected }) {
                        Act(title: "Check In", icon: "checkmark.circle", action: .checkIn(id))
                    }
                    Button("Add Observation", systemImage: "square.and.pencil") { edit = "Observation" }
                }
                Section("Individual Care") {
                    ValueRow(title: "Personality", value: dog.personality)
                    ValueRow(title: "Favourite activity", value: dog.favouriteActivity)
                    ValueRow(title: "Routine", value: dog.carePlan)
                    Button("Edit Care Plan", systemImage: "pencil") { edit = "Care Plan" }
                    ValueRow(title: "Diet", value: dog.diet)
                    ValueRow(title: "Health", value: dog.health)
                    ValueRow(title: "Vaccination review", value: "Business day \(dog.vaccinationDueDay + 1)")
                    Button("Record Vaccination Update", systemImage: "checkmark.shield") { edit = "Vaccination" }
                }
                if !dog.medications.isEmpty {
                    Section("Medication") {
                        ForEach(dog.medications) { med in
                            ValueRow(title: med.name, value: "\(med.instructions) \(med.givenDays.contains(state.day) ? "Recorded today." : "Not yet recorded today.")")
                            if dog.present && med.dueDay <= state.day && !med.givenDays.contains(state.day) {
                                Act(title: "Record Medication Given", icon: "pills", action: .medication(id, med.id), confirmation: "Record the scheduled medication as given according to this dog's care plan?")
                            }
                        }
                    }
                }
                Section("Relationships") {
                    NavRow(title: state.customers.first { $0.id == dog.ownerID }?.name ?? "Owner", icon: "person.crop.circle", destination: .customer(dog.ownerID), detail: "Owner")
                    Act(title: "Send Owner Care Update", icon: "paperplane", action: .contactOwner(id))
                    ForEach(state.dogs.filter { dog.friends.contains($0.id) }) { friend in NavRow(title: friend.name, icon: "heart", destination: .dog(friend.id), detail: "Familiar friend") }
                    ForEach(state.staff.filter { dog.trustedStaff.contains($0.id) }) { staff in NavRow(title: staff.name, icon: "person.badge.shield.checkmark", destination: .employee(staff.id), detail: "Trusted staff member") }
                }
                Section("Bookings and History") {
                    Button("New Booking", systemImage: "calendar.badge.plus") { booking = true }
                    ForEach(state.bookings.filter { $0.dogID == id && $0.day >= state.day }) { booking in BookingRow(booking: booking) }
                    ValueRow(title: "Attendance", value: "\(dog.attendedDays.count) completed care days")
                    ForEach(dog.observations.suffix(30).reversed()) { note in ValueRow(title: "Day \(note.day + 1)", value: note.text) }
                }
            } else { Text("This dog is no longer in the current business.") }
        }.listStyle(.plain).navigationTitle(dog?.name ?? "Dog")
            .sheet(isPresented: Binding(get: { edit != nil }, set: { if !$0 { edit = nil } })) {
                if let edit, let dog {
                    NoteEditor(title: edit, initial: edit == "Care Plan" ? dog.carePlan : "", suggestions: edit == "Observation" ? ["Settled after a quiet introduction.", "Enjoyed enrichment and rested well.", "Needed extra reassurance.", "Owner informed of a care concern."] : []) { text in
                        if edit == "Vaccination" { return store.send(.vaccination(id, stateDay: (store.state?.day ?? 0) + 365, note: text)) }
                        return store.send(edit == "Care Plan" ? .carePlan(id, text) : .observation(id, text))
                    }
                }
            }
            .sheet(isPresented: $booking) { BookingEditor(dogID: id) }
    }
}
struct NoteEditor: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let initial: String
    var suggestions: [String] = []
    let save: (String) -> Bool
    @State private var text = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField(title, text: $text, axis: .vertical).lineLimit(3...8)
                ForEach(suggestions, id: \.self) { suggestion in Button(suggestion) { text = suggestion } }
                Button("Save", systemImage: "checkmark") { if save(text) { dismiss() } }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.navigationTitle(title).onAppear { text = initial }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
struct EnquiriesView: View {
    @EnvironmentObject private var store: BusinessStore
    @State private var showHandled = false
    var body: some View {
        List {
            Toggle("Include handled enquiries", isOn: $showHandled)
            if let state = store.state {
                let values = state.enquiries.filter { showHandled || $0.isActionable || $0.status == .informationRequested }
                if values.isEmpty { Text("No new enquiries. A local campaign or community partnership can introduce your business to owners.") }
                ForEach(values) { enquiry in
                    NavRow(title: enquiry.dog.name, icon: "dog", destination: .enquiry(enquiry.id), detail: "\(enquiry.customer.name). \(enquiry.service.title). \(enquiry.status.rawValue).")
                        .accessibilityActions {
                            if enquiry.isActionable {
                                Button("Send Quote") { store.send(.decideEnquiry(enquiry.id, "quote")) }
                                Button("Request Information") { store.send(.decideEnquiry(enquiry.id, "information")) }
                            }
                        }
                }
                NavRow(title: "Marketing", icon: "megaphone", destination: .business)
            }
        }.listStyle(.plain).navigationTitle("Enquiries")
    }
}
struct EnquiryDetailView: View {
    @EnvironmentObject private var store: BusinessStore
    let id: UUID
    private var enquiry: Enquiry? { store.state?.enquiries.first { $0.id == id } }
    var body: some View {
        List {
            if let enquiry {
                ValueRow(title: "Owner", value: enquiry.customer.name)
                ValueRow(title: "Dog", value: "\(enquiry.dog.name). \(enquiry.dog.breed). \(enquiry.dog.ageMonths / 12) years old.")
                ValueRow(title: "Requested care", value: "\(enquiry.service.title), business day \(enquiry.requestedDay + 1)")
                ValueRow(title: "Behaviour", value: enquiry.dog.personality)
                ValueRow(title: "Health and requirements", value: enquiry.requirements)
                ValueRow(title: "Source", value: enquiry.source)
                ValueRow(title: "Status", value: enquiry.status.rawValue)
                if let quote = enquiry.quote { ValueRow(title: "Agreed quote", value: money(quote)) }
                if enquiry.isActionable {
                    Act(title: "Accept Enquiry", icon: "checkmark.circle", action: .decideEnquiry(id, "accept"), confirmation: "Accept this customer and create their first booking at the quoted or current price?")
                    Act(title: "Send Quote", icon: "sterlingsign.circle", action: .decideEnquiry(id, "quote"))
                    Act(title: "Request More Information", icon: "questionmark.bubble", action: .decideEnquiry(id, "information"))
                    Act(title: "Add to Waiting List", icon: "clock", action: .decideEnquiry(id, "wait"))
                    Act(title: "Decline Politely", icon: "xmark.circle", action: .decideEnquiry(id, "decline"), confirmation: "Decline this enquiry? It will remain in your handled history.", destructive: true)
                }
            } else { Text("This enquiry is no longer available.") }
        }.listStyle(.plain).navigationTitle("Enquiry")
    }
}
struct BookingRow: View {
    @EnvironmentObject private var store: BusinessStore
    let booking: Booking
    var body: some View {
        NavRow(title: store.state?.dogs.first { $0.id == booking.dogID }?.name ?? "Dog booking", icon: "calendar", destination: .booking(booking.id), detail: "Day \(booking.day + 1). \(booking.service.title). \(booking.status.rawValue).")
    }
}
struct BookingsView: View {
    @EnvironmentObject private var store: BusinessStore
    @State private var history = false
    var body: some View {
        List {
            Toggle("Include past bookings", isOn: $history)
            if let state = store.state {
                let bookings = state.bookings.filter { history || $0.day >= state.day }.sorted { $0.day < $1.day }
                if bookings.isEmpty { Text("No bookings in this view. Open a dog's profile to arrange care.") }
                ForEach(bookings) { BookingRow(booking: $0) }
            }
        }.listStyle(.plain).navigationTitle("Bookings")
    }
}
struct BookingDetailView: View {
    @EnvironmentObject private var store: BusinessStore
    let id: UUID
    var body: some View {
        List {
            if let state = store.state, let b = state.bookings.first(where: { $0.id == id }) {
                NavRow(title: state.dogs.first { $0.id == b.dogID }?.name ?? "Dog", icon: "dog", destination: .dog(b.dogID))
                ValueRow(title: "Care", value: b.service.title)
                ValueRow(title: "Business day", value: "\(b.day + 1)")
                ValueRow(title: "Agreed price", value: money(b.price))
                ValueRow(title: "Status", value: b.status.rawValue)
                ValueRow(title: "Payment", value: b.paid ? "Paid. Refunded: \(money(b.refunded))." : "Due at collection")
                if b.day == state.day && b.status == .expected { Act(title: "Check In", icon: "checkmark.circle", action: .checkIn(b.dogID)) }
                if b.status == .checkedIn { Act(title: "Check Out", icon: "door.left.hand.open", action: .checkOut(b.dogID)) }
                if b.status == .expected { Act(title: "Cancel Booking", icon: "calendar.badge.minus", action: .cancelBooking(id), confirmation: "Cancel this booking without a fee?", destructive: true) }
            }
        }.listStyle(.plain).navigationTitle("Booking")
    }
}
struct BookingEditor: View {
    @EnvironmentObject private var store: BusinessStore
    @Environment(\.dismiss) private var dismiss
    let dogID: UUID
    @State private var offset = 0
    @State private var service: Service = .dayCare
    var body: some View {
        NavigationStack {
            Form {
                Picker("Service", selection: $service) { ForEach(Service.allCases) { Text($0.title).tag($0) } }
                Picker("Business day", selection: $offset) { ForEach(0..<91) { Text("Day \((store.state?.day ?? 0) + $0 + 1)").tag($0) } }
                ValueRow(title: "Price per care day", value: money(store.state?.prices[service.rawValue] ?? 0))
                if let blocker = store.state?.serviceBlocker(service) { Text(blocker).foregroundStyle(.secondary) }
                Button("Confirm Booking", systemImage: "calendar.badge.checkmark") {
                    if store.send(.book(dogID, service, (store.state?.day ?? 0) + offset)) { dismiss() }
                }
            }.navigationTitle("New Booking").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
