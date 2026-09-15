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
        var deferred = Set<String>()
        var checked = Set<String>()
        for _ in 0..<16 {
            let viewport = app.frame
            let bars = app.tabBars.allElementsBoundByIndex.map(\.frame) + app.navigationBars.allElementsBoundByIndex.map(\.frame) + XCUIApplication(bundleIdentifier: "com.apple.springboard").statusBars.allElementsBoundByIndex.map(\.frame)
            let headings = ["todayCareHeading", "businessPulseHeading"].map { app.staticTexts[$0] }.filter(\.exists).map { (id: $0.identifier, frame: $0.frame) }
            func obscured(_ frame: CGRect, identifier: String) -> Bool {
                !viewport.contains(frame) || bars.contains(where: { $0.intersects(frame) }) || headings.contains(where: { $0.id != identifier && $0.frame.intersects(frame) })
            }
            let visibleLabels = app.staticTexts.allElementsBoundByIndex.filter { element in
                let frame = element.frame
                return !frame.isEmpty && !obscured(frame, identifier: element.identifier)
            }.map(\.label)
            for attempt in 0..<3 {
                do {
                    try app.performAccessibilityAudit(for: [.contrast, .elementDetection, .hitRegion, .sufficientElementDescription, .trait]) { issue in
                        // Use captured geometry: live queries inside the callback can time out
                        // Apple's audit service. Every deferred label must pass in full view.
                        if issue.auditType == .contrast, let element = issue.element,
                           obscured(element.frame, identifier: element.identifier), !element.label.isEmpty {
                            deferred.insert(element.label)
                            return true
                        }
                        return false
                    }
                    break
                } catch {
                    let failure = error as NSError
                    guard failure.domain == "com.apple.xcode.xctest.accessibilityAudit", failure.code == -56, attempt < 2 else { throw error }
                    print("Apple audit service timed out; repeating the complete audit, attempt \(attempt + 2).")
                    Thread.sleep(forTimeInterval: 1)
                }
            }
            checked.formUnion(visibleLabels)
            deferred.subtract(checked)
            if deferred.isEmpty { break }
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(deferred.isEmpty, "Obscured text was not subsequently audited in full view: \(deferred)")
        screenshot("today-large-text-audited", app: app)
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
        try app.performAccessibilityAudit(for: [.contrast, .sufficientElementDescription, .trait])
        let revenue = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Care revenue.")).firstMatch
        for _ in 0..<5 {
            if revenue.exists && revenue.isHittable { break }
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(revenue.exists)
        XCTAssertTrue(revenue.isHittable)
        XCTAssertTrue(revenue.label.contains("£"))
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
    func testHalfVolumeAndIndividualSoundPreviews() {
        let app = launch(seed: true)
        app.tabBars.buttons["More"].tap(); app.buttons["Settings and Sync"].tap()
        let music = app.sliders["volume-Music"]
        for _ in 0..<5 {
            if music.exists && music.isHittable { break }
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(music.exists)
        XCTAssertTrue(String(describing: music.value ?? "").contains("50"))
        music.adjust(toNormalizedSliderPosition: 0.8)
        XCTAssertFalse(String(describing: music.value ?? "").contains("50"))
        let library = app.buttons["Sound Library"]
        for _ in 0..<8 {
            if library.exists && library.isHittable { break }
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(library.isHittable); library.tap()
        let preview = app.buttons["preview-music-town"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5)); preview.tap()
        XCTAssertTrue(app.buttons["stopAudioPreview"].exists); app.buttons["stopAudioPreview"].tap()
        screenshot("individual-audio-library", app: app)
    }
}
