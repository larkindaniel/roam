import XCTest
@testable import Roam

final class M4TimestampPrecisionTests: XCTestCase {
    func testServerDatesWithinOneMillisecondRetainTheirOrder() throws {
        let earlier = try XCTUnwrap(RoamJSON.parseDate("2026-10-14T01:34:48.601100+00:00"))
        let later = try XCTUnwrap(RoamJSON.parseDate("2026-10-14 01:34:48.601900+00"))
        XCTAssertLessThan(earlier, later)
        XCTAssertEqual(later.timeIntervalSince(earlier), 0.0008, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(RoamJSON.parseDate(RoamJSON.formatDate(earlier))).timeIntervalSince(earlier), 0, accuracy: 0.000001)
    }

    func testDecodedAndPersistedTieCannotReverseServerRepresentativeByUUID() throws {
        let older = RankedEntry(ratingID: UUID(uuidString: "ffffffff-ffff-4fff-8fff-ffffffffffff")!, experienceID: UUID(), name: "Older", locality: nil,
                                firstRatedAt: try XCTUnwrap(RoamJSON.parseDate("2026-10-14T01:34:48.601100Z")))
        let newer = RankedEntry(ratingID: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, experienceID: UUID(), name: "Newer", locality: nil,
                                firstRatedAt: try XCTUnwrap(RoamJSON.parseDate("2026-10-14T01:34:48.601900Z")))
        let ranking = CategoryRanking(category: .culture, revision: 2, liked: [TieGroup(entries: [newer, older])])
        let decoded = try RoamJSON.decoder.decode(CategoryRanking.self, from: RoamJSON.encoder.encode(ranking))
        XCTAssertEqual(decoded.liked.first?.representative.ratingID, older.ratingID)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("m4-precise-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = AccountStorage(root: directory)
        let account = UUID()
        try storage.write(ranking, name: "ranking-draft", userID: account)
        let restored = try XCTUnwrap(storage.read(CategoryRanking.self, name: "ranking-draft", userID: account))
        XCTAssertEqual(restored.liked.first?.representative.ratingID, older.ratingID)
        XCTAssertLessThan(restored.liked[0].entries[0].firstRatedAt, restored.liked[0].entries[1].firstRatedAt)
    }
}
