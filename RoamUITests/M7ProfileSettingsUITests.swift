import XCTest

/// M7 fixture journeys: Travel Profile rows and filters, the expanded globe and its list, New this
/// year, native sharing, settings with failure rollback, profile editing with a restored draft,
/// Blocked/Muted lists, report history, help and account deletion. Server rules, settings
/// persistence and real deletion cleanup are covered by pgTAP, the backend suite and the worker test.
final class M7ProfileSettingsUITests: RoamUITestCase {
    private func first(_ prefix: String, type: XCUIElement.ElementType = .any) -> XCUIElement {
        app.descendants(matching: type).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
    }

    private func text(containing value: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", value)).firstMatch
    }

    /// Scrolls until `target` is hittable: down the screen while it's below (or not yet created by a
    /// lazy list), back up if it's above the visible area.
    @discardableResult
    private func reveal(_ target: XCUIElement, in scrollIdentifier: String? = nil, maxSwipes: Int = 12,
                        file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let scroll = scrollIdentifier.map { element($0) } ?? app.windows.firstMatch
        _ = target.waitForExistence(timeout: 3)
        for _ in 0..<maxSwipes {
            if target.exists && target.isHittable { break }
            if target.exists && target.frame.maxY < app.windows.firstMatch.frame.midY {
                scroll.swipeDown()
            } else {
                scroll.swipeUp()
            }
        }
        XCTAssertTrue(target.exists && target.isHittable, "Not reachable: \(target)", file: file, line: line)
        return target
    }

    private func openTravelProfile() {
        waitFor(element("profile-root"), timeout: 10)
        let segment = app.segmentedControls["profile-tabs"].buttons["Travel Profile"]
        reveal(segment, in: "profile-root").tap()
    }

    private func openSettings() {
        waitFor(element("open-settings")).tap()
        waitFor(element("settings"))
    }

