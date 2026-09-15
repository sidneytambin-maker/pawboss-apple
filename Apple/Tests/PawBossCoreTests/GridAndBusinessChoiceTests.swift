import XCTest
@testable import PawBossCore

final class PrioritySlotTests: XCTestCase {
    func testThreeSlotsReplaceOrSwapWithoutExceedingLimit() {
        var model = DailyPrioritySlots(["rest", "enrichment", "cleaning"])
        model.select("training", at: 0)
        XCTAssertEqual(model.slots, ["training", "enrichment", "cleaning"])
        model.select("cleaning", at: 0)
        XCTAssertEqual(model.slots, ["cleaning", "enrichment", "training"])
        model.select("", at: 1)
        XCTAssertEqual(model.selected, ["cleaning", "training"])
        model.select("bogus", at: 0); model.select("rest", at: -1)
        XCTAssertEqual(model.slots, ["cleaning", "", "training"])
    }
    func testInvalidLegacySelectionsAreNormalised() {
        XCTAssertEqual(DailyPrioritySlots(["rest", "rest", "bogus", "cleaning"]).slots, ["rest", "cleaning", ""])
        XCTAssertEqual(DailyPrioritySlots([]).slots, ["", "", ""])
        XCTAssertEqual(DailyPrioritySlots(DailyPrioritySlots.choices).selected.count, 3)
    }
}

