import SwiftUI
import PawBossCore

struct DailyPrioritiesView: View {
    @EnvironmentObject private var store: BusinessStore
    @State private var selection = DailyPrioritySlots([])
    var body: some View {
        Form {
            ForEach(0..<3, id:\.self) { index in
                Section {
                    Picker("Daily priority \(index + 1)", selection: Binding(get: { selection.slots[index] }, set: { value in
                        selection.select(value, at:index)
                        store.announce("Daily priority \(index + 1): \(value.isEmpty ? "none" : value). \(selection.selected.map { $0.capitalized }.joined(separator: ", ")).")
                    })) {
                        Text("None").tag("")
                        ForEach(DailyPrioritySlots.choices, id:\.self) { Text($0.capitalized).tag($0) }
                    }.accessibilityIdentifier("dailyPriority\(index + 1)")
                        .accessibilityHint("Choosing a priority already in another slot swaps the two slots.")
                    Text(DailyPrioritySlots.explanation(selection.slots[index])).font(.subheadline)
                }
            }
            Button("Save Daily Priorities", systemImage:"checkmark") { store.send(.priorities(selection.selected)) }
                .accessibilityIdentifier("saveDailyPriorities")
                .accessibilityHint("Applies these priorities to daily routines. Replacing a priority changes the support provided by those routines.")
            if !store.status.isEmpty { Text(store.status).font(.footnote) }
        }.navigationTitle("Daily Priorities").onAppear { selection = DailyPrioritySlots(store.state?.priorities ?? []) }
    }
}

struct OpeningGuideView: View {
    @EnvironmentObject private var store: BusinessStore
    var body: some View {
        List {
            if let state = store.state, let catalog = store.catalog {
                Text("Welcome to \(state.name)").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Image("Welcome").resizable().scaledToFit().frame(maxHeight:store.isWatch ? 90 : 160).accessibilityHidden(true)
                let stages = state.openingStages
                let completed = stages.filter(\.complete).count
                ProgressView(value:Double(completed), total:Double(stages.count))
                    .accessibilityLabel("Your first opening").accessibilityValue("\(completed) of \(stages.count) stages complete")
                ValueRow(title:"Your opening budget", value:"\(money(state.cash)) available. Borrowing is optional; start with essentials and keep a reserve.")
                if let stage = stages.first(where: { !$0.complete }) {
                    Section(stage.title) {
                        Text(stage.detail)
                        switch stage.id {
                        case "registration":
                            Act(title:"Register Business", icon:"doc.badge.plus", action:.register, confirmation:"Register \(state.name) for \(money(catalog.economy.registration))?")
                        case "space":
                            if !state.hasRoom(.multipurpose) && !state.hasRoom(.puppy) {
                                Act(title:"Use Room Two for Play and Rest", icon:"house", action:.configureRoom("room2",.multipurpose), confirmation:"Give room two a play and rest purpose? You can customise both starter rooms.")
                            }
                            if let room = state.areas.first(where: { [.multipurpose,.puppy].contains($0.purpose) }) {
                                Act(title:"Fit Washable Floor in \(room.name)", icon:"square.grid.3x3", action:.floorRoom(room.id), confirmation:"Fit missing floor squares at \(money((try? catalog.item("floor").price) ?? 1200)) each? Existing furniture stays in place.")
                                NavRow(title:"Customise \(room.name)", icon:"square.grid.3x3", destination:.area(room.id))
                            }
                            NavRow(title:"Choose a Different Room Layout", icon:"house", destination:.premises)
                        case "boundary":
                            if let grounds = state.areas.first(where: \.isOutdoor) {
                                let missing = state.boundaryCells(in: grounds).filter { r, c in !grounds.items.contains { $0.row == r && $0.column == c && ["fence","gate"].contains($0.definitionID) } }.count
                                if missing > 0 {
                                    let cost = Pence(missing) * ((try? catalog.item("fence").price) ?? 2500)
                                    Act(title:"Build Missing Fence Panels", icon:"rectangle.dashed", action:.buildBoundary, confirmation:"Build \(missing) missing boundary panels for \(money(cost))? Existing gates are kept.")
                                }
                            }
                            NavRow(title:"Place the Gate in Your Grounds", icon:"door.left.hand.closed", destination:.area("outdoor"), detail:"Choose an edge square, then Add Item and Gate. A replaced fence panel is credited.")
                            if state.has("gate") { NavRow(title:"Check Boundary Repairs", icon:"wrench.adjustable", destination:.premises) }
                        case "essentials":
                            ForEach(state.readiness().filter { ["water","rest","hygiene","staffing"].contains($0.id) && !$0.complete }) { check in
                                ValueRow(title:check.title, value:check.help)
                            }
                            NavRow(title:"Equip Room Two", icon:"bed.double", destination:.area("room2"), detail:"Choose empty squares for water, a bed and enrichment toys.")
                            NavRow(title:"Equip Room One", icon:"cross.case", destination:.area("room1"), detail:"Cleaning and first aid cupboards complete the essentials.")
                            NavRow(title:"Review Care Cover", icon:"person.2", destination:.staff)
                        case "approval":
                            if !state.insured { Act(title:"Arrange Insurance", icon:"shield", action:.insure, confirmation:"Pay \(money(catalog.economy.insurance)) for one year's insurance?") }
                            let needsApplication = !state.licence.applied || (!state.licenceValid && state.licence.validUntilDay != nil)
                            if needsApplication { Act(title:"Apply for Day Care Licence", icon:"doc.text", action:.applyLicence, confirmation:"Pay the \(money(catalog.economy.licence)) licence application fee?") }
                            if !state.licenceValid && state.licence.applied && !needsApplication {
                                if let due = state.licence.inspectionDay {
                                    ValueRow(title:"Inspection booked", value:"In \(max(0,due-state.day)) game days. Complete each day when you are ready.")
                                    Act(title:"Complete Setup Day", icon:"sun.horizon", action:.nextDay, confirmation:"Pay today's due commitments and move forward one game day? Inspection progress follows the normal game calendar.")
                                } else {
                                    Act(title:"Book Council Inspection", icon:"checkmark.seal", action:.requestInspection, confirmation:"Pay \(money(catalog.economy.inspection)) for an inspection in two game days? The actual site will be checked.")
                                }
                                NavRow(title:"Read Inspection Findings", icon:"checklist", destination:.readiness)
                            }
                        default:
                            Act(title:"Open for Care", icon:"door.left.hand.open", action:.open)
                            NavRow(title:"Review Readiness", icon:"checklist", destination:.readiness)
                        }
                    }
                } else {
                    Section("Your first opening is complete") {
                        Text("A welcoming space, a careful budget and a new business story. Now build relationships at a pace your care team can manage.")
                        Act(title:"Introduce Your Business Locally", icon:"megaphone", action:.market, confirmation:"Spend thirty-five pounds on a seven-day introduction campaign?")
                        NavRow(title:"Meet Your Enquiries", icon:"envelope.open", destination:.enquiries)
                    }
                }
                NavigationLink {
                    List {
                        ForEach(stages) { stage in
                            Label(stage.title, systemImage:stage.complete ? "checkmark.circle.fill" : "circle")
                                .accessibilityLabel("\(stage.title). \(stage.complete ? "Complete" : "Still to do").")
                        }
                    }.navigationTitle("Opening Journey")
                } label: { Label("Your Opening Journey", systemImage: "list.bullet.clipboard") }
                Button("Return to Business", systemImage:"arrow.uturn.backward") { store.path = [] }
                    .accessibilityIdentifier("returnFromOpening")
            }
        }.listStyle(.plain).navigationTitle("Your First Opening")
    }
}

