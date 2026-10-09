import XCTest

final class SimulatorSmokeTests: XCTestCase {
    func testDemoPreviewReplayAndExit() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Preview demo map"].waitForExistence(timeout: 15))
        app.buttons["Preview demo map"].tap()
        XCTAssertTrue(app.buttons["Replay a sample walk"].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Synthetic demo map with fog"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Replay a sample walk"].tap()
        XCTAssertTrue(app.staticTexts["Replay · sample walk, not real GPS"].waitForExistence(timeout: 5))
        app.buttons["Back to my map"].tap()
        XCTAssertTrue(app.buttons["Start walking"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Preview demo map"].exists)
    }

    func testPlannerFailurePreservesInputAndWalkingEntry() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Start walking"].waitForExistence(timeout: 20))
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
        XCTAssertTrue(app.buttons["Start walking"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Start walking"].waitForExistence(timeout: 10))
    }

    func testSimulatorLaunchPerformance() {
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTApplicationLaunchMetric()], options: options) {
            XCUIApplication().launch()
        }
    }
}
