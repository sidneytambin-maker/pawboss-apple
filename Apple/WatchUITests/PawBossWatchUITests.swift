import XCTest

final class PawBossWatchUITests: XCTestCase {
    func launch(seed: Bool) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reset-test-game"]
        if seed { app.launchArguments.append("--seed-business") }
        app.launch(); return app
    }
    func testWaitingStateHasRefreshNotFakeBusiness() {
        let app = launch(seed: false)
        XCTAssertTrue(app.buttons["Refresh Sync"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Meadow Care"].exists)
    }
    func testMenuHasSubstantialSections() {
        let app = launch(seed: true)
        XCTAssertTrue(app.buttons["Menu"].waitForExistence(timeout: 10)); app.buttons["Menu"].tap()
        XCTAssertTrue(app.buttons["Today"].exists); XCTAssertTrue(app.buttons["Office"].exists)
        app.swipeUp()
        XCTAssertTrue(app.buttons["Finance"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "watch-menu"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testOfficeOpensEnquiries() {
        let app = launch(seed: true)
        app.buttons["Menu"].tap(); app.buttons["Office"].tap()
        XCTAssertTrue(app.buttons["Enquiries and Quotes"].waitForExistence(timeout: 5))
        app.buttons["Enquiries and Quotes"].tap()
        XCTAssertTrue(app.switches["Include handled enquiries"].waitForExistence(timeout: 5))
    }
}
