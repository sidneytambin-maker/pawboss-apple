import XCTest

final class PawBossUITests: XCTestCase {
    func launch(seed: Bool = false, large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-test-game"]
        if seed { app.launchArguments.append("--seed-business") }
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch(); return app
    }
    func screenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testFirstRunAndNewBusiness() {
        let app = launch()
        XCTAssertTrue(app.buttons["New Business"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Continue"].isEnabled)
        screenshot("first-run", app: app)
        app.buttons["New Business"].tap()
        app.textFields["businessName"].tap(); app.textFields["businessName"].typeText("Meadow Care")
        app.textFields["ownerName"].tap(); app.textFields["ownerName"].typeText("Sam")
        app.buttons["Create Business"].tap()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Meadow Care"].exists)
        screenshot("new-business-today", app: app)
    }
    func testFiveTabsAndOfficeHierarchy() {
        let app = launch(seed: true)
        for title in ["Today", "Office", "Dogs", "Premises", "More"] { XCTAssertTrue(app.tabBars.buttons[title].exists) }
        app.tabBars.buttons["Office"].tap()
        XCTAssertTrue(app.buttons["Staff and Recruitment"].exists)
        app.buttons["Staff and Recruitment"].tap()
        XCTAssertTrue(app.buttons["Recruitment"].waitForExistence(timeout: 5))
        screenshot("staff", app: app)
    }
    func testPremisesHasNonDragCoordinateControls() {
        let app = launch(seed: true)
        app.tabBars.buttons["Premises"].tap()
        app.swipeUp()
        let area = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Room two")).firstMatch
        XCTAssertTrue(area.waitForExistence(timeout: 5)); area.tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["selectedSquare"].waitForExistence(timeout: 5))
        screenshot("premises-coordinate-editor", app: app)
    }
    func testLargeTextDashboardAccessibility() throws {
        let app = launch(seed: true, large: true)
        screenshot("today-accessibility-xxxlarge", app: app)
        try app.performAccessibilityAudit(for: [.contrast, .elementDetection, .hitRegion, .sufficientElementDescription, .trait])
    }
    func testMainMenuReturnsWithoutLosingBusiness() {
        let app = launch(seed: true)
        app.tabBars.buttons["More"].tap(); app.swipeUp()
        app.buttons["Main Menu"].tap()
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Continue"].isEnabled)
    }
    func testDogCareIsSavedAcrossRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-test-game", "--seed-care-business"]
        app.launch()
        app.tabBars.buttons["Dogs"].tap()
        let dog = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "dog-row-")).firstMatch
        XCTAssertTrue(dog.waitForExistence(timeout: 10)); dog.tap()
        XCTAssertTrue(app.buttons["Check In"].waitForExistence(timeout: 5)); app.buttons["Check In"].tap()
        XCTAssertTrue(app.buttons["Check Out"].waitForExistence(timeout: 5))
        screenshot("dog-care-record", app: app)
        app.terminate(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 10)); app.buttons["Continue"].tap()
        app.tabBars.buttons["Dogs"].tap(); dog.tap()
        XCTAssertTrue(app.buttons["Check Out"].waitForExistence(timeout: 5))
    }
    func testReportsContainChartAndSemanticValues() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-test-game", "--seed-care-business"]
        app.launch(); app.tabBars.buttons["More"].tap(); app.buttons["Reports"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["businessTrend"].waitForExistence(timeout: 10))
        screenshot("business-reports", app: app)
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait])
        app.swipeUp()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Care revenue.")).firstMatch.exists)
    }
    func testDarkAppearanceAndAudioSettings() throws {
        let app = launch(seed: true)
        app.tabBars.buttons["More"].tap()
        app.buttons["Settings and Sync"].tap()
        app.buttons["appearancePicker"].tap()
        app.buttons["Dark"].tap()
        screenshot("settings-dark", app: app)
        try app.performAccessibilityAudit(for: [.contrast, .sufficientElementDescription, .trait])
        app.swipeUp()
        XCTAssertTrue(app.sliders.matching(NSPredicate(format: "label CONTAINS %@", "volume")).count > 0)
        screenshot("settings-audio", app: app)
    }
}
