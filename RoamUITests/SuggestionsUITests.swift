import XCTest

/// #4 journeys in fixture mode: onboarding (pick places you've been, then rank them), and the reason lines on Discover,
/// a city page and a country page. Screenshots are named `suggestions-NN-…` for the PR.
final class SuggestionsUITests: RoamUITestCase {
    private func tapPrimary(_ identifier: String) {
        if app.keyboards.count > 0 { app.keyboards.buttons.allElementsBoundByIndex.last?.tap() }
        let button = waitFor(element(identifier))
        if !button.isHittable { app.swipeUp() }
        button.tap()
    }

    /// Taps a stop on the feeling picker: 0 Didn't like, 1 Neutral, 2 Liked it.
    private func feel(_ stop: Int) {
        let slider = waitFor(element("rating-feeling-slider"))
        slider.coordinate(withNormalizedOffset: CGVector(dx: (Double(stop) + 0.5) / 3, dy: 0.5)).tap()
    }

    /// From the photo step, skips photo, home and friends.
    private func skipToBeen() {
        waitFor(element("choose-avatar"))
        tapPrimary("setup-continue")
        waitFor(element("choose-home-city"))
        tapPrimary("setup-continue")
        waitFor(app.staticTexts["Find friends"], timeout: 10)
        tapPrimary("setup-continue")
        waitFor(element("onboarding-been-continue"), timeout: 10)
    }

    func testOnboardingPicksPlacesThenRanksThem() {
        // The default scenario has places on Roam; the newcomer hasn't set up yet.
        launch(account: "newcomer", scenario: "default")
        let name = waitFor(element("display-name-field"))
        name.tap()
        name.typeText("Avery Stone")
        tapPrimary("setup-continue")
        let handle = waitFor(element("handle-field"))
        handle.tap()
        handle.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20) + "avery_stone")
        waitFor(element("handle-available"))
        tapPrimary("setup-continue")
        waitFor(element("choose-avatar"))
        tapPrimary("setup-continue")
        waitFor(element("choose-home-city")).tap()
        let search = waitFor(app.searchFields.firstMatch)
        search.tap()
        search.typeText("Lisbon")
        waitFor(element("destination-Lisbon-Lisboa")).tap()
        waitFor(app.staticTexts["Lisbon, Lisboa, Portugal"])
        tapPrimary("setup-continue")
        waitFor(app.staticTexts["Find friends"])
        tapPrimary("setup-continue")

        // Where have you been? Places around Lisbon, most-rated first.
        let harbor = waitFor(element("onboarding-place-Harbor Lantern Café"), timeout: 10)
        capture("suggestions-01-onboarding-been")
        harbor.tap()
        element("onboarding-place-Saltmarsh Oyster Bar").tap()
        XCTAssertTrue(harbor.isSelected)
        capture("suggestions-02-onboarding-picked")
        tapPrimary("onboarding-been-continue")

        // One at a time: how was it, then which did you like more.
        waitFor(element("onboarding-progress"))
        XCTAssertEqual(element("onboarding-progress").label, "1 of 2")
        capture("suggestions-03-onboarding-feeling")
        feel(2)
        // The first food place has nothing to compare with, so it saves straight away.
        waitFor(app.staticTexts["2 of 2"])
        feel(2)
        let preferNew = waitFor(element("onboarding-prefer-new"))
        capture("suggestions-04-onboarding-compare")
        preferNew.tap()

        waitFor(element("setup-finish"))
        element("setup-finish").tap()
        waitFor(element("been-intro"))
    }

    func testOnboardingCanBeSkipped() {
        launch(account: "newcomer", scenario: "default")
        let name = waitFor(element("display-name-field"))
        name.tap()
        name.typeText("Robin Vale")
        tapPrimary("setup-continue")
        waitFor(element("handle-available"))
        tapPrimary("setup-continue")
        skipToBeen()
        // No home: search only, and Skip for now goes straight on.
        waitFor(element("onboarding-search"))
        XCTAssertEqual(element("onboarding-been-continue").label, "Skip for now")
        tapPrimary("onboarding-been-continue")
        waitFor(element("setup-finish"))
    }

    func testDiscoverCityAndCountryExplainEachSuggestion() {
        launch(account: "maya")
        let cities = waitFor(element("discover-cities"), timeout: 10)
        XCTAssertTrue(cities.exists)
        // Sam's shared Wellington list and Theo's Edinburgh pick lead; the Iceland trip city follows.
        let wellington = waitFor(element("discover-city-Wellington"))
        XCTAssertTrue(app.staticTexts["New Zealand · On Sam's Wellington list"].exists)
        XCTAssertTrue(app.staticTexts["United Kingdom · Theo sent you a place here"].exists)
        XCTAssertTrue(app.staticTexts["Iceland · On your Iceland trip"].exists)
        capture("suggestions-05-discover")

        wellington.tap()
        waitFor(element("foryou-place-Driftwood Kayak Co."), timeout: 10)
        XCTAssertTrue(app.staticTexts["On Sam's Wellington list"].exists)
        capture("suggestions-06-city")

        // Long-press: Not interested takes it away.
        element("foryou-place-Driftwood Kayak Co.").press(forDuration: 1.0)
        waitFor(app.buttons["Not interested"]).tap()
        waitForDisappearance(element("foryou-place-Driftwood Kayak Co."))
    }

    func testCountryPageSuggestsItsCities() {
        launch(account: "maya", extra: ["-roam-initial-route", "country:GB"])
        waitFor(element("country-suggested-Edinburgh"), timeout: 10)
        XCTAssertTrue(app.staticTexts["Theo sent you a place here"].exists)
        capture("suggestions-07-country")
    }

    func testNoFriendsMeansAnHonestEmptyDiscover() {
        launch(account: "newcomer", scenario: "new-account")
        // A brand-new account goes through setup first; skip straight to the end.
        let name = waitFor(element("display-name-field"))
        name.tap()
        name.typeText("Kai Moss")
        tapPrimary("setup-continue")
        waitFor(element("handle-available"))
        tapPrimary("setup-continue")
        skipToBeen()
        tapPrimary("onboarding-been-continue")
        tapPrimary("setup-finish")
        if element("been-intro-continue").waitForExistence(timeout: 5) { element("been-intro-continue").tap() }
        waitFor(element("tab-foryou")).tap()
        waitFor(element("discover-empty"), timeout: 10)
        capture("suggestions-08-discover-empty")
    }
}
