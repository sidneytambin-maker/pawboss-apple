import SwiftUI
import PawBossCore

struct PremisesView: View {
    @EnvironmentObject private var store: BusinessStore
    var body: some View {
        List {
            if let state = store.state, let catalog = store.catalog {
                if let area = state.areas.first(where: \.isOutdoor) {
                    SiteMap(state: state, area: area, catalog: catalog, selectedRow: -1, selectedColumn: -1)
                        .aspectRatio(1, contentMode: .fit).accessibilityHidden(true)
                }
                Section("Your Site") {
                    ForEach(state.areas) { area in
                        NavRow(title: area.name, icon: area.isOutdoor ? "leaf" : "house", destination: .area(area.id), detail: "\(area.rows) by \(area.columns). \(area.isOutdoor ? (state.secureBoundary ? "Secure boundary" : "Boundary needs attention") : area.purpose.title).")
                    }
                }
                Section("Maintenance and Growth") {
                    ValueRow(title: "Cleanliness", value: state.cleanliness >= 80 ? "Clean and well kept" : state.cleanliness >= 60 ? "Cleaning due" : "Deep cleaning needed")
                    Act(title: "Deep Clean", icon: "sparkles", action: .clean, confirmation: "Spend twelve pounds on additional deep cleaning supplies?")
                    let repairCost = (try? store.engine?.maintenanceQuote) ?? 0
                    Act(title: "Maintain Worn Equipment", icon: "wrench.adjustable", action: .maintain, confirmation: "Repair equipment below ninety percent condition for \(money(repairCost))?")
                        .disabled(repairCost == 0)
                    NavRow(title: "Readiness", icon: "checklist", destination: .readiness)
                    Act(title: "Purchase Additional Land", icon: "square.dashed.inset.filled", action: .expandLand, confirmation: "Purchase the next larger plot for three thousand five hundred pounds? Keep a cash reserve, close the site and obtain planning first. A new boundary and inspection will be needed.")
                }
            }
        }.listStyle(.plain).navigationTitle("Premises")
    }
}
struct AreaView: View {
    @EnvironmentObject private var store: BusinessStore
    let id: String
    @State private var row = 0
    @State private var column = 0
    @State private var purpose: RoomUse = .unassigned
    @State private var itemID = "water"
    @State private var moving: UUID?
    @State private var remove = false
    @AccessibilityFocusState private var buildFocused: Bool
    private var area: Area? { store.state?.areas.first { $0.id == id } }
    var body: some View {
        List {
            if let area, let state = store.state, let catalog = store.catalog {
                SiteMap(state: state, area: area, catalog: catalog, selectedRow: row, selectedColumn: column)
                    .aspectRatio(1, contentMode: .fit).accessibilityHidden(true)
                Section("Location") {
                    Picker("Row", selection: $row) { ForEach(0..<area.rows, id: \.self) { Text("\($0 + 1)").tag($0) } }
                    Picker("Column", selection: $column) { ForEach(0..<area.columns, id: \.self) { Text(String(Character(UnicodeScalar(65 + $0)!))).tag($0) } }
                    let objects = state.itemsAt(area: area, row: row, column: column, catalog: catalog)
                    Text(state.squareDescription(area: area, row: row, column: column, catalog: catalog))
                        .font(.headline).accessibilityIdentifier("selectedSquare")
                        .accessibilityActions {
                            Button("Build Here") { buildFocused = true }
                            if let top = objects.first {
                                Button("Move") { moving = top.id }
                                Button("Remove") { remove = true }
                            }
                        }
                    ForEach(objects) { object in
                        if let definition = try? catalog.item(object.definitionID) {
                            ValueRow(title: definition.name, value: "\(definition.detail) Condition \(object.condition) percent. Weekly running cost \(money(definition.weeklyCost)).")
                            if definition.layer != .building {
                                Button("Move \(definition.name)", systemImage: "arrow.up.and.down.and.arrow.left.and.right") { moving = object.id }
                            }
                        }
                    }
                    if let moving {
                        Button("Move to \(area.coordinate(row: row, column: column))", systemImage: "checkmark") {
                            if store.send(.move(moving, id, row, column)) { self.moving = nil }
                        }
                        Button("Cancel Move", role: .cancel) { self.moving = nil }
                    }
                    if let top = objects.first {
                        Act(title: "Remove Selected Item", icon: "trash", action: .remove(top.id, id), confirmation: "Remove this item and recover its current resale value? The site must be closed.", destructive: true)
                    }
                }
                Section("Build Here") {
                    Picker("Equipment", selection: $itemID) {
                        ForEach(catalog.items.filter { area.isOutdoor ? $0.outdoors : $0.indoors }) { Text($0.name).tag($0.id) }
                    }.accessibilityFocused($buildFocused)
                    if let definition = try? catalog.item(itemID) {
                        ValueRow(title: "Purchase", value: "\(money(definition.price)). \(definition.width) by \(definition.height). \(definition.detail)")
                        ValueRow(title: "Ongoing commitment", value: "\(money(definition.weeklyCost)) per week. Typical life \(definition.lifespanDays) game days.")
                        ValueRow(title: "Cash after purchase", value: "\(money(state.cash - definition.price)). This excludes upcoming wages, rent and care supplies.")
                        Act(title: "Build \(definition.name)", icon: "hammer", action: .build(itemID, id, row, column), confirmation: "Install \(definition.name.lowercased()) at \(area.coordinate(row: row, column: column)) for \(money(definition.price))?")
                    }
                    if area.isOutdoor { Act(title: "Build Missing Perimeter", icon: "rectangle.dashed", action: .buildBoundary, confirmation: "Install missing boundary panels at twenty-five pounds each, keeping existing gates?") }
                    else { Act(title: "Floor Entire Room", icon: "square.grid.3x3", action: .floorRoom(id), confirmation: "Fit missing washable floor tiles at twelve pounds each? Furniture remains in place.") }
                }
                if !area.isOutdoor {
                    Section("Room Purpose") {
                        Picker("Use", selection: $purpose) { ForEach(RoomUse.allCases) { Text($0.title).tag($0) } }
                        Act(title: "Save Room Use", icon: "checkmark", action: .configureRoom(id, purpose))
                    }
                }
            }
        }.listStyle(.plain).navigationTitle(area?.name ?? "Area")
            .onAppear { purpose = area?.purpose ?? .unassigned }
            .confirmationDialog("Remove the selected item?", isPresented: $remove, titleVisibility: .visible) {
                if let area, let state = store.state, let catalog = store.catalog, let top = state.itemsAt(area: area, row: row, column: column, catalog: catalog).first {
                    Button("Remove", role: .destructive) { store.send(.remove(top.id, id)) }
                }
                Button("Cancel", role: .cancel) {}
            }
    }
}
struct SiteMap: View {
    let state: BusinessState
    let area: Area
    let catalog: Catalog
    let selectedRow: Int
    let selectedColumn: Int
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Canvas { context, size in
            let cell = min(size.width / Double(area.columns), size.height / Double(area.rows))
            for row in 0..<area.rows {
                for column in 0..<area.columns {
                    let rect = CGRect(x: Double(column) * cell, y: Double(row) * cell, width: cell, height: cell)
                    let base = area.isOutdoor ? Color(red: 0.71, green: 0.84, blue: 0.60) : Color(red: 0.83, green: 0.88, blue: 0.86)
                    context.fill(Path(rect.insetBy(dx: 0.7, dy: 0.7)), with: .color(base.opacity((row + column) % 2 == 0 ? 1 : 0.85)))
                    if area.isOutdoor && state.starterBuilding(row: row, column: column) {
                        context.fill(Path(rect.insetBy(dx: 0.5, dy: 0.5)), with: .color(Color(red: 0.25, green: 0.47, blue: 0.49)))
                    }
                }
            }
            for item in area.items.sorted(by: { a, b in
                ((try? catalog.item(a.definitionID).layer) == .ground ? 0 : 1) < ((try? catalog.item(b.definitionID).layer) == .ground ? 0 : 1)
            }) {
                guard let definition = try? catalog.item(item.definitionID) else { continue }
                let rect = CGRect(x: Double(item.column) * cell + 2, y: Double(item.row) * cell + 2, width: Double(definition.width) * cell - 4, height: Double(definition.height) * cell - 4)
                let color: Color = definition.layer == .ground ? .white.opacity(0.65) : definition.layer == .boundary ? (definition.id == "gate" ? .pawGold : .pawGreen) : item.condition < 45 ? .pawCoral : definition.layer == .building ? .cyan : .white
                context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(color))
                if definition.layer != .ground && definition.layer != .boundary {
                    let symbol = icon(definition.id)
                    var image = context.resolve(Image(systemName: symbol))
                    image.shading = .color(.black)
                    context.draw(image, in: rect.insetBy(dx: max(2, cell * 0.18), dy: max(2, cell * 0.18)))
                }
            }
            if selectedRow >= 0 {
                let rect = CGRect(x: Double(selectedColumn) * cell + 1, y: Double(selectedRow) * cell + 1, width: cell - 2, height: cell - 2)
                context.stroke(Path(rect), with: .color(.black), style: StrokeStyle(lineWidth: 3, dash: [5, 2]))
            }
        }.background(scheme == .dark ? Color.black : Color.white)
    }
    private func icon(_ id: String) -> String {
        if ["snuffle","scentposts","digbox","sensorymat"].contains(id) { return "leaf.fill" }
        if ["puzzle","trainingkit","lickmat","softplay"].contains(id) { return "puzzlepiece.fill" }
        if ["retrieve","tunnel","lowhurdles"].contains(id) { return "tennisball.fill" }
        if ["orthobed","raisedbed","blankets","quietden","privacy","acoustic"].contains(id) { return "bed.double.fill" }
        if ["coolmat","fan"].contains(id) { return "fan.fill" }
        if id == "canopy" { return "umbrella.fill" }
        if ["pawwash","towels","washer","mop","bins","handwash","toywash"].contains(id) { return "sparkles" }
        if ["locker","breaktable"].contains(id) { return "chair.fill" }
        if id == "kettle" { return "cup.and.saucer.fill" }
        if id == "noticeboard" { return "list.bullet.clipboard.fill" }
        return ["bed": "bed.double.fill", "water": "drop.fill", "toys": "tennisball.fill", "cleaning": "sparkles", "firstaid": "cross.case.fill", "desk": "desktopcomputer", "shade": "umbrella.fill", "agility": "triangle.fill", "garden": "leaf.fill", "grooming": "scissors", "vehicle": "car.fill", "extension": "house.fill", "staffbench": "chair.fill"][id] ?? "square.fill"
    }
}
