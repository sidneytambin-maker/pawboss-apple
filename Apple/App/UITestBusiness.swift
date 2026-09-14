#if DEBUG
import Foundation
import PawBossCore

enum UITestBusiness {
    static func make(catalog: Catalog) throws -> BusinessState {
        var engine = try GameEngine(state: catalog.newBusiness(name: "Meadow Care", owner: "Sam", title: "Owner", seed: 42), catalog: catalog)
        let opening: [GameAction] = [.register, .configureRoom("room1", .reception), .configureRoom("room2", .multipurpose),
            .floorRoom("room2"), .buildBoundary, .build("gate", "outdoor", 0, 1), .build("bed", "room2", 0, 0),
            .build("water", "room2", 0, 1), .build("toys", "room2", 0, 2), .build("cleaning", "room1", 0, 0),
            .build("firstaid", "room1", 0, 1), .insure, .applyLicence, .requestInspection, .nextDay, .nextDay, .open, .market]
        func require(_ action: GameAction, _ engine: inout GameEngine) throws {
            let result = engine.perform(action)
            if !result.applied { throw GameError.invalid(result.message) }
        }
        for action in opening { try require(action, &engine) }
        for _ in 0..<14 where engine.state.pendingEnquiries.isEmpty { try require(.nextDay, &engine) }
        guard let enquiry = engine.state.pendingEnquiries.first else { throw GameError.invalid("No test enquiry generated") }
        try require(.decideEnquiry(enquiry.id, "accept"), &engine)
        guard let booking = engine.state.bookings.first else { throw GameError.invalid("Test booking missing") }
        while engine.state.day < booking.day { try require(.nextDay, &engine) }
        return engine.state
    }
}
#endif
