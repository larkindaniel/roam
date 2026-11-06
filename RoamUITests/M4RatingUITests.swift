import XCTest

/// Observable fixture journeys. Real RPC transaction evidence is a separate backend suite.
final class M4RatingUITests: RoamUITestCase {
    private func openDetail(query: String, name: String) {
        let search = waitFor(element("experience-search-field"))
        search.tap()
        search.typeText(query)
        waitFor(element("experience-row-\(name)"), timeout: 10).staticTexts[name].firstMatch.tap()
        waitFor(element("experience-detail"))
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

    private func chooseCategory(_ title: String) {
        ratingControl("rating-category-picker").tap()
        waitFor(app.buttons[title]).tap()
        XCTAssertTrue(element("rating-category").label.contains(title))
    }

    private func chooseSentiment(_ name: String) {
        ratingControl("rating-sentiment-\(name)").tap()
        waitFor(element("rating-details"))
        XCTAssertTrue(element("rating-publication-disclosure").exists)
    }

    private func assertUnknownDateSwitch(_ toggle: XCUIElement, value: String,
                                         file: StaticString = #filePath, line: UInt = #line) {
        let expected = NSPredicate { _, _ in toggle.value as? String == value }
        let status = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: expected, object: toggle)], timeout: 3)
        if status != .completed {
            let attachment = XCTAttachment(string: app.debugDescription)
            attachment.name = "m4-date-editor-state-mismatch"
            attachment.lifetime = .keepAlways
            add(attachment)
            capture("m4-date-editor-state-mismatch", settle: 0)
        }
        XCTAssertEqual(status, .completed, "Date unknown switch must be \(value). Actual: \(toggle.debugDescription)", file: file, line: line)
    }

    func testFirstRatingShowsNumericResultInEveryCategoryWithoutComparison() {
        let categories = ["Food & Drink", "Outdoors", "Day Trips", "Culture", "Nightlife", "Activities", "Stays"]
        for (index, category) in categories.enumerated() {
            launch(scenario: "empty", tab: "search")
            openDetail(query: "terrace", name: "Terrace Steps Café")
            waitFor(element("detail-log")).tap()
            waitFor(element("rating-flow"))
            chooseCategory(category)
            chooseSentiment("liked")
            XCTAssertFalse(element("rating-result").exists)
            ratingControl("rating-okay").tap()
            waitFor(element("rating-result"), timeout: 15)
            XCTAssertFalse(element("rating-comparison").exists)
            XCTAssertTrue(element("rating-result-score").label.contains("8.4"))
            XCTAssertTrue(element("rating-result-position").label.contains("Position 1 of 1"))
            XCTAssertTrue(element("rating-result-position").label.contains(category))
            capture(String(format: "m4-%02d-first-rating-%d", index + 1, index + 1))
            ratingControl("rating-done").tap()
            waitForDisappearance(element("rating-flow"))
            waitFor(element("detail-add-visit"))
        }
    }

    func testTooToughSharesExistingGroupScoreAndShowsTie() {
        launch(tab: "search")
        openDetail(query: "terrace", name: "Terrace Steps Café")
        waitFor(element("detail-log")).tap()
        chooseCategory("Food & Drink")
        chooseSentiment("liked")
        ratingControl("rating-okay").tap()
        waitFor(element("rating-comparison"))
        XCTAssertTrue(element("rating-place").label.contains("Terrace Steps Café"))
        XCTAssertTrue(element("rating-category").label.contains("Food & Drink"))
        XCTAssertFalse(element("rating-undo").isEnabled)
        capture("m4-08-comparison")
        ratingControl("rating-too-tough").tap()
        waitFor(element("rating-result"), timeout: 15)
        XCTAssertTrue(element("rating-result-score").label.contains("6.7"))
        XCTAssertTrue(app.staticTexts["Tied with 1 other experience."].exists)
        capture("m4-09-tied-result")
    }

    func testOptionalEditorsCancelDoneUndoAndSkip() {
        launch(tab: "search")
        openDetail(query: "terrace", name: "Terrace Steps Café")
        waitFor(element("detail-log")).tap()
        chooseCategory("Food & Drink")
        capture("m4-23-sentiment-category")
        chooseSentiment("liked")
        ratingControl("rating-edit-note").tap()
        let note = waitFor(element("rating-note-text"))
        note.tap(); note.typeText("Canceled memory")
        element("rating-editor-cancel").tap()
        XCTAssertFalse(app.staticTexts["Canceled memory"].exists)
        ratingControl("rating-edit-note").tap()
        waitFor(element("rating-note-text")).tap()
        element("rating-note-text").typeText("A quiet evening above the harbor.")
        element("rating-editor-done").tap()
        XCTAssertTrue(app.staticTexts["A quiet evening above the harbor."].exists)
        let knownDate = ratingControl("rating-edit-date").label
        XCTAssertFalse(knownDate.contains("Date unknown"))
        element("rating-edit-date").tap()
        let canceledUnknown = waitFor(app.switches["rating-date-unknown"])
        assertUnknownDateSwitch(canceledUnknown, value: "0")
        XCTAssertTrue(canceledUnknown.isHittable)
        canceledUnknown.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        assertUnknownDateSwitch(canceledUnknown, value: "1")
        element("rating-editor-cancel").tap()
        waitForDisappearance(element("rating-date-unknown"))
        XCTAssertEqual(waitFor(element("rating-edit-date")).label, knownDate, "Cancel discards the editor's unknown-date change")
        ratingControl("rating-edit-date").tap()
        let appliedUnknown = waitFor(app.switches["rating-date-unknown"])
        assertUnknownDateSwitch(appliedUnknown, value: "0", file: #filePath, line: #line)
        XCTAssertTrue(appliedUnknown.isHittable)
        appliedUnknown.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        assertUnknownDateSwitch(appliedUnknown, value: "1")
        capture("m4-24-date-editor-unknown")
        element("rating-editor-done").tap()
        waitForDisappearance(element("rating-date-unknown"))
        let appliedDate = waitFor(element("rating-edit-date"))
        let savedUnknown = NSPredicate { _, _ in appliedDate.label.contains("Date unknown") }
        let status = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: savedUnknown, object: appliedDate)], timeout: 3)
        if status != .completed {
            let attachment = XCTAttachment(string: app.debugDescription)
            attachment.name = "m4-date-after-done-mismatch"
            attachment.lifetime = .keepAlways
            add(attachment)
            capture("m4-date-after-done-mismatch", settle: 0)
        }
        XCTAssertEqual(status, .completed, "Done must apply the unknown date. Actual date row: \(appliedDate.debugDescription)")
        ratingControl("rating-edit-date").tap()
        assertUnknownDateSwitch(waitFor(app.switches["rating-date-unknown"]), value: "1")
        element("rating-editor-cancel").tap()
        waitForDisappearance(element("rating-date-unknown"))
        XCTAssertTrue(element("rating-edit-date").label.contains("Date unknown"), "Reopening and canceling preserves the applied unknown date")
        capture("m4-10-details-before-comparison")
        ratingControl("rating-okay").tap()
        waitFor(element("rating-comparison"))
        let firstExisting = element("rating-prefer-existing").label
        ratingControl("rating-prefer-new").tap()
        XCTAssertTrue(waitFor(element("rating-undo")).isEnabled)
        ratingControl("rating-undo").tap()
        XCTAssertEqual(element("rating-prefer-existing").label, firstExisting)
        XCTAssertFalse(element("rating-undo").isEnabled)
        capture("m4-11-comparison-after-undo")
        XCTAssertTrue(element("rating-skip-explanation").label.contains("approximately"))
        ratingControl("rating-skip").tap()
        waitFor(element("rating-result"), timeout: 15)
        XCTAssertTrue(element("rating-result-score").label.contains("8.4"))
        capture("m4-12-skipped-result")
    }

    func testKeepDraftResumesAndDiscardDoesNotPublish() {
        launch(tab: "search")
        openDetail(query: "terrace", name: "Terrace Steps Café")
        waitFor(element("detail-log")).tap()
        chooseCategory("Food & Drink")
        chooseSentiment("fine")
        element("rating-close").tap()
        waitFor(app.buttons["Keep draft"]).tap()
        waitForDisappearance(element("rating-flow"))
        XCTAssertTrue(element("detail-log").exists, "Closing a draft has not created a rating")
        element("detail-log").tap()
        waitFor(element("rating-details"))
        XCTAssertTrue(element("rating-sentiment").label.contains("It was fine"))
        capture("m4-13-resumed-draft")
        element("rating-close").tap()
        waitFor(app.buttons["Discard draft"]).tap()
        waitForDisappearance(element("rating-flow"))
        element("detail-log").tap()
        waitFor(element("rating-sentiment-liked"))
        XCTAssertFalse(element("rating-details").exists)
    }

    func testFirstFineAndDislikedShowTheirImmediateScores() {
        for (index, entry) in [("fine", "5.0"), ("disliked", "1.7")].enumerated() {
            launch(scenario: "empty", tab: "search")
            openDetail(query: "terrace", name: "Terrace Steps Café")
            waitFor(element("detail-log")).tap()
            chooseCategory("Food & Drink")
            chooseSentiment(entry.0)
            ratingControl("rating-okay").tap()
            waitFor(element("rating-result"), timeout: 15)
            XCTAssertFalse(element("rating-comparison").exists)
            XCTAssertTrue(element("rating-result-score").label.contains(entry.1))
            capture("m4-\(17 + index)-first-\(entry.0)")
        }
    }

    func testComparisonControlsAtAccessibilityTextSize() {
        launch(tab: "search", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        openDetail(query: "terrace", name: "Terrace Steps Café")
        waitFor(element("detail-log")).tap()
        chooseCategory("Food & Drink")
        chooseSentiment("liked")
        ratingControl("rating-okay").tap()
        waitFor(element("rating-comparison"))
        XCTAssertGreaterThanOrEqual(ratingControl("rating-prefer-new").frame.height, 44)
        XCTAssertGreaterThanOrEqual(ratingControl("rating-prefer-existing").frame.height, 44)
        XCTAssertTrue(ratingControl("rating-skip").isHittable)
        XCTAssertTrue(ratingControl("rating-too-tough").isHittable)
        capture("m4-19-comparison-ax-large")
        ratingControl("rating-too-tough").tap()
        waitFor(element("rating-result"), timeout: 15)
        XCTAssertTrue(ratingControl("rating-done").isHittable)
    }

    func testRevisitRerankAndRemovalRetainMemory() {
        launch(tab: "search")
        openDetail(query: "harbor", name: "Harbor Lantern Café")
        waitFor(element("detail-add-visit")).tap()
        waitFor(element("rating-details"))
        XCTAssertFalse(element("rating-sentiment-liked").exists)
        ratingControl("rating-edit-note").tap()
        waitFor(element("rating-note-text")).tap()
        element("rating-note-text").typeText("A later return by the water.")
        element("rating-editor-done").tap()
        ratingControl("rating-okay").tap()
        waitFor(element("rating-visit-saved"), timeout: 15)
        XCTAssertFalse(element("rating-comparison").exists)
        capture("m4-14-revisit-saved")
        ratingControl("rating-done").tap()
        waitFor(element("detail-overflow")).tap()
        waitFor(element("detail-rerank")).tap()
        chooseSentiment("fine")
        XCTAssertTrue(app.staticTexts["A later return by the water."].exists, "Rerank retains its existing anchor memory")
        ratingControl("rating-okay").tap()
        waitFor(element("rating-comparison"))
        XCTAssertFalse(element("rating-prefer-existing").label.contains("Harbor Lantern Café"), "Rerank excludes its own existing entry")
        ratingControl("rating-too-tough").tap()
        waitFor(element("rating-result"), timeout: 15)
        XCTAssertTrue(element("rating-result-score").label.contains("5.0"))
        capture("m4-15-rerank-result")
        ratingControl("rating-done").tap()
        waitFor(element("detail-overflow")).tap()
        waitFor(element("detail-remove-ranking")).tap()
        waitFor(app.buttons["Cancel"]).tap()
        XCTAssertTrue(element("detail-add-visit").exists, "Cancel leaves the ranking intact")
        element("detail-overflow").tap()
        element("detail-remove-ranking").tap()
        waitFor(element("confirm-remove-ranking")).tap()
        waitFor(element("detail-log"), timeout: 15)
        let memory = app.staticTexts["A later return by the water."].firstMatch
        for _ in 0..<6 where !memory.isHittable { app.swipeUp() }
        XCTAssertTrue(memory.exists, "Removing the ranking keeps the populated visit memory")
        capture("m4-16-ranking-removed-memory-retained")
        tab("My Places").tap()
        waitFor(element("list-kind")).buttons["Want to Go"].tap()
        XCTAssertFalse(element("experience-row-Harbor Lantern Café").exists, "Removal does not recreate a Want bookmark")
    }

    func testResultCloseReturnsToUpdatedSearchAndLastVisitRequiresDistinctConfirmation() {
        launch(scenario: "empty", tab: "search")
        let search = waitFor(element("experience-search-field"))
        search.tap(); search.typeText("terrace")
        let row = waitFor(element("experience-row-Terrace Steps Café"))
        waitFor(element("log-Terrace Steps Café")).tap()
        chooseCategory("Food & Drink")
        chooseSentiment("liked")
        XCTAssertEqual(app.keyboards.count, 0, "Row Log dismisses the Search keyboard before presenting rating details")
        ratingControl("rating-okay").tap()
        waitFor(element("rating-result"), timeout: 15)
        element("rating-close").tap()
        waitForDisappearance(element("rating-flow"))
        XCTAssertFalse(app.buttons["Keep draft"].exists, "An acknowledged result closes directly")
        let updatedScore = row.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Your score 8.4 out of 10")).firstMatch
        waitFor(updatedScore)
        XCTAssertEqual(element("log-Terrace Steps Café").label, "Add visit Terrace Steps Café")
        capture("m4-20-updated-invoking-search")
        row.staticTexts["Terrace Steps Café"].firstMatch.tap()
        waitFor(element("experience-detail"))
        let deletion = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "detail-delete-visit-")).firstMatch
        for _ in 0..<8 where !deletion.isHittable { app.swipeUp() }
        waitFor(deletion).tap()
        waitFor(element("confirm-delete-last-visit"))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "your ranking and rating activity will also be removed")).firstMatch.exists)
        capture("m4-21-last-visit-confirmation")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(deletion.exists)
        deletion.tap()
        element("confirm-delete-last-visit").tap()
        for _ in 0..<8 where !element("detail-log").isHittable { app.swipeDown() }
        waitFor(element("detail-log"), timeout: 15)
        XCTAssertFalse(element("detail-memories").exists)
        capture("m4-22-last-visit-deleted")
    }
}
