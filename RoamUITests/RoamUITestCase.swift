import XCTest

/// Base class for fixture-mode UI journeys. Screenshots are attached with stable names and
/// exported to screenshots/<milestone>/ by scripts/export-screenshots.sh.
class RoamUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// `resetState: false` keeps this simulator's account-scoped drafts from the previous launch
    /// (the in-memory fixture backend itself always starts from its seed).
    func launch(account: String? = "maya", scenario: String = "default", tab: String? = nil, latency: Int = 0,
                location: String? = nil, resetState: Bool = true, extra: [String] = []) {
        app = XCUIApplication()
        var arguments = ["-roam-backend", "fixture", "-roam-ui-testing", "-roam-fixture-scenario", scenario]
        if resetState { arguments.append("-roam-reset-state") }
        if let account { arguments += ["-roam-fixture-account", account] }
        if let tab { arguments += ["-roam-initial-tab", tab] }
        if latency > 0 { arguments += ["-roam-fixture-latency", String(latency)] }
        if let location { arguments += ["-roam-location", location] }
        app.launchArguments = arguments + extra
        app.launch()
    }

    /// Attaches a full-screen screenshot named `<milestone>-<name>`.
    func capture(_ name: String, settle: TimeInterval = 0.6) {
        if settle > 0 { Thread.sleep(forTimeInterval: settle) }
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func tab(_ title: String) -> XCUIElement {
        app.tabBars.buttons[title].firstMatch
    }

    /// Search, Explore and Profile open from For You's navigation bar.
    func openFromForYou(_ identifier: String) {
        tab("For You").tap()
        element(identifier).tap()
    }

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @discardableResult
    func waitFor(_ element: XCUIElement, timeout: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing \(element)", file: file, line: line)
        return element
    }

    func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, "Still visible: \(element)", file: file, line: line)
    }
}
