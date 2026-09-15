import SwiftUI
import PawBossCore

struct PremisesView: View {
    var body: some View { AreaView(id: "outdoor", overview: true) }
}

private struct GridSelection: Identifiable {
    let row: Int
    let column: Int
    var adding = false
    var id: String { "\(row)-\(column)" }
}

struct AreaView: View {
    @EnvironmentObject private var store: BusinessStore
    let id: String
    var overview = false
    @State private var selection: GridSelection?
    @State private var moving: UUID?
    @State private var removing: UUID?
    @State private var tools = false
    @State private var lastSquare: String?
    @AccessibilityFocusState private var focusedSquare: String?
    private var area: Area? { store.state?.areas.first { $0.id == id } }

    var body: some View {
        ScrollView(.vertical) {
            if let area, let state = store.state, let catalog = store.catalog {
                VStack(alignment: .leading, spacing: 16) {
                    if overview {
                        HStack {
                            Text("Outdoor grounds").font(.headline).accessibilityAddTraits(.isHeader)
                            Spacer()
                            Button("Area Options", systemImage: "slider.horizontal.3") { tools = true }
                                .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                                .accessibilityIdentifier("areaOptions")
                        }.padding(.horizontal)
                        roomLinks(state)
                    }
                    else { Text(area.isOutdoor ? "Outdoor grounds" : area.purpose.title).font(.headline).padding(.horizontal) }
                    if let moving, let object = area.items.first(where: { $0.id == moving }), let definition = try? catalog.item(object.definitionID) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Moving \(definition.name.lowercased())", systemImage: definition.symbol).font(.headline)
                            Button("Cancel Move", systemImage: "xmark") { self.moving = nil; store.announce("Move cancelled. The item has not moved.") }
                        }.padding(.horizontal)
                    }
                    ScrollView(.horizontal) {
                        VStack(spacing: 4) {
                            ForEach(0..<area.rows, id: \.self) { row in
                                HStack(spacing: 4) {
                                    ForEach(0..<area.columns, id: \.self) { column in
                                        square(area: area, state: state, catalog: catalog, row: row, column: column)
                                    }
                                }
                            }
                        }.padding(4)
                    }.accessibilityIdentifier("premisesGrid")
                    Text("\(area.columns) columns, \(area.rows) rows").font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                }.padding(.vertical, 12)
            }
        }
        .navigationTitle(overview ? "Premises" : area?.name ?? "Area")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !overview {
                    Button("Area Options", systemImage: "slider.horizontal.3") { tools = true }.accessibilityIdentifier("areaOptions")
                }
            }
        }
        .sheet(item: $selection, onDismiss: { focusedSquare = lastSquare }) { square in
            NavigationStack {
                if square.adding {
                    EquipmentCatalogueView(areaID: id, row: square.row, column: square.column, onComplete: { selection = nil })
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { selection = nil } } }
                } else {
                    SquareInspector(areaID: id, row: square.row, column: square.column,
                        onMove: { object in beginMove(object); selection = nil },
                        onRoom: { room in selection = nil; store.path.append(.area(room)) },
                        onComplete: { selection = nil })
                }
            }
        }
        .sheet(isPresented: $tools) { NavigationStack { AreaOptionsView(id: id) } }
        .confirmationDialog(removalMessage, isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            if let removing {
                Button("Remove Item", role: .destructive) { store.send(.remove(removing, id)); self.removing = nil }
            }
            Button("Cancel", role: .cancel) { removing = nil }
        }
    }
    private func roomLinks(_ state: BusinessState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Starter building: two rooms").font(.headline).accessibilityAddTraits(.isHeader)
            ForEach(state.areas.filter { ["room1", "room2"].contains($0.id) }) { room in
                NavRow(title: room.name, icon: "door.left.hand.open", destination: .area(room.id),
                       detail: "\(room.purpose.title). \(room.columns) by \(room.rows).")
                    .accessibilityIdentifier("roomLink-\(room.id)")
            }
            ForEach(state.areas.filter { !$0.isOutdoor && !["room1", "room2"].contains($0.id) }) { room in
                NavRow(title: room.name, icon: "house.fill", destination: .area(room.id), detail: room.purpose.title)
            }
        }.padding(.horizontal)
    }
    private func square(area: Area, state: BusinessState, catalog: Catalog, row: Int, column: Int) -> some View {
        let key = "\(row)-\(column)"
        let objects = state.itemsAt(area: area, row: row, column: column, catalog: catalog)
        let building = area.isOutdoor && state.starterBuilding(row: row, column: column)
        return Button {
            lastSquare = key
            if let moving {
                if store.send(.move(moving, id, row, column)) { self.moving = nil }
            } else { selection = GridSelection(row: row, column: column) }
        } label: {
            SiteSquare(state: state, area: area, catalog: catalog, row: row, column: column,
                       selected: lastSquare == key, moving: objects.contains { $0.id == moving })
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.squareDescription(area: area, row: row, column: column, catalog: catalog))
        .accessibilityHint(moving != nil ? "Activate to move the selected item here. Cancel Move keeps its original position." : building ? "Open either room in the starter building." : "Activate for square details. Actions include adding an item and managing its contents.")
        .accessibilityIdentifier("square-\(id)-\(row)-\(column)")
        .accessibilityFocused($focusedSquare, equals: key)
        .accessibilityActions {
            if moving != nil {
                Button("Move Item Here") {
                    if let moving, store.send(.move(moving, id, row, column)) { self.moving = nil }
                }
            } else if building {
                Button("Open Room One") { store.path.append(.area("room1")) }
                Button("Open Room Two") { store.path.append(.area("room2")) }
            } else {
                Button("Add Item") { lastSquare = key; selection = GridSelection(row: row, column: column, adding: true) }
                ForEach(objects) { object in
                    if let definition = try? catalog.item(object.definitionID), definition.layer != .building {
                        Button("Move \(definition.name)") { lastSquare = key; beginMove(object.id) }
                        Button("Remove \(definition.name)") { lastSquare = key; removing = object.id }
                    }
                }
            }
        }
    }
    private func beginMove(_ object: UUID) {
        moving = object
        let name = area?.items.first { $0.id == object }.flatMap { try? store.catalog?.item($0.definitionID).name } ?? "item"
        store.announce("Choose a destination square for \(name.lowercased()). Activate that square to move it. Cancel Move leaves it where it is.")
    }
    private var removalMessage: String {
        guard let area, let object = area.items.first(where: { $0.id == removing }), let definition = try? store.catalog?.item(object.definitionID) else { return "Remove this item?" }
        return "Remove \(definition.name.lowercased()) at \(area.coordinate(row: object.row, column: object.column)) for \(money(definition.price * Pence(object.condition) / 400)) resale? The site must be closed."
    }
}

