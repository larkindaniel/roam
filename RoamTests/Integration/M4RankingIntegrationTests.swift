import Foundation
import Supabase
import UIKit
import XCTest
@testable import Roam

/// Public RPC journeys against the real local backend; each run owns new fictional accounts.
final class M4RankingIntegrationTests: BackendTestCase {
    private func place(_ backend: SupabaseBackend, category: ExperienceCategory = .foodDrink) async throws -> ExperienceSummary {
        try await backend.resolve(PlaceCandidate(provider: .mapkit, providerPlaceID: "I-M4-\(UUID().uuidString)",
            name: "Ranking Place \(UUID().uuidString.prefix(8))", address: "1 Ranking Lane, Lisbon", locality: "Lisbon", region: "Lisboa",
            countryCode: "PT", countryName: "Portugal", latitude: 38.713, longitude: -9.143, phone: nil, website: nil,
            providerCategory: nil, timeZoneIdentifier: "Europe/Lisbon", isLocality: false, suggestedCategory: category))
    }

    private func request(_ backend: SupabaseBackend, experience: UUID, category: ExperienceCategory = .foodDrink,
                         sentiment: Sentiment = .liked, choice: ComparisonChoice = .preferExisting,
                         intent: RatingIntent = .firstLog, visit: VisitPayload? = nil,
                         operation: UUID = UUID()) async throws -> RatingCommitRequest {
        let ranking = try await backend.categoryRanking(category)
        let base = intent == .rerank ? ranking.removing(experienceID: experience) : ranking
        var insertion = InsertionSession(sentiment: sentiment, groups: base.groups(for: sentiment))
        while !insertion.isComplete { insertion.choose(choice) }
        return RatingCommitRequest(operationID: operation, intent: intent, experienceID: experience, category: category,
            sentiment: sentiment, baseRevision: ranking.revision, answers: insertion.answers, visit: visit)
    }

    private func outcome(_ backend: SupabaseBackend, _ request: RatingCommitRequest) async -> Result<RatingCommitResult, RoamError> {
        do { return .success(try await backend.commitRating(request)) }
        catch let error as RoamError { return .failure(error) }
        catch { return .failure(.server(error.localizedDescription)) }
    }

    private func requireFailure(_ backend: SupabaseBackend, _ request: RatingCommitRequest,
                                matching predicate: (RoamError) -> Bool = { if case .validation = $0 { return true }; return false }) async {
        let result = await outcome(backend, request)
        switch result {
        case .success: XCTFail("An invalid ranking intent was acknowledged")
        case .failure(let error): XCTAssertTrue(predicate(error), "Unexpected error: \(error)")
        }
    }

    func testFirstLogsAcrossAllSevenCategoriesAreAtomicAndIdempotent() async throws {
        let (owner, _) = try await newMember(handlePrefix: "rk")
        let (viewer, _) = try await newMember(handlePrefix: "rv")
        for category in ExperienceCategory.allCases {
            let experience = try await place(owner, category: category)
            _ = try await owner.setBookmark(experienceID: experience.id, saved: true)
            let payload = VisitPayload(date: LocalDate(isoString: "2020-01-02"), timeZoneIdentifier: "America/Toronto",
                                       publicNote: "Public memory in \(category.rawValue)", mediaIDs: [])
            let intent = try await request(owner, experience: experience.id, category: category, visit: payload)
            let result = try await owner.commitRating(intent)
            XCTAssertEqual(result.score.tenths, 84)
            XCTAssertEqual(result.rank, 1)
            XCTAssertEqual(result.categoryCount, 1)
            XCTAssertEqual(result.revision, 1)
            let repeated = try await owner.commitRating(intent)
            XCTAssertEqual(repeated, result, "Receipt precedes already-rated and stale-revision checks")
            let library = try await owner.library()
            XCTAssertFalse(library.bookmarked.contains(experience.id))
            XCTAssertEqual(library.rated[experience.id], category)
            XCTAssertTrue(library.visited.contains(experience.id))
            let detail = try await owner.detail(experienceID: experience.id)
            XCTAssertEqual(detail.myVisits.count, 1)
            XCTAssertEqual(detail.publicActivity.count, 1)
            XCTAssertEqual(detail.myVisits.first?.publicNote, payload.publicNote)
            let publicDetail = try await viewer.detail(experienceID: experience.id)
            XCTAssertTrue(publicDetail.myVisits.isEmpty)
            XCTAssertNil(publicDetail.myRating)
            XCTAssertFalse(publicDetail.hasPrivateNote)
            XCTAssertEqual(publicDetail.publicActivity.first?.note, payload.publicNote)
        }
    }

