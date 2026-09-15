import Foundation

public extension ItemDefinition {
    var placementVerb: String {
        if layer == .boundary || layer == .building { return "Build" }
        if id == "garden" { return "Plant" }
        if id == "path" { return "Lay" }
        if layer == .ground { return "Fit" }
        if ["grooming","washer","handwash","pawwash","fan","acoustic","canopy","cleaning","firstaid"].contains(id) { return "Install" }
        return "Place"
    }
    var placedVerb: String {
        switch placementVerb { case "Build": return "Built"; case "Fit": return "Fitted"; case "Install": return "Installed"; case "Plant": return "Planted"; case "Lay": return "Laid"; default: return "Placed" }
    }
    var symbol: String {
        if ["snuffle","scentposts","digbox","sensorymat","garden"].contains(id) { return "leaf.fill" }
        if ["puzzle","trainingkit","lickmat","softplay"].contains(id) { return "puzzlepiece.fill" }
        if ["retrieve","tunnel","lowhurdles","toys","agility"].contains(id) { return "tennisball.fill" }
        if ["bed","orthobed","raisedbed","blankets","quietden","privacy","acoustic"].contains(id) { return "bed.double.fill" }
        if ["coolmat","fan"].contains(id) { return "fan.fill" }
        if ["canopy","shade"].contains(id) { return "umbrella.fill" }
        if ["pawwash","towels","washer","mop","bins","handwash","toywash","cleaning"].contains(id) { return "sparkles" }
        if ["locker","breaktable","staffbench"].contains(id) { return "chair.fill" }
        if id == "kettle" { return "cup.and.saucer.fill" }
        if id == "noticeboard" { return "list.bullet.clipboard.fill" }
        return ["water":"drop.fill","firstaid":"cross.case.fill","desk":"desktopcomputer","grooming":"scissors","vehicle":"car.fill","extension":"house.fill","fence":"rectangle.split.3x1","gate":"door.left.hand.closed","floor":"square.grid.3x3","path":"point.topleft.down.curvedto.point.bottomright.up"][id] ?? "shippingbox.fill"
    }
}

public struct CareEquipmentSupport: Equatable {
    public var welfare: Int
    public var stressRelief: Int
    public var explanation: String
}
public extension BusinessState {
    func careHas(_ ids: [String]) -> Bool {
        areas.contains { area in
            let careRoom = [.multipurpose, .quiet, .puppy, .boarding].contains(area.purpose)
            return (area.isOutdoor || careRoom) && area.items.contains { ids.contains($0.definitionID) && available($0) }
        }
    }
    func equipmentSupport(for dog: Dog) -> CareEquipmentSupport {
        var benefits: [String] = []
        let activity = dog.favouriteActivity.lowercased()
        let description = (dog.personality + " " + dog.health).lowercased()
        if priorities.contains("rest") && has("bed") {
            if dog.ageMonths >= 96 && careHas(["orthobed", "blankets"]) { benefits.append("Extra comfort supported senior rest") }
            else if (dog.confidence < 50 || description.contains("quiet") || description.contains("sensitive") || description.contains("calm")) && careHas(["privacy", "acoustic", "quietden", "raisedbed"]) { benefits.append("A quieter retreat supported settling") }
        }
        if priorities.contains("enrichment") && has("toys") {
            if (activity.contains("scent") || activity.contains("sniff") || activity.contains("digging")) && careHas(["snuffle", "scentposts", "digbox", "garden"]) { benefits.append("Scent equipment matched the individual activity plan") }
            else if (activity.contains("puzzle") || activity.contains("learning")) && careHas(["puzzle", "trainingkit"]) { benefits.append("Learning equipment matched the individual activity plan") }
            else if activity.contains("retriev") && careHas(["retrieve"]) { benefits.append("Retrieving equipment matched the individual activity plan") }
            else if (activity.contains("quiet") || activity.contains("sensory")) && careHas(["sensorymat", "lickmat"]) { benefits.append("Quiet enrichment matched the individual activity plan") }
            else if dog.ageMonths < 12 && careHas(["softplay"]) { benefits.append("Gentle supervised exploration supported puppy confidence") }
            else if dog.ageMonths >= 12 && dog.ageMonths < 96 && dog.confidence >= 60 && dog.energy >= 65 && !description.contains("no jumping") && !description.contains("avoid high jumps") && careHas(["agility", "tunnel", "lowhurdles"]) { benefits.append("Suitable supervised movement complemented planned rest") }
        }
        if priorities.contains("rest") && has("water") {
            if weather == "Warm sunshine" && careHas(["shade", "coolmat", "fan", "canopy"]) { benefits.append("Warm-weather equipment supported a quieter routine") }
            if weather == "Cold snap" && careHas(["blankets", "quietden"]) { benefits.append("Warm bedding supported cold-weather rest") }
            if weather.contains("rain") && careHas(["canopy"]) { benefits.append("Covered space provided a dry outdoor pause") }
        }
        // Equipment complements, but cannot compensate for missing fundamental care.
        let safe = has("water") && has("bed") && cleanliness >= 60 && dogs.filter(\.present).count <= careCapacity
        guard safe else { return .init(welfare: 0, stressRelief: 0, explanation: "") }
        return .init(welfare: min(3, benefits.count), stressRelief: min(2, benefits.count), explanation: benefits.joined(separator: ". "))
    }
    var cleaningEquipmentSupport: Int {
        guard priorities.contains("cleaning") else { return 0 }
        let general = ["washer", "mop", "bins", "handwash", "toywash"].filter { has($0) }.count
        let wet = weather.contains("rain") ? ["pawwash", "towels"].filter { has($0) }.count : 0
        return min(3, general + wet)
    }
    var teamEquipmentSupport: Int {
        guard careCapacity > dogs.filter(\.present).count else { return 0 }
        let fixtures = areas.filter { $0.purpose == .staff || $0.purpose == .reception }.flatMap(\.items)
        return min(2, Set(fixtures.filter { available($0) && ["staffbench", "locker", "kettle", "breaktable", "noticeboard"].contains($0.definitionID) }.map(\.definitionID)).count)
    }
}
public enum CustomerSchedule {
    public static let habits = ["Two weekdays each week", "Three weekdays each week", "Two separated weekdays", "Three alternate weekdays", "Two morning half-days", "One weekly settling visit"]
    public static let communications = ["Email", "Collection handover", "Telephone update", "Written care diary", "Short message", "Detailed weekly summary"]
    public static func offsets(for habit: String) -> [Int] {
        switch habit {
        case "Three weekdays each week": return [0, 1, 2]
        case "Two separated weekdays": return [1, 3]
        case "Three alternate weekdays": return [0, 2, 4]
        case "Two morning half-days": return [0, 3]
        case "One weekly settling visit": return [2]
        default: return [0, 1]
        }
    }
    public static func service(for habit: String) -> Service { habit == "Two morning half-days" ? .halfDay : .dayCare }
}
