import Foundation
import XCTest
@testable import Roam

private actor RatingFlowTestService: RankingService {
    var rankings: [CategoryRanking]
    var responses: [Result<RatingCommitResult, RoamError>]
    var visitResponses: [Result<AddVisitResult, RoamError>]
    private(set) var commits: [RatingCommitRequest] = []
    private(set) var visits: [AddVisitRequest] = []
    private(set) var categories: [ExperienceCategory] = []
    private var rankingFailure: RoamError?
    private let holdsCommit: Bool
    private var heldCommit: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private let holdsFirstRanking: Bool
    private let throwsOnCancelledRanking: Bool
    private var heldRanking: CheckedContinuation<Void, Never>?
    private var rankingStarted: CheckedContinuation<Void, Never>?

    init(rankings: [CategoryRanking] = [], responses: [Result<RatingCommitResult, RoamError>] = [],
         visitResponses: [Result<AddVisitResult, RoamError>] = [], holdsCommit: Bool = false, rankingFailure: RoamError? = nil,
         holdsFirstRanking: Bool = false, throwsOnCancelledRanking: Bool = false) {
        self.rankings = rankings; self.responses = responses; self.visitResponses = visitResponses; self.holdsCommit = holdsCommit
        self.rankingFailure = rankingFailure
        self.holdsFirstRanking = holdsFirstRanking
        self.throwsOnCancelledRanking = throwsOnCancelledRanking
    }
    func categoryRanking(_ category: ExperienceCategory) async throws -> CategoryRanking {
        categories.append(category)
        if let rankingFailure { throw rankingFailure }
        let captured = rankings.isEmpty ? .empty(category) : rankings.removeFirst()
        if holdsFirstRanking && categories.count == 1 {
            await withCheckedContinuation { heldRanking = $0; rankingStarted?.resume(); rankingStarted = nil }
            if throwsOnCancelledRanking { try Task.checkCancellation() }
        }
        return captured
    }
    func waitForRanking() async {
        guard heldRanking == nil else { return }
        await withCheckedContinuation { rankingStarted = $0 }
    }
    func releaseRanking() { heldRanking?.resume(); heldRanking = nil }
    func setRankingFailure(_ error: RoamError?) { rankingFailure = error }
    func commitRating(_ request: RatingCommitRequest) async throws -> RatingCommitResult {
        commits.append(request)
        if holdsCommit {
            await withCheckedContinuation { heldCommit = $0; started?.resume(); started = nil }
        }
        guard !responses.isEmpty else { throw RoamError.unavailable }
        return try responses.removeFirst().get()
    }
    func waitForCommit() async {
        guard heldCommit == nil else { return }
        await withCheckedContinuation { started = $0 }
    }
    func releaseCommit() { heldCommit?.resume(); heldCommit = nil }
    func addVisit(_ request: AddVisitRequest) async throws -> AddVisitResult {
        visits.append(request)
        guard !visitResponses.isEmpty else { throw RoamError.unavailable }
        return try visitResponses.removeFirst().get()
    }
    func removeRating(experienceID: UUID, operationID: UUID) async throws { throw RoamError.unavailable }
    func deleteVisit(visitID: UUID, operationID: UUID, allowRatingRemoval: Bool) async throws -> DeleteVisitResult { throw RoamError.unavailable }
}

