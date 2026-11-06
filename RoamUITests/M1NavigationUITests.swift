import XCTest

/// M1: five tabs with independent stacks, back/modal routing, state restoration inside a tab,
/// deferred routes absent, globe feasibility screenshots.
final class M1NavigationUITests: RoamUITestCase {
    func testTabsHaveIndependentStacksAndKeepState() {
        launch(tab: "profile")
        waitFor(element("mini-globe"), timeout: 12)
        capture("m1-05-profile-root", settle: 4)
        element("mini-globe").tap()
        waitFor(element("expanded-globe"))
        capture("m1-06-globe-expanded", settle: 5)

        // Switching tabs keeps the Profile stack where it was.
        tab("Feed").tap()
        waitFor(element("feed-root"))
        capture("m1-01-feed-root")
        tab("Your Lists").tap()
        waitFor(element("lists-root"))
        capture("m1-02-lists-root")
        tab("Search").tap()
        waitFor(element("search-root"))
        capture("m1-03-search-root")
        tab("Profile").tap()
        XCTAssertTrue(element("expanded-globe").waitForExistence(timeout: 5), "Profile stack should be restored on return")

        // Back returns to the profile root.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        waitFor(element("mini-globe"))
    }

    func testDestinationPickerIsModalAndReturnsToInvoker() {
        launch(tab: "explore")
        waitFor(element("explore-root"))
        capture("m1-04-explore-root")
        element("explore-destination-button").tap()
        waitFor(element("destination-picker"))
        // Close returns to Explore unchanged.
        element("close-destination-picker").tap()
        waitForDisappearance(element("destination-picker"))
        XCTAssertTrue(element("explore-root").exists)

        element("explore-destination-button").tap()
        let field = app.searchFields.firstMatch
        waitFor(field).tap()
        field.typeText("Portland")
        // Same-name cities are disambiguated by region and country.
        waitFor(element("destination-Portland-Oregon"))
        XCTAssertTrue(element("destination-Portland-Maine").exists)
        capture("m1-08-destination-picker")
        element("destination-Portland-Oregon").tap()
        waitForDisappearance(element("destination-picker"))
        XCTAssertTrue(app.buttons["explore-destination-button"].label.contains("Portland, Oregon"))
        capture("m1-09-explore-portland", settle: 3)
    }

    func testCurrentLocationDenialKeepsManualSearch() {
        launch(tab: "explore", location: "denied")
        element("explore-destination-button").tap()
        waitFor(element("use-current-location")).tap()
        let message = waitFor(element("location-message"))
        XCTAssertTrue(message.label.contains("Choose a destination"))
        XCTAssertTrue(app.searchFields.firstMatch.exists, "Manual destination search stays available")
    }

    func testDeferredFeaturesHaveNoEntryPoints() {
        launch(tab: "profile")
        waitFor(element("mini-globe"), timeout: 12)
        for title in ["Guides", "Leaderboard", "Import", "Trending", "Challenges", "City score"] {
            XCTAssertFalse(app.buttons[title].exists, "\(title) must not have a v1 entry point")
            XCTAssertFalse(app.staticTexts[title].exists, "\(title) must not appear in v1")
        }
        XCTAssertEqual(app.tabBars.buttons.count, 5)
    }
}
