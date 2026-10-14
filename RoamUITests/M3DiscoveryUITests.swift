import XCTest

/// M3 fixture journeys: S03 search, S04 destination, S05 Explore, S06 detail, S12/S13 lists and filters.
final class M3DiscoveryUITests: RoamUITestCase {
    private func search(_ text: String) {
        let field = waitFor(element("experience-search-field"))
        field.tap()
        if let value = field.value as? String, !value.isEmpty, value != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        field.typeText(text)
    }

    private func scrollTo(_ identifier: String) -> XCUIElement {
        let target = element(identifier)
        var attempts = 0
        while !(target.exists && target.isHittable) && attempts < 8 {
            app.swipeUp()
            attempts += 1
        }
        return target
    }

    func testSearchOpensDetailAndSaveSyncsToWantToGo() {
        launch(tab: "search")
        search("harbor")
        waitFor(element("experience-row-Harbor Lantern Café"), timeout: 10)
        capture("m3-01-search-results")
        element("experience-row-Harbor Lantern Café").staticTexts["Harbor Lantern Café"].firstMatch.tap()
        waitFor(element("experience-detail"))
        waitFor(element("detail-already-been"))
        XCTAssertTrue(element("detail-your-score").label.contains("10.0"))
        XCTAssertTrue(element("detail-following-score").label.contains("2 people"))
        capture("m3-02-detail-rated", settle: 1.5)
        app.swipeUp()
        capture("m3-03-detail-about-activity")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        search("terrace")
        let save = waitFor(element("save-Terrace Steps Café"), timeout: 10)
        save.tap()
        waitFor(app.buttons["Saved to Want to Go. Remove Terrace Steps Café"])
        capture("m3-04-search-saved")
        element("experience-row-Terrace Steps Café").staticTexts["Terrace Steps Café"].firstMatch.tap()
        waitFor(element("detail-save"))
        XCTAssertTrue(element("detail-save").label.contains("Saved"))
        capture("m3-05-detail-saved", settle: 1.5)

        tab("Your Lists").tap()
        waitFor(element("list-kind")).buttons["Want to Go"].tap()
        waitFor(element("experience-row-Terrace Steps Café"))
        capture("m3-06-want-list")
    }

    func testNoResultsAndDestinationContext() {
        launch(tab: "search")
        search("zzqx")
        waitFor(element("search-no-results"), timeout: 10)
        capture("m3-07-search-no-results")
        element("destination-chip").tap()
        let field = waitFor(app.searchFields.firstMatch)
        field.tap()
        field.typeText("Kyoto")
        waitFor(element("destination-Kyoto-Kyoto")).tap()
        XCTAssertTrue(waitFor(element("destination-chip")).label.contains("Kyoto"))
        search("lantern")
        waitFor(element("experience-row-Lantern Hill Lookout"), timeout: 10)
        capture("m3-08-search-near-kyoto")
        element("search-segment").buttons["Members"].tap()
        let members = waitFor(element("member-search-field"))
        members.tap()
        members.typeText("theo")
        waitFor(element("member-row-theowanders"), timeout: 10)
        capture("m3-09-member-search")
    }

    func testListsCategoryOrderFiltersAndUnrankedMemories() {
        launch(tab: "lists")
        waitFor(element("experience-row-Harbor Lantern Café"), timeout: 10)
        capture("m3-10-been-all")
        XCTAssertFalse(app.staticTexts["1. Harbor Lantern Café"].exists, "All mode shows no combined ordinal")
        element("category-scope").tap()
        app.buttons["Food & Drink"].tap()
        waitFor(app.staticTexts["1. Harbor Lantern Café"])
        capture("m3-11-been-food-ranked")

        // Staged filters: Cancel discards, Apply applies, Clear all clears the draft.
        element("category-scope").tap()
        app.buttons["All categories"].tap()
        element("open-filters").tap()
        waitFor(element("filter-sheet"))
        waitFor(element("filter-option-Kyoto")).tap()
        capture("m3-12-filter-sheet")
        element("filter-cancel").tap()
        XCTAssertTrue(waitFor(element("experience-row-Harbor Lantern Café")).exists, "Cancel discards the draft")
        element("open-filters").tap()
        waitFor(element("filter-sheet"))
        waitFor(element("filter-option-Kyoto")).tap()
        element("filter-apply").tap()
        waitFor(element("experience-row-Aster House"))
        XCTAssertTrue(element("experience-row-Lantern Hill Lookout").exists)
        XCTAssertFalse(element("experience-row-Harbor Lantern Café").exists)
        capture("m3-13-been-filtered-kyoto")
        element("open-filters").tap()
        waitFor(element("filter-sheet"))
        element("filter-clear").tap()
        let unranked = app.switches["filter-unranked"]
        unranked.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(unranked.value as? String, "1")
        element("filter-apply").tap()
        waitFor(element("experience-row-Lumen Street Hawker Hall"))
        capture("m3-14-unranked-memories")

        let searchField = element("list-search-field")
        searchField.tap()
        searchField.typeText("zzz")
        waitFor(element("filtered-empty"))
        capture("m3-15-filtered-empty")
        app.buttons["Reset filters"].tap()
        waitFor(element("experience-row-Harbor Lantern Café"))
    }

    func testExploreWorksWithLocationDeniedAndTogglesMapList() {
        launch(tab: "explore", location: "denied")
        waitFor(element("explore-current-location")).tap()
        waitFor(element("explore-location-message"))
        capture("m3-16-explore-location-denied")
        element("explore-destination-button").tap()
        let field = waitFor(app.searchFields.firstMatch)
        field.tap()
        field.typeText("Lisbon")
        waitFor(element("destination-Lisbon-Lisboa")).tap()
        waitFor(element("explore-map"), timeout: 10)
        capture("m3-17-explore-map-lisbon", settle: 3)
        element("explore-chip-Food & Drink").tap()
        element("map-list-toggle").tap()
        waitFor(element("experience-row-Harbor Lantern Café"), timeout: 10)
        XCTAssertTrue(element("experience-row-Morning Tide Bakery").exists, "Unsaved MapKit-style places appear without being persisted")
        capture("m3-18-explore-list-food")
    }

    func testOtherMembersListsUseViewerActions() {
        launch(tab: "search")
        element("search-segment").buttons["Members"].tap()
        let members = waitFor(element("member-search-field"))
        members.tap()
        members.typeText("theo")
        waitFor(element("member-row-theowanders"), timeout: 10).staticTexts["Theo Park"].tap()
        waitFor(element("profile-want-count"), timeout: 10).tap()
        waitFor(element("member-lists"))
        waitFor(element("experience-row-Old Mill Cinema"))
        capture("m3-19-member-want-list")
    }
}
