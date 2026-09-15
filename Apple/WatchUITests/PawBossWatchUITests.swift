import XCTest

final class PawBossWatchUITests: XCTestCase {
    func launch(seed: Bool) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reset-test-game"]
        if seed { app.launchArguments.append("--seed-business") }
        app.launch(); return app
    }
    func openMenu(_ app: XCUIApplication) {
        // watchOS exposes nested native toolbar wrappers for the same visible button.
        let menu = app.navigationBars.buttons.matching(identifier: "watchMenu").firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10)); menu.tap()
        XCTAssertTrue(app.buttons["Office"].waitForExistence(timeout: 10))
    }
    func reach(_ element: XCUIElement, in app: XCUIApplication, attempts: Int = 30) {
        for _ in 0..<attempts {
            if element.exists && element.isHittable { return }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.80))
            start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.62)))
        }
        XCTAssertTrue(element.exists && element.isHittable, "Control not reached: \(element)")
    }
    func testWatchPremisesSquaresOpenItemCatalogue() {
        let app = launch(seed: true); openMenu(app)
        let more = app.buttons["More"]; reach(more, in: app); more.tap()
        let premises = app.buttons["Premises"]; reach(premises, in: app); premises.tap()
        let room = app.buttons["roomLink-room2"]; reach(room, in: app); room.tap()
        let square = app.buttons["square-room2-0-0"]; reach(square, in: app)
        XCTAssertEqual(square.label, "A1. Empty.")
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "watch-room-grid"; attachment.lifetime = .keepAlways; add(attachment)
        square.tap()
        let addItem = app.buttons["addItem"]; reach(addItem, in: app); addItem.tap()
        let water = app.buttons["catalogue-water"]; reach(water, in: app); water.tap()
        let purchase = app.buttons["purchaseItem"]; reach(purchase, in: app)
        XCTAssertTrue(purchase.label.contains("Place"))
    }
    func testWaitingStateHasRefreshNotFakeBusiness() {
        let app = launch(seed: false)
        XCTAssertTrue(app.buttons["Refresh Sync"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Meadow Care"].exists)
    }
    func testMenuHasSubstantialSections() {
        let app = launch(seed: true)
        openMenu(app)
        XCTAssertTrue(app.buttons["Today"].exists); XCTAssertTrue(app.buttons["Office"].exists)
        app.swipeUp()
        XCTAssertTrue(app.buttons["Finance"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "watch-menu"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testOfficeOpensEnquiries() {
        let app = launch(seed: true)
        openMenu(app); app.buttons["Office"].tap()
        XCTAssertTrue(app.buttons["Enquiries and Quotes"].waitForExistence(timeout: 5))
        app.buttons["Enquiries and Quotes"].tap()
        XCTAssertTrue(app.switches["Include handled enquiries"].waitForExistence(timeout: 5))
    }
    func testDogCareActionsAreAvailableOnWatch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-test-game", "--seed-care-business"]
        app.launch(); openMenu(app)
        let dogs = app.buttons["Dogs"]
        for _ in 0..<4 {
            if dogs.exists && dogs.isHittable { break }
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(dogs.exists); dogs.tap()
        let dog = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "dog-row-")).firstMatch
        XCTAssertTrue(dog.waitForExistence(timeout: 10)); dog.tap()
        let checkIn = app.buttons["Check In"]
        for _ in 0..<6 {
            if checkIn.exists && checkIn.isHittable { break }
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(checkIn.exists); XCTAssertTrue(checkIn.isHittable)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "watch-dog-care"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testWatchAudioDefaultsAndPreviews() {
        let app = launch(seed: true)
        openMenu(app)
        let more = app.buttons["More"]; reach(more, in: app); more.tap()
        let settings = app.buttons["Settings and Sync"]; reach(settings, in: app); settings.tap()
        let music = app.sliders["volume-Music"]; reach(music, in: app)
        XCTAssertTrue(String(describing: music.value ?? "").contains("50"))
        let library = app.buttons["Sound Library"]; reach(library, in: app); library.tap()
        XCTAssertTrue(app.buttons["stopAudioPreview"].waitForExistence(timeout: 5))
        let preview = app.buttons["preview-music-town"]; reach(preview, in: app); preview.tap()
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "watch-audio-library"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
