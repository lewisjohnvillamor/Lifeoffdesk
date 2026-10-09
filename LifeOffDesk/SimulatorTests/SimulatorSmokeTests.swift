import XCTest

final class SimulatorSmokeTests: XCTestCase {
    func testDemoPreviewReplayAndExit() {
        let app = XCUIApplication()
        app.launchArguments = ["--skip-intro"]
        app.launch()
        XCTAssertTrue(app.buttons["Layers"].waitForExistence(timeout: 15))
        app.buttons["Layers"].tap()
        XCTAssertTrue(app.buttons["Preview demo map"].waitForExistence(timeout: 5))
        app.buttons["Preview demo map"].tap()
        XCTAssertTrue(app.buttons["Replay a sample adventure"].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Synthetic demo map with fog"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Replay a sample adventure"].tap()
        XCTAssertTrue(app.staticTexts["Demo world"].waitForExistence(timeout: 5))
        app.buttons["Back to my map"].tap()
        XCTAssertTrue(app.buttons["Start exploring"].waitForExistence(timeout: 5))

    }

    func testPlannerFailurePreservesInputAndWalkingEntry() {
        let app = XCUIApplication()
        app.launchArguments = ["--skip-intro"]
        app.launch()
        XCTAssertTrue(app.buttons["Start exploring"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Simulator · no AI · simulated GPS"].exists)
        app.buttons["Help me choose somewhere"].tap()
        let request = app.textFields["Outing request"]
        XCTAssertTrue(request.waitForExistence(timeout: 5))
        request.tap()
        request.typeText("May 30 minutes ako, gusto ko ng park.")
        app.buttons["Ask"].tap()
        let failure = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "AI is unavailable in Simulator")).firstMatch
        XCTAssertTrue(failure.waitForExistence(timeout: 5))
        XCTAssertEqual(request.value as? String, "May 30 minutes ako, gusto ko ng park.")
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Start exploring"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Start exploring"].waitForExistence(timeout: 10))
    }

    func testIntroShowsOnceAndCanBeSkipped() {
        let app = XCUIApplication()
        app.launchArguments = ["--show-intro"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Every street you walk becomes your map."].waitForExistence(timeout: 10))
        app.buttons["Skip"].tap()
        XCTAssertTrue(app.buttons["Start exploring"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["Start exploring"].waitForExistence(timeout: 10), "Intro is shown only once")
    }

    func testSimulatorLaunchPerformance() {
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTApplicationLaunchMetric()], options: options) {
            let app = XCUIApplication()
            app.launchArguments = ["--skip-intro"]
            app.launch()
        }
    }
}