@MainActor
final class M4RatingFlowTests: XCTestCase {
    private func storage() throws -> AccountStorage {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("roam-rating-tests-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return AccountStorage(root: root)
    }
    private func request(category: ExperienceCategory? = .foodDrink, mode: LogRequest.Mode = .firstLog,
                         locked: Bool = false, existingVisit: Visit? = nil) -> LogRequest {
        let experience = ExperienceSummary(id: UUID(), placeID: UUID(), name: "Test Harbor", category: category,
                                            locality: "Lisbon", region: "Lisboa", countryCode: "PT", countryName: "Portugal",
                                            latitude: 38.7, longitude: -9.1, providerPlaceID: nil,
                                            followingScore: nil, followingCount: 0, viewer: .none)
        return LogRequest(experience: experience, mode: mode, suggestedCategory: category, destinationTimeZone: "Asia/Tokyo",
                          categoryLocked: locked, existingVisit: existingVisit)
    }
    private func result(_ category: ExperienceCategory = .foodDrink, sentiment: Sentiment = .liked) -> RatingCommitResult {
        RatingCommitResult(ratingID: UUID(), visitID: UUID(), activityID: UUID(), category: category, sentiment: sentiment,
                           score: Score(tenths: sentiment == .liked ? 84 : sentiment == .fine ? 50 : 17),
                           rank: 1, groupSize: 1, categoryCount: 1, revision: 1)
    }
    private func ranked(_ name: String, experienceID: UUID = UUID()) -> RankedEntry {
        RankedEntry(ratingID: UUID(), experienceID: experienceID, name: name, locality: "Lisbon", firstRatedAt: Date(timeIntervalSince1970: 100))
    }

    func testFirstItemInEveryCategorySkipsComparisonsAndUsesAcknowledgedNumericResult() async throws {
        for category in ExperienceCategory.allCases {
            let acknowledged = result(category)
            let service = RatingFlowTestService(responses: [.success(acknowledged)])
            // A place with no category yet: the first logger picks it.
            let model = RatingFlowModel(request: request(category: nil), accountID: UUID(), ranking: service, storage: try storage())
            model.selectCategory(category)
            model.selectSentiment(.liked)
            XCTAssertEqual(model.step, .details, "Details follows sentiment before Okay")
            XCTAssertNil(model.completion)
            await model.okay()
            XCTAssertEqual(model.step, .result)
            XCTAssertEqual(model.completion, .rating(acknowledged))
            let commits = await service.commits
            XCTAssertEqual(commits.count, 1)
            XCTAssertEqual(commits.first?.category, category, "An unlocked metadata suggestion can be confirmed in another category")
            XCTAssertEqual(commits.first?.answers, [])
            XCTAssertNotNil(commits.first?.visit)
        }
    }

    func testSavingDisablesEditsDuplicateSubmissionAndResultUntilAcknowledgement() async throws {
        let acknowledged = result()
        let service = RatingFlowTestService(responses: [.success(acknowledged)], holdsCommit: true)
        let model = RatingFlowModel(request: request(), accountID: UUID(), ranking: service, storage: try storage())
        model.selectSentiment(.liked)
        let save = Task { await model.okay() }
        await service.waitForCommit()
        XCTAssertEqual(model.step, .saving)
        XCTAssertNil(model.completion)
        XCTAssertFalse(model.canEdit)
        XCTAssertFalse(model.updateDetails(note: "Too late", date: nil))
        model.selectSentiment(.disliked)
        await model.okay()
        await model.retrySave()
        await service.releaseCommit()
        await save.value
        XCTAssertEqual(model.completion, .rating(acknowledged))
        let commits = await service.commits
        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(commits.first?.sentiment, .liked)
    }

    func testFirstFineAndDislikedPartitionsTerminateWithoutComparison() async throws {
        for sentiment in [Sentiment.fine, .disliked] {
            let acknowledged = result(sentiment: sentiment)
            let service = RatingFlowTestService(responses: [.success(acknowledged)])
            let model = RatingFlowModel(request: request(), accountID: UUID(), ranking: service, storage: try storage())
            model.selectSentiment(sentiment)
            await model.okay()
            XCTAssertEqual(model.completion, .rating(acknowledged))
            let commits = await service.commits
            XCTAssertEqual(commits.first?.sentiment, sentiment)
            XCTAssertEqual(commits.first?.answers, [])
        }
    }

    func testUncertainSaveSurvivesRestartAndRetriesExactOperationAndPayload() async throws {
        let service = RatingFlowTestService(responses: [.failure(.timeout), .success(result())])
        let account = UUID(), request = request(), storage = try storage()
        let model = RatingFlowModel(request: request, accountID: account, ranking: service, storage: storage)
        model.selectSentiment(.liked)
        XCTAssertTrue(model.updateDetails(note: "Original public memory", date: nil))
        await model.okay()
        XCTAssertEqual(model.step, .retry)
        XCTAssertNil(model.completion)
        let resumed = RatingFlowModel(request: request, accountID: account, ranking: service, storage: storage)
        XCTAssertEqual(resumed.operationID, model.operationID)
        XCTAssertEqual(resumed.step, .retry)
        XCTAssertFalse(resumed.updateDetails(note: "Changed after timeout", date: nil))
        await resumed.retrySave()
        let commits = await service.commits
        XCTAssertEqual(commits.count, 2)
        XCTAssertEqual(commits[0], commits[1], "The exact immutable request is retried after an uncertain response")
        XCTAssertEqual(commits[1].visit?.publicNote, "Original public memory")
        XCTAssertEqual(resumed.step, .result)
        XCTAssertTrue(storage.names(userID: account, prefix: "rating-draft-").isEmpty)
    }

    func testRankingLoadFailureKeepsDetailsAndRetriesBeforeAnyCommit() async throws {
        let service = RatingFlowTestService(responses: [.success(result())], rankingFailure: .offline)
        let model = RatingFlowModel(request: request(), accountID: UUID(), ranking: service, storage: try storage())
        model.selectSentiment(.liked)
        XCTAssertTrue(model.updateDetails(note: "Keep while offline", date: nil))
        let operation = model.operationID
        await model.okay()
        XCTAssertEqual(model.step, .details)
        XCTAssertEqual(model.visit.publicNote, "Keep while offline")
        XCTAssertEqual(model.operationID, operation)
        XCTAssertNil(model.completion)
        let before = await service.commits
        XCTAssertTrue(before.isEmpty)
        await service.setRankingFailure(nil)
        await model.okay()
        XCTAssertEqual(model.step, .result)
    }

    func testCancelledRankingLoadReturnsToEditableDetailsAndOkayRetries() async throws {
        for serviceThrowsCancellation in [false, true] {
            let service = RatingFlowTestService(responses: [.success(result())], holdsFirstRanking: true,
                                                throwsOnCancelledRanking: serviceThrowsCancellation)
            let model = RatingFlowModel(request: request(), accountID: UUID(), ranking: service, storage: try storage())
            model.selectSentiment(.liked)
            XCTAssertTrue(model.updateDetails(note: "Keep this interrupted memory", date: nil, mediaIDs: [UUID()]))
            let enrichment = model.visit, operation = model.operationID
            let load = Task { await model.okay() }
            await service.waitForRanking()
            XCTAssertEqual(model.step, .loading)
            load.cancel()
            await service.releaseRanking()
            await load.value
            XCTAssertEqual(model.step, .details, "Cancellation must not strand the screen in Loading")
            XCTAssertTrue(model.canEdit)
            XCTAssertEqual(model.visit, enrichment)
            XCTAssertEqual(model.operationID, operation)
            XCTAssertNil(model.completion)
            XCTAssertTrue(model.message?.contains("Okay to retry") == true)
            let before = await service.commits
            XCTAssertTrue(before.isEmpty)

            await model.okay()
            XCTAssertEqual(model.step, .result)
            let commits = await service.commits, categories = await service.categories
            XCTAssertEqual(commits.count, 1)
            XCTAssertEqual(commits.first?.visit, enrichment)
            XCTAssertEqual(categories, [.foodDrink, .foodDrink])
        }
    }

    func testTieRepresentativeUsesMicrosecondsAndUndoReturnsToIt() async throws {
        let older = RankedEntry(ratingID: UUID(uuidString: "ffffffff-ffff-4fff-8fff-ffffffffffff")!, experienceID: UUID(),
                                 name: "True older tie member", locality: "Lisbon",
                                 firstRatedAt: RoamJSON.parseDate("2026-10-13T18:00:00.601100Z")!)
        let younger = RankedEntry(ratingID: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, experienceID: UUID(),
                                   name: "Younger tie member with smaller UUID", locality: "Lisbon",
                                   firstRatedAt: RoamJSON.parseDate("2026-10-13T18:00:00.601900Z")!)
        let middle = ranked("Second group")
        let groups = [TieGroup(entries: [ranked("First group")]), TieGroup(entries: [middle]),
                      TieGroup(entries: [younger, older]), TieGroup(entries: [ranked("Fourth group")])]
        let ranking = CategoryRanking(category: .foodDrink, revision: 12, liked: groups)
        let service = RatingFlowTestService(rankings: [ranking], responses: [.success(result())])
        let model = RatingFlowModel(request: request(), accountID: UUID(), ranking: service, storage: try storage())
        model.selectSentiment(.liked)
        await model.okay()
        XCTAssertEqual(model.comparison?.ratingID, older.ratingID, "Microseconds, rather than inverse UUID order, select the true older member")
        let tied = try XCTUnwrap(model.session?.groups[2])
        XCTAssertLessThan(tied.entries[0].firstRatedAt, tied.entries[1].firstRatedAt)
        await model.choose(.preferNew)
        XCTAssertEqual(model.comparison?.ratingID, middle.ratingID)
        model.undo()
        XCTAssertEqual(model.comparison?.ratingID, older.ratingID)
        XCTAssertEqual(model.session?.answers, [])
        await model.choose(.preferExisting)
        await model.choose(.skip)
        let commits = await service.commits
        XCTAssertEqual(commits.first?.answers.first?.comparedRatingID, older.ratingID)
        XCTAssertEqual(commits.first?.answers.map(\.choice), [.preferExisting, .skip])
        XCTAssertEqual(model.step, .result)
    }
    func testAnUnfinishedLogIsNotKeptAndReopensFreshAtNeutral() async throws {
        let groups = (0..<4).map { TieGroup(entries: [ranked("Food group \($0)")]) }
        let service = RatingFlowTestService(rankings: [CategoryRanking(category: .foodDrink, revision: 7, liked: groups)])
        let account = UUID(), original = request(), storage = try storage()
        let model = RatingFlowModel(request: original, accountID: account, ranking: service, storage: storage)
        model.selectSentiment(.liked)
        XCTAssertTrue(model.updateDetails(note: "Not kept", date: nil, mediaIDs: [UUID()]))
        await model.okay()
        await model.choose(.preferNew)
        model.keepDraft()

        let reopened = RatingFlowModel(request: original, accountID: account, ranking: service, storage: storage)
        XCTAssertEqual(reopened.step, .details)
        XCTAssertEqual(reopened.sentiment, .fine, "A log always starts at Neutral")
        XCTAssertEqual(reopened.visit.publicNote, "")
        XCTAssertEqual(reopened.visit.mediaIDs, [])
        XCTAssertNil(reopened.session)
        XCTAssertNotEqual(reopened.operationID, model.operationID)
        let commits = await service.commits
        XCTAssertTrue(commits.isEmpty)
    }
    func testNewCanonicalCategoryDoesNotChangeAnImmutablePendingReceiptRequest() async throws {
        let service = RatingFlowTestService(responses: [.failure(.timeout), .success(result())])
        let account = UUID(), original = request(), storage = try storage()
        let model = RatingFlowModel(request: original, accountID: account, ranking: service, storage: storage)
        model.selectSentiment(.liked)
        await model.okay()
        var summary = original.experience
        summary.category = .outdoors
        let fresh = LogRequest(experience: summary, mode: .firstLog, suggestedCategory: .outdoors,
                               destinationTimeZone: original.destinationTimeZone, categoryLocked: true)
        let restored = RatingFlowModel(request: fresh, accountID: account, ranking: service, storage: storage)
        XCTAssertEqual(restored.step, .retry)
        XCTAssertEqual(restored.operationID, model.operationID)
        await restored.retrySave()
        let commits = await service.commits
        XCTAssertEqual(commits.count, 2)
        XCTAssertEqual(commits[0], commits[1], "Receipt resolution must use the exact original category, operation and payload")
    }

    func testFailedDurableDraftWriteBlocksCommitUntilStorageRecovers() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("roam-rating-invalid-root-\(UUID())")
        try Data([1]).write(to: root)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let service = RatingFlowTestService(responses: [.success(result())])
        let model = RatingFlowModel(request: request(), accountID: UUID(), ranking: service, storage: AccountStorage(root: root))
        model.selectSentiment(.liked)
        await model.okay()
        XCTAssertNotNil(model.persistenceError)
        XCTAssertNil(model.completion)
        let before = await service.commits
        XCTAssertTrue(before.isEmpty, "A save cannot begin unless its exact request was recorded durably")
        try FileManager.default.removeItem(at: root)
        await model.retrySave()
        XCTAssertEqual(model.step, .result)
        let after = await service.commits
        XCTAssertEqual(after.count, 1)
    }

