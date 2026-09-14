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
        app.launch(); openMenu(app); app.buttons["Dogs"].tap()
        let dog = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "dog-row-")).firstMatch
        XCTAssertTrue(dog.waitForExistence(timeout: 10)); dog.tap()
        app.swipeUp()
        XCTAssertTrue(app.buttons["Check In"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "watch-dog-care"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
