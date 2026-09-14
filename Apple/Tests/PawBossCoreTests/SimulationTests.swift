import XCTest
@testable import PawBossCore

final class SimulationTests: XCTestCase {
    func fresh() throws -> GameEngine {
        let catalog = try Catalog.bundled()
        return try GameEngine(state: catalog.newBusiness(name: "Meadow Care", owner: "Sam", title: "Owner", seed: 42), catalog: catalog)
    }
    func apply(_ action: GameAction, to engine: inout GameEngine, file: StaticString = #filePath, line: UInt = #line) {
        let result = engine.perform(action)
        XCTAssertTrue(result.applied, result.message, file: file, line: line)
    }
    func ready() throws -> GameEngine {
        var engine = try fresh()
        for action: GameAction in [.register, .configureRoom("room1", .reception), .configureRoom("room2", .multipurpose), .floorRoom("room2"), .buildBoundary, .build("gate", "outdoor", 0, 1), .build("bed", "room2", 0, 0), .build("water", "room2", 0, 1), .build("toys", "room2", 0, 2), .build("cleaning", "room1", 0, 0), .build("firstaid", "room1", 0, 1), .insure, .applyLicence, .requestInspection, .nextDay, .nextDay, .open] { apply(action, to: &engine) }
        return engine
    }
    func customerGame() throws -> GameEngine {
        var engine = try ready()
        engine.generateEnquiry(source: "Test campaign")
        apply(.decideEnquiry(engine.state.enquiries[0].id, "accept"), to: &engine)
        apply(.nextDay, to: &engine)
        return engine
    }
    func testStartsEmptyAndDebtFree() throws {
        let engine = try fresh()
        XCTAssertTrue(engine.state.dogs.isEmpty); XCTAssertTrue(engine.state.customers.isEmpty)
        XCTAssertTrue(engine.state.bookings.isEmpty); XCTAssertEqual(engine.state.loan.principal, 0)
        XCTAssertEqual(engine.weeklyPayroll, 0); XCTAssertFalse(engine.state.isOpen)
    }
    func testOpeningWithoutLoanAndCashReserve() throws {
        let engine = try ready()
        XCTAssertTrue(engine.state.isOpen); XCTAssertTrue(engine.state.readiness().allSatisfy(\.complete))
        XCTAssertEqual(engine.state.loan.principal, 0); XCTAssertGreaterThan(engine.state.cash, 400000)
    }
    func testInspectionNotInstantAndFailureExplained() throws {
        var engine = try fresh()
        apply(.register, to: &engine); apply(.applyLicence, to: &engine); apply(.requestInspection, to: &engine)
        XCTAssertFalse(engine.state.licenceValid)
        apply(.nextDay, to: &engine); XCTAssertFalse(engine.state.licenceValid)
        apply(.nextDay, to: &engine); XCTAssertEqual(engine.state.licence.result, "Requires improvement")
        XCTAssertFalse(engine.state.licence.findings.isEmpty)
        XCTAssertFalse(engine.perform(.open).applied)
    }
    func testRepeatCommandHasExactlyOneFinancialEffect() throws {
        var engine = try fresh()
        let command = GameCommand(businessID: engine.state.id, day: 0, action: .register)
        let first = engine.apply(command); let cash = engine.state.cash
        let second = engine.apply(command)
        XCTAssertEqual(first.id, second.id); XCTAssertEqual(engine.state.cash, cash)
        XCTAssertEqual(engine.state.receipts.count, 1)
    }
    func testDifferentRepeatedRegistrationAlsoRejected() throws {
        var engine = try fresh(); apply(.register, to: &engine)
        let cash = engine.state.cash
        XCTAssertFalse(engine.perform(.register).applied); XCTAssertEqual(engine.state.cash, cash)
    }
    func testStaleWatchDayRejectedWithoutMoneyChange() throws {
        var engine = try fresh()
        let command = GameCommand(businessID: engine.state.id, day: 0, action: .register)
        apply(.nextDay, to: &engine)
        let cash = engine.state.cash
        XCTAssertFalse(engine.apply(command).applied); XCTAssertEqual(engine.state.cash, cash)
    }
    func testWrongBusinessRejected() throws {
        var engine = try fresh()
        XCTAssertFalse(engine.apply(GameCommand(businessID: UUID(), day: 0, action: .register)).applied)
        XCTAssertFalse(engine.state.licence.registered)
    }
    func testNoPhantomIncomeForEmptyBusiness() throws {
        var engine = try ready()
        for _ in 0..<35 { apply(.nextDay, to: &engine) }
        XCTAssertTrue(engine.state.reports.allSatisfy { $0.attendance == 0 && $0.revenue == 0 })
        XCTAssertLessThan(engine.state.cash, 750000)
    }
    func testEnquiryCannotBeAcceptedTwice() throws {
        var engine = try ready(); engine.generateEnquiry(source: "Local marketing")
        let id = engine.state.enquiries[0].id
        apply(.decideEnquiry(id, "accept"), to: &engine)
        XCTAssertFalse(engine.perform(.decideEnquiry(id, "accept")).applied)
        XCTAssertEqual(engine.state.dogs.count, 1); XCTAssertEqual(engine.state.customers.count, 1)
        XCTAssertTrue(engine.state.pendingEnquiries.isEmpty)
    }
    func testInformationRequestWaitsForReply() throws {
        var engine = try fresh(); engine.generateEnquiry(source: "Local marketing")
        let id = engine.state.enquiries[0].id
        apply(.decideEnquiry(id, "information"), to: &engine); XCTAssertTrue(engine.state.pendingEnquiries.isEmpty)
        apply(.nextDay, to: &engine); XCTAssertEqual(engine.state.pendingEnquiries.count, 1)
    }
    func testDeclineCannotBeReaccepted() throws {
        var engine = try ready(); engine.generateEnquiry(source: "Local marketing")
        let id = engine.state.enquiries[0].id
        apply(.decideEnquiry(id, "decline"), to: &engine)
        XCTAssertFalse(engine.perform(.decideEnquiry(id, "accept")).applied)
    }
    func testUniqueGeneratedIdentitiesAndOwners() throws {
        var engine = try fresh()
        for _ in 0..<200 { engine.generateEnquiry(source: "Population test") }
        XCTAssertEqual(Set(engine.state.enquiries.map { $0.customer.id }).count, 200)
        XCTAssertEqual(Set(engine.state.enquiries.map { $0.customer.name }).count, 200)
        XCTAssertEqual(Set(engine.state.enquiries.map { $0.dog.name }).count, 200)
        XCTAssertTrue(engine.state.enquiries.allSatisfy { $0.dog.ownerID == $0.customer.id })
    }
    func testFailedAcceptanceRollsBackDogAndCustomer() throws {
        var engine = try ready(); engine.generateEnquiry(source: "Local marketing")
        engine.state.ownerOnDuty = false
        XCTAssertFalse(engine.perform(.decideEnquiry(engine.state.enquiries[0].id, "accept")).applied)
        XCTAssertTrue(engine.state.dogs.isEmpty); XCTAssertTrue(engine.state.customers.isEmpty)
    }
    func testQuoteAndBookingKeepAgreedPrice() throws {
        var engine = try ready(); engine.generateEnquiry(source: "Local marketing")
        let enquiry = engine.state.enquiries[0]
        apply(.decideEnquiry(enquiry.id, "quote"), to: &engine)
        let quote = engine.state.enquiries[0].quote
        apply(.setPrice(enquiry.service, 8000), to: &engine)
        apply(.decideEnquiry(enquiry.id, "accept"), to: &engine)
        XCTAssertEqual(engine.state.bookings[0].price, quote)
    }
    func testCapacityPreventsOverselling() throws {
        var engine = try ready()
        for _ in 0..<5 { engine.generateEnquiry(source: "Local marketing") }
        for e in engine.state.enquiries.prefix(4) { apply(.decideEnquiry(e.id, "accept"), to: &engine) }
        XCTAssertFalse(engine.perform(.decideEnquiry(engine.state.enquiries[4].id, "accept")).applied)
        XCTAssertEqual(engine.state.bookings.count, 4)
    }
    func testCareCheckoutAndRepeatDoNotDuplicatePayment() throws {
        var engine = try customerGame(); let id = engine.state.dogs[0].id
        apply(.checkIn(id), to: &engine); apply(.care(id), to: &engine); apply(.checkOut(id), to: &engine)
        let cash = engine.state.cash
        XCTAssertFalse(engine.perform(.checkOut(id)).applied); XCTAssertEqual(engine.state.cash, cash)
        XCTAssertEqual(engine.state.dogs[0].attendedDays.count, 1)
    }
    func testMedicationCannotBeGivenTwice() throws {
        var engine = try customerGame(); let id = engine.state.dogs[0].id
        let med = Medication(name: "Test medicine", instructions: "Game prescription", dueDay: engine.state.day)
        engine.state.dogs[0].medications = [med]
        apply(.checkIn(id), to: &engine); apply(.medication(id, med.id), to: &engine)
        XCTAssertFalse(engine.perform(.medication(id, med.id)).applied)
        XCTAssertEqual(engine.state.dogs[0].medications[0].givenDays.count, 1)
    }
    func testPoorCareDoesNotRetainIncome() throws {
        var engine = try customerGame(); let id = engine.state.dogs[0].id
        engine.state.dogs[0].welfare = 35
        apply(.checkIn(id), to: &engine); apply(.checkOut(id), to: &engine)
        XCTAssertEqual(engine.state.bookings[0].refunded, engine.state.bookings[0].price)
        XCTAssertTrue(engine.state.messages.contains { $0.kind == .complaint })
    }
    func testBoundaryBuilderKeepsGateAndChargesOnlyMissing() throws {
        var engine = try fresh()
        apply(.build("fence", "outdoor", 0, 0), to: &engine)
        apply(.build("gate", "outdoor", 0, 0), to: &engine)
        let cash = engine.state.cash
        apply(.buildBoundary, to: &engine)
        XCTAssertEqual(cash - engine.state.cash, 35 * 2500)
        XCTAssertTrue(engine.state.secureBoundary)
        XCTAssertFalse(engine.perform(.buildBoundary).applied)
    }
    func testLayeredFloorAndBedSpeakOnlyTopObject() throws {
        var engine = try fresh()
        apply(.build("floor", "room2", 0, 0), to: &engine)
        apply(.build("bed", "room2", 0, 0), to: &engine)
        let area = engine.state.areas[2]
        XCTAssertEqual(engine.state.squareDescription(area: area, row: 0, column: 0, catalog: engine.catalog), "A1. Dog bed.")
    }
    func testInvalidPlacementNeverSpends() throws {
        var engine = try fresh(); let cash = engine.state.cash
        XCTAssertFalse(engine.perform(.build("fence", "outdoor", 5, 5)).applied)
        XCTAssertFalse(engine.perform(.build("bed", "room2", 4, 4)).applied)
        XCTAssertFalse(engine.perform(.build("shade", "outdoor", 9, 9)).applied)
        XCTAssertEqual(engine.state.cash, cash)
    }
    func testBoundaryTransactionRollsBackWhenUnaffordable() throws {
        var engine = try fresh(); engine.post(-700000, "Test investment", kind: .investment)
        let cash = engine.state.cash
        XCTAssertFalse(engine.perform(.buildBoundary).applied)
        XCTAssertTrue(engine.state.areas[0].items.isEmpty); XCTAssertEqual(engine.state.cash, cash)
    }
    func testHirePayDismissAndOwnerNotOnPayroll() throws {
        var engine = try fresh(); let id = engine.state.staff[0].id
        XCTAssertEqual(engine.weeklyPayroll, 0)
        apply(.hire(id), to: &engine); XCTAssertGreaterThan(engine.weeklyPayroll, 0)
        XCTAssertFalse(engine.perform(.hire(id)).applied)
        XCTAssertFalse(engine.perform(.pay(id, 100)).applied)
        apply(.pay(id, 1500), to: &engine); apply(.dismiss(id), to: &engine)
        XCTAssertEqual(engine.weeklyPayroll, 0)
    }
    func testLoanPrincipalIsNotIncomeOrOperatingExpense() throws {
        var engine = try fresh()
        apply(.borrow(100000), to: &engine); apply(.repay(10000), to: &engine); apply(.nextDay, to: &engine)
        XCTAssertEqual(engine.state.reports[0].revenue, 0); XCTAssertEqual(engine.state.reports[0].expenses, 0)
        XCTAssertEqual(engine.state.loan.principal, 90000)
    }
    func testAutosaveRoundTripAndReplay() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = FileBusinessRepository(directory: dir)
        var engine = try fresh()
        let command = GameCommand(businessID: engine.state.id, day: 0, action: .register)
        _ = engine.apply(command); try repo.save(engine.state)
        var loaded = try GameEngine(state: XCTUnwrap(repo.load()), catalog: engine.catalog)
        let cash = loaded.state.cash; _ = loaded.apply(command)
        XCTAssertEqual(loaded.state.cash, cash)
    }
    func testCorruptSaveDoesNotOverwriteGoodBackup() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = FileBusinessRepository(directory: dir)
        var engine = try fresh(); try repo.save(engine.state); apply(.register, to: &engine); try repo.save(engine.state)
        let backup = try Data(contentsOf: repo.backupURL)
        try Data("broken".utf8).write(to: repo.url)
        XCTAssertThrowsError(try repo.load()); XCTAssertThrowsError(try repo.save(engine.state))
        XCTAssertEqual(try Data(contentsOf: repo.backupURL), backup)
        XCTAssertFalse(try repo.recoverBackup().licence.registered)
    }
    func testFutureSaveVersionRejectedWithoutMigrationGuessing() throws {
        let state = try fresh().state
        var envelope = SaveEnvelope(business: state); envelope.version = 99
        XCTAssertThrowsError(try FileBusinessRepository.decode(JSONEncoder().encode(envelope)))
    }
    func testWatchQueueDurableAndOnlyMatchingReceiptRemovesCommand() throws {
        let state = try fresh().state
        let command = GameCommand(businessID: state.id, day: 0, action: .register)
        var outbox = WatchOutbox(); outbox.enqueue(command); outbox.enqueue(command)
        var loaded = try JSONDecoder().decode(WatchOutbox.self, from: JSONEncoder().encode(outbox))
        loaded.receive(Receipt(id: UUID(), applied: true, message: "Unrelated", revision: 1))
        XCTAssertEqual(loaded.pending.count, 1)
        loaded.receive(Receipt(id: command.id, applied: false, message: "Rejected safely", revision: 1))
        XCTAssertTrue(loaded.pending.isEmpty); XCTAssertFalse(loaded.results[0].applied)
    }
    func testDeterministicDaySimulation() throws {
        var a = try fresh(); var b = a
        for _ in 0..<100 { apply(.nextDay, to: &a); apply(.nextDay, to: &b) }
        XCTAssertEqual(a.state.cash, b.state.cash); XCTAssertEqual(a.state.weather, b.state.weather)
        XCTAssertEqual(a.state.generator, b.state.generator)
    }
}