    func testStaleRevisionKeepsEnrichmentAndRequiresFreshComparisons() async throws {
        let old = ranked("Old comparison"), updated = ranked("New comparison")
        let service = RatingFlowTestService(rankings: [CategoryRanking(category: .foodDrink, revision: 3, liked: [TieGroup(entries: [old])]),
                                                       CategoryRanking(category: .foodDrink, revision: 4, liked: [TieGroup(entries: [updated])])],
                                            responses: [.failure(.staleRevision), .success(result())])
        let model = RatingFlowModel(request: request(), accountID: UUID(), ranking: service, storage: try storage())
        model.selectSentiment(.liked)
        let photo = UUID()
        XCTAssertTrue(model.updateDetails(note: "Keep this memory", date: nil, mediaIDs: [photo]))
        await model.okay()
        let oldOperation = model.operationID
        await model.choose(.skip)
        XCTAssertEqual(model.step, .details)
        XCTAssertNil(model.completion)
        XCTAssertNotEqual(model.operationID, oldOperation, "A definitely rejected operation may be replaced")
        XCTAssertEqual(model.visit.publicNote, "Keep this memory")
        XCTAssertEqual(model.visit.mediaIDs, [photo])
        XCTAssertNil(model.visit.date)
        XCTAssertTrue(model.message?.contains("compare again") == true)
        await model.okay()
        XCTAssertEqual(model.comparison?.ratingID, updated.ratingID)
        await model.choose(.tooTough)
        let commits = await service.commits
        XCTAssertEqual(commits.map(\.baseRevision), [3, 4])
        XCTAssertEqual(commits[1].answers.first?.comparedRatingID, updated.ratingID)
        XCTAssertEqual(commits[0].visit, commits[1].visit)
    }

