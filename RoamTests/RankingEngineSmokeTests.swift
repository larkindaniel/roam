import XCTest
@testable import Roam

/// M1 smoke coverage of score math; M4 adds the full roam-category-v1 suite.
final class RankingEngineSmokeTests: XCTestCase {
    func testFirstScoresPerSentiment() {
        XCTAssertEqual(ScoreMath.score(groupIndex: 0, groupCount: 1, sentiment: .liked).formatted, "8.4")
        XCTAssertEqual(ScoreMath.score(groupIndex: 0, groupCount: 1, sentiment: .fine).formatted, "5.0")
        XCTAssertEqual(ScoreMath.score(groupIndex: 0, groupCount: 1, sentiment: .disliked).formatted, "1.7")
    }

    func testFirstItemNeedsNoComparison() {
        let session = InsertionSession(sentiment: .liked, groups: [])
        XCTAssertTrue(session.isComplete)
        XCTAssertEqual(session.outcome, .newGroup(slot: 0, approximate: false))
        XCTAssertNil(session.currentComparison)
    }
}