private struct SiteSquare: View {
    let state: BusinessState
    let area: Area
    let catalog: Catalog
    let row: Int
    let column: Int
    let selected: Bool
    let moving: Bool
    private var definition: ItemDefinition? {
        state.itemsAt(area: area, row: row, column: column, catalog: catalog).first.flatMap { try? catalog.item($0.definitionID) }
    }
    private var building: Bool { area.isOutdoor && state.starterBuilding(row: row, column: column) }
    private var object: PlacedItem? { state.itemsAt(area: area, row: row, column: column, catalog: catalog).first }
    private var symbol: String? {
        if building {
            if row == 4 && column == 2 { return "1.square.fill" }
            if row == 4 && column == 6 { return "2.square.fill" }
            return nil
        }
        if let object, let definition, definition.width > 1 || definition.height > 1 {
            if row != object.row || column != object.column {
                return row == object.row ? "arrow.left" : column == object.column ? "arrow.up" : "arrow.up.left"
            }
        }
        return definition?.symbol ?? (area.isOutdoor ? "leaf" : "square.dashed")
    }
    private var background: Color {
        if building { return Color(red: 0.17, green: 0.40, blue: 0.40) }
        if definition?.id == "gate" { return .pawGold }
        if definition?.layer == .boundary { return Color(red: 0.22, green: 0.36, blue: 0.25) }
        if definition != nil { return Color(red: 0.95, green: 0.97, blue: 0.93) }
        if area.isOutdoor { return (row + column).isMultiple(of: 2) ? Color(red: 0.64, green: 0.80, blue: 0.42) : Color(red: 0.74, green: 0.87, blue: 0.55) }
        return (row + column).isMultiple(of: 2) ? Color(red: 0.78, green: 0.86, blue: 0.86) : Color(red: 0.88, green: 0.93, blue: 0.92)
    }
    private var foreground: Color { building || (definition?.layer == .boundary && definition?.id != "gate") ? .white : Color(red: 0.10, green: 0.19, blue: 0.13) }
    var body: some View {
        VStack(spacing: 4) {
            Text(area.coordinate(row: row, column: column)).font(.system(size: 13, weight: .bold, design: .rounded)).monospaced()
            Image(systemName: symbol ?? "square.fill")
                .font(.system(size: 23, weight: .semibold)).frame(height: 26)
                .opacity(symbol == nil ? 0 : 1).accessibilityHidden(true)
        }
        .frame(width: 64, height: 68)
        .foregroundStyle(foreground)
        .background(background, in: RoundedRectangle(cornerRadius: 5))
        .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(moving ? Color.pawCoral : selected ? Color.black : foreground.opacity(0.22), lineWidth: moving || selected ? 3 : 1) }
        .overlay(alignment: .bottomTrailing) {
            if let object = state.itemsAt(area: area, row: row, column: column, catalog: catalog).first, object.condition < 45 {
                Image(systemName: "wrench.fill").font(.system(size: 10)).padding(3).background(Color.pawGold, in: Circle()).foregroundStyle(.black)
            }
        }
    }
}

