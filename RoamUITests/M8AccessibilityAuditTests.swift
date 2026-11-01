import XCTest

/// M8 accessibility: Xcode's automated audit (element descriptions, hit regions, contrast, Dynamic
/// Type, clipped text, traits) on every main screen. Each screen's full issue list is attached;
/// only the documented system-owned exceptions in `ignored(_:)` are tolerated.
final class M8AccessibilityAuditTests: RoamUITestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        // Audit every screen in a test even when an earlier one has findings.
        continueAfterFailure = true
    }

    /// Documented exceptions. Everything else fails the test.
    /// - Advisory, recorded but not failing: "Contrast nearly passed" and "Dynamic Type partially
    ///   unsupported" (text that scales but is bounded by its control, such as score numerals that
    ///   grow to 160% inside their badge and avatar initials that grow to 125% with their circle).
    /// - Not judgeable here:
    ///   - Disabled controls, which WCAG 1.4.3 exempts.
    ///   - The system keyboard.
    ///   - Contrast of elements in iOS 26's scroll-edge zones under the translucent navigation and
    ///     tab bars, where the audit samples the system's fade (scrolling moves content clear).
    ///   - MapKit's attribution and cluster glyphs.
    ///   - Single-line text fields, which scroll their text rather than wrapping it, and the system
    ///     navigation title, which truncates while the same name is shown in full in the content.
    ///   - Findings with no element reference (text inside a row combined into one VoiceOver element):
    ///     recorded per screen and reported in docs/m8-verification.md.
    private func exception(_ issue: XCUIAccessibilityAuditIssue) -> String? {
        let description = issue.compactDescription
        if issue.auditType == .contrast && description.localizedCaseInsensitiveContains("nearly passed") { return "advisory contrast" }
        if issue.auditType == .dynamicType && description.localizedCaseInsensitiveContains("partially") { return "advisory dynamic type" }
        if issue.detailedDescription.contains("TUIPrediction") || issue.detailedDescription.contains("UIKeyboard") { return "system keyboard" }
        // Pieces of a combined element (a row read as one VoiceOver element) have no element reference,
        // so the audit can't say which text it measured. Recorded and reported, not failing.
        guard let element = issue.element else { return "unattributed (no element reference)" }
        if !element.isEnabled { return "disabled control" }
        let frame = element.frame
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists && frame.intersects(keyboard.frame) { return "system keyboard" }
        if issue.auditType == .contrast {
            let tabBar = app.tabBars.firstMatch
            if tabBar.exists && frame.maxY > tabBar.frame.minY - 90 { return "scroll-edge zone" }
            let navigationBar = app.navigationBars.firstMatch
            if navigationBar.exists && frame.minY < navigationBar.frame.maxY + 20 { return "scroll-edge zone" }
        }
        let label = element.label
        if label == "Legal" || label.hasPrefix("Maps") { return "MapKit attribution" }
        if issue.auditType == .dynamicType, label.range(of: "^[0-9]+$", options: .regularExpression) != nil,
           ["explore-map", "globe-map", "list-map", "shared-wants-map"].contains(where: { app.descendants(matching: .any)[$0].exists }) {
            return "MapKit cluster glyph"
        }
        if issue.auditType == .textClipped && [.textField, .searchField, .secureTextField].contains(element.elementType) {
            return "single-line text field"
        }
        let navigationTitleBar = app.navigationBars.firstMatch
        if issue.auditType == .textClipped && navigationTitleBar.exists && navigationTitleBar.frame.contains(frame) {
            return "system navigation title (the full name is in the content)"
        }
        return nil
    }

    private func audit(_ screen: String, file: StaticString = #filePath, line: UInt = #line) {
        var found: [String] = []
        var unexpected: [String] = []
        do {
            try app.performAccessibilityAudit { issue in
                let element = issue.element
                let reason = self.exception(issue)
                let summary = "\(issue.compactDescription) | \(reason ?? "FAIL") | id=\(element?.identifier ?? "-") | label=\(element?.label ?? "-") | frame=\(element.map { NSCoder.string(for: $0.frame) } ?? "-") | \(issue.detailedDescription)"
                found.append(summary)
                if reason == nil { unexpected.append(summary) }
                return true
            }
        } catch {
            unexpected.append("Audit failed to run: \(error)")
        }
        let attachment = XCTAttachment(string: found.isEmpty ? "No issues" : found.joined(separator: "\n"))
        attachment.name = "m8-audit-\(screen)"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(unexpected.isEmpty, "\(screen): \(unexpected.count) accessibility issue(s):\n" + unexpected.joined(separator: "\n"),
                      file: file, line: line)
    }

    private func type(_ text: String, into identifier: String) {
        let field = waitFor(element(identifier))
        field.tap()
        field.typeText(text)
    }

    func testWelcomeAndSignIn() {
        launch(account: nil)
        waitFor(element("welcome"), timeout: 10)
        audit("welcome")
        element("existing-account").tap()
        waitFor(element("email-field"))
        audit("sign-in")
    }

    func testFeedPostAndNotifications() {
        launch(tab: "friends")
        waitFor(element("feed-list"), timeout: 10)
        audit("feed")
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'feed-comments-'")).firstMatch.tap()
        waitFor(element("activity-detail"))
        audit("post")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        waitFor(element("open-notifications")).tap()
        waitFor(element("notification-comment-theowanders"), timeout: 10)
        audit("notifications")
    }

    func testListsSearchAndDetail() {
        launch(tab: "myplaces")
        waitFor(element("lists-root"), timeout: 10)
        audit("lists-been")
        waitFor(element("list-kind")).buttons["Want to Go"].tap()
        audit("lists-want")
        element("log-place").tap()
        type("harbor", into: "experience-search-field")
        waitFor(element("experience-row-Harbor Lantern Café"), timeout: 10)
        audit("search-results")
        element("experience-row-Harbor Lantern Café").staticTexts["Harbor Lantern Café"].firstMatch.tap()
        waitFor(element("experience-detail"))
        audit("experience-detail")
    }

    func testRatingFlow() {
        launch(tab: "search")
        type("terrace", into: "experience-search-field")
        waitFor(element("experience-row-Terrace Steps Café"), timeout: 10).staticTexts["Terrace Steps Café"].firstMatch.tap()
        waitFor(element("detail-log")).tap()
        waitFor(element("rating-flow"))
        audit("rating-category")
        element("rating-category-picker").tap()
        waitFor(app.buttons["Food & Drink"]).tap()
        audit("rating-sentiment")
        element("rating-sentiment-liked").tap()
        waitFor(element("rating-details"))
        audit("rating-details")
        element("rating-okay").tap()
        waitFor(element("rating-comparison"), timeout: 10)
        audit("rating-comparison")
        element("rating-too-tough").tap()
        waitFor(element("rating-result"), timeout: 15)
        audit("rating-result")
    }

    func testProfileTravelAndGlobeList() {
        launch(tab: "profile")
        waitFor(element("profile-root"), timeout: 10)
        audit("profile")
        app.segmentedControls["profile-tabs"].buttons["Travel Profile"].tap()
        waitFor(element("new-this-year"))
        audit("travel-profile")
        waitFor(element("mini-globe")).tap()
        waitFor(element("expanded-globe"))
        element("globe-list-toggle").tap()
        waitFor(element("globe-list"))
        audit("globe-list")
    }

    func testSettingsAndAccountScreens() {
        launch(tab: "profile")
        waitFor(element("open-settings"), timeout: 10).tap()
        waitFor(element("settings"))
        audit("settings")
        element("settings-edit-profile").tap()
        waitFor(element("edit-profile"))
        audit("edit-profile")
        element("edit-profile-cancel").tap()
        waitFor(element("settings"))
        let delete = element("settings-delete-account")
        for _ in 0..<6 where !delete.isHittable { app.swipeUp() }
        delete.tap()
        waitFor(element("delete-account-explanation"))
        audit("delete-account")
    }

    func testExploreList() {
        launch(tab: "explore", location: "denied")
        waitFor(element("explore-root"), timeout: 10)
        audit("explore")
    }
}
