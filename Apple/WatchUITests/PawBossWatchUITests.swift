import XCTest

final class PawBossWatchUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }
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
            // Native tap scrolls an existing offscreen control into view. Searching
            // beyond it can discard a lazily loaded row and miss it entirely.
            if element.exists { return }
            let content = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.scrollViews.firstMatch
            let surface = content.exists ? content : app.windows.element(boundBy: 0)
            let start = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            let end = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.15)
        }
        XCTAssertTrue(element.exists, "Control not found: \(element)")
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
        XCTAssertTrue(purchase.label.contains("Place")); purchase.tap()
        // The native Watch action controller keeps the title, not the SwiftUI ID.
        let confirmation = app.buttons.matching(identifier: "Confirm \u{00A3}10.00").firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5)); XCTAssertTrue(confirmation.isEnabled)
        app.buttons.matching(identifier: "AX_ActionContentControllerCancelButton").firstMatch.tap()
        XCTAssertFalse(confirmation.exists)
        XCTAssertTrue(purchase.waitForExistence(timeout: 5))
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
        for category in ["Music", "Ambience", "Dogs", "Customers", "Office", "Gameplay"] {
            let choice = app.buttons["volumeSettings-\(category)"]; reach(choice, in: app); choice.tap()
            let volume = app.sliders["volume-\(category)"]
            XCTAssertTrue(volume.waitForExistence(timeout: 5)); XCTAssertTrue(volume.isHittable)
            XCTAssertTrue(String(describing: volume.value ?? "").contains("50"), "Default volume for \(category)")
            XCTAssertTrue(app.buttons["Preview Sounds"].isHittable)
            if category == "Music" {
                let attachment = XCTAttachment(screenshot: app.screenshot())
                attachment.name = "watch-volume-control"; attachment.lifetime = .keepAlways; add(attachment)
            }
            app.navigationBars.buttons.matching(identifier: "BackButton").firstMatch.tap()
        }
        let library = app.buttons["Sound Library"]; reach(library, in: app); library.tap()
        XCTAssertTrue(app.buttons["stopAudioPreview"].waitForExistence(timeout: 5))
        let preview = app.buttons["preview-music-town"]; reach(preview, in: app); preview.tap()
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "watch-audio-library"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