extension SimulationTests {
    func testPrioritySelectionSavesAndRoundTripsWatchCommand() throws {
        var engine = try fresh()
        let choices = ["maintenance", "communication", "training"]
        let command = GameCommand(businessID: engine.state.id, day: engine.state.day, action: .priorities(choices))
        let decoded = try JSONDecoder().decode(GameCommand.self, from: JSONEncoder().encode(command))
        XCTAssertTrue(engine.apply(decoded).applied)
        let restored = try JSONDecoder().decode(BusinessState.self, from: JSONEncoder().encode(engine.state))
        XCTAssertEqual(restored.priorities, choices)
        XCTAssertFalse(engine.perform(.priorities(["rest", "rest"])).applied)
        XCTAssertEqual(engine.state.priorities, choices)
        apply(.priorities([]), to: &engine)
        XCTAssertTrue(engine.state.priorities.isEmpty)
    }
    func testEveryProviderCategoryHasThreeMeaningfulChoices() throws {
        let engine = try fresh()
        for category in ["Vet", "Supplier", "Trainer", "Groomer", "Community"] {
            let providers = engine.catalog.world.filter { $0.category == category }
            XCTAssertGreaterThanOrEqual(providers.count, 3)
            XCTAssertEqual(Set(providers.compactMap { $0.terms?.fee }).count, providers.count)
            XCTAssertTrue(providers.allSatisfy { $0.terms?.valid == true && !$0.terms!.advantage.isEmpty && !$0.terms!.tradeoff.isEmpty })
        }
    }
    func testProviderMigrationPreservesOldRecordsAndMarketPrices() throws {
        let engine = try customerGame()
        var old = engine.state
        old.world.removeAll { !["vets", "supplies", "trainer", "groomer", "rescue"].contains($0.id) && $0.category != "Competitor" }
        for index in old.world.indices { old.world[index].terms = nil }
        let restored = try JSONDecoder().decode(BusinessState.self, from: JSONEncoder().encode(old))
        let migrated = try GameEngine(state: restored, catalog: engine.catalog)
        XCTAssertEqual(migrated.state.dogs.map(\.id), old.dogs.map(\.id))
        XCTAssertEqual(migrated.state.bookings.map(\.id), old.bookings.map(\.id))
        XCTAssertEqual(migrated.state.cash, old.cash)
        XCTAssertEqual(migrated.state.world.filter { $0.category != "Competitor" }.count, 15)
        XCTAssertNil(migrated.state.partnerContracts)
        XCTAssertEqual(migrated.state.world.filter { $0.category == "Competitor" }.map(\.price), old.world.filter { $0.category == "Competitor" }.map(\.price))
    }
    func testAgreementChargesOnceAndCannotStackWithinCategory() throws {
        var engine = try fresh()
        let start = engine.state.cash
        let command = GameCommand(businessID: engine.state.id, day: 0, action: .community("supplier-bulk"))
        XCTAssertTrue(engine.apply(command).applied)
        XCTAssertTrue(engine.apply(command).applied)
        XCTAssertEqual(engine.state.cash, start - 1000)
        XCTAssertFalse(engine.perform(.community("supplier-bulk")).applied)
        XCTAssertEqual(engine.state.supplyDiscount, 15)
        apply(.community("supplier-local"), to: &engine)
        XCTAssertEqual(engine.state.cash, start - 1000 - 6000)
        XCTAssertEqual(engine.state.supplyDiscount, 5)
        XCTAssertEqual(engine.state.partnerContracts?.count, 1)
        XCTAssertNil(engine.state.eventLastDays["partner-supplier-bulk"])
    }
    func testAgreementExpiresAfterThirtyDaysWithoutRenewalCharge() throws {
        var engine = try fresh()
        apply(.community("supplier-bulk"), to: &engine)
        engine.state.day = 29; XCTAssertEqual(engine.state.supplyDiscount, 15)
        let agreementEntries = engine.state.ledger.filter { $0.description.hasPrefix("30-day agreement") }.count
        apply(.nextDay, to: &engine)
        XCTAssertNil(engine.state.activePartner("Supplier")); XCTAssertEqual(engine.state.supplyDiscount, 0)
        XCTAssertEqual(engine.state.ledger.filter { $0.description.hasPrefix("30-day agreement") }.count, agreementEntries)
        apply(.community("supplier-bulk"), to: &engine)
        XCTAssertEqual(engine.state.activePartner("Supplier")?.startDay, 30)
    }
    func testCancellingAgreementStopsBenefitsWithoutRefund() throws {
        var engine = try fresh(); apply(.community("supplier-bulk"), to: &engine)
        let cash = engine.state.cash
        apply(.endPartnership("Supplier"), to: &engine)
        XCTAssertEqual(engine.state.cash, cash); XCTAssertEqual(engine.state.supplyDiscount, 0)
        XCTAssertNil(engine.state.eventLastDays["partner-supplier-bulk"])
        XCTAssertFalse(engine.perform(.endPartnership("Supplier")).applied)
    }
    func testAgreementSnapshotAndIdentifiersSurviveSave() throws {
        var engine = try fresh(); apply(.community("vets"), to: &engine)
        let saved = try JSONDecoder().decode(BusinessState.self, from: JSONEncoder().encode(engine.state))
        let restored = try GameEngine(state: saved, catalog: engine.catalog)
        XCTAssertEqual(restored.state.partnerContracts, engine.state.partnerContracts)
        XCTAssertEqual(restored.state.activePartner("Vet")?.terms.fee, 4500)
    }
    func testInvalidAgreementIsRejectedWithoutCrashing() throws {
        var engine = try fresh(); apply(.community("vets"), to: &engine)
        engine.state.partnerContracts?["Vet"]?.startDay = -1
        XCTAssertThrowsError(try GameEngine(state: engine.state, catalog: engine.catalog))
        engine.state.partnerContracts?["Vet"]?.startDay = 0
        engine.state.partnerContracts?["Vet"]?.terms.supplyDiscount = 101
        XCTAssertThrowsError(try GameEngine(state: engine.state, catalog: engine.catalog))
    }
    func testSupplierDiscountAffectsRealCareLedger() throws {
        var engine = try customerGame(); apply(.community("supplier-bulk"), to: &engine)
        let dog = engine.state.dogs[0].id
        apply(.checkIn(dog), to: &engine); apply(.care(dog), to: &engine); apply(.checkOut(dog), to: &engine)
        let supplies = try XCTUnwrap(engine.state.ledger.last { $0.description.hasPrefix("Care supplies:") })
        XCTAssertEqual(supplies.amount, -(engine.catalog.economy.dailySuppliesPerDog * 85 / 100))
    }
    func testTrainerDiscountAffectsRealCourseCharge() throws {
        var engine = try fresh(); apply(.community("trainer-specialist"), to: &engine)
        let member = engine.state.staff[0].id
        apply(.hire(member), to: &engine)
        let course = try XCTUnwrap(GameEngine.courses.first { !engine.state.staff[0].qualifications.contains($0) })
        let cash = engine.state.cash
        apply(.train(member, course), to: &engine)
        XCTAssertEqual(engine.state.cash, cash - 9000)
        XCTAssertEqual(engine.trainingPrice, 9000)
    }
    func testSupplierReliabilityHasExplicitBackupCost() throws {
        var engine = try fresh(); apply(.community("supplier-bulk"), to: &engine)
        engine.state.partnerContracts?["Supplier"]?.terms.reliability = 0
        let cash = engine.state.cash
        engine.partnerDailyConsequences(attendance: 2)
        XCTAssertEqual(engine.state.cash, cash - 1000)
        XCTAssertTrue(engine.state.messages.last!.body.contains("local top-up"))
        engine.state.partnerContracts?["Supplier"]?.terms.reliability = 100
        engine.partnerDailyConsequences(attendance: 2)
        XCTAssertEqual(engine.state.cash, cash - 1000)
    }
    func testPartnerSupportIsCappedAndDoesNotReplaceOpeningRequirements() throws {
        var engine = try fresh()
        apply(.community("vets"), to: &engine); apply(.community("community-settling"), to: &engine)
        XCTAssertEqual(engine.state.partnerCareSupport, 1)
        XCTAssertFalse(engine.perform(.open).applied)
        apply(.community("groomer-boutique"), to: &engine)
        apply(.community("trainer"), to: &engine)
        XCTAssertEqual(engine.state.partnerReferralStrength, 3)
    }
    func testOpeningJourneyUsesActualReadiness() throws {
        var engine = try fresh()
        XCTAssertEqual(engine.state.openingStages.map(\.id), ["registration", "space", "boundary", "essentials", "approval", "opening"])
        XCTAssertEqual(engine.state.openingStages.first { !$0.complete }?.id, "registration")
        apply(.register, to: &engine)
        XCTAssertEqual(engine.state.openingStages.first { !$0.complete }?.id, "space")
        let opened = try ready()
        XCTAssertTrue(opened.state.openingStages.allSatisfy(\.complete))
        XCTAssertEqual(opened.state.loan.principal, 0)
    }
    func testGridDescriptionsNameEmptyBoundaryAndBothStarterRooms() throws {
        var engine = try fresh()
        var area = engine.state.areas[0]
        XCTAssertEqual(engine.state.squareDescription(area: area, row: 0, column: 0, catalog: engine.catalog), "A1. Empty.")
        XCTAssertTrue(engine.state.squareDescription(area: area, row: 3, column: 1, catalog: engine.catalog).contains("two customisable rooms"))
        XCTAssertTrue(engine.state.areas.contains { $0.id == "room1" })
        XCTAssertTrue(engine.state.areas.contains { $0.id == "room2" })
        apply(.build("fence", "outdoor", 0, 0), to: &engine)
        area = engine.state.areas[0]
        let text = engine.state.squareDescription(area: area, row: 0, column: 0, catalog: engine.catalog)
        XCTAssertTrue(text.hasPrefix("A1.")); XCTAssertTrue(text.lowercased().contains("fence")); XCTAssertTrue(text.contains("boundary"))
    }
    func testGridDescribesAllLayersAndFullFootprint() throws {
        var engine = try fresh()
        apply(.floorRoom("room2"), to: &engine); apply(.build("water", "room2", 0, 0), to: &engine)
        let area = engine.state.areas[2]
        let text = engine.state.squareDescription(area: area, row: 0, column: 0, catalog: engine.catalog)
        XCTAssertTrue(text.contains("Water bowl")); XCTAssertTrue(text.contains("Washable floor"))
        let large = try XCTUnwrap(engine.catalog.items.first { $0.width > 1 && $0.layer != .building && $0.outdoors })
        apply(.build(large.id, "outdoor", 1, 1), to: &engine)
        let grounds = engine.state.areas[0]
        let footprint = engine.state.squareDescription(area: grounds, row: 1, column: 2, catalog: engine.catalog)
        XCTAssertTrue(footprint.contains(large.name)); XCTAssertTrue(footprint.contains("starts at B2"))
    }
    func testGridMoveKeepsIDAndRejectsOverlapWithoutCharge() throws {
        var engine = try fresh()
        apply(.build("water", "room2", 0, 0), to: &engine)
        apply(.build("bed", "room2", 0, 1), to: &engine)
        let object = engine.state.areas[2].items[0]
        let cash = engine.state.cash
        XCTAssertFalse(engine.perform(.move(object.id, "room2", 0, 1)).applied)
        XCTAssertEqual(engine.state.cash, cash)
        apply(.move(object.id, "room2", 1, 0), to: &engine)
        XCTAssertEqual(engine.state.areas[2].items[0].id, object.id)
        XCTAssertEqual(engine.state.areas[2].items[0].row, 1)
        XCTAssertEqual(engine.state.cash, cash)
        XCTAssertTrue(engine.state.history.last!.text.contains("A2"))
        apply(.remove(object.id, "room2"), to: &engine)
        XCTAssertEqual(engine.state.cash, cash + (try engine.catalog.item("water").price / 4))
    }
    func testGridGateQuoteMatchesChargeAndKeepsGateDescription() throws {
        var engine = try fresh(); apply(.build("fence", "outdoor", 0, 0), to: &engine)
        let gate = try engine.catalog.item("gate")
        let quote = engine.state.placementPrice(gate, area: engine.state.areas[0], row: 0, column: 0, catalog: engine.catalog)
        XCTAssertEqual(quote, gate.price - (try engine.catalog.item("fence").price))
        let cash = engine.state.cash
        apply(.build("gate", "outdoor", 0, 0), to: &engine)
        XCTAssertEqual(engine.state.cash, cash - quote)
        XCTAssertEqual(engine.state.areas[0].items.count, 1)
        XCTAssertTrue(engine.state.squareDescription(area: engine.state.areas[0], row: 0, column: 0, catalog: engine.catalog).lowercased().contains("gate, boundary"))
    }
    func testEquipmentUsesRealisticPlacementLanguage() throws {
        var engine = try fresh()
        for (id, verb) in [("water","Place"), ("bed","Place"), ("fence","Build"), ("gate","Build"), ("floor","Fit"), ("washer","Install"), ("garden","Plant"), ("path","Lay")] {
            XCTAssertEqual(try engine.catalog.item(id).placementVerb, verb)
        }
        let receipt = engine.perform(.build("water", "room2", 0, 0))
        XCTAssertTrue(receipt.applied); XCTAssertEqual(receipt.message, "Placed water bowl at A1.")
        XCTAssertTrue(engine.state.ledger.last!.description.hasPrefix("Placed"))
    }
}
