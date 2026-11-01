import XCTest

/// M6 fixture journeys: feed, likes, comments with failure/retry, notifications, follow graph,
/// mute, block, Shared Want to Go and post removal. Multi-account RLS evidence is the backend suite.
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
        element("log-place").tap()
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

    func testFeedShowsFollowedPostsNewestFirstAndLikesOptimistically() {
        launch(tab: "friends")
        waitFor(element("feed-list"), timeout: 10)
        let newest = first("feed-card-")
        XCTAssertTrue(newest.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Jonas Weber")).firstMatch.exists,
                      "The newest followed post leads the feed")
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
        launch(scenario: "comment-uncertain", tab: "friends")
        waitFor(element("feed-list"), timeout: 10)
        let harbor = card(containing: "Custard tarts")
        reveal(harbor, in: "feed-list", maxSwipes: 8)
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

    func testFollowersFollowingSearchAndFollowBack() {
        launch(tab: "profile")
        waitFor(element("profile-friends")).tap()
        waitFor(element("follow-list"))
        waitFor(element("member-row-lenaeats"), timeout: 10)
        XCTAssertTrue(element("member-row-samexplores").exists)
        capture("m6-07-followers")
        let followBack = element("member-row-lenaeats").buttons["follow-button"]
        XCTAssertTrue(followBack.label.contains("Follow"))
        followBack.tap()
        let following = NSPredicate(format: "label BEGINSWITH 'Following'")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: following, object: followBack)], timeout: 5), .completed)
        app.searchFields.firstMatch.tap()
        app.searchFields.firstMatch.typeText("sam")
        waitForDisappearance(element("member-row-lenaeats"), timeout: 5)
        XCTAssertTrue(element("member-row-samexplores").exists)
        capture("m6-08-followers-search")
        app.searchFields.firstMatch.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3))
        waitFor(element("member-row-lenaeats"), timeout: 5)
        app.buttons["Following"].firstMatch.tap()
        waitFor(element("member-row-jonashikes"), timeout: 10)
        XCTAssertTrue(element("member-row-lenaeats").exists, "The new follow appears in Following")
    }

    func testMuteHidesFeedPostsButKeepsProfileActivity() {
        launch(tab: "friends")
        waitFor(element("feed-list"), timeout: 10)
        XCTAssertTrue(card(containing: "Jonas Weber").exists)
        openProfile(handle: "jonashikes")
        waitFor(element("profile-overflow")).tap()
        waitFor(element("profile-mute")).tap()
        waitFor(element("profile-muted"), timeout: 5)
        reveal(element("profile-activity"), in: "profile-root")
        XCTAssertTrue(first("feed-card-").exists, "A muted member's profile still shows their posts")
        capture("m6-09-muted-profile")
        tab("Friends").tap()
        waitFor(element("feed-list"), timeout: 10)
        waitForDisappearance(card(containing: "Jonas Weber"), timeout: 10)
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
        tab("Friends").tap()
        waitFor(element("feed-list"), timeout: 10)
        XCTAssertFalse(card(containing: "Theo Park").waitForExistence(timeout: 3), "The blocked member's posts leave the feed")
        capture("m6-12-feed-after-block")
    }

    func testSharedWantToGoListMapAndHonestEmptyState() {
        launch(tab: "friends")
        openProfile(handle: "theowanders")
        waitFor(element("profile-shared-wants")).tap()
        waitFor(element("shared-wants"))
        waitFor(element("shared-wants-list"), timeout: 10)
        XCTAssertTrue(element("shared-wants-count").label.contains("2 places"))
        capture("m6-13-shared-wants-list")
        waitFor(element("map-list-toggle")).tap()
        waitFor(element("shared-wants-map"))
        capture("m6-14-shared-wants-map")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        openProfile(handle: "lenaeats")
        waitFor(element("profile-shared-wants")).tap()
        waitFor(element("shared-wants-empty"), timeout: 10)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Neither Want to Go list is changed")).firstMatch.exists)
        capture("m6-15-shared-wants-empty")
    }

    func testOwnerRemovesPostButKeepsTheRanking() {
        launch(tab: "friends")
        waitFor(element("feed-list"), timeout: 10)
        let own = card(containing: "Back again")
        reveal(own, in: "feed-list", maxSwipes: 8)
        own.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'feed-comments-'")).firstMatch.tap()
        waitFor(element("activity-detail"))
        waitFor(element("activity-overflow")).tap()
        waitFor(element("activity-remove")).tap()
        capture("m6-16-remove-post-confirmation")
        waitFor(element("confirm-remove-post")).tap()
        waitForDisappearance(element("activity-detail"), timeout: 10)
        XCTAssertFalse(card(containing: "Back again").waitForExistence(timeout: 3))
        element("log-place").tap()
        let search = waitFor(element("experience-search-field"))
        search.tap()
        search.typeText("harbor")
        waitFor(element("experience-row-Harbor Lantern Café"), timeout: 10).staticTexts["Harbor Lantern Café"].firstMatch.tap()
        waitFor(element("detail-your-score"))
        XCTAssertTrue(element("detail-your-score").label.contains("10.0"), "Removing a post keeps the ranking")
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

    func testFollowersEmptyStateForAMemberWithoutFollowers() {
        launch(tab: "friends")
        openProfile(handle: "priyaplans")
        waitFor(element("profile-friends")).tap()
        waitFor(element("follow-list-empty"), timeout: 10)
        XCTAssertTrue(app.staticTexts["No one follows this member yet."].exists)
        capture("m6-20-followers-empty")
    }

    func testEmptyFeedOffersFindPeople() {
        launch(scenario: "empty", tab: "friends")
        waitFor(element("feed-empty"), timeout: 10)
        capture("m6-17-feed-empty")
        app.buttons["Find people"].tap()
        waitFor(element("member-search-field"))
    }
}
