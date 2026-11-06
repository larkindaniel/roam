import XCTest
@testable import Roam

final class M4FixtureParityTests: XCTestCase {
    private func backend() -> FixtureBackend { FixtureBackend(scenario: "empty", signedInHandle: "maya", latencyMilliseconds: 0) }
    private func place(_ backend: FixtureBackend) async throws -> ExperienceSummary {
        try await backend.resolve(PlaceCandidate(provider: .fixture, providerPlaceID: UUID().uuidString, name: "Receipt Café", address: "1 Test Street",
                                                locality: "Lisbon", region: "Lisboa", countryCode: "PT", countryName: "Portugal", latitude: 38.7, longitude: -9.1,
                                                phone: nil, website: nil, providerCategory: nil, timeZoneIdentifier: "Europe/Lisbon", isLocality: false, suggestedCategory: .foodDrink))
    }
    private func request(_ id: UUID, operation: UUID = UUID(), intent: RatingIntent = .firstLog, sentiment: Sentiment = .liked, revision: Int = 0,
                         note: String = "Retained public memory") -> RatingCommitRequest {
        RatingCommitRequest(operationID: operation, intent: intent, experienceID: id, category: .foodDrink, sentiment: sentiment,
                            baseRevision: revision, answers: [], visit: VisitPayload(date: LocalDate(isoString: "2026-01-01"), timeZoneIdentifier: "UTC", publicNote: note, mediaIDs: []))
    }

    func testStableFingerprintAndDuplicateReceiptSurviveReencodedRequest() async throws {
        let backend = backend()
        let experience = try await place(backend)
        let intent = request(experience.id)
        let restored = try JSONDecoder().decode(RatingCommitRequest.self, from: JSONEncoder().encode(intent))
        XCTAssertEqual(try MutationFingerprint.digest(restored), try MutationFingerprint.digest(intent))
        let first = try await backend.commitRating(intent)
        let repeated = try await backend.commitRating(restored)
        XCTAssertEqual(first, repeated)
        do {
            _ = try await backend.commitRating(request(experience.id, operation: intent.operationID, note: "Changed payload"))
            XCTFail("Same operation cannot change its intent")
        } catch { guard case RoamError.conflict = error else { return XCTFail("Expected operation conflict") } }
        let detail = try await backend.detail(experienceID: experience.id)
        XCTAssertEqual(detail.myVisits.count, 1)
        XCTAssertEqual(detail.publicActivity.count, 1)
    }

    func testOldRemovalReceiptCannotRemoveNewRankingAndRetainsMemory() async throws {
        let backend = backend()
        let experience = try await place(backend)
        _ = try await backend.commitRating(request(experience.id))
        _ = try await backend.savePrivateNote(experienceID: experience.id, text: "Only the owner")
        let removeOperation = UUID()
        try await backend.removeRating(experienceID: experience.id, operationID: removeOperation)
        let removed = try await backend.detail(experienceID: experience.id)
        XCTAssertNil(removed.myRating)
        XCTAssertEqual(removed.myVisits.first?.publicNote, "Retained public memory")
        XCTAssertTrue(removed.hasPrivateNote)
        XCTAssertTrue(removed.publicActivity.isEmpty)
        let current = try await backend.categoryRanking(.foodDrink)
        let rerated = try await backend.commitRating(request(experience.id, revision: current.revision, note: "New rating"))
        try await backend.removeRating(experienceID: experience.id, operationID: removeOperation)
        let retained = try await backend.detail(experienceID: experience.id)
        XCTAssertEqual(retained.myRating?.ratingID, rerated.ratingID)
        XCTAssertEqual(retained.myVisits.count, 2)
    }

    func testLastVisitDeletionReturnsOriginalTrueReceiptOnRetry() async throws {
        let backend = backend()
        let experience = try await place(backend)
        let logged = try await backend.commitRating(request(experience.id))
        let visit = try XCTUnwrap(logged.visitID)
        let operation = UUID()
        let first = try await backend.deleteVisit(visitID: visit, operationID: operation, allowRatingRemoval: true)
        let repeated = try await backend.deleteVisit(visitID: visit, operationID: operation, allowRatingRemoval: true)
        XCTAssertTrue(first.removedRating)
        XCTAssertEqual(repeated, first)
        let detail = try await backend.detail(experienceID: experience.id)
        XCTAssertNil(detail.myRating)
        XCTAssertTrue(detail.myVisits.isEmpty)
        XCTAssertTrue(detail.publicActivity.isEmpty)
    }

