import SwiftUI
import PawBossCore

enum DogTask: String, Hashable {
    case observation = "Add Observation", carePlan = "Care Plan", medication = "Medication", vaccination = "Vaccination Record"
}
struct DogTaskView: View {
    @EnvironmentObject private var store: BusinessStore
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    let task: DogTask
    @State private var text = ""
    @AccessibilityFocusState private var focus: Bool
    private var dog: Dog? { store.state?.dogs.first { $0.id == id } }
    var body: some View {
        Form {
            if let dog, let state = store.state {
                Text(dog.name).font(.headline).accessibilityAddTraits(.isHeader).accessibilityFocused($focus)
                if task == .medication {
                    if dog.medications.isEmpty { Text("No medication recorded.") }
                    ForEach(dog.medications) { med in
                        ValueRow(title: med.name, value: "\(med.instructions) \(med.givenDays.contains(state.day) ? "Recorded today." : "Not recorded today.")")
                        if dog.present && med.dueDay <= state.day && !med.givenDays.contains(state.day) {
                            Act(title: "Record \(med.name) Given", icon: "pills", action: .medication(id, med.id), confirmation: "Confirm the care plan has been followed and this medication was given?")
                        }
                    }
                    if !dog.present { Text("Medication can be recorded after check-in.") }
                } else {
                    TextField(task.rawValue, text: $text, axis: .vertical).lineLimit(3...8)
                    if task == .observation {
                        ForEach(["Settled after a quiet introduction.", "Enjoyed enrichment and rested well.", "Needed extra reassurance.", "Owner informed of a care concern."], id: \.self) { note in Button(note) { text = note } }
                    }
                    Button("Save", systemImage: "checkmark") {
                        let action: GameAction = task == .carePlan ? .carePlan(id, text) : task == .vaccination ? .vaccination(id, stateDay: state.day + 365, note: text) : .observation(id, text)
                        if store.send(action) { dismiss() }
                    }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else { Text("This dog is no longer in the current business.") }
        }.navigationTitle(task.rawValue)
            .onAppear { if task == .carePlan { text = dog?.carePlan ?? "" }; focus = true }
    }
}
enum StaffTask: String, Hashable { case pay = "Review Pay", training = "Training", role = "Change Role", rota = "Rota" }
struct StaffTaskView: View {
    @EnvironmentObject private var store: BusinessStore
    let id: UUID
    let task: StaffTask
    @State private var wage = ""
    @State private var role: StaffRole = .handler
    @State private var course = "Dog behaviour"
    @State private var days: Set<Int> = []
    @AccessibilityFocusState private var focus: Bool
    private var member: StaffMember? { store.state?.staff.first { $0.id == id } }
    var body: some View {
        Form {
            if let member, member.employed {
                Text(member.name).font(.headline).accessibilityAddTraits(.isHeader).accessibilityFocused($focus)
                switch task {
                case .pay:
                    ValueRow(title: "Current pay", value: "\(money(member.hourlyPay)) per hour; \(member.hoursPerWeek) hours weekly.")
                    TextField("Hourly pay in pounds", text: $wage)
                    Button("Save Pay", systemImage: "checkmark") {
                        guard let pence = MoneyInput.parse(wage) else { store.errorMessage = "Enter pounds and pence, for example 14.50."; return }
                        store.send(.pay(id, pence))
                    }
                case .training:
                    ValueRow(title: "Development", value: member.development)
                    Picker("Training course", selection: $course) { ForEach(GameEngine.courses, id: \.self) { Text($0) } }
                    Act(title: "Arrange Training", icon: "graduationcap", action: .train(id, course), confirmation: "Invest \(money(store.engine?.trainingPrice ?? 12000)) in this course, including any active trainer agreement discount?")
                case .role:
                    Picker("Role", selection: $role) { ForEach(StaffRole.allCases) { Text($0.title).tag($0) } }
                    Act(title: "Update Role", icon: "person.badge.key", action: .staffRole(id, role))
                    Act(title: "Promote", icon: "star", action: .promote(id), confirmation: "Promote this colleague and increase hourly pay by one pound fifty?")
                case .rota:
                    if let until = member.absentUntilDay, until >= (store.state?.day ?? 0) { ValueRow(title: "Absence", value: "Away through business day \(until + 1)") }
                    ForEach(0..<7) { day in
                        Toggle(["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][day], isOn: Binding(get: { days.contains(day) }, set: { if $0 { days.insert(day) } else { days.remove(day) } }))
                    }
                    Act(title: "Save Rota", icon: "calendar", action: .rota(id, days.sorted()))
                }
            } else { Text("This colleague is not currently employed.") }
        }.navigationTitle(task.rawValue).onAppear {
            if let member { wage = MoneyInput.edit(member.hourlyPay); role = member.role; days = Set(member.workingWeekdays) }
            focus = true
        }
    }
}