    func testGoldenScoresTiesAndRerankPreserveIdentityAndHistoricalSnapshots() async throws {
        let (owner, _) = try await newMember(handlePrefix: "rg")
        var experiences: [ExperienceSummary] = []
        var results: [RatingCommitResult] = []
        for _ in 0..<3 {
            let experience = try await place(owner)
            let intent = try await request(owner, experience: experience.id)
            experiences.append(experience)
            results.append(try await owner.commitRating(intent))
        }
        let ranking = try await owner.categoryRanking(.foodDrink)
        XCTAssertEqual(ranking.placements().map { $0.score.tenths }, [100, 84, 67])
        let before = try await owner.detail(experienceID: experiences[0].id)
        let oldRating = try XCTUnwrap(before.myRating)
        XCTAssertEqual(before.publicActivity.first?.scoreSnapshot?.tenths, 84)

        let tied = try await place(owner)
        let tieIntent = try await request(owner, experience: tied.id, choice: .tooTough)
        let tie = try await owner.commitRating(tieIntent)
        XCTAssertEqual(tie.groupSize, 2)
        XCTAssertEqual(tie.score.tenths, 84)
        XCTAssertEqual(tie.rank, 2)
        let fine = try await place(owner)
        let fineIntent = try await request(owner, experience: fine.id, sentiment: .fine)
        let fineResult = try await owner.commitRating(fineIntent)
        XCTAssertEqual(fineResult.score.tenths, 50)
        let disliked = try await place(owner)
        let dislikedIntent = try await request(owner, experience: disliked.id, sentiment: .disliked)
        let dislikedResult = try await owner.commitRating(dislikedIntent)
        XCTAssertEqual(dislikedResult.score.tenths, 17)

        let memory = VisitPayload(date: LocalDate(isoString: "2020-02-03"), timeZoneIdentifier: "Europe/Lisbon",
                                  publicNote: "Edited retained memory", mediaIDs: [])
        let rerankIntent = try await request(owner, experience: experiences[0].id, sentiment: .disliked,
                                            choice: .tooTough, intent: .rerank, visit: memory)
        let rerank = try await owner.commitRating(rerankIntent)
        XCTAssertEqual(rerank.ratingID, results[0].ratingID)
        XCTAssertNil(rerank.visitID)
        XCTAssertEqual(rerank.score.tenths, 17)
        let after = try await owner.detail(experienceID: experiences[0].id)
        XCTAssertEqual(after.myRating?.firstRatedAt, oldRating.firstRatedAt)
        XCTAssertEqual(after.myVisits.count, 1)
        XCTAssertEqual(after.myVisits.first?.publicNote, memory.publicNote)
        XCTAssertEqual(after.myVisits.first?.visitDate.date, memory.date)
        XCTAssertEqual(after.publicActivity.first { $0.id == results[0].activityID }?.scoreSnapshot?.tenths, 84)
        XCTAssertEqual(after.publicActivity.first { $0.id == results[0].activityID }?.publishedAt, before.publicActivity.first?.publishedAt)
        XCTAssertEqual(after.publicActivity.first { $0.id == rerank.activityID }?.type, .rerank)
    }