    func testRerankEditsRetainedVisitWithoutAddingVisitOrChangingPublishedTime() async throws {
        let backend = backend()
        let experience = try await place(backend)
        let logged = try await backend.commitRating(request(experience.id))
        let original = try await backend.detail(experienceID: experience.id)
        _ = try await backend.commitRating(request(experience.id, intent: .rerank, sentiment: .fine, revision: 1, note: "Edited during rerank"))
        let updated = try await backend.detail(experienceID: experience.id)
        XCTAssertEqual(updated.myVisits.count, 1)
        XCTAssertEqual(updated.myVisits.first?.id, original.myVisits.first?.id)
        XCTAssertEqual(updated.myVisits.first?.publicNote, "Edited during rerank")
        XCTAssertEqual(updated.myRating?.score, Score(tenths: 50))
        let oldActivity = try XCTUnwrap(updated.publicActivity.first { $0.id == logged.activityID })
        let previous = try XCTUnwrap(original.publicActivity.first { $0.id == logged.activityID })
        XCTAssertEqual(oldActivity.publishedAt, previous.publishedAt)
        XCTAssertEqual(oldActivity.scoreSnapshot, Score(tenths: 84))
        XCTAssertEqual(oldActivity.note, "Edited during rerank")
    }

    func testFutureRevisitRejectsWithoutAnyDurableEffects() async throws {
        let backend = backend()
        let experience = try await place(backend)
        _ = try await backend.commitRating(request(experience.id))
        let before = try await backend.categoryRanking(.foodDrink)
        let future = LocalDate.today(in: TimeZone(secondsFromGMT: 0)!).adding(days: 1)
        do {
            _ = try await backend.addVisit(AddVisitRequest(operationID: UUID(), experienceID: experience.id,
                                                           visit: VisitPayload(date: future, timeZoneIdentifier: "UTC", publicNote: "", mediaIDs: [])))
            XCTFail("Future completed visit must reject")
        } catch { guard case RoamError.validation = error else { return XCTFail("Expected future-date validation") } }
        let after = try await backend.categoryRanking(.foodDrink)
        let detail = try await backend.detail(experienceID: experience.id)
        XCTAssertEqual(after, before)
        XCTAssertEqual(detail.myVisits.count, 1)
        XCTAssertEqual(detail.publicActivity.count, 1)
    }

    func testInvalidComparisonAndTimeZoneRejectBeforeWriting() async throws {
        let backend = backend()
        let first = try await place(backend)
        _ = try await backend.commitRating(request(first.id))
        let second = try await place(backend)
        let incomplete = request(second.id, revision: 1)
        do {
            _ = try await backend.commitRating(incomplete)
            XCTFail("A fresh revision must still supply valid comparisons")
        } catch { guard case RoamError.validation = error else { return XCTFail("Expected answer validation") } }
        let invalidZone = RatingCommitRequest(operationID: UUID(), intent: .firstLog, experienceID: second.id, category: .foodDrink,
                                             sentiment: .fine, baseRevision: 1, answers: [],
                                             visit: VisitPayload(date: nil, timeZoneIdentifier: "Moon/Sea", publicNote: "", mediaIDs: []))
        do {
            _ = try await backend.commitRating(invalidZone)
            XCTFail("Invalid time zones must reject")
        } catch { guard case RoamError.validation = error else { return XCTFail("Expected zone validation") } }
        let detail = try await backend.detail(experienceID: second.id)
        let ranking = try await backend.categoryRanking(.foodDrink)
        XCTAssertNil(detail.myRating)
        XCTAssertTrue(detail.myVisits.isEmpty)
        XCTAssertEqual(ranking.revision, 1)
    }

    func testUnknownRemovalCannotAcknowledgeAnUnknownExperience() async throws {
        let backend = backend()
        do {
            try await backend.removeRating(experienceID: UUID(), operationID: UUID())
            XCTFail("Unknown experience must not acknowledge removal")
        } catch { guard case RoamError.notFound = error else { return XCTFail("Expected not found") } }
    }

    func testStaleOrdinaryVisitDeletionRequiresFreshLastVisitConsent() async throws {
        let backend = backend()
        let experience = try await place(backend)
        let logged = try await backend.commitRating(request(experience.id))
        let added = try await backend.addVisit(AddVisitRequest(operationID: UUID(), experienceID: experience.id,
                                                              visit: VisitPayload(date: nil, timeZoneIdentifier: nil, publicNote: "Second", mediaIDs: [])))
        _ = try await backend.deleteVisit(visitID: try XCTUnwrap(logged.visitID), operationID: UUID())
        let rejectedID = UUID()
        do {
            _ = try await backend.deleteVisit(visitID: added.visitID, operationID: rejectedID)
            XCTFail("An ordinary confirmation must not delete a last Visit's ranking")
        } catch { XCTAssertEqual(error as? RoamError, .lastVisitConfirmationRequired) }
        let unchanged = try await backend.detail(experienceID: experience.id)
        XCTAssertNotNil(unchanged.myRating)
        XCTAssertEqual(unchanged.myVisits.count, 1)
        let confirmed = try await backend.deleteVisit(visitID: added.visitID, operationID: UUID(), allowRatingRemoval: true)
        XCTAssertTrue(confirmed.removedRating)
    }
}
