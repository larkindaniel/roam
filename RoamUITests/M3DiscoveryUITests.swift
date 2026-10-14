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

    private func filterControl(_ identifier: String, towardTop: Bool = false,
                               file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let list = waitFor(element("filter-options"), file: file, line: line)
        let navigationBar = waitFor(app.navigationBars["Filters"], file: file, line: line)
        let clear = waitFor(element("filter-clear"), file: file, line: line)
        let apply = waitFor(element("filter-apply"), file: file, line: line)
        let target = element(identifier)

        func viewport() -> CGRect {
            let listFrame = list.frame.intersection(app.frame)
            let top = max(listFrame.minY, navigationBar.frame.maxY)
            // List's accessibility frame includes the safe-area footer. XCUITest can call
            // covered rows hittable, so exclude both footer actions and their 16-point padding.
            let bottom = min(listFrame.maxY, min(clear.frame.minY, apply.frame.minY) - 16)
            return CGRect(x: listFrame.minX, y: top, width: listFrame.width, height: max(0, bottom - top))
        }

        func fullyVisible() -> Bool {
            target.exists && target.isHittable && !target.frame.isEmpty && viewport().contains(target.frame)
        }

        var attempts = 0
        while !fullyVisible() && attempts < 40 {
            let visible = viewport()
            let maximumDrag = min(CGFloat(150), visible.height / 3)
            let distance: CGFloat
            if target.exists && !target.frame.isEmpty {
                distance = visible.midY - target.frame.midY
            } else {
                distance = towardTop ? maximumDrag : -maximumDrag
            }
            let displacement = max(-maximumDrag, min(maximumDrag, distance))
            // Full List swipes can fling a large-text row from below the footer to above
            // the navigation bar. Short slow drags remain inside the visible List area;
            // the final hold stops momentum before checking the target's new geometry.
            let origin = list.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            let startOffset = CGVector(dx: visible.midX - list.frame.minX, dy: visible.midY - list.frame.minY)
            let start = origin.withOffset(startOffset)
            let end = origin.withOffset(CGVector(dx: startOffset.dx, dy: startOffset.dy + displacement))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
            attempts += 1
        }
        XCTAssertTrue(fullyVisible(), "Filter control must fit entirely between the navigation bar and footer before interaction: \(identifier), frame \(target.frame), viewport \(viewport())", file: file, line: line)
        return target
    }

    private func assertSelected(_ control: XCUIElement, _ selected: Bool,
                                file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate { _, _ in control.isSelected == selected }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: control)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed,
                       "Expected selected state \(selected) before continuing", file: file, line: line)
    }

    private func chooseExploreDestination(_ city: String, region: String, placeCount: Int) {
        waitFor(element("explore-destination-button")).tap()
        let field = waitFor(app.searchFields.firstMatch)
        field.tap()
        field.typeText(city)
        let destination = waitFor(element("destination-\(city)-\(region)"))
        XCTAssertTrue(destination.isHittable)
        destination.tap()
        waitForDisappearance(element("destination-picker"))
        XCTAssertTrue(waitFor(element("explore-destination-button")).label.contains(city))
        let map = waitFor(element("explore-map"), timeout: 10)
        let loaded = NSPredicate { _, _ in map.label.contains("Map with \(placeCount) places") }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: loaded, object: map)], timeout: 10), .completed,
                       "Map must show the chosen city's loaded places before capture")
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
        let canceledKyoto = filterControl("filter-option-Kyoto")
        assertSelected(canceledKyoto, false)
        canceledKyoto.tap()
        assertSelected(canceledKyoto, true)
        XCTAssertTrue(element("filter-clear").isEnabled)
        XCTAssertEqual(element("filter-apply").label, "Apply (1)")
        capture("m3-12-filter-sheet")
        element("filter-cancel").tap()
        XCTAssertTrue(waitFor(element("experience-row-Harbor Lantern Café")).exists, "Cancel discards the draft")
        element("open-filters").tap()
        waitFor(element("filter-sheet"))
        let appliedKyoto = filterControl("filter-option-Kyoto")
        assertSelected(appliedKyoto, false, file: #filePath, line: #line)
        appliedKyoto.tap()
        assertSelected(appliedKyoto, true)
        XCTAssertTrue(element("filter-apply").isHittable)
        element("filter-apply").tap()
        waitFor(element("experience-row-Aster House"))
        XCTAssertTrue(element("experience-row-Lantern Hill Lookout").exists)
        XCTAssertFalse(element("experience-row-Harbor Lantern Café").exists)
        capture("m3-13-been-filtered-kyoto")
        element("open-filters").tap()
        waitFor(element("filter-sheet"))
        let retainedKyoto = filterControl("filter-option-Kyoto")
        assertSelected(retainedKyoto, true)
        element("filter-clear").tap()
        assertSelected(retainedKyoto, false)
        XCTAssertFalse(element("filter-clear").isEnabled)
        XCTAssertEqual(element("filter-apply").label, "Apply")
        let unranked = filterControl("filter-unranked", towardTop: true)
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
        // Maya's home city defaults to Lisbon. A different manual city makes the denial
        // capture prove browsing survives denial, and makes the later Lisbon state distinct.
        chooseExploreDestination("Kyoto", region: "Kyoto", placeCount: 2)
        waitFor(element("explore-current-location")).tap()
        waitFor(element("explore-location-message"))
        XCTAssertTrue(element("explore-destination-button").label.contains("Kyoto"))
        XCTAssertTrue(element("explore-map").exists)
        capture("m3-16-explore-location-denied", settle: 3)
        chooseExploreDestination("Lisbon", region: "Lisboa", placeCount: 5)
        waitFor(app.buttons["Dismiss"]).tap()
        waitForDisappearance(element("explore-location-message"))
        capture("m3-17-explore-map-lisbon", settle: 3)
        element("explore-chip-Food & Drink").tap()
        element("map-list-toggle").tap()
        waitFor(element("experience-row-Harbor Lantern Café"), timeout: 10)
        XCTAssertTrue(element("experience-row-Morning Tide Bakery").exists, "Unsaved MapKit-style places appear without being persisted")
        capture("m3-18-explore-list-food")
    }

    func testFilterControlsRemainReachableAtAccessibilityTextSize() {
        launch(tab: "lists", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        let open = waitFor(element("open-filters"))
        XCTAssertTrue(open.isHittable, "Filters stays reachable before opening the sheet at large text sizes")
        XCTAssertTrue(element("sort-menu").isHittable)
        capture("m3-20-lists-ax-large")
        open.tap()
        waitFor(element("filter-sheet"))
        let food = filterControl("chip-food_drink")
        XCTAssertGreaterThanOrEqual(food.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(food.frame.maxX, app.frame.maxX, "Category labels fit inside the screen")
        food.tap()
        assertSelected(food, true)
        XCTAssertTrue(element("filter-clear").isHittable)
        element("filter-clear").tap()
        assertSelected(food, false)
        let kyoto = filterControl("filter-option-Kyoto")
        kyoto.tap()
        assertSelected(kyoto, true)
        XCTAssertTrue(element("filter-apply").isHittable, "Apply remains reachable after scrolling the city facets")
        XCTAssertTrue(element("filter-cancel").isHittable)
        capture("m3-21-filter-ax-large-selected")
        element("filter-apply").tap()
        waitFor(element("experience-row-Aster House"))
        XCTAssertFalse(element("experience-row-Harbor Lantern Café").exists)
    }

    func testExploreSelectedPlaceAndSearchThisArea() {
        launch(tab: "explore", location: "denied")
        waitFor(element("explore-map"), timeout: 10)
        element("map-list-toggle").tap()
        let showOnMap = waitFor(element("explore-show-on-map-Harbor Lantern Café"), timeout: 10)
        XCTAssertTrue(showOnMap.isHittable)
        showOnMap.tap()
        let card = waitFor(element("selected-place-card"))
        XCTAssertTrue(card.staticTexts["Harbor Lantern Café"].exists, "The selected map card identifies the same list experience")
        capture("m3-22-explore-selected-place", settle: 2)
        element("map-list-toggle").tap()
        let selectedRow = waitFor(element("explore-list-row-Harbor Lantern Café"))
        assertSelected(selectedRow, true)
        capture("m3-23-explore-selected-list")
        element("map-list-toggle").tap()

        // A gesture within the actual map changes its viewport; searching loads that viewport
        // and clears the old selection when its experience is outside the new results.
        let map = waitFor(element("explore-map"))
        let start = map.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.35))
        let end = map.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.35))
        for _ in 0..<3 { start.press(forDuration: 0.1, thenDragTo: end) }
        let searchArea = waitFor(element("search-this-area"))
        XCTAssertTrue(searchArea.isHittable)
        capture("m3-24-explore-search-this-area", settle: 1)
        searchArea.tap()
        waitForDisappearance(element("search-this-area"), timeout: 10)
        XCTAssertFalse(element("explore-load-error").exists)
        capture("m3-25-explore-new-viewport", settle: 2)
        element("map-list-toggle").tap()
        waitFor(app.staticTexts["Nothing here yet"])
        XCTAssertFalse(element("experience-row-Harbor Lantern Café").exists,
                       "Results from the old region are replaced after moving outside it")
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