    func testConcurrentIdenticalOperationReturnsOneReceiptAndChangedIntentConflicts() async throws {
        let (owner, email) = try await newMember(handlePrefix: "rc")
        let second = try await signedIn(email, password: "integration-pass-123")
        let experience = try await place(owner)
        _ = try await owner.setBookmark(experienceID: experience.id, saved: true)
        let intent = try await request(owner, experience: experience.id)
        async let a = outcome(owner, intent)
        async let b = outcome(second, intent)
        let (first, duplicate) = await (a, b)
        let saved = try first.get()
        XCTAssertEqual(try duplicate.get(), saved)
        let detail = try await owner.detail(experienceID: experience.id)
        XCTAssertEqual(detail.myVisits.count, 1)
        XCTAssertEqual(detail.publicActivity.count, 1)
        let changed = RatingCommitRequest(operationID: intent.operationID, intent: intent.intent, experienceID: intent.experienceID,
            category: intent.category, sentiment: .fine, baseRevision: intent.baseRevision, answers: intent.answers, visit: intent.visit)
        await requireFailure(owner, changed) { if case .conflict = $0 { return true }; return false }
        let persisted = try await owner.library()
        XCTAssertFalse(persisted.bookmarked.contains(experience.id))
    }

    func testConcurrentCategoryRevisionRejectsStaleWithoutPartialWrites() async throws {
        let (owner, email) = try await newMember(handlePrefix: "rs")
        let second = try await signedIn(email, password: "integration-pass-123")
        let firstPlace = try await place(owner)
        let secondPlace = try await place(owner)
        _ = try await owner.setBookmark(experienceID: firstPlace.id, saved: true)
        _ = try await owner.setBookmark(experienceID: secondPlace.id, saved: true)
        let firstIntent = try await request(owner, experience: firstPlace.id)
        let secondIntent = try await request(second, experience: secondPlace.id)
        async let a = outcome(owner, firstIntent)
        async let b = outcome(second, secondIntent)
        let (first, other) = await (a, b)
        let outcomes = [first, other]
        XCTAssertEqual(outcomes.compactMap { try? $0.get() }.count, 1)
        XCTAssertEqual(outcomes.filter { if case .failure(.staleRevision) = $0 { return true }; return false }.count, 1)
        let winner = try XCTUnwrap(outcomes.compactMap { try? $0.get() }.first)
        let loser = (try? first.get()) == nil ? firstPlace : secondPlace
        let losingDetail = try await owner.detail(experienceID: loser.id)
        XCTAssertNil(losingDetail.myRating)
        XCTAssertTrue(losingDetail.myVisits.isEmpty)
        let library = try await owner.library()
        XCTAssertTrue(library.bookmarked.contains(loser.id))
        let ranking = try await owner.categoryRanking(.foodDrink)
        XCTAssertEqual(ranking.entryCount, 1)
        XCTAssertEqual(ranking.revision, winner.revision)
    }

    func testConcurrentActorsConfirmExactlyOneCanonicalCategory() async throws {
        let (first, _) = try await newMember(handlePrefix: "ra")
        let (second, _) = try await newMember(handlePrefix: "rb")
        let experience = try await place(first)
        _ = try await first.setBookmark(experienceID: experience.id, saved: true)
        _ = try await second.setBookmark(experienceID: experience.id, saved: true)
        let aRequest = try await request(first, experience: experience.id, category: .foodDrink)
        let bRequest = try await request(second, experience: experience.id, category: .outdoors)
        async let a = outcome(first, aRequest)
        async let b = outcome(second, bRequest)
        let (aResult, bResult) = await (a, b)
        let saved = [aResult, bResult].compactMap { try? $0.get() }
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual([aResult, bResult].filter { if case .failure(.validation) = $0 { return true }; return false }.count, 1)
        let acknowledged = try XCTUnwrap(saved.first)
        let detail = try await first.detail(experienceID: experience.id)
        XCTAssertTrue(detail.categoryLocked)
        XCTAssertEqual(detail.summary.category, acknowledged.category)
        let losingClient = (try? aResult.get()) == nil ? first : second
        let losingDetail = try await losingClient.detail(experienceID: experience.id)
        XCTAssertTrue(losingDetail.myVisits.isEmpty)
        XCTAssertNil(losingDetail.myRating)
        let losingLibrary = try await losingClient.library()
        XCTAssertTrue(losingLibrary.bookmarked.contains(experience.id))
    }