struct PartnerDetailView: View {
    @EnvironmentObject private var store: BusinessStore
    let id: String
    var body: some View {
        List {
            if let provider = store.catalog?.world.first(where: { $0.id == id }), let terms = provider.terms, let state = store.state {
                Label(provider.category, systemImage:providerSymbol(provider.category)).font(.headline)
                Text(provider.name).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                ValueRow(title:"Thirty-day agreement", value:"\(money(terms.fee)) paid now. No automatic renewal.")
                ValueRow(title:"Advantages", value:terms.advantage)
                ValueRow(title:"Trade-offs", value:terms.tradeoff)
                ValueRow(title:"Cash after choosing", value:money(state.cash - terms.fee))
                if let current = state.activePartner(provider.category) {
                    ValueRow(title:"Current agreement", value:"\(store.catalog?.world.first { $0.id == current.providerID }?.name ?? current.providerID). Active through business day \(current.endDay).")
                    if current.providerID == id {
                        Act(title:"End This Agreement", icon:"xmark.circle", action:.endPartnership(provider.category), confirmation:"End this agreement now? Benefits stop immediately and the upfront fee is not refunded.", destructive:true)
                    } else {
                        choose(provider, terms:terms, replacing:true)
                    }
                } else { choose(provider, terms:terms, replacing:false) }
                NavRow(title:"Review Finance", icon:"sterlingsign.circle", destination:.finance)
            }
        }.listStyle(.plain).navigationTitle("Provider")
    }
    private func choose(_ provider: WorldBusiness, terms: PartnerTerms, replacing: Bool) -> some View {
        Act(title:replacing ? "Switch to \(provider.name)" : "Choose \(provider.name)", icon:"checkmark.circle", action:.community(provider.id),
            confirmation:"Pay \(money(terms.fee)) for 30 days with \(provider.name)? \(replacing ? "This replaces your current agreement in this category without a refund. " : "")No automatic renewal.")
    }
}
func providerSymbol(_ category: String) -> String {
    ["Vet":"cross.case.fill","Supplier":"shippingbox.fill","Trainer":"graduationcap.fill","Groomer":"scissors","Community":"person.3.fill","Competitor":"building.2.fill"][category] ?? "building.2"
}
