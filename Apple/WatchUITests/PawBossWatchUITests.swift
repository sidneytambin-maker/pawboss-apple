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
        func reach(_ element: XCUIElement, attempts: Int = 14) {
            for _ in 0..<attempts {
                if element.exists && element.isHittable { return }
                app.swipeUp(velocity: .slow)
            }
            XCTAssertTrue(element.isHittable)
        }
        let more = app.buttons["More"]; reach(more); more.tap()
        let settings = app.buttons["Settings and Sync"]; reach(settings); settings.tap()
        let music = app.sliders["volume-Music"]; reach(music)
        XCTAssertTrue(String(describing: music.value ?? "").contains("50"))
        let library = app.buttons["Sound Library"]; reach(library); library.tap()
        XCTAssertTrue(app.buttons["stopAudioPreview"].waitForExistence(timeout: 5))
        let preview = app.buttons["preview-music-town"]; reach(preview); preview.tap()
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "watch-audio-library"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