    func testBookmarkRacingFirstLogCannotRecreateWant() async throws {
        let (owner, email) = try await newMember(handlePrefix: "rw")
        let savingClient = try await signedIn(email, password: "integration-pass-123")
        for _ in 0..<3 {
            let experience = try await place(owner)
            _ = try await owner.setBookmark(experienceID: experience.id, saved: true)
            let intent = try await request(owner, experience: experience.id)
            async let commit = outcome(owner, intent)
            async let save: Bool = {
                do { return try await savingClient.setBookmark(experienceID: experience.id, saved: true) }
                catch let error as RoamError { XCTAssertEqual(error, .alreadyRated); return false }
                catch { XCTFail("Unexpected bookmark error: \(error)"); return false }
            }()
            let (result, _) = await (commit, save)
            _ = try result.get()
            let library = try await owner.library()
            XCTAssertFalse(library.bookmarked.contains(experience.id))
            let detail = try await owner.detail(experienceID: experience.id)
            XCTAssertEqual(detail.myVisits.count, 1)
            XCTAssertNotNil(detail.myRating)
        }
    }

    func testRemovalAndLastVisitReceiptsPreserveMemoriesAndLaterRankings() async throws {
        let (owner, _) = try await newMember(handlePrefix: "rm")
        let experience = try await place(owner)
        let payload = VisitPayload(date: LocalDate(isoString: "2020-01-02"), timeZoneIdentifier: "UTC", publicNote: "Retained first memory", mediaIDs: [])
        let intent = try await request(owner, experience: experience.id, visit: payload)
        _ = try await owner.commitRating(intent)
        let beforeRevisit = try await owner.categoryRanking(.foodDrink)
        let revisitIntent = AddVisitRequest(operationID: UUID(), experienceID: experience.id,
            visit: VisitPayload(date: nil, timeZoneIdentifier: nil, publicNote: "Retained unknown-date memory", mediaIDs: []))
        let revisit = try await owner.addVisit(revisitIntent)
        let duplicate = try await owner.addVisit(revisitIntent)
        XCTAssertEqual(duplicate, revisit)
        let afterRevisit = try await owner.categoryRanking(.foodDrink)
        XCTAssertEqual(afterRevisit, beforeRevisit, "Revisit leaves all score/order/revision data intact")
        let removal = UUID()
        try await owner.removeRating(experienceID: experience.id, operationID: removal)
        let unranked = try await owner.detail(experienceID: experience.id)
        XCTAssertNil(unranked.myRating)
        XCTAssertEqual(Set(unranked.myVisits.map(\.publicNote)), [payload.publicNote, revisitIntent.visit.publicNote])
        XCTAssertTrue(unranked.publicActivity.isEmpty)
        let memories = try await owner.been(ownerID: try XCTUnwrap(unranked.myVisits.first).ownerID)
        XCTAssertEqual(memories.first { $0.id == experience.id }?.isRanked, false)
        let relog = try await request(owner, experience: experience.id)
        let newRating = try await owner.commitRating(relog)
        try await owner.removeRating(experienceID: experience.id, operationID: removal)
        let afterRetry = try await owner.detail(experienceID: experience.id)
        XCTAssertEqual(afterRetry.myRating?.ratingID, newRating.ratingID, "An old removal receipt cannot delete a later rating")
        XCTAssertEqual(afterRetry.myVisits.count, 3)
        var lastVisit: UUID?
        var lastOperation: UUID?
        for (index, visit) in afterRetry.myVisits.enumerated() {
            let operation = UUID()
            let result = try await owner.deleteVisit(visitID: visit.id, operationID: operation,
                                                    allowRatingRemoval: index == afterRetry.myVisits.count - 1)
            XCTAssertEqual(result.removedRating, index == afterRetry.myVisits.count - 1)
            lastVisit = visit.id
            lastOperation = operation
        }
        let nextLog = try await request(owner, experience: experience.id)
        let nextRating = try await owner.commitRating(nextLog)
        let oldDeletion = try await owner.deleteVisit(visitID: XCTUnwrap(lastVisit), operationID: XCTUnwrap(lastOperation), allowRatingRemoval: true)
        XCTAssertTrue(oldDeletion.removedRating)
        let final = try await owner.detail(experienceID: experience.id)
        XCTAssertEqual(final.myRating?.ratingID, nextRating.ratingID)
        XCTAssertEqual(final.myVisits.count, 1, "Replaying old deletion must not remove the new Visit")
    }