    private func openProfile(handle: String) {
        openFromForYou("open-search")
        waitFor(app.buttons["Members"]).tap()
        let field = waitFor(element("member-search-field"))
        field.tap()
        let existing = (field.value as? String) ?? ""
        if !existing.isEmpty && existing != "Name or @handle" {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        field.typeText(handle)
        waitFor(element("member-row-\(handle)"), timeout: 10).tap()
        waitFor(element("profile-root"))
    }

    private func back() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    /// The system share sheet is out of process; Close dismisses it without sharing anything.
    private func dismissShareSheet() {
        let close = app.buttons["Close"].firstMatch
        if close.waitForExistence(timeout: 5) {
            close.tap()
        } else {
            app.otherElements["ActivityListView"].firstMatch.swipeDown(velocity: .fast)
        }
    }

    func testTravelProfileRowsFilterTheMapAndListAndNewThisYear() {
        launch(tab: "profile")
        openTravelProfile()
        let newThisYear = reveal(element("new-this-year"), in: "profile-root")
        XCTAssertTrue(newThisYear.label.contains("8"), "Eight places were first visited this year: \(newThisYear.label)")
        XCTAssertTrue(newThisYear.label.contains("1 place with an unknown visit date isn't counted"))
        capture("m7-01-travel-profile")
        app.segmentedControls["travel-breakdown"].buttons["Cities"].tap()
        let maine = reveal(element("travel-row-city-us|maine|portland"), in: "profile-root")
        XCTAssertTrue(element("travel-row-city-us|oregon|portland").exists, "Both Portlands are separate cities")
        reveal(element("travel-no-city"), in: "profile-root")
        capture("m7-02-travel-cities")
        maine.tap()
        waitFor(element("expanded-globe"))
        let summary = waitFor(element("globe-filter-summary"), timeout: 10)
        XCTAssertEqual(summary.label, "Showing Portland: 1 place")
        XCTAssertTrue(element("globe-totals").label.contains("10 countries · 11 cities"), "Header totals stay all-time")
        capture("m7-03-globe-filtered-map", settle: 2.5)
        element("globe-list-toggle").tap()
        waitFor(element("globe-list-row-Gull & Pine Tavern"))
        XCTAssertFalse(element("globe-list-row-Rosebud Supper Club").exists, "Portland, Oregon is a different city")
        capture("m7-04-globe-filtered-list")
        back()
        waitFor(element("profile-root"))
        reveal(element("new-this-year"), in: "profile-root").tap()
        waitFor(element("new-this-year-list"))
        waitFor(element("new-this-year-row-Lumen Street Hawker Hall"))
        XCTAssertFalse(element("new-this-year-row-Rosebud Supper Club").exists, "A place first visited last year isn't new")
        XCTAssertFalse(element("new-this-year-row-Ice Fjord Overlook").exists, "Unknown dates aren't counted")
        capture("m7-05-new-this-year")
    }

    func testExpandedGlobeShadesVisitedCountriesWithAnEquivalentList() {
        // The globe never depends on location permission.
        launch(tab: "profile", location: "denied")
        waitFor(element("profile-root"), timeout: 10)
        waitFor(element("mini-globe")).tap()
        waitFor(element("expanded-globe"))
        XCTAssertTrue(waitFor(element("globe-totals"), timeout: 10).label.contains("10 countries · 11 cities"))
        capture("m7-06-globe", settle: 3)
        element("globe-style-toggle").tap()
        capture("m7-07-flat-map", settle: 2.5)
        element("globe-list-toggle").tap()
        waitFor(element("globe-list"))
        waitFor(app.staticTexts["Countries (all-time)"])
        reveal(element("globe-list-row-Ice Fjord Overlook"), in: "globe-list")
        XCTAssertTrue(text(containing: "Location unavailable").exists || text(containing: "Greenland").exists,
                      "A place without a city still shows its country")
        capture("m7-08-globe-list")
        element("globe-list-row-Ice Fjord Overlook").tap()
        waitFor(element("experience-detail"), timeout: 10)
    }

    func testAnotherMembersTravelAndSharingWritesNothing() {
        launch(tab: "friends")
        openProfile(handle: "theowanders")
        openTravelProfile()
        reveal(element("new-this-year"), in: "profile-root")
        reveal(element("travel-row-category-food_drink"), in: "profile-root")
        capture("m7-09-other-travel-profile")
        let followers = element("profile-friends").label
        waitFor(element("share-profile")).tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].firstMatch.waitForExistence(timeout: 8)
                      || app.navigationBars["UIActivityContentView"].firstMatch.waitForExistence(timeout: 2), "The system share sheet opened")
        capture("m7-10-share-profile", settle: 1.2)
        dismissShareSheet()
        waitFor(element("profile-root"))
        XCTAssertEqual(element("profile-friends").label, followers, "Cancelling a share changed nothing")
        openFromForYou("open-search")
        waitFor(app.buttons["Experiences"]).tap()
        let search = waitFor(element("experience-search-field"))
        search.tap()
        search.typeText("harbor")
        waitFor(element("experience-row-Harbor Lantern Café"), timeout: 10).staticTexts["Harbor Lantern Café"].firstMatch.tap()
        waitFor(element("experience-detail"), timeout: 10)
        waitFor(element("share-experience")).tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].firstMatch.waitForExistence(timeout: 8)
                      || app.navigationBars["UIActivityContentView"].firstMatch.waitForExistence(timeout: 2))
        capture("m7-11-share-experience", settle: 1.2)
        dismissShareSheet()
        waitFor(element("experience-detail"))
    }

    func testSettingsRollBackAFailedSaveAndApplyUnitsAfterAcknowledgement() {
        launch(scenario: "settings-save-failure", tab: "profile", location: "granted")
        openSettings()
        capture("m7-12-settings")
        let haptics = reveal(app.switches["settings-haptics"])
        XCTAssertEqual(haptics.value as? String, "1")
        haptics.switches.firstMatch.tap()
        waitFor(element("settings-save-error-message"), timeout: 10)
        XCTAssertEqual(haptics.value as? String, "1", "A failed save puts the previous value back")
        capture("m7-13-settings-save-failed")
        element("settings-retry").tap()
        waitForDisappearance(element("settings-save-error-message"), timeout: 10)
        XCTAssertEqual(haptics.value as? String, "0", "Retry saved the same change")
        let unit = reveal(element("settings-distance-unit"))
        unit.tap()
        waitFor(app.buttons["Miles"].firstMatch).tap()
        let miles = NSPredicate(format: "label CONTAINS 'Miles' OR value CONTAINS 'Miles'")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: miles, object: element("settings-distance-unit"))], timeout: 8), .completed)
        capture("m7-14-settings-saved")
        tab("My Places").tap()
        waitFor(element("sort-menu"), timeout: 10).tap()
        waitFor(app.buttons["Distance"].firstMatch).tap()
        waitFor(text(containing: " mi"), timeout: 10)
        XCTAssertFalse(text(containing: " km").exists, "List distances use the acknowledged unit")
        capture("m7-15-lists-in-miles")
    }

    func testEditProfileValidatesKeepsAnInterruptedDraftAndSaves() {
        launch(tab: "profile")
        waitFor(element("profile-edit"), timeout: 10).tap()
        waitFor(element("edit-profile"))
        let name = waitFor(element("edit-profile-name"))
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12))
        waitFor(text(containing: "This is required."), timeout: 5)
        XCTAssertFalse(app.buttons["edit-profile-save"].isEnabled, "An empty name can't be saved")
        let handle = element("edit-profile-handle")
        handle.tap()
        handle.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + "theowanders")
        waitFor(text(containing: "@theowanders is taken"), timeout: 8)
        capture("m7-16-edit-profile-invalid")
        handle.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + "mayaroams")
        name.tap()
        name.typeText("Maya C")
        // Interrupt: the draft must come back after a restart. (Bio trimming is covered by
        // M7EditProfileModelTests; a multi-line field places the cursor wherever the tap lands.)
        app.terminate()
        launch(tab: "profile", resetState: false)
        waitFor(element("profile-edit"), timeout: 10).tap()
        waitFor(element("edit-profile-restored"), timeout: 8)
        XCTAssertEqual(element("edit-profile-name").value as? String, "Maya C")
        capture("m7-17-edit-profile-restored")
        waitFor(app.buttons["edit-profile-save"]).tap()
        waitFor(element("profile-root"), timeout: 10)
        waitFor(app.staticTexts["Maya C"].firstMatch, timeout: 10)
        XCTAssertTrue(text(containing: "Collecting quiet trails").exists, "The untouched bio is kept")
        capture("m7-18-profile-after-edit")
        waitFor(element("profile-edit")).tap()
        XCTAssertFalse(element("edit-profile-restored").waitForExistence(timeout: 2), "A saved edit leaves no draft")
        element("edit-profile-cancel").tap()
        waitFor(element("profile-root"))
    }

    func testMutedAndBlockedListsUnmuteAndUnblock() {
        launch(tab: "friends")
        openProfile(handle: "jonashikes")
        waitFor(element("profile-overflow")).tap()
        waitFor(element("profile-mute")).tap()
        waitFor(element("profile-muted"), timeout: 5)
        back()
        openProfile(handle: "priyaplans")
        waitFor(element("profile-overflow")).tap()
        waitFor(element("profile-block")).tap()
        waitFor(element("confirm-block")).tap()
        openFromForYou("open-profile")
        openSettings()
        reveal(element("settings-muted")).tap()
        waitFor(element("safety-remove-jonashikes"), timeout: 10)
        capture("m7-19-muted-members")
        element("safety-remove-jonashikes").tap()
        waitFor(element("confirm-safety-remove")).tap()
        waitFor(app.staticTexts["No one is muted"], timeout: 8)
        back()
        reveal(element("settings-blocked")).tap()
        waitFor(element("safety-remove-priyaplans"), timeout: 10)
        capture("m7-20-blocked-members")
        element("safety-remove-priyaplans").tap()
        waitFor(element("confirm-safety-remove"))
        XCTAssertTrue(text(containing: "aren't restored").exists, "The confirmation says unblocking doesn't restore follows")
        capture("m7-21-unblock-confirmation", settle: 0.8)
        element("confirm-safety-remove").tap()
        waitFor(app.staticTexts["No one is blocked"], timeout: 8)
        capture("m7-22-blocked-empty")
    }

    func testReportHistoryShowsStoredReportsHonestly() {
        launch(tab: "friends")
        openProfile(handle: "samexplores")
        waitFor(element("profile-overflow")).tap()
        waitFor(element("profile-report")).tap()
        waitFor(element("report-reason-spam")).tap()
        element("report-send").tap()
        waitFor(element("report-received"), timeout: 10)
        app.buttons["Done"].firstMatch.tap()
        openFromForYou("open-profile")
        openSettings()
        reveal(element("settings-reports")).tap()
        let row = waitFor(element("report-row"), timeout: 10)
        XCTAssertTrue(row.label.contains("Member · Spam"))
        XCTAssertTrue(row.label.contains("Received, not yet reviewed"), "Nothing claims a review happened")
        capture("m7-23-report-history")
        back()
        reveal(element("settings-help-ranking")).tap()
        waitFor(element("help-ranking"))
        XCTAssertTrue(text(containing: "Too tough means the two places are a tie").exists)
        capture("m7-24-help-ranking")
        back()
        reveal(element("settings-help-privacy")).tap()
        waitFor(element("help-privacy"))
        capture("m7-25-help-privacy")
    }

    func testDeleteAccountNeedsReauthenticationAndSignsOut() {
        launch(tab: "profile")
        openSettings()
        reveal(element("settings-delete-account")).tap()
        waitFor(element("delete-account-explanation"))
        capture("m7-26-delete-account")
        element("delete-account-continue").tap()
        let password = waitFor(element("delete-account-password"))
        password.tap()
        password.typeText("not-the-password")
        element("delete-account-reauth").tap()
        waitFor(element("delete-account-error"), timeout: 8)
        capture("m7-27-delete-reauth-failed")
        password.tap()
        password.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20) + "roam-fixture-pass")
        element("delete-account-reauth").tap()
        waitFor(element("delete-account-confirm"), timeout: 8).tap()
        waitFor(element("delete-account-final")).tap()
        let status = waitFor(element("delete-account-status"), timeout: 10)
        XCTAssertTrue(status.label.contains("still in progress"), "The pending server job isn't reported as finished")
        capture("m7-28-delete-requested")
        element("delete-account-done").tap()
        waitFor(element("welcome"), timeout: 10)
        waitFor(element("deletion-notice"))
        capture("m7-29-signed-out-after-deletion")
    }

    func testLargeTextKeepsTravelProfileAndSettingsUsable() {
        launch(tab: "profile", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        openTravelProfile()
        reveal(element("new-this-year"), in: "profile-root")
        capture("m7-30-large-text-travel")
        reveal(element("travel-row-category-food_drink"), in: "profile-root")
        capture("m7-31-large-text-travel-rows")
        app.windows.firstMatch.swipeDown()
        app.windows.firstMatch.swipeDown()
        openSettings()
        reveal(app.switches["settings-haptics"])
        capture("m7-32-large-text-settings")
    }

    func testOwnEmptyTravelProfileInvitesALog() {
        launch(account: "maya", scenario: "empty", tab: "profile")
        openTravelProfile()
        waitFor(element("travel-empty"), timeout: 10)
        capture("m7-33-travel-empty")
        element("travel-empty-log").tap()
        waitFor(element("experience-search-field"), timeout: 8)
    }
}