    func testUndoRestoresUncommittedQuestionAndSkipFinishesWithoutTie() async throws {
        let groups = (0..<4).map { TieGroup(entries: [ranked("Existing \($0)")]) }
        let service = RatingFlowTestService(rankings: [CategoryRanking(category: .foodDrink, revision: 7, liked: groups)], responses: [.success(result())])
        let model = RatingFlowModel(request: request(), accountID: UUID(), ranking: service, storage: try storage())
        model.selectSentiment(.liked)
        await model.okay()
        let original = model.comparison
        XCTAssertFalse(model.canUndo)
        await model.choose(.preferNew)
        XCTAssertTrue(model.canUndo)
        XCTAssertNotEqual(model.comparison, original)
        model.undo()
        XCTAssertEqual(model.comparison, original)
        XCTAssertEqual(model.session?.answers, [])
        await model.choose(.preferExisting)
        await model.choose(.skip)
        let commits = await service.commits
        XCTAssertEqual(commits.first?.answers.map(\.choice), [.preferExisting, .skip])
        XCTAssertEqual(model.step, .result)
    }

    func testRerankExcludesOwnEntryAndPreservesAnchorMediaWhenEditing() async throws {
        var request = request(mode: .rerank)
        let asset = MediaRef(id: UUID(), path: "owned/attached.jpg", width: 100, height: 100, position: 0)
        let anchor = Visit(id: UUID(), experienceID: request.experience.id, ownerID: UUID(), visitDate: .unknown,
                           publicNote: "Original memory", media: [asset], createdAt: Date(), updatedAt: Date())
        request.existingVisit = anchor
        let own = ranked("Test Harbor", experienceID: request.experience.id), other = ranked("Other")
        let service = RatingFlowTestService(rankings: [CategoryRanking(category: .foodDrink, revision: 2, liked: [TieGroup(entries: [own]), TieGroup(entries: [other])])],
                                            responses: [.success(result())])
        let model = RatingFlowModel(request: request, accountID: anchor.ownerID, ranking: service, storage: try storage())
        XCTAssertTrue(model.categoryLocked)
        model.selectCategory(.culture)
        XCTAssertEqual(model.category, .foodDrink)
        model.selectSentiment(.liked)
        XCTAssertEqual(model.visit.mediaIDs, [asset.id])
        XCTAssertTrue(model.updateDetails(note: "Updated memory", date: nil))
        await model.okay()
        XCTAssertEqual(model.comparison?.ratingID, other.ratingID)
        await model.choose(.tooTough)
        let commits = await service.commits, visits = await service.visits
        XCTAssertEqual(commits.first?.intent, .rerank)
        XCTAssertEqual(commits.first?.visit?.publicNote, "Updated memory")
        XCTAssertEqual(commits.first?.visit?.mediaIDs, [asset.id])
        XCTAssertTrue(visits.isEmpty, "Reranking never submits an Add visit")
    }

