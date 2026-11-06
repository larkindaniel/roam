import XCTest

/// M8 end-to-end fixture journeys. Two members start with empty lists and no follows and walk the
/// whole product: search → detail → Want → sentiment/details → compare/tie → immediate score →
/// automatic follower feed → comment → notifications → repeat visit/rerank → globe/counts → Shared
/// Want to Go → ranking removal with retained memories. `M8JourneyIntegrationTests` runs the same
/// chain against the real local backend.
final class M8JourneyUITests: RoamUITestCase {
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

    private func text(containing value: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", value)).firstMatch
    }

    @discardableResult
    private func reveal(_ target: XCUIElement, in scrollIdentifier: String? = nil, maxSwipes: Int = 10,
                        file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let scroll = scrollIdentifier.map { element($0) } ?? app.windows.firstMatch
        _ = target.waitForExistence(timeout: 3)
        for _ in 0..<maxSwipes {
            if target.exists && target.isHittable { break }
            if target.exists && target.frame.maxY < app.windows.firstMatch.frame.midY { scroll.swipeDown() } else { scroll.swipeUp() }
        }
        XCTAssertTrue(target.exists && target.isHittable, "Not reachable: \(target)", file: file, line: line)
        return target
    }

    @discardableResult
    private func ratingControl(_ identifier: String) -> XCUIElement {
        let target = element(identifier)
        let scroll = waitFor(element("rating-scroll"))
        for _ in 0..<8 {
            if target.exists && target.isHittable { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(target.exists && target.isHittable, "Rating control remains reachable: \(identifier)")
        return target
    }

    /// Returns the Search tab to its root (an earlier member search may have pushed a profile).
    private func searchRoot() {
        tab("Search").tap()
        for _ in 0..<4 where !app.buttons["Experiences"].exists {
            let back = app.navigationBars.buttons["BackButton"].firstMatch
            guard back.exists else { break }
            back.tap()
        }
    }

    /// Scrolls a list until a lazily created row exists, searching down and then back up (rows
    /// scrolled out of view are recycled and stop existing).
    @discardableResult
    private func scrollTo(_ target: XCUIElement, maxSwipes: Int = 8, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        for _ in 0..<maxSwipes where !target.exists { app.swipeUp() }
        for _ in 0..<(maxSwipes * 2) where !target.exists { app.swipeDown() }
        XCTAssertTrue(target.exists, "Never appeared: \(target)", file: file, line: line)
        return target
    }

    private func openPlace(_ query: String, _ name: String) {
        searchRoot()
        waitFor(app.buttons["Experiences"]).tap()
        type(query, into: "experience-search-field")
        waitFor(element("experience-row-\(name)"), timeout: 10).staticTexts[name].firstMatch.tap()
        waitFor(element("experience-detail"))
    }

    private func openMember(_ handle: String) {
        searchRoot()
        waitFor(app.buttons["Members"]).tap()
        type(handle, into: "member-search-field")
        waitFor(element("member-row-\(handle)"), timeout: 10).tap()
        waitFor(element("profile-root"))
    }

    /// First log of the open place with its suggested category; returns the result's score label.
    @discardableResult
    private func log(sentiment: String = "liked", note: String? = nil, tie: Bool = false, category: String? = nil) -> String {
        waitFor(element("detail-log")).tap()
        waitFor(element("rating-flow"))
        if let category {
            ratingControl("rating-category-picker").tap()
            waitFor(app.buttons[category]).tap()
        }
        ratingControl("rating-sentiment-\(sentiment)").tap()
        waitFor(element("rating-details"))
        if let note {
            ratingControl("rating-edit-note").tap()
            waitFor(element("rating-note-text")).tap()
            element("rating-note-text").typeText(note)
            element("rating-editor-done").tap()
        }
        ratingControl("rating-okay").tap()
        if tie {
            waitFor(element("rating-comparison"), timeout: 10)
            ratingControl("rating-too-tough").tap()
        }
        let score = waitFor(element("rating-result-score"), timeout: 15).label
        return score
    }

    private func finishRating() {
        ratingControl("rating-done").tap()
        waitForDisappearance(element("rating-flow"))
    }

    private func signOut() {
        tab("Profile").tap()
        waitFor(element("open-settings")).tap()
        waitFor(element("settings"))
        reveal(element("settings-sign-out")).tap()
        app.sheets.buttons["Sign out"].firstMatch.tap()
        waitFor(element("welcome"), timeout: 10)
    }

    private func signIn(_ email: String) {
        waitFor(element("existing-account")).tap()
        type(email, into: "email-field")
        type("roam-fixture-pass", into: "password-field")
        if app.keyboards.count > 0 { app.keyboards.buttons.allElementsBoundByIndex.last?.tap() }
        let primary = waitFor(element("auth-primary"))
        if !primary.isHittable { app.swipeUp() }
        primary.tap()
        waitFor(app.tabBars.firstMatch, timeout: 15)
    }

    func testTwoMembersFromEmptyListsThroughFeedCommentRevisitTravelSharedWantsAndRetainedMemory() {
        // Maya: no follows, nothing saved.
        launch(scenario: "empty", tab: "feed")
        waitFor(element("feed-empty"), timeout: 10)
        capture("m8-01-empty-feed-no-follows")

        openPlace("harbor", "Harbor Lantern Café")
        waitFor(element("detail-save")).tap()
        waitFor(app.buttons["Saved to Want to Go"].firstMatch, timeout: 8)
        let first = log(note: "Sunset tarts on the terrace.")
        XCTAssertTrue(first.contains("8.4"), "The first liked place scores 8.4 at once: \(first)")
        capture("m8-02-first-score")
        finishRating()
        XCTAssertFalse(app.buttons["Saved to Want to Go"].exists, "Ranking a saved place moves it from Want to Go to Been")

        openPlace("saltmarsh", "Saltmarsh Oyster Bar")
        let tied = log(tie: true)
        XCTAssertTrue(tied.contains("8.4"), "Two tied liked places share 8.4: \(tied)")
        XCTAssertTrue(app.staticTexts["Tied with 1 other experience."].exists)
        capture("m8-03-tie-result")
        finishRating()

        openPlace("lagoon", "Glass Lagoon Baths")
        waitFor(element("detail-save")).tap()
        waitFor(app.buttons["Saved to Want to Go"].firstMatch, timeout: 8)
        signOut()

        // Theo: follows Maya, sees her history in the feed, comments and shares a Want.
        signIn("theo@roam.test")
        tab("Feed").tap()
        waitFor(element("feed-empty"), timeout: 10)
        openMember("mayaroams")
        waitFor(element("profile-root")).buttons["follow-button"].firstMatch.tap()
        let following = NSPredicate(format: "label BEGINSWITH 'Following'")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: following, object: app.buttons["follow-button"].firstMatch)],
                                      timeout: 8), .completed)
        tab("Feed").tap()
        let post = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'feed-card-'"))
            .containing(NSPredicate(format: "label CONTAINS %@", "Sunset tarts")).firstMatch
        waitFor(post, timeout: 10)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'feed-card-'")).count >= 2,
                      "Following exposes both automatic posts")
        post.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'feed-comments-'")).firstMatch.tap()
        waitFor(element("activity-detail"))
        type("Saving this for Lisbon!", into: "comment-field")
        element("comment-send").tap()
        waitFor(app.staticTexts["Saving this for Lisbon!"], timeout: 10)
        capture("m8-04-follower-comment")

        openPlace("lagoon", "Glass Lagoon Baths")
        waitFor(element("detail-save")).tap()
        waitFor(app.buttons["Saved to Want to Go"].firstMatch, timeout: 8)
        openMember("mayaroams")
        reveal(element("profile-shared-wants"), in: "profile-root").tap()
        waitFor(element("shared-wants-list"), timeout: 10)
        XCTAssertTrue(element("shared-wants-count").label.contains("1 place"))
        waitFor(text(containing: "Glass Lagoon Baths"))
        capture("m8-05-shared-want")
        signOut()

        // Maya: notifications, a repeat visit and a rerank, travel counts, then ranking removal.
        signIn("maya@roam.test")
        tab("Feed").tap()
        let bell = waitFor(element("open-notifications"), timeout: 10)
        XCTAssertTrue(bell.label.contains("2 unread"), "A follow and a comment: \(bell.label)")
        bell.tap()
        waitFor(element("notification-comment-theowanders"), timeout: 10)
        waitFor(element("notification-follow-theowanders"))
        capture("m8-06-notifications")

        openPlace("harbor", "Harbor Lantern Café")
        waitFor(element("detail-add-visit")).tap()
        waitFor(element("rating-details"))
        ratingControl("rating-okay").tap()
        waitFor(element("rating-visit-saved"), timeout: 15)
        finishRating()
        waitFor(element("detail-overflow")).tap()
        waitFor(element("detail-rerank")).tap()
        ratingControl("rating-sentiment-fine").tap()
        waitFor(element("rating-details"))
        ratingControl("rating-okay").tap()
        let reranked = waitFor(element("rating-result-score"), timeout: 15).label
        XCTAssertTrue(reranked.contains("5.0"), "Alone among fine places it scores 5.0: \(reranked)")
        finishRating()

        tab("Profile").tap()
        waitFor(element("profile-root"), timeout: 10)
        XCTAssertTrue(waitFor(element("mini-globe")).label.contains("1 country, 1 city"), "One country and one city: \(element("mini-globe").label)")
        reveal(app.segmentedControls["profile-tabs"].buttons["Travel Profile"], in: "profile-root").tap()
        reveal(element("new-this-year"), in: "profile-root")
        capture("m8-07-travel-counts")
        element("new-this-year").tap()
        waitFor(element("new-this-year-list"))
        waitFor(text(containing: "2 places first visited in"), timeout: 8)
        XCTAssertTrue(element("new-this-year-row-Harbor Lantern Café").exists && element("new-this-year-row-Saltmarsh Oyster Bar").exists,
                      "Both places count once, despite Harbor's repeat visit")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        openPlace("harbor", "Harbor Lantern Café")
        waitFor(element("detail-overflow")).tap()
        waitFor(element("detail-remove-ranking")).tap()
        waitFor(element("confirm-remove-ranking")).tap()
        waitFor(element("detail-log"), timeout: 15)
        waitFor(app.staticTexts["Unranked memory"])
        let memory = app.staticTexts["Sunset tarts on the terrace."].firstMatch
        for _ in 0..<6 where !memory.isHittable { app.swipeUp() }
        XCTAssertTrue(memory.exists, "Removing the ranking keeps the visit memory")
        capture("m8-08-ranking-removed-memory-kept")
        tab("Profile").tap()
        let travel = waitFor(element("mini-globe"), timeout: 10)
        XCTAssertTrue(travel.label.contains("1 country, 1 city"), "Travel counts keep retained visits: \(travel.label)")
    }

    func testAllSevenCategoriesRankIndependentlyInOneSession() {
        launch(scenario: "empty", tab: "search")
        let places: [(query: String, name: String, category: String)] = [
            ("harbor", "Harbor Lantern Café", "Food & Drink"), ("cedar", "Cedar Ridge Trail", "Outdoors"),
            ("willow", "Willow Bay", "Day Trips"), ("quay", "North Quay Gallery", "Culture"),
            ("moonline", "Moonline Jazz Room", "Nightlife"), ("kite", "Blue Kite Workshop", "Activities"),
            ("aster", "Aster House", "Stays"),
        ]
        for place in places {
            openPlace(place.query, place.name)
            let score = log()
            XCTAssertTrue(score.contains("8.4"), "\(place.name) is first in \(place.category): \(score)")
            XCTAssertFalse(element("rating-comparison").exists, "No comparison across categories")
            XCTAssertTrue(element("rating-result-position").label.contains(place.category))
            finishRating()
        }
        tab("Your Lists").tap()
        waitFor(element("lists-root"), timeout: 10)
        capture("m8-09-seven-categories-been")
        // Each place is in Been: the list's own search finds it (no scrolling through recycled rows).
        for place in places {
            type(place.name, into: "list-search-field")
            waitFor(element("experience-row-\(place.name)"), timeout: 8)
            element("list-search-field-clear").tap()
        }
        element("list-search-field").typeText("\n")   // the keyboard would cover the tab bar
        tab("Profile").tap()
        waitFor(element("profile-root"), timeout: 10)
        reveal(app.segmentedControls["profile-tabs"].buttons["Travel Profile"], in: "profile-root").tap()
        for place in places {
            let row = element("travel-row-category-\(Self.rawCategory(place.category))")
            reveal(row, in: "profile-root")
            XCTAssertTrue(row.label.contains("1 place"), "\(place.category): \(row.label)")
        }
        capture("m8-10-seven-categories-travel")
    }

    private static func rawCategory(_ title: String) -> String {
        ["Food & Drink": "food_drink", "Outdoors": "outdoors", "Day Trips": "day_trips", "Culture": "culture",
         "Nightlife": "nightlife", "Activities": "activities", "Stays": "stays"][title]!
    }
}
