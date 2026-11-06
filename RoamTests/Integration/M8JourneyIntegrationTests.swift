import Foundation
import XCTest
@testable import Roam

/// M8: the complete two-member journey through the public API of the real local backend, starting
/// from empty lists and no follows. Each run owns new fictional accounts.
final class M8JourneyIntegrationTests: BackendTestCase {
    private var year: Int { Calendar.current.component(.year, from: Date()) }
    private var today: LocalDate { LocalDate.today(in: TimeZone(identifier: "Europe/Lisbon")!) }

    private func place(_ backend: SupabaseBackend, _ name: String, category: ExperienceCategory, locality: String = "Lisbon",
                       region: String = "Lisboa", country: String = "PT", countryName: String = "Portugal",
                       latitude: Double = 38.71, longitude: Double = -9.14) async throws -> ExperienceSummary {
        try await backend.resolve(PlaceCandidate(provider: .mapkit, providerPlaceID: "I-M8-\(UUID().uuidString)",
            name: "\(name) \(UUID().uuidString.prefix(6))", address: "8 Journey Street", locality: locality, region: region,
            countryCode: country, countryName: countryName, latitude: latitude, longitude: longitude, phone: nil, website: nil,
            providerCategory: nil, timeZoneIdentifier: "Europe/Lisbon", isLocality: false, suggestedCategory: category))
    }

    private func commit(_ backend: SupabaseBackend, _ experience: ExperienceSummary, category: ExperienceCategory,
                        sentiment: Sentiment = .liked, choice: ComparisonChoice = .preferExisting, intent: RatingIntent = .firstLog,
                        note: String = "") async throws -> RatingCommitResult {
        let ranking = try await backend.categoryRanking(category)
        let base = intent == .rerank ? ranking.removing(experienceID: experience.id) : ranking
        var insertion = InsertionSession(sentiment: sentiment, groups: base.groups(for: sentiment))
        while !insertion.isComplete { insertion.choose(choice) }
        return try await backend.commitRating(RatingCommitRequest(operationID: UUID(), intent: intent, experienceID: experience.id,
            category: category, sentiment: sentiment, baseRevision: ranking.revision, answers: insertion.answers,
            visit: intent == .firstLog ? VisitPayload(date: today, timeZoneIdentifier: "Europe/Lisbon", publicNote: note, mediaIDs: []) : nil))
    }

