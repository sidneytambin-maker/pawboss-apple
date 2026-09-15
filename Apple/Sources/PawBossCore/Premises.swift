import Foundation

public struct ReadinessCheck: Identifiable {
    public var id: String
    public var title: String
    public var complete: Bool
    public var help: String
}
public extension BusinessState {
    func available(_ item: PlacedItem) -> Bool { item.readyDay <= day && item.condition >= 45 }
    func has(_ itemID: String) -> Bool {
        areas.contains { $0.items.contains { $0.definitionID == itemID && available($0) } }
    }
    func hasRoom(_ use: RoomUse) -> Bool { areas.contains { !$0.isOutdoor && $0.purpose == use } }
    func boundaryCells(in area: Area) -> [(Int, Int)] {
        (0..<area.rows).flatMap { row in (0..<area.columns).compactMap { col in
            row == 0 || col == 0 || row == area.rows - 1 || col == area.columns - 1 ? (row, col) : nil
        } }
    }
    var secureBoundary: Bool {
        guard let area = areas.first(where: \.isOutdoor) else { return false }
        return boundaryCells(in: area).allSatisfy { row, col in
            area.items.contains { $0.row == row && $0.column == col && ["fence", "gate"].contains($0.definitionID) && available($0) }
        } && has("gate")
    }
    var licenceValid: Bool { (licence.validUntilDay ?? -1) >= day }
    var insured: Bool { (licence.insuranceUntilDay ?? -1) >= day }
    var careCapacity: Int {
        let staffCapacity = staff.filter { $0.onDuty(day: day) && $0.role.caresForDogs }.reduce(0) { $0 + max(1, $1.skill / 15) }
        let roomCapacity = areas.filter { [.multipurpose, .quiet, .puppy, .boarding].contains($0.purpose) }.count * 6
        return min(licence.capacity, roomCapacity, (ownerOnDuty ? 4 : 0) + staffCapacity)
    }
    func readiness() -> [ReadinessCheck] {
        [
            .init(id: "registration", title: "Business registered", complete: licence.registered, help: "Register your business in Office, Business."),
            .init(id: "rooms", title: "Play and rest space", complete: hasRoom(.multipurpose) || (hasRoom(.puppy) && hasRoom(.quiet)), help: "Configure a room for play and rest in Premises."),
            .init(id: "floor", title: "Cleanable dog-room flooring", complete: areas.contains { [.multipurpose, .puppy].contains($0.purpose) && $0.items.filter { $0.definitionID == "floor" && available($0) }.count >= $0.rows * $0.columns }, help: "Fit washable flooring across the dog room."),
            .init(id: "security", title: "Secure fence and gate", complete: secureBoundary, help: "Build the perimeter and replace a fence panel with a gate."),
            .init(id: "water", title: "Drinking water", complete: has("water"), help: "Place a water bowl in a dog room or outdoor play area."),
            .init(id: "rest", title: "Rest and enrichment", complete: has("bed") && has("toys"), help: "Place a dog bed and enrichment toys."),
            .init(id: "hygiene", title: "Cleaning and welfare supplies", complete: has("cleaning") && has("firstaid") && cleanliness >= 60, help: "Install cleaning and first aid cupboards and keep the site clean."),
            .init(id: "insurance", title: "Insurance in force", complete: insured, help: "Arrange annual insurance in Office, Business."),
            .init(id: "staffing", title: "Care cover available", complete: careCapacity > 0, help: "Keep owner cover on or roster a qualified handler."),
            .init(id: "licence", title: "Council approval", complete: licenceValid, help: "Apply for a licence and book an inspection. Findings explain any work needed.")
        ]
    }
    func serviceBlocker(_ service: Service) -> String? {
        if !licenceValid || !insured { return "Current insurance and council approval are required." }
        switch service {
        case .dayCare, .halfDay: return nil
        case .overnight, .holiday:
            if !licence.boarding || !hasRoom(.boarding) { return "A boarding room and boarding approval are required." }
            if !staff.contains(where: { $0.employed && $0.qualifications.contains("Overnight care") }) { return "Train a staff member in overnight care first." }
        case .grooming:
            if !has("grooming") || !hasRoom(.grooming) || !staff.contains(where: { $0.onDuty(day: day) && $0.role == .groomer }) { return "A grooming room, station and groomer on duty are required." }
        case .pickup, .dropoff:
            if !has("vehicle") || !staff.contains(where: { $0.onDuty(day: day) && $0.qualifications.contains("Dog transport") }) { return "A transport vehicle and trained driver on duty are required." }
        case .specialist:
            if !hasRoom(.quiet) || !staff.contains(where: { $0.onDuty(day: day) && $0.qualifications.contains("Dog behaviour") }) { return "A quiet room and behaviour-trained handler on duty are required." }
        }
        return nil
    }
    func itemsAt(area: Area, row: Int, column: Int, catalog: Catalog) -> [PlacedItem] {
        area.items.filter { placed in
            guard let item = try? catalog.item(placed.definitionID) else { return false }
            return row >= placed.row && row < placed.row + item.height && column >= placed.column && column < placed.column + item.width
        }.sorted { a, b in
            let rank: [Layer: Int] = [.ground: 0, .boundary: 1, .building: 2, .furniture: 3]
            return rank[(try? catalog.item(a.definitionID).layer) ?? .ground, default: 0] > rank[(try? catalog.item(b.definitionID).layer) ?? .ground, default: 0]
        }
    }
    func starterBuilding(row: Int, column: Int) -> Bool { (3...6).contains(row) && (1...8).contains(column) }
    func squareDescription(area: Area, row: Int, column: Int, catalog: Catalog) -> String {
        let coordinate = area.coordinate(row: row, column: column)
        if area.isOutdoor && starterBuilding(row: row, column: column) {
            return "\(coordinate). Starter building, two customisable rooms."
        }
        let objects = itemsAt(area: area, row: row, column: column, catalog: catalog)
        guard !objects.isEmpty else { return "\(coordinate). Empty." }
        let contents = objects.compactMap { object -> String? in
            guard let definition = try? catalog.item(object.definitionID) else { return nil }
            var text = definition.name
            if definition.layer == .boundary { text += ", boundary" }
            if definition.width > 1 || definition.height > 1 {
                text += ", \(definition.width) by \(definition.height), starts at \(area.coordinate(row: object.row, column: object.column))"
            }
            if object.readyDay > day { text += ", ready on day \(object.readyDay + 1)" }
            else if object.condition < 45 { text += ", repair needed" }
            return text
        }
        return "\(coordinate). \(contents.joined(separator: ". "))."
    }
    func placementPrice(_ definition: ItemDefinition, area: Area, row: Int, column: Int, catalog: Catalog) -> Pence {
        let replacesFence = definition.id == "gate" && itemsAt(area: area, row: row, column: column, catalog: catalog).contains { $0.definitionID == "fence" }
        let credit = replacesFence ? ((try? catalog.item("fence").price) ?? 0) : 0
        return max(0, definition.price - credit)
    }
}