private struct SquareInspector: View {
    @EnvironmentObject private var store: BusinessStore
    let areaID: String
    let row: Int
    let column: Int
    let onMove: (UUID) -> Void
    let onRoom: (String) -> Void
    let onComplete: () -> Void
    private var area: Area? { store.state?.areas.first { $0.id == areaID } }
    var body: some View {
        List {
            if let area, let state = store.state, let catalog = store.catalog {
                Text(state.squareDescription(area: area, row: row, column: column, catalog: catalog)).font(.headline)
                if area.isOutdoor && state.starterBuilding(row: row, column: column) {
                    ForEach(state.areas.filter { ["room1", "room2"].contains($0.id) }) { room in
                        Button { onRoom(room.id) } label: { Label("\(room.name): \(room.purpose.title)", systemImage: "door.left.hand.open") }
                    }
                } else {
                    NavigationLink {
                        EquipmentCatalogueView(areaID: areaID, row: row, column: column, onComplete: onComplete)
                    } label: { Label("Add Item", systemImage: "plus") }
                    .accessibilityIdentifier("addItem")
                    ForEach(state.itemsAt(area: area, row: row, column: column, catalog: catalog)) { object in
                        if let definition = try? catalog.item(object.definitionID) {
                            Section(definition.name) {
                                ValueRow(title: "Condition", value: "\(object.condition) percent. \(money(definition.weeklyCost)) per week.")
                                Text(definition.detail)
                                if definition.layer != .building {
                                    Button { onMove(object.id) } label: { Label("Move \(definition.name)", systemImage: "arrow.up.and.down.and.arrow.left.and.right") }
                                        .accessibilityIdentifier("move-\(definition.id)")
                                    Act(title: "Remove \(definition.name)", icon: "trash", action: .remove(object.id, areaID),
                                        confirmation: "Remove \(definition.name.lowercased()) for \(money(definition.price * Pence(object.condition) / 400)) resale? The site must be closed.", destructive: true)
                                } else if object.readyDay <= state.day {
                                    Button("Open Building", systemImage: "door.left.hand.open") { onRoom("room-\(object.id.uuidString)") }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(area?.coordinate(row: row, column: column) ?? "Square")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark", action: onComplete) } }
    }
}

private struct EquipmentCatalogueView: View {
    @EnvironmentObject private var store: BusinessStore
    let areaID: String
    let row: Int
    let column: Int
    let onComplete: () -> Void
    @State private var search = ""
    private var area: Area? { store.state?.areas.first { $0.id == areaID } }
    private var items: [ItemDefinition] {
        guard let area, let catalog = store.catalog else { return [] }
        let essentials = ["fence", "gate", "floor", "water", "bed", "toys", "cleaning", "firstaid"]
        return catalog.items.filter {
            (area.isOutdoor ? $0.outdoors : $0.indoors) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.detail.localizedCaseInsensitiveContains(search))
        }.sorted {
            let left = essentials.firstIndex(of: $0.id) ?? 100
            let right = essentials.firstIndex(of: $1.id) ?? 100
            return left == right ? $0.name < $1.name : left < right
        }
    }
    var body: some View {
        List {
            if let area, let state = store.state, let catalog = store.catalog {
                ForEach(items) { definition in
                    NavigationLink {
                        EquipmentPurchaseView(areaID: areaID, row: row, column: column, itemID: definition.id, onComplete: onComplete)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: definition.symbol).frame(width: 24).foregroundStyle(Color.pawGreen)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(definition.name).font(.headline)
                                Text(money(state.placementPrice(definition, area: area, row: row, column: column, catalog: catalog))).font(.subheadline)
                            }
                        }.padding(.vertical, 4)
                    }
                    .accessibilityLabel("\(definition.name). \(money(state.placementPrice(definition, area: area, row: row, column: column, catalog: catalog))).")
                    .accessibilityHint("Review the cost, space and ongoing commitment before purchase.")
                    .accessibilityIdentifier("catalogue-\(definition.id)")
                }
            }
        }.searchable(text: $search).navigationTitle("Add Item")
    }
}

private struct EquipmentPurchaseView: View {
    @EnvironmentObject private var store: BusinessStore
    let areaID: String
    let row: Int
    let column: Int
    let itemID: String
    let onComplete: () -> Void
    @State private var confirm = false
    var body: some View {
        List {
            if let state = store.state, let catalog = store.catalog, let area = state.areas.first(where: { $0.id == areaID }), let definition = try? catalog.item(itemID) {
                let cost = state.placementPrice(definition, area: area, row: row, column: column, catalog: catalog)
                Label(definition.name, systemImage: definition.symbol).font(.headline)
                ValueRow(title: "Purchase", value: "\(money(cost)) at \(area.coordinate(row: row, column: column)). \(definition.width) by \(definition.height) squares.")
                if cost < definition.price { Text("Includes credit for the fence panel replaced by this gate.") }
                Text(definition.detail)
                ValueRow(title: "Ongoing commitment", value: "\(money(definition.weeklyCost)) per week. Typical life \(definition.lifespanDays) game days.")
                ValueRow(title: "Cash after purchase", value: "\(money(state.cash - cost)). Wages, rent and care supplies still need a reserve.")
                Button { confirm = true } label: { Label("\(definition.placementVerb) \(definition.name)", systemImage: "plus.circle") }
                    .accessibilityIdentifier("purchaseItem")
                    .confirmationDialog("\(definition.placementVerb) \(definition.name.lowercased()) at \(area.coordinate(row: row, column: column)) for \(money(cost))?", isPresented: $confirm, titleVisibility: .visible) {
                        Button("Confirm \(money(cost))") {
                            if store.send(.build(itemID, areaID, row, column)) { onComplete() }
                        }.accessibilityIdentifier("confirmPurchase")
                        Button("Cancel", role: .cancel) {}
                    }
            }
        }.navigationTitle("Review Item")
    }
}

private struct AreaOptionsView: View {
    @EnvironmentObject private var store: BusinessStore
    @Environment(\.dismiss) private var dismiss
    let id: String
    @State private var purpose: RoomUse = .unassigned
    @State private var loaded = false
    var body: some View {
        Form {
            if let state = store.state, let catalog = store.catalog, let area = state.areas.first(where: { $0.id == id }) {
                if area.isOutdoor {
                    let missing = state.boundaryCells(in: area).filter { r, c in !area.items.contains { $0.row == r && $0.column == c && ["fence", "gate"].contains($0.definitionID) } }.count
                    if missing > 0 {
                        let cost = Pence(missing) * ((try? catalog.item("fence").price) ?? 2500)
                        Act(title: "Build Missing Fence Panels", icon: "rectangle.dashed", action: .buildBoundary, confirmation: "Build \(missing) missing boundary panels for \(money(cost))? Existing gates stay in place.")
                    }
                } else {
                    Picker("Room Purpose", selection: $purpose) { ForEach(RoomUse.allCases) { Text($0.title).tag($0) } }
                    Act(title: "Save Room Purpose", icon: "checkmark", action: .configureRoom(id, purpose))
                    let missing = area.rows * area.columns - area.items.filter { $0.definitionID == "floor" }.count
                    if missing > 0 {
                        let cost = Pence(missing) * ((try? catalog.item("floor").price) ?? 1200)
                        Act(title: "Fit Washable Floor", icon: "square.grid.3x3", action: .floorRoom(id), confirmation: "Fit \(missing) missing floor squares for \(money(cost))? Furniture remains in place.")
                    }
                }
                Section("Site Care") {
                    ValueRow(title: "Cleanliness", value: "\(state.cleanliness) percent")
                    if state.cleanliness < 100 { Act(title: "Deep Clean", icon: "sparkles", action: .clean, confirmation: "Spend twelve pounds on deep cleaning supplies?") }
                    let cost = (try? store.engine?.maintenanceQuote) ?? 0
                    if cost > 0 { Act(title: "Maintain Worn Equipment", icon: "wrench.adjustable", action: .maintain, confirmation: "Repair worn equipment for \(money(cost))?") }
                    Button("Readiness", systemImage: "checklist") { dismiss(); store.path.append(.readiness) }
                }
                if area.isOutdoor {
                    Section("Growth") {
                        Act(title: "Purchase Additional Land", icon: "square.dashed.inset.filled", action: .expandLand, confirmation: "Purchase the next plot for three thousand five hundred pounds? Close the site, obtain planning and keep a cash reserve. A new boundary and inspection are required.")
                    }
                }
            }
        }.navigationTitle("Area Options")
            .onAppear {
                if !loaded { purpose = store.state?.areas.first { $0.id == id }?.purpose ?? .unassigned; loaded = true }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() } } }
    }
}