    func testTwoMembersWalkTheWholeJourneyAgainstTheRealBackend() async throws {
        let (maya, _) = try await newMember(handlePrefix: "jm")
        let (theo, _) = try await newMember(handlePrefix: "jt")
        let mayaProfile = try await maya.ownProfile(), theoProfile = try await theo.ownProfile()
        let mayaID = try XCTUnwrap(mayaProfile?.id), theoID = try XCTUnwrap(theoProfile?.id)

        // Empty, no-follow start.
        let emptyFeed = try await theo.feed(cursor: nil)
        XCTAssertTrue(emptyFeed.items.isEmpty, "No default follows, so nothing in the feed")

        // Want, then the first log ranks it at once and moves it out of Want to Go.
        let harbor = try await place(maya, "Journey Harbor", category: .foodDrink)
        _ = try await maya.setBookmark(experienceID: harbor.id, saved: true)
        let first = try await commit(maya, harbor, category: .foodDrink, note: "Sunset tarts on the terrace.")
        XCTAssertEqual(first.score, Score(tenths: 84))
        XCTAssertEqual(first.rank, 1)
        let afterFirst = try await maya.library()
        XCTAssertFalse(afterFirst.bookmarked.contains(harbor.id), "Ranking removes the Want bookmark in the same transaction")

        // A comparison answered Too tough ties both places at the same score and rank.
        let oysters = try await place(maya, "Journey Oysters", category: .foodDrink)
        let tied = try await commit(maya, oysters, category: .foodDrink, choice: .tooTough)
        XCTAssertEqual(tied.score, Score(tenths: 84))
        XCTAssertEqual(tied.groupSize, 2)
        let ranking = try await maya.categoryRanking(.foodDrink)
        XCTAssertEqual(ranking.groups(for: .liked).count, 1, "One tie group")

        // Following exposes both automatic posts, newest first; a comment notifies the author.
        _ = try await theo.setFollow(userID: mayaID, following: true)
        let feed = try await theo.feed(cursor: nil)
        XCTAssertEqual(feed.items.map(\.id), [tied.activityID, first.activityID])
        XCTAssertEqual(feed.items.last?.scoreSnapshot, Score(tenths: 84), "Posts carry the score when posted")
        let comment = try await theo.postComment(activityID: first.activityID, body: "Saving this for Lisbon!", operationID: UUID())
        let notices = try await maya.notifications(cursor: nil)
        XCTAssertEqual(Set(notices.items.map(\.type)), [.follow, .comment])
        XCTAssertTrue(notices.items.allSatisfy { $0.actor.id == theoID })

        // A repeat visit posts without reranking; Rank again moves it to fine, alone at 5.0.
        let revisit = try await maya.addVisit(AddVisitRequest(operationID: UUID(), experienceID: harbor.id,
            visit: VisitPayload(date: today, timeZoneIdentifier: "Europe/Lisbon", publicNote: "Back for more.", mediaIDs: [])))
        let rerank = try await commit(maya, harbor, category: .foodDrink, sentiment: .fine, intent: .rerank)
        XCTAssertEqual(rerank.score, Score(tenths: 50))
        let feedAfter = try await theo.feed(cursor: nil)
        XCTAssertEqual(Array(feedAfter.items.map(\.id).prefix(2)), [rerank.activityID, revisit.activityID])

        // Travel: one country, one city, both places new this year (the revisit doesn't count again).
        let travel = try await theo.travelProfile(userID: mayaID, year: year)
        XCTAssertEqual(travel.countryCount, 1)
        XCTAssertEqual(travel.cityCount, 1)
        XCTAssertEqual(travel.newThisYear.count, 2)
        XCTAssertEqual(travel.pins.first { $0.experienceID == harbor.id }?.visitCount, 2)

        // Shared Want to Go is the exact intersection.
        let baths = try await place(maya, "Journey Baths", category: .activities, locality: "Reykjavík", region: "Capital Region",
                                    country: "IS", countryName: "Iceland", latitude: 64.14, longitude: -21.9)
        let onlyMine = try await place(maya, "Journey Only Mine", category: .culture)
        _ = try await maya.setBookmark(experienceID: baths.id, saved: true)
        _ = try await maya.setBookmark(experienceID: onlyMine.id, saved: true)
        _ = try await theo.setBookmark(experienceID: baths.id, saved: true)
        let shared = try await theo.sharedWants(with: mayaID)
        XCTAssertEqual(shared.map(\.experience.id), [baths.id])

        // Removing the ranking keeps memories and travel, and removes the rating's post and comment.
        try await maya.removeRating(experienceID: harbor.id, operationID: UUID())
        let memories = try await theo.publicMemories(experienceID: harbor.id, cursor: nil)
        XCTAssertEqual(Set(memories.items.map(\.publicNote)), ["Sunset tarts on the terrace.", "Back for more."])
        let travelAfter = try await theo.travelProfile(userID: mayaID, year: year)
        XCTAssertEqual(travelAfter.pins.count, travel.pins.count, "Visits still count after the ranking is removed")
        let feedAfterRemoval = try await theo.feed(cursor: nil)
        XCTAssertFalse(feedAfterRemoval.items.contains { $0.id == first.activityID || $0.id == rerank.activityID })
        let comments = try? await theo.comments(activityID: first.activityID, cursor: nil)
        XCTAssertFalse(comments?.items.contains { $0.id == comment.id } ?? false, "The rating post's comments go with it")
    }
}
