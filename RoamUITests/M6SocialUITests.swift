import XCTest

/// Fixture journeys for activity, friendship, sharing and trip invitations.
final class M6SocialUITests: RoamUITestCase {
    private func first(_ prefix: String, type: XCUIElement.ElementType = .any) -> XCUIElement {
        app.descendants(matching: type).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
    }

    @discardableResult
    private func reveal(_ target: XCUIElement, in scrollIdentifier: String, maxSwipes: Int = 10,
                        file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let scroll = element(scrollIdentifier)
        for _ in 0..<maxSwipes {
            if target.exists && target.isHittable { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(target.exists && target.isHittable, "Not reachable: \(target)", file: file, line: line)
        return target
    }

    private func card(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'feed-card-'"))
            .containing(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func openProfile(handle: String) {
        waitFor(element("open-friends")).tap()
        waitFor(element("find-people")).tap()
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

    func testFeedShowsFriendVisitsNewestFirstAndLikesOptimistically() {
        launch(tab: "friends")
        waitFor(element("feed-list"), timeout: 10)
        let newest = first("feed-card-")
        XCTAssertTrue(newest.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Theo Park")).firstMatch.exists,
                      "The newest friend activity leads the feed")
        capture("m6-01-feed")
        let like = newest.buttons["like-button"]
        let before = like.label
        like.tap()
        let liked = NSPredicate(format: "label BEGINSWITH 'Liked'")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: liked, object: like)], timeout: 5), .completed,
                       "Like toggled from \(before)")
        capture("m6-02-feed-liked")
    }

    func testCommentFailureKeepsTextAndRetryPostsOnce() {
        launch(scenario: "comment-uncertain", tab: "profile")
        waitFor(element("profile-activity"), timeout: 10)
        let harbor = card(containing: "Custard tarts")
        reveal(harbor, in: "profile-root", maxSwipes: 8)
        harbor.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'feed-comments-'")).firstMatch.tap()
        waitFor(element("activity-detail"))
        waitFor(app.staticTexts["Adding this to my Lisbon list right now."])
        let field = waitFor(element("comment-field"))
        field.tap()
        field.typeText("Thanks Theo, go at sunset!")
        element("comment-send").tap()
        waitFor(element("comment-error"), timeout: 10)
        XCTAssertEqual(field.value as? String, "Thanks Theo, go at sunset!", "A failed send keeps the comment text")
        capture("m6-03-comment-send-failed")
        element("comment-send").tap()
        waitFor(app.staticTexts["Thanks Theo, go at sunset!"], timeout: 10)
        waitForDisappearance(element("comment-error"))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "Thanks Theo, go at sunset!")).count, 1,
                       "Retrying the uncertain send posted exactly one comment")
        capture("m6-04-comment-posted-once")
    }

    func testNotificationsGroupUnreadRouteToPostAndMarkAllRead() {
        launch(tab: "friends")
        let bell = waitFor(element("open-notifications"))
        XCTAssertTrue(bell.label.contains("2 unread"))
        bell.tap()
        waitFor(element("notification-comment-theowanders"), timeout: 10)
        XCTAssertTrue(app.staticTexts["Unread"].exists)
        XCTAssertTrue(app.staticTexts["Earlier"].exists)
        capture("m6-05-notifications")
        waitFor(element("notification-comment-theowanders")).tap()
        waitFor(element("activity-detail"))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        waitFor(element("notification-follow-samexplores"))
        waitFor(app.buttons["notifications-mark-all"]).tap()
        waitForDisappearance(app.staticTexts["Unread"])
        capture("m6-06-notifications-all-read")
    }

    func testAcceptingRequestAddsTheMemberToFriends() {
        launch(tab: "friends")
        waitFor(element("open-friends")).tap()
        waitFor(element("follow-segment")).buttons["Requests"].tap()
        let lena = waitFor(element("member-row-lenaeats"), timeout: 10)
        capture("m6-07-friend-requests")
        waitFor(lena.buttons["follow-button"]).tap()
        waitForDisappearance(lena)
        waitFor(element("follow-segment")).buttons["Friends"].tap()
        waitFor(element("member-row-lenaeats"), timeout: 10)
        capture("m6-08-friends-after-accepting")
    }

    func testMuteHidesFeedPostsButKeepsProfileActivity() {
        launch(tab: "friends")
        waitFor(element("feed-list"), timeout: 10)
        XCTAssertTrue(card(containing: "Theo Park").exists)
        openProfile(handle: "theowanders")
        waitFor(element("profile-overflow")).tap()
        waitFor(element("profile-mute")).tap()
        waitFor(element("profile-muted"), timeout: 5)
        reveal(element("profile-activity"), in: "profile-root")
        XCTAssertTrue(first("feed-card-").exists, "A muted member's profile still shows their posts")
        capture("m6-09-muted-profile")
        element("tab-friends").tap()
        waitFor(element("feed-list"), timeout: 10)
        waitForDisappearance(card(containing: "Theo Park"), timeout: 10)
        capture("m6-10-feed-without-muted")
    }

    func testBlockRemovesTheMemberFromFeedAndSearch() {
        launch(tab: "friends")
        waitFor(element("feed-list"), timeout: 10)
        openProfile(handle: "theowanders")
        waitFor(element("profile-overflow")).tap()
        waitFor(element("profile-block")).tap()
        capture("m6-11-block-confirmation")
        waitFor(element("confirm-block")).tap()
        waitForDisappearance(element("profile-root"), timeout: 10)
        let field = waitFor(element("member-search-field"))
        field.tap()
        field.typeText(XCUIKeyboardKey.delete.rawValue + "o")
        XCTAssertFalse(element("member-row-theowanders").waitForExistence(timeout: 3), "A blocked member is excluded from search")
        field.typeText("\n")
        element("tab-friends").tap()
        waitFor(element("feed-list"), timeout: 10)
        XCTAssertFalse(card(containing: "Theo Park").waitForExistence(timeout: 3), "The blocked member's posts leave the feed")
        capture("m6-12-feed-after-block")
    }

    func testSentPlaceOpensTheMapWithItsSenderAndNote() {
        launch(tab: "myplaces")
        waitFor(element("myplaces-sheet-header")).tap()
        let received = waitFor(element("open-received-shares"))
        if !received.isHittable { app.swipeUp() }
        received.tap()
        waitFor(element("received-shares"))
        waitFor(element("foryou-pick-open-Old Mill Cinema")).tap()
        waitFor(element("experience-detail"))
        waitFor(element("detail-map"))
        waitFor(app.staticTexts["The Sunday double bill is the best night out in Edinburgh."])
        capture("m6-13-received-place")
    }

    func testAcceptingTripInvitationMakesTheTripLinkAvailable() {
        launch(scenario: "social-activities", tab: "myplaces")
        waitFor(element("myplaces-sheet-header")).tap()
        let invitations = waitFor(element("open-trip-invitations"))
        if !invitations.isHittable { app.swipeUp() }
        invitations.tap()
        waitFor(element("trip-invitations"))
        waitFor(app.staticTexts["Lisbon weekend"])
        waitFor(element("accept-trip-invitation")).tap()
        waitFor(element("trip-detail"))
        waitFor(app.staticTexts["Lisbon weekend"])
        capture("m6-14-accepted-trip")

        element("tab-friends").tap()
        let trip = waitFor(element("activity-trip"))
        trip.tap()
        waitFor(element("trip-detail"))
    }

    func testTaggedFriendCanRemoveTheirOwnTag() {
        launch(scenario: "social-activities", tab: "friends")
        let harbor = card(containing: "Maya was right about the tarts.")
        waitFor(harbor)
        XCTAssertTrue(harbor.staticTexts["With Maya Chen"].exists)
        let comments = harbor.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'feed-comments-'")).firstMatch
        reveal(comments, in: "feed-list").tap()
        waitFor(element("activity-overflow")).tap()
        waitFor(element("remove-my-tag")).tap()
        waitForDisappearance(app.staticTexts["With Maya Chen"])
        capture("m6-15-tag-removed")
    }

    func testOwnerRemovesPostButKeepsTheRanking() {
        launch(tab: "profile")
        waitFor(element("profile-activity"), timeout: 10)
        let own = card(containing: "Back again")
        reveal(own, in: "profile-root", maxSwipes: 8)
        own.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'feed-comments-'")).firstMatch.tap()
        waitFor(element("activity-detail"))
        waitFor(element("activity-overflow")).tap()
        waitFor(element("activity-remove")).tap()
        capture("m6-16-remove-post-confirmation")
        waitFor(element("confirm-remove-post")).tap()
        waitForDisappearance(element("activity-detail"), timeout: 10)
        XCTAssertFalse(card(containing: "Back again").waitForExistence(timeout: 3))
        element("tab-foryou").tap()
        let search = waitFor(element("discover-search"))
        search.tap()
        search.typeText("harbor")
        waitFor(element("experience-row-Harbor Lantern Café"), timeout: 10).staticTexts["Harbor Lantern Café"].firstMatch.tap()
        XCTAssertTrue(waitFor(element("detail-add-visit")).label.contains("Been"), "Removing a post keeps the ranked place")
    }

    func testLargeTextFeedAndPostKeepActionsReachable() {
        launch(tab: "friends", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        waitFor(element("feed-list"), timeout: 10)
        capture("m6-18-large-text-feed")
        let comments = first("feed-card-").buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'feed-comments-'")).firstMatch
        reveal(comments, in: "feed-list", maxSwipes: 6)
        comments.tap()
        waitFor(element("activity-detail"))
        XCTAssertTrue(waitFor(element("comment-field")).isHittable, "The composer stays reachable at large text")
        capture("m6-19-large-text-post")
    }

    func testEmptyFeedOffersFindPeople() {
        launch(scenario: "empty", tab: "friends")
        waitFor(element("feed-empty"), timeout: 10)
        capture("m6-17-feed-empty")
        app.buttons["Find people"].tap()
        waitFor(element("member-search-field"))
    }
}