    func testAddVisitUsesExistingRatingWithoutCategoryLoadOrComparison() async throws {
        let acknowledged = AddVisitResult(visitID: UUID(), activityID: UUID())
        let service = RatingFlowTestService(visitResponses: [.success(acknowledged)])
        let model = RatingFlowModel(request: request(mode: .addVisit), accountID: UUID(), ranking: service, storage: try storage())
        XCTAssertEqual(model.step, .details)
        XCTAssertTrue(model.updateDetails(note: "A return visit", date: nil))
        await model.okay()
        XCTAssertEqual(model.completion, .visit(acknowledged))
        let categories = await service.categories, commits = await service.commits, visits = await service.visits
        XCTAssertTrue(categories.isEmpty)
        XCTAssertTrue(commits.isEmpty)
        XCTAssertEqual(visits.count, 1)
        XCTAssertEqual(visits.first?.visit.publicNote, "A return visit")
    }

    func testOnlyYourOwnEditsCountAsSomethingToDiscard() throws {
        let model = RatingFlowModel(request: request(), accountID: UUID(), ranking: RatingFlowTestService(), storage: try storage())
        XCTAssertFalse(model.hasNonemptyDraft, "Neutral and today's date are filled in for you, so closing asks nothing")
        model.suggestTrip(UUID())
        XCTAssertFalse(model.hasNonemptyDraft, "A guessed trip isn't an edit either")
        model.setFeeling(.liked)
        XCTAssertTrue(model.hasNonemptyDraft)
        model.setFeeling(.fine)
        XCTAssertFalse(model.hasNonemptyDraft)
        XCTAssertTrue(model.updateDetails(note: "Something typed", date: model.visit.date))
        XCTAssertTrue(model.hasNonemptyDraft)
    }

