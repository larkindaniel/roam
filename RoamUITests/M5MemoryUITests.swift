import XCTest

/// M5 fixture journeys: memory editors, private notes, the real system Photos picker, per-photo
/// upload failure/retry/removal, gallery/viewer states, reports and retained memories.
/// Real Storage/inspection/RLS evidence is the separate backend suite.
final class M5MemoryUITests: RoamUITestCase {
    private let harborNote = "Back again: still the best terrace in town."

    private func openDetail(query: String, name: String) {
        let search = waitFor(element("experience-search-field"))
        search.tap()
        search.typeText(query)
        waitFor(element("experience-row-\(name)"), timeout: 10).staticTexts[name].firstMatch.tap()
        waitFor(element("experience-detail"))
    }

    private func first(_ prefix: String, type: XCUIElement.ElementType = .any) -> XCUIElement {
        app.descendants(matching: type).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
    }

    /// Scrolls the screen's main scroll view until `target` is hittable.
    @discardableResult
    private func reveal(_ target: XCUIElement, in scrollIdentifier: String = "experience-detail", maxSwipes: Int = 10,
                        file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let scroll = element(scrollIdentifier)
        for _ in 0..<maxSwipes {
            if target.exists && target.isHittable { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(target.exists && target.isHittable, "Not reachable: \(target)", file: file, line: line)
        return target
    }

    @discardableResult
    private func ratingControl(_ identifier: String) -> XCUIElement { reveal(element(identifier), in: "rating-scroll", maxSwipes: 8) }

    private func waitUntilEnabled(_ target: XCUIElement, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: target)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: timeout), .completed, "Never enabled: \(target)", file: file, line: line)
    }

    /// Places the cursor after the existing text before typing.
    private func append(_ text: String, to editor: XCUIElement) {
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.92)).tap()
        editor.typeText(text)
    }

    func testMemoryEditorCancelKeepsDetailAndDoneUpdatesItWithoutANewPost() {
        launch(tab: "search")
        openDetail(query: "harbor", name: "Harbor Lantern Café")
        let edit = reveal(first("detail-edit-visit-", type: .button))
        capture("m5-01-detail-own-memories")
        edit.tap()
        waitFor(element("memory-editor"))
        append(" Ask for the corner table.", to: waitFor(element("memory-note-text")))
        capture("m5-02-memory-editor-draft")
        element("memory-editor-cancel").tap()
        waitForDisappearance(element("memory-editor"))
        XCTAssertTrue(app.staticTexts[harborNote].exists, "Cancel leaves the saved memory unchanged")
        reveal(first("detail-edit-visit-", type: .button)).tap()
        let note = waitFor(element("memory-note-text"))
        XCTAssertEqual(note.value as? String, harborNote, "A cancelled edit was discarded, not kept as a draft")
        append(" Ask for the corner table.", to: note)
        element("memory-editor-done").tap()
        waitForDisappearance(element("memory-editor"), timeout: 10)
        waitFor(app.staticTexts["\(harborNote) Ask for the corner table."])
        capture("m5-03-detail-after-memory-edit")
    }

    func testPrivateNoteIsSeparateFromPublicMemoriesAndCanBeDeleted() {
        launch(tab: "search")
        openDetail(query: "harbor", name: "Harbor Lantern Café")
        let row = reveal(element("detail-private-note"))
        XCTAssertTrue(row.label.contains("Add a private note"))
        row.tap()
        waitFor(element("private-note-editor"))
        waitFor(element("private-note-warning"))
        let text = waitFor(element("private-note-text"))
        text.tap()
        text.typeText("Locker 12 by the stairs.")
        capture("m5-04-private-note-editor")
        element("private-note-done").tap()
        waitForDisappearance(element("private-note-editor"), timeout: 10)
        XCTAssertTrue(reveal(element("detail-private-note")).label.contains("Private note"))
        XCTAssertFalse(app.staticTexts["Locker 12 by the stairs."].exists, "Private text never appears on the public detail")
        element("detail-private-note").tap()
        XCTAssertEqual(waitFor(element("private-note-text")).value as? String, "Locker 12 by the stairs.")
        waitFor(element("private-note-delete")).tap()
        waitFor(element("confirm-delete-private-note")).tap()
        waitForDisappearance(element("private-note-editor"), timeout: 10)
        XCTAssertTrue(reveal(element("detail-private-note")).label.contains("Add a private note"))
    }

    func testSystemPickerUploadFailureRetryRemovalAndPublishedPhoto() {
        launch(scenario: "media-partial-failure", tab: "search")
        openDetail(query: "terrace", name: "Terrace Steps Café")
        waitFor(element("detail-log")).tap()
        ratingControl("rating-category-picker").tap()
        waitFor(app.buttons["Food & Drink"]).tap()
        ratingControl("rating-sentiment-liked").tap()
        ratingControl("rating-edit-photos").tap()
        waitFor(element("photo-editor"))
        element("photo-picker").tap()
        waitFor(app.navigationBars["Photos"].buttons["Cancel"], timeout: 15).tap()
        XCTAssertEqual(waitFor(element("photo-count")).label, "0 of 6 photos", "Cancelling the system picker changes nothing")
        element("photo-picker").tap()
        // The system picker is a remote view: its cells exist but report not hittable, so tap their frames.
        let grid = app.images.matching(identifier: "PXGGridLayout-Info")
        waitFor(grid.element(boundBy: 1), timeout: 15)
        grid.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        grid.element(boundBy: 1).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let pickerDone = app.navigationBars["Photos"].buttons["Done"]
        waitUntilEnabled(pickerDone)
        capture("m5-05a-system-picker-selection")
        pickerDone.tap()
        let failed = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'photo-status-' AND label == %@", "Upload failed · Retry or remove")).firstMatch
        waitFor(failed, timeout: 20)
        XCTAssertEqual(element("photo-count").label, "2 of 6 photos")
        XCTAssertFalse(app.buttons["photo-editor-done"].isEnabled, "A failed photo blocks Done instead of disappearing")
        capture("m5-05-photo-upload-failed")
        let failedID = failed.identifier.replacingOccurrences(of: "photo-status-", with: "")
        element("photo-retry-\(failedID)").tap()
        waitForDisappearance(failed, timeout: 20)
        waitUntilEnabled(app.buttons["photo-editor-done"])
        capture("m5-06-photos-ready-after-retry")
        first("photo-remove-", type: .button).tap()
        XCTAssertEqual(waitFor(element("photo-count")).label, "1 of 6 photos")
        element("photo-editor-done").tap()
        waitForDisappearance(element("photo-editor"))
        XCTAssertTrue(element("rating-edit-photos").label.contains("1 photo"))
        ratingControl("rating-okay").tap()
        waitFor(element("rating-comparison"), timeout: 15)
        ratingControl("rating-too-tough").tap()
        waitFor(element("rating-result"), timeout: 15)
        capture("m5-07-result-after-photo-upload")
        ratingControl("rating-done").tap()
        waitForDisappearance(element("rating-flow"))
        reveal(first("detail-visit-photo-", type: .button))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'detail-visit-photo-'")).count, 1,
                       "Exactly the one kept photo was attached")
    }

    func testGalleryViewerRemovesOwnPhotosToEmptyAndReportsAnotherMembersPhoto() {
        launch(tab: "search")
        openDetail(query: "harbor", name: "Harbor Lantern Café")
        reveal(first("detail-visit-photo-", type: .button)).tap()
        waitFor(element("visit-gallery"))
        waitFor(element("gallery-photo-0"))
        XCTAssertTrue(element("gallery-photo-1").exists)
        capture("m5-08-visit-gallery")
        element("gallery-photo-0").tap()
        waitFor(element("photo-viewer"))
        capture("m5-09-viewer-own-photo")
        waitUntilEnabled(element("viewer-remove"))
        element("viewer-remove").tap()
        waitFor(element("confirm-remove-photo")).tap()
        waitUntilEnabled(element("viewer-remove"))
        element("viewer-remove").tap()
        waitFor(element("confirm-remove-photo")).tap()
        waitFor(app.staticTexts["No photos"], timeout: 10)
        element("viewer-close").tap()
        waitFor(element("gallery-empty"))
        capture("m5-10-gallery-empty-after-removal")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        waitFor(element("experience-detail"))
        let theirs = reveal(first("memory-photo-", type: .button))
        theirs.tap()
        waitFor(element("gallery-photo-0")).tap()
        XCTAssertFalse(element("viewer-remove").exists, "Another member's photo cannot be removed")
        waitFor(element("viewer-report")).tap()
        waitFor(element("report-reason-inappropriate")).tap()
        element("report-send").tap()
        waitFor(element("report-received"), timeout: 10)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "hasn't been reviewed yet")).firstMatch.exists,
                      "The receipt never claims human review")
        capture("m5-11-photo-report-receipt")
    }

    func testRemovingTheRankingKeepsTheMemoryOnDetail() {
        launch(tab: "search")
        openDetail(query: "cedar", name: "Cedar Ridge Trail")
        waitFor(element("detail-overflow")).tap()
        waitFor(element("detail-remove-ranking")).tap()
        waitFor(element("confirm-remove-ranking")).tap()
        waitFor(app.staticTexts["Unranked memory"], timeout: 10)
        reveal(app.staticTexts["Larches turning gold near the top. Bring layers."])
        XCTAssertTrue(first("detail-visit-photo-", type: .button).exists, "The memory keeps its photo after the ranking is removed")
        capture("m5-12-retained-memory-after-ranking-removal")
    }

    func testInterruptedMemoryEditSurvivesRelaunchUntilDiscarded() {
        launch(tab: "search")
        openDetail(query: "harbor", name: "Harbor Lantern Café")
        reveal(first("detail-edit-visit-", type: .button)).tap()
        append(" Interrupted draft.", to: waitFor(element("memory-note-text")))
        app.terminate()
        launch(tab: "search", resetState: false)
        openDetail(query: "harbor", name: "Harbor Lantern Café")
        reveal(first("detail-edit-visit-", type: .button)).tap()
        XCTAssertEqual(waitFor(element("memory-note-text")).value as? String, "\(harborNote) Interrupted draft.",
                       "The owner's interrupted draft is restored after relaunch")
        capture("m5-13-restored-memory-draft")
        element("memory-editor-cancel").tap()
        waitForDisappearance(element("memory-editor"))
        reveal(first("detail-edit-visit-", type: .button)).tap()
        XCTAssertEqual(waitFor(element("memory-note-text")).value as? String, harborNote, "Cancel discarded the restored draft")
    }

    func testGalleryLoadingThenFailureOffersRetry() {
        launch(scenario: "gallery-read-failure", tab: "search", latency: 1_500)
        openDetail(query: "harbor", name: "Harbor Lantern Café")
        reveal(first("detail-visit-photo-", type: .button)).tap()
        waitFor(element("gallery-loading"), timeout: 5)
        capture("m5-14a-gallery-loading", settle: 0)
        waitFor(element("gallery-error"), timeout: 10)
        capture("m5-14-gallery-load-error")
        waitFor(app.buttons["Try again"]).tap()
        waitFor(element("gallery-photo-0"), timeout: 10)
    }

    func testLargeTextKeepsMemoryActionsGalleryAndEditorReachable() {
        launch(tab: "search", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        openDetail(query: "harbor", name: "Harbor Lantern Café")
        reveal(first("detail-edit-visit-", type: .button), maxSwipes: 16)
        capture("m5-15-large-text-memories")
        first("detail-edit-visit-", type: .button).tap()
        waitFor(element("memory-editor"))
        XCTAssertTrue(element("memory-editor-done").isHittable)
        capture("m5-16-large-text-memory-editor")
        element("memory-editor-cancel").tap()
        waitForDisappearance(element("memory-editor"))
        reveal(first("memory-card-"), maxSwipes: 16)
        capture("m5-17-large-text-public-memories")
    }
}