    /// The app's real upload preparation: M5 server inspection rejects raw UIKit JPEG metadata.
    @MainActor
    private func jpeg() throws -> ImageProcessor.Processed {
        try ImageProcessor.prepare(XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }.jpegData(compressionQuality: 0.8)))
    }

    func testStaleTwoClientVisitDeletionRequiresExplicitRatingRemovalConsent() async throws {
        let (owner, email) = try await newMember(handlePrefix: "rd")
        let second = try await signedIn(email, password: "integration-pass-123")
        let experience = try await place(owner)
        let intent = try await request(owner, experience: experience.id)
        _ = try await owner.commitRating(intent)
        _ = try await owner.addVisit(AddVisitRequest(operationID: UUID(), experienceID: experience.id,
            visit: VisitPayload(date: nil, timeZoneIdentifier: nil, publicNote: "Second consent memory", mediaIDs: [])))
        let ownerObserved = try await owner.detail(experienceID: experience.id)
        let otherObserved = try await second.detail(experienceID: experience.id)
        XCTAssertEqual(ownerObserved.myVisits.count, 2)
        XCTAssertEqual(otherObserved.myVisits.count, 2)
        let firstVisit = try XCTUnwrap(ownerObserved.myVisits.first)
        let secondVisit = try XCTUnwrap(otherObserved.myVisits.first { $0.id != firstVisit.id })
        let firstOperation = UUID()
        let first = try await owner.deleteVisit(visitID: firstVisit.id, operationID: firstOperation, allowRatingRemoval: false)
        XCTAssertFalse(first.removedRating)
        do {
            _ = try await second.deleteVisit(visitID: secondVisit.id, operationID: UUID(), allowRatingRemoval: false)
            XCTFail("The ordinary confirmation must not silently remove Rating after another client deletes a Visit")
        } catch let error as RoamError {
            XCTAssertEqual(error, .lastVisitConfirmationRequired)
        }
        let retained = try await owner.detail(experienceID: experience.id)
        XCTAssertEqual(retained.myVisits.map(\.id), [secondVisit.id])
        XCTAssertNotNil(retained.myRating)
        do {
            _ = try await owner.deleteVisit(visitID: firstVisit.id, operationID: firstOperation, allowRatingRemoval: true)
            XCTFail("Changing consent under an acknowledged UUID must conflict")
        } catch let error as RoamError {
            guard case .conflict = error else { return XCTFail("Unexpected changed-consent error: \(error)") }
        }
        let confirmedOperation = UUID()
        let confirmed = try await second.deleteVisit(visitID: secondVisit.id, operationID: confirmedOperation, allowRatingRemoval: true)
        XCTAssertTrue(confirmed.removedRating)
        let repeated = try await owner.deleteVisit(visitID: secondVisit.id, operationID: confirmedOperation, allowRatingRemoval: true)
        XCTAssertEqual(repeated, confirmed)
        let deleted = try await owner.detail(experienceID: experience.id)
        XCTAssertTrue(deleted.myVisits.isEmpty)
        XCTAssertNil(deleted.myRating)
    }

    func testRerankEditsRetainedMemoryAndReusesOnlyCompletedOwnedMedia() async throws {
        let (owner, _) = try await newMember(handlePrefix: "rp")
        let (other, _) = try await newMember(handlePrefix: "ro")
        let photo = try await jpeg()
        let data = photo.data
        let first = try await owner.stage(jpegData: data, width: photo.width, height: photo.height, purpose: .visit)
        let second = try await owner.stage(jpegData: data, width: photo.width, height: photo.height, purpose: .visit)
        let experience = try await place(owner)
        let payload = VisitPayload(date: LocalDate(isoString: "2020-01-02"), timeZoneIdentifier: "UTC", publicNote: "Original photo memory", mediaIDs: [first.id, second.id])
        let intent = try await request(owner, experience: experience.id, visit: payload)
        let saved = try await owner.commitRating(intent)
        let retried = try await owner.commitRating(intent)
        XCTAssertEqual(retried, saved, "An attached asset does not invalidate an acknowledged receipt")
        let before = try await owner.detail(experienceID: experience.id)
        let originalVisit = try XCTUnwrap(before.myVisits.first)
        let foreignPlace = try await place(other)
        _ = try await other.setBookmark(experienceID: foreignPlace.id, saved: true)
        let foreignIntent = try await request(other, experience: foreignPlace.id, visit: payload)
        await requireFailure(other, foreignIntent)
        let foreignDetail = try await other.detail(experienceID: foreignPlace.id)
        XCTAssertTrue(foreignDetail.myVisits.isEmpty)
        XCTAssertNil(foreignDetail.myRating)
        let foreignLibrary = try await other.library()
        XCTAssertTrue(foreignLibrary.bookmarked.contains(foreignPlace.id))

        let edited = VisitPayload(date: LocalDate(isoString: "2021-02-03"), timeZoneIdentifier: "America/Toronto",
                                  publicNote: "Updated photo memory", mediaIDs: [second.id, first.id])
        let rerankIntent = try await request(owner, experience: experience.id, intent: .rerank, visit: edited)
        let rerank = try await owner.commitRating(rerankIntent)
        XCTAssertNil(rerank.visitID)
        let after = try await owner.detail(experienceID: experience.id)
        XCTAssertEqual(after.myVisits.count, 1)
        XCTAssertEqual(after.myVisits.first?.id, originalVisit.id)
        XCTAssertEqual(after.myVisits.first?.media.map(\.id), edited.mediaIDs)
        XCTAssertEqual(after.myVisits.first?.publicNote, edited.publicNote)
        XCTAssertEqual(after.publicActivity.first { $0.id == saved.activityID }?.publishedAt,
                       before.publicActivity.first { $0.id == saved.activityID }?.publishedAt)
        let changed = RatingCommitRequest(operationID: rerankIntent.operationID, intent: .rerank, experienceID: experience.id,
            category: rerankIntent.category, sentiment: rerankIntent.sentiment, baseRevision: rerankIntent.baseRevision,
            answers: rerankIntent.answers, visit: payload)
        await requireFailure(owner, changed) { if case .conflict = $0 { return true }; return false }
        let reduced = VisitPayload(date: edited.date, timeZoneIdentifier: edited.timeZoneIdentifier, publicNote: edited.publicNote, mediaIDs: [first.id])
        let removingPhoto = try await request(owner, experience: experience.id, intent: .rerank, visit: reduced)
        _ = try await owner.commitRating(removingPhoto)
        try await owner.removeRating(experienceID: experience.id, operationID: UUID())
        let retained = try await owner.detail(experienceID: experience.id)
        XCTAssertEqual(retained.myVisits.first?.media.map(\.id), [first.id])
        let retainedImage = try await owner.imageData(path: first.path)
        XCTAssertEqual(retainedImage, data, "Ranking removal retains actual uploaded photo bytes")
    }

    func testInvalidIntentsRetainWantAndCanRetryAfterAcknowledgedValidationFailure() async throws {
        let (owner, _) = try await newMember(handlePrefix: "ri")
        let first = try await place(owner)
        let firstIntent = try await request(owner, experience: first.id)
        _ = try await owner.commitRating(firstIntent)
        let experience = try await place(owner)
        _ = try await owner.setBookmark(experienceID: experience.id, saved: true)
        let valid = try await request(owner, experience: experience.id)
        let stale = RatingCommitRequest(operationID: valid.operationID, intent: valid.intent, experienceID: experience.id,
            category: valid.category, sentiment: valid.sentiment, baseRevision: 0, answers: [], visit: nil)
        await requireFailure(owner, stale) { $0 == .staleRevision }
        let incomplete = RatingCommitRequest(operationID: valid.operationID, intent: valid.intent, experienceID: experience.id,
            category: valid.category, sentiment: valid.sentiment, baseRevision: valid.baseRevision, answers: [], visit: nil)
        await requireFailure(owner, incomplete)
        let malformed = RatingCommitRequest(operationID: valid.operationID, intent: valid.intent, experienceID: experience.id,
            category: valid.category, sentiment: valid.sentiment, baseRevision: valid.baseRevision,
            answers: [ComparisonAnswer(comparedRatingID: UUID(), choice: .tooTough)], visit: nil)
        await requireFailure(owner, malformed)
        let visits = [
            VisitPayload(date: LocalDate.today().adding(days: 10), timeZoneIdentifier: "UTC", publicNote: "Future", mediaIDs: []),
            VisitPayload(date: nil, timeZoneIdentifier: nil, publicNote: String(repeating: "x", count: 5001), mediaIDs: []),
            VisitPayload(date: nil, timeZoneIdentifier: nil, publicNote: "Missing upload", mediaIDs: [UUID()]),
        ]
        for visit in visits {
            let invalid = RatingCommitRequest(operationID: valid.operationID, intent: valid.intent, experienceID: experience.id,
                category: valid.category, sentiment: valid.sentiment, baseRevision: valid.baseRevision, answers: valid.answers, visit: visit)
            await requireFailure(owner, invalid)
        }
        let unchanged = try await owner.detail(experienceID: experience.id)
        XCTAssertNil(unchanged.myRating)
        XCTAssertTrue(unchanged.myVisits.isEmpty)
        XCTAssertTrue(unchanged.publicActivity.isEmpty)
        let library = try await owner.library()
        XCTAssertTrue(library.bookmarked.contains(experience.id))
        let ranking = try await owner.categoryRanking(.foodDrink)
        XCTAssertEqual(ranking.revision, valid.baseRevision)
        let result = try await owner.commitRating(valid)
        XCTAssertEqual(result.revision, valid.baseRevision + 1)
    }

    func testRawActorScoreAndOrderInjectionCannotCreateDurableRows() async throws {
        let (owner, _) = try await newMember(handlePrefix: "rx")
        let experience = try await place(owner)
        let intent = try await request(owner, experience: experience.id)
        let session = try await owner.client.auth.session
        let encoded = try RoamJSON.encoder.encode(intent)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for (field, value) in [("actorID", UUID().uuidString as Any), ("score", 10 as Any), ("order", [] as [String] as Any)] {
            var injected = original
            injected[field] = value
            let body = try JSONSerialization.data(withJSONObject: ["p_request": injected])
            let (status, data) = try await rest("rest/v1/rpc/commit_rating", token: session.accessToken, method: "POST", body: body)
            XCTAssertEqual(status, 400)
            let response = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertTrue((response["message"] as? String)?.hasPrefix("roam:validation:") == true)
        }
        let detail = try await owner.detail(experienceID: experience.id)
        XCTAssertNil(detail.myRating)
        XCTAssertTrue(detail.myVisits.isEmpty)
        let ranking = try await owner.categoryRanking(.foodDrink)
        XCTAssertEqual(ranking.revision, 0)
    }
}
