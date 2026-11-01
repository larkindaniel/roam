import XCTest

/// M8 layout stress on the compact iPhone: a 49-character display name, a 104-character place name
/// and a 13-place tie group (Harbor plus 12). Long text must wrap without pushing scores or actions off screen, and
/// tied places share one score and rank.
final class M8LayoutStressUITests: RoamUITestCase {
    private let longPlace = "The Extraordinarily Long-Named Harbourside Tea Room and Botanical Garden Café of the Old Lisbon Waterfront"
    private let longName = "Maximiliana Alexandra Constantinople-Featherstone"

    private func card(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'feed-card-'"))
            .containing(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    func testLongNamesWrapAndActionsStayReachable() {
        launch(scenario: "stress", tab: "friends")
        let post = waitFor(card(containing: "Harbourside Tea Room"), timeout: 10)
        XCTAssertTrue(post.buttons["like-button"].firstMatch.isHittable, "Like stays reachable beside a long place name")
        XCTAssertTrue(post.frame.width <= app.windows.firstMatch.frame.width, "The card stays within the screen")
        capture("m8-11-long-names-feed")
        post.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'feed-comments-'")).firstMatch.tap()
        waitFor(element("activity-detail"))
        XCTAssertTrue(waitFor(element("comment-field")).isHittable)
        capture("m8-12-long-names-post")
        openFromForYou("open-profile")
        waitFor(element("profile-root"), timeout: 10)
        XCTAssertTrue(app.staticTexts[longName].firstMatch.exists, "The full display name is shown")
        XCTAssertTrue(element("profile-edit").isHittable)
        capture("m8-13-long-name-profile")
    }

    func testLargeTieGroupSharesOneScoreAndRank() {
        launch(scenario: "stress", tab: "myplaces")
        waitFor(element("lists-root"), timeout: 10)
        waitFor(element("category-scope")).tap()
        waitFor(app.buttons["Food & Drink"]).tap()
        waitFor(element("experience-row-Tie Test Kitchen 1"), timeout: 10)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH '1. Tie Test Kitchen 1,'")).firstMatch.exists,
                      "Tied places show rank 1")
        let tied = element("experience-row-Tie Test Kitchen 7")
        for _ in 0..<10 where !tied.exists { app.swipeUp() }
        XCTAssertTrue(tied.exists)
        XCTAssertTrue(tied.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '10.0'")).firstMatch.exists,
                      "Every place in the top tie group scores 10.0")
        capture("m8-14-large-tie-list")
        // The row's name, category and visit are one combined button.
        tied.buttons.matching(NSPredicate(format: "label BEGINSWITH '1. Tie Test Kitchen 7,'")).firstMatch.tap()
        waitFor(element("experience-detail"))
        waitFor(app.staticTexts["Tied with 12 others"], timeout: 8)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '#1 of 16'")).firstMatch.exists,
                      "Competition ranking: every tied place is #1")
        capture("m8-15-large-tie-detail")
    }
}
