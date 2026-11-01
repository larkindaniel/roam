import XCTest

/// M2 fixture journeys for S01/S26. Fixture codes: sign-up 123456, recovery 654321.
final class M2AuthUITests: RoamUITestCase {
    private func type(_ text: String, into identifier: String) {
        let field = waitFor(element(identifier))
        field.tap()
        let existing = (field.value as? String) ?? ""
        let placeholder = field.placeholderValue ?? ""
        if !existing.isEmpty && existing != placeholder {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        field.typeText(text)
    }

    private func tapPrimary(_ identifier: String = "auth-primary") {
        if app.keyboards.count > 0 { app.keyboards.buttons.allElementsBoundByIndex.last?.tap() }
        let button = waitFor(element(identifier))
        if !button.isHittable { app.swipeUp() }
        button.tap()
    }

    func testEmailSignUpVerifiesThenProgressiveSetupLandsInYourLists() {
        launch(account: nil, scenario: "new-account")
        waitFor(element("welcome"))
        capture("m2-01-welcome")
        element("continue-with-email").tap()
        waitFor(element("sign-up"))
        type("avery@roam.test", into: "email-field")
        type("my long travel passphrase", into: "password-field")
        capture("m2-02-sign-up")
        tapPrimary()
        waitFor(element("verify-email"))
        type("000000", into: "code-field")
        tapPrimary()
        waitFor(element("auth-error"))
        capture("m2-03-verify-wrong-code")
        let code = element("code-field")
        code.tap()
        code.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "123456")
        tapPrimary()

        waitFor(element("profile-setup"))
        type("Avery Stone", into: "display-name-field")
        capture("m2-04-setup-name")
        tapPrimary("setup-continue")
        let handle = waitFor(element("handle-field"))
        handle.tap()
        handle.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20) + "mayaroams")
        waitFor(element("handle-unavailable"))
        capture("m2-05-setup-handle-taken")
        handle.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 9) + "avery_stone")
        waitFor(element("handle-available"))
        capture("m2-06-setup-handle-available")
        tapPrimary("setup-continue")
        waitFor(element("choose-avatar"))
        capture("m2-07-setup-photo")
        tapPrimary("setup-continue")
        waitFor(element("choose-home-city")).tap()
        let search = waitFor(app.searchFields.firstMatch)
        search.tap()
        search.typeText("Lisbon")
        waitFor(element("destination-Lisbon-Lisboa")).tap()
        waitFor(app.staticTexts["Lisbon, Lisboa, Portugal"])
        capture("m2-08-setup-home")
        tapPrimary("setup-continue")
        waitFor(element("member-row-theowanders"), timeout: 10)
        capture("m2-09-setup-people")
        XCTAssertEqual(app.buttons.matching(identifier: "follow-button").matching(NSPredicate(format: "label BEGINSWITH 'Following'")).count, 0,
                       "Nobody is preselected")
        app.descendants(matching: .any)["member-row-theowanders"].buttons["follow-button"].tap()
        tapPrimary("setup-continue")
        waitFor(element("setup-finish"))
        capture("m2-10-setup-visibility")
        element("setup-finish").tap()

        // First completed setup lands in Your Lists with one-time Been education.
        waitFor(element("been-intro"))
        XCTAssertTrue(tab("My Places").isSelected)
        capture("m2-11-been-intro")
        element("been-intro-continue").tap()
        waitFor(element("log-coachmark"))
        capture("m2-12-log-coachmark")
    }

    func testFailedSignInIsGenericThenPasswordRecovery() {
        launch(account: nil)
        element("existing-account").tap()
        type("maya@roam.test", into: "email-field")
        type("not-the-password", into: "password-field")
        tapPrimary()
        let error = waitFor(element("auth-error"))
        XCTAssertTrue(error.label.contains("Email or password is incorrect"))
        capture("m2-13-sign-in-error")
        element("forgot-password").tap()
        waitFor(element("forgot-password-screen"))
        capture("m2-14-forgot-password")
        tapPrimary()
        waitFor(element("reset-code"))
        type("654321", into: "code-field")
        capture("m2-15-reset-code")
        tapPrimary()
        waitFor(element("set-new-password"))
        type("a fresh passphrase here", into: "new-password-field")
        capture("m2-16-set-new-password")
        tapPrimary()
        waitFor(element("feed-root"), timeout: 10)
    }

    func testSetupResumesAfterRelaunchWithTypedName() {
        launch(account: "newcomer", scenario: "new-account")
        type("Robin Vale", into: "display-name-field")
        tapPrimary("setup-continue")
        waitFor(element("handle-field"))
        app.terminate()
        // Relaunch without resetting local state: the account-scoped draft resumes setup.
        app.launchArguments = ["-roam-backend", "fixture", "-roam-ui-testing", "-roam-fixture-scenario", "new-account", "-roam-fixture-account", "newcomer"]
        app.launch()
        let handle = waitFor(element("handle-field"))
        XCTAssertEqual(handle.value as? String, "robinvale", "Resumes on the handle step with the derived handle")
        capture("m2-17-setup-resumed")
    }

    func testSettingsShowsAccountAndSignsOut() {
        launch(tab: "profile")
        waitFor(element("open-settings")).tap()
        waitFor(element("settings"))
        capture("m2-18-settings")
        element("settings-sign-out").tap()
        app.sheets.buttons["Sign out"].firstMatch.tap()
        waitFor(element("welcome"))
    }
}