    func testClosingAnUnsavedLogWritesNothingAndLeavesNothingBehind() async throws {
        let service = RatingFlowTestService(), owner = UUID(), other = UUID(), request = request(), storage = try storage()
        let model = RatingFlowModel(request: request, accountID: owner, ranking: service, storage: storage)
        model.selectSentiment(.liked)
        XCTAssertTrue(model.updateDetails(note: "Never saved", date: nil))
        model.keepDraft()
        let reopened = RatingFlowModel(request: request, accountID: owner, ranking: service, storage: storage)
        XCTAssertNotEqual(reopened.operationID, model.operationID)
        XCTAssertEqual(reopened.visit.publicNote, "")
        XCTAssertEqual(reopened.sentiment, .fine)
        let foreign = RatingFlowModel(request: request, accountID: other, ranking: service, storage: storage)
        XCTAssertEqual(foreign.visit.publicNote, "")
        reopened.discardDraft()
        XCTAssertTrue(storage.names(userID: owner, prefix: "rating-draft-").isEmpty)
        let commits = await service.commits, visits = await service.visits, categories = await service.categories
        XCTAssertTrue(commits.isEmpty && visits.isEmpty && categories.isEmpty)
    }
    func testAccountChangeCannotSubmitOrReuseAnotherAccountsDraft() async throws {
        let owner = UUID(), service = RatingFlowTestService()
        var active: UUID? = owner
        let model = RatingFlowModel(request: request(), accountID: owner, ranking: service, storage: try storage(), currentAccount: { active })
        model.selectSentiment(.liked)
        active = UUID()
        await model.okay()
        let commits = await service.commits, categories = await service.categories
        XCTAssertTrue(commits.isEmpty && categories.isEmpty)
        XCTAssertNil(model.completion)
        XCTAssertTrue(model.message?.contains("owns this draft") == true)
    }