extension GameEngine {
    mutating func build(itemID: String, areaID: String, row: Int, column: Int, movingID: UUID? = nil) throws {
        let definition = try catalog.item(itemID)
        guard let areaIndex = state.areas.firstIndex(where: { $0.id == areaID }) else { throw GameError.invalid("Choose an existing area.") }
        let area = state.areas[areaIndex]
        guard (area.isOutdoor ? definition.outdoors : definition.indoors) else { throw GameError.invalid("\(definition.name) is not suitable for this area.") }
        guard row >= 0, column >= 0, row + definition.height <= area.rows, column + definition.width <= area.columns else { throw GameError.invalid("This item extends beyond the area. Choose another square.") }
        if definition.requiresInspection && !state.licenceValid { throw GameError.invalid("Pass your first inspection before adding this facility.") }
        if itemID == "extension" && movingID == nil {
            guard (state.planningReadyDay ?? Int.max) <= state.day else { throw GameError.invalid("Apply for planning approval in Business before constructing an extension.") }
        }
        if definition.layer == .boundary {
            guard row == 0 || column == 0 || row == area.rows - 1 || column == area.columns - 1 else { throw GameError.invalid("Fences and gates belong on the edge of the plot.") }
        }
        var replacedFence: UUID?
        for r in row..<(row + definition.height) {
            for c in column..<(column + definition.width) {
                if area.isOutdoor && state.starterBuilding(row: r, column: c) { throw GameError.invalid("The starter building occupies this square.") }
                for existing in state.itemsAt(area: area, row: r, column: c, catalog: catalog) where existing.id != movingID {
                    let other = try catalog.item(existing.definitionID)
                    if definition.id == "gate" && other.id == "fence" { replacedFence = existing.id; continue }
                    if definition.layer == other.layer || definition.layer == .building || other.layer == .building || definition.layer == .boundary || other.layer == .boundary {
                        throw GameError.invalid("This would overlap \(other.name.lowercased()). Choose a free square.")
                    }
                }
            }
        }
        if let movingID {
            guard let i = state.areas[areaIndex].items.firstIndex(where: { $0.id == movingID }) else { throw GameError.invalid("The item has already moved or been removed.") }
            guard definition.layer != .building else { throw GameError.invalid("A building cannot be moved after construction.") }
            guard !state.isOpen else { throw GameError.invalid("Close the site before moving equipment or boundaries.") }
            state.areas[areaIndex].items[i].row = row; state.areas[areaIndex].items[i].column = column
        } else {
            let credit = replacedFence == nil ? 0 : try catalog.item("fence").price
            try spend(max(0, definition.price - credit), "\(definition.placedVerb) \(definition.name.lowercased()) at \(area.name), \(area.coordinate(row: row, column: column))", kind: .investment)
            state.areas[areaIndex].items.append(PlacedItem(definitionID: itemID, row: row, column: column, installedDay: state.day, readyDay: state.day + (definition.layer == .building ? 7 : 0)))
        }
        if let replacedFence { state.areas[areaIndex].items.removeAll { $0.id == replacedFence } }
    }
    mutating func buildBoundary() throws {
        guard let index = state.areas.firstIndex(where: \.isOutdoor) else { return }
        let area = state.areas[index]
        let missing = state.boundaryCells(in: area).filter { r, c in !area.items.contains { $0.row == r && $0.column == c && ["gate", "fence"].contains($0.definitionID) } }
        guard !missing.isEmpty else { throw GameError.invalid("Your perimeter is already built. Repair worn panels through Maintenance.") }
        for (r, c) in missing { try build(itemID: "fence", areaID: area.id, row: r, column: c) }
    }
    mutating func floorRoom(_ areaID: String) throws {
        guard let area = state.areas.first(where: { $0.id == areaID && !$0.isOutdoor }) else { throw GameError.invalid("Choose an indoor room.") }
        let missing = (0..<area.rows).flatMap { row in (0..<area.columns).compactMap { col in
            area.items.contains { $0.definitionID == "floor" && $0.row == row && $0.column == col } ? nil : (row, col)
        } }
        guard !missing.isEmpty else { throw GameError.invalid("This room already has washable flooring.") }
        for (r, c) in missing { try build(itemID: "floor", areaID: areaID, row: r, column: c) }
    }
}