    func testDateUsesDestinationDayUnknownIsValidFutureAndLongNoteAreRejected() throws {
        let now = ISO8601DateFormatter().date(from: "2026-10-14T03:00:00Z")!
        let model = RatingFlowModel(request: request(), accountID: UUID(), ranking: RatingFlowTestService(), storage: try storage(), now: { now })
        XCTAssertEqual(model.visit.date, LocalDate(isoString: "2026-10-14"))
        XCTAssertEqual(model.visit.timeZoneIdentifier, "Asia/Tokyo")
        XCTAssertFalse(model.updateDetails(note: "Future", date: model.today.adding(days: 1)))
        XCTAssertFalse(model.updateDetails(note: String(repeating: "a", count: 5_001), date: nil))
        XCTAssertTrue(model.updateDetails(note: "Known memory, unknown date", date: nil))
        XCTAssertNil(model.visit.date)
    }

    func testAnUnconfirmedSaveOlderThanThirtyDaysIsDropped() async throws {
        let start = Date(), owner = UUID(), request = request(), storage = try storage()
        let service = RatingFlowTestService(responses: [.failure(.timeout)])
        let model = RatingFlowModel(request: request, accountID: owner, ranking: service, storage: storage, now: { start })
        model.selectSentiment(.liked)
        await model.okay()
        XCTAssertEqual(model.step, .retry, "A save that wasn't confirmed is kept to check")
        let expired = RatingFlowModel(request: request, accountID: owner, ranking: service, storage: storage,
                                      now: { start.addingTimeInterval(31 * 86_400) })
        XCTAssertEqual(expired.step, .details)
        XCTAssertEqual(expired.sentiment, .fine)
        XCTAssertNotEqual(expired.operationID, model.operationID)
    }
    private func quickRequest(category: ExperienceCategory? = .foodDrink) -> LogRequest {
        var value = request(category: category)
        value.startsWithDetails = true
        return value
    }

    func testLogAPlaceSavesAVisitInOneStepWithoutARating() async throws {
        let service = RatingFlowTestService(visitResponses: [.success(AddVisitResult(visitID: UUID(), activityID: UUID()))])
        let model = RatingFlowModel(request: quickRequest(), accountID: UUID(), ranking: service, storage: try storage())
        XCTAssertEqual(model.step, .details, "No feeling or comparison is asked for first")
        XCTAssertEqual(model.sentiment, .fine, "A new log starts at Neutral")
        model.logWithoutRanking()
        XCTAssertTrue(model.skipsRanking)
        model.setAudience(.onlyMe)
        await model.okay()
        let saved = await service.visits
        let rated = await service.commits
        XCTAssertEqual(saved.first?.category, .foodDrink)
        XCTAssertEqual(saved.first?.visit.audience, .onlyMe)
        XCTAssertTrue(rated.isEmpty, "Logging never creates a rating by itself")
    }

    func testAPlaceWithNoKnownCategoryAsksBeforeSaving() throws {
        let model = RatingFlowModel(request: quickRequest(category: nil), accountID: UUID(), ranking: RatingFlowTestService(), storage: try storage())
        XCTAssertEqual(model.step, .details)
        XCTAssertNil(model.category)
        model.selectCategory(.culture)
        XCTAssertEqual(model.category, .culture)
    }

    func testRankingStaysAvailableFromLogAPlace() throws {
        let model = RatingFlowModel(request: quickRequest(), accountID: UUID(), ranking: RatingFlowTestService(), storage: try storage())
        model.backToSentiment()
        XCTAssertEqual(model.step, .sentiment)
        XCTAssertFalse(model.skipsRanking)
        model.selectSentiment(.liked)
        XCTAssertFalse(model.skipsRanking, "Choosing a feeling continues to comparisons")
    }

}
