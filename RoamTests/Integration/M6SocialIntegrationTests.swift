import Foundation
import XCTest
@testable import Roam

/// M6 public-API journeys against the real local backend with an owner, a follower, an
/// unrelated/blocked member and anonymous calls. Each test creates its own fictional accounts.
final class M6SocialIntegrationTests: BackendTestCase {
    private func place(_ backend: SupabaseBackend, name: String = "Social Place") async throws -> ExperienceSummary {
        try await backend.resolve(PlaceCandidate(provider: .mapkit, providerPlaceID: "I-M6-\(UUID().uuidString)",
            name: "\(name) \(UUID().uuidString.prefix(6))", address: "6 Social Street, Madrid", locality: "Madrid", region: "Madrid",
            countryCode: "ES", countryName: "Spain", latitude: 40.41, longitude: -3.70, phone: nil, website: nil,
            providerCategory: nil, timeZoneIdentifier: "Europe/Madrid", isLocality: false, suggestedCategory: .nightlife))
    }

    @discardableResult
    private func log(_ backend: SupabaseBackend, _ experience: ExperienceSummary, note: String = "Social memory",
                     sentiment: Sentiment = .liked) async throws -> RatingCommitResult {
        let ranking = try await backend.categoryRanking(.nightlife)
        var insertion = InsertionSession(sentiment: sentiment, groups: ranking.groups(for: sentiment))
        while !insertion.isComplete { insertion.choose(.preferExisting) }
        return try await backend.commitRating(RatingCommitRequest(operationID: UUID(), intent: .firstLog, experienceID: experience.id,
            category: .nightlife, sentiment: sentiment, baseRevision: ranking.revision, answers: insertion.answers,
            visit: VisitPayload(date: LocalDate(isoString: "2026-04-05"), timeZoneIdentifier: "Europe/Madrid", publicNote: note, mediaIDs: [])))
    }

    private func id(_ backend: SupabaseBackend) async throws -> UUID {
        let profile = try await backend.ownProfile()
        return try XCTUnwrap(profile?.id)
    }

    private func handle(_ backend: SupabaseBackend) async throws -> String {
        let profile = try await backend.ownProfile()
        return try XCTUnwrap(profile?.handle)
    }

    private func expectFailure(_ description: String, _ predicate: (RoamError) -> Bool, _ operation: () async throws -> Void) async {
        do { try await operation(); XCTFail("\(description): unexpectedly succeeded") }
        catch let error as RoamError { XCTAssertTrue(predicate(error), "\(description): unexpected \(error)") }
        catch { XCTFail("\(description): unexpected \(error)") }
    }

    func testFollowingExposesHistoryAndNewPostsByPublicationTime() async throws {
        let (owner, _) = try await newMember(handlePrefix: "fo")
        let (follower, _) = try await newMember(handlePrefix: "ff")
        let (stranger, _) = try await newMember(handlePrefix: "fs")
        let ownerID = try await id(owner)
        let earlier = try await log(owner, try await place(owner, name: "Earlier"))
        _ = try await log(stranger, try await place(stranger, name: "Stranger"))
        let empty = try await follower.feed(cursor: nil)
        XCTAssertTrue(empty.items.isEmpty, "No default follows; nothing until following")
        let requested = try await follower.friendAction(userID: ownerID, action: .request)
        XCTAssertEqual(requested, .sent)
        let pending = try await follower.feed(cursor: nil)
        XCTAssertTrue(pending.items.isEmpty, "A pending request shows nothing")
        let followerID = try await id(follower)
        let accepted = try await owner.friendAction(userID: followerID, action: .accept)
        XCTAssertEqual(accepted, .friends)
        let history = try await follower.feed(cursor: nil)
        XCTAssertEqual(history.items.map(\.id), [earlier.activityID], "Following exposes earlier eligible posts, never strangers'")
        let newer = try await log(owner, try await place(owner, name: "Newer"))
        let updated = try await follower.feed(cursor: nil)
        XCTAssertEqual(updated.items.map(\.id), [newer.activityID, earlier.activityID], "Newest publication first")
        let removed = try await follower.friendAction(userID: ownerID, action: .remove)
        XCTAssertEqual(removed, .none)
        let afterUnfollow = try await follower.feed(cursor: nil)
        XCTAssertTrue(afterUnfollow.items.isEmpty)
        let profile = try await follower.publicProfile(userID: ownerID)
        XCTAssertEqual(profile.followingCount, 0)
    }

    func testLikesCommentsAndNotificationsAreIdempotent() async throws {
        let (owner, _) = try await newMember(handlePrefix: "lo")
        let (fan, _) = try await newMember(handlePrefix: "lf")
        let ownerID = try await id(owner)
        let posted = try await log(owner, try await place(owner))
        try await befriend(fan, owner)
        let likedOnce = try await fan.setLike(activityID: posted.activityID, liked: true)
        let likedTwice = try await fan.setLike(activityID: posted.activityID, liked: true)
        XCTAssertTrue(likedOnce && likedTwice)
        let liked = try await fan.activity(id: posted.activityID)
        XCTAssertEqual(liked.likeCount, 1)
        let operation = UUID()
        let comment = try await fan.postComment(activityID: posted.activityID, body: "Count me in", operationID: operation)
        let retried = try await fan.postComment(activityID: posted.activityID, body: "Count me in", operationID: operation)
        XCTAssertEqual(retried.id, comment.id, "A retried comment is stored once")
        await expectFailure("same operation, different text", { if case .conflict = $0 { return true }; return false }) {
            _ = try await fan.postComment(activityID: posted.activityID, body: "Changed", operationID: operation)
        }
        let notes = try await owner.notifications(cursor: nil)
        XCTAssertEqual(Set(notes.items.map(\.type)), [.like, .comment], "Accepting a request clears its notification")
        let unreadAtStart = try await owner.unreadCount()
        XCTAssertEqual(unreadAtStart, 2)
        try await owner.markRead(id: try XCTUnwrap(notes.items.first).id)
        let unreadAfterOne = try await owner.unreadCount()
        XCTAssertEqual(unreadAfterOne, 1)
        try await owner.markAllRead()
        let unreadAfterAll = try await owner.unreadCount()
        XCTAssertEqual(unreadAfterAll, 0)
        try await fan.deleteComment(id: comment.id)
        let afterDelete = try await owner.notifications(cursor: nil)
        XCTAssertFalse(afterDelete.items.contains { $0.type == .comment }, "A deleted comment removes its notification")
        let afterDeletePost = try await fan.activity(id: posted.activityID)
        XCTAssertEqual(afterDeletePost.commentCount, 0)
        // Recipient preferences are proven in 05_m6_social_test.sql; the settings API and UI arrive in M7.
    }

    func testBlockIsMutualServerSideAndUnblockDoesNotRestoreFollows() async throws {
        let (owner, _) = try await newMember(handlePrefix: "bo")
        let (blocked, _) = try await newMember(handlePrefix: "bb")
        let ownerID = try await id(owner)
        let blockedID = try await id(blocked)
        let experience = try await place(owner)
        let posted = try await log(owner, experience)
        _ = try await owner.setBookmark(experienceID: try await place(owner, name: "Want").id, saved: true)
        try await befriend(blocked, owner)
        try await owner.setBlock(userID: blockedID, blocked: true)
        await expectFailure("profile", { $0 == .notFound }) { _ = try await blocked.publicProfile(userID: ownerID) }
        await expectFailure("post", { $0 == .unavailable }) { _ = try await blocked.activity(id: posted.activityID) }
        await expectFailure("like", { $0 == .unavailable }) { _ = try await blocked.setLike(activityID: posted.activityID, liked: true) }
        await expectFailure("comment", { $0 == .unavailable }) {
            _ = try await blocked.postComment(activityID: posted.activityID, body: "Hi", operationID: UUID())
        }
        await expectFailure("lists", { $0 == .notFound }) { _ = try await blocked.want(ownerID: ownerID) }
        await expectFailure("shared wants", { $0 == .notFound }) { _ = try await blocked.sharedWants(with: ownerID) }
        await expectFailure("friend request", { $0 == .notFound }) { _ = try await blocked.friendAction(userID: ownerID, action: .request) }
        let memories = try await blocked.publicMemories(experienceID: experience.id, cursor: nil)
        XCTAssertTrue(memories.items.isEmpty, "Public memories exclude the blocker")
        let search = try await blocked.searchMembers(query: try await handle(owner), cursor: nil)
        XCTAssertTrue(search.items.isEmpty)
        let blockedList = try await owner.blockedMembers()
        XCTAssertEqual(blockedList.map(\.id), [blockedID])
        try await owner.setBlock(userID: blockedID, blocked: false)
        let restored = try await blocked.publicProfile(userID: ownerID)
        XCTAssertEqual(restored.relationship.friendState, .none, "Unblocking never restores a friendship")
        XCTAssertEqual(restored.followingCount, 0)
    }

    func testMuteAffectsOnlyTheFeed() async throws {
        let (author, _) = try await newMember(handlePrefix: "ma")
        let (muter, _) = try await newMember(handlePrefix: "mm")
        let authorID = try await id(author)
        let posted = try await log(author, try await place(author))
        try await befriend(muter, author)
        try await muter.setMute(userID: authorID, muted: true)
        let mutedFeed = try await muter.feed(cursor: nil)
        XCTAssertTrue(mutedFeed.items.isEmpty)
        let profilePosts = try await muter.profileActivity(userID: authorID, cursor: nil)
        XCTAssertEqual(profilePosts.items.map(\.id), [posted.activityID])
        let muted = try await muter.mutedMembers()
        XCTAssertEqual(muted.map(\.id), [authorID])
        try await muter.setMute(userID: authorID, muted: false)
        let unmutedFeed = try await muter.feed(cursor: nil)
        XCTAssertEqual(unmutedFeed.items.map(\.id), [posted.activityID])
    }

    func testSharedWantToGoIsTheExactIntersection() async throws {
        let (first, _) = try await newMember(handlePrefix: "sw")
        let (second, _) = try await newMember(handlePrefix: "sx")
        let secondID = try await id(second)
        let common = try await place(first, name: "Common")
        let onlyFirst = try await place(first, name: "Only first")
        let onlySecond = try await place(second, name: "Only second")
        _ = try await first.setBookmark(experienceID: common.id, saved: true)
        _ = try await first.setBookmark(experienceID: onlyFirst.id, saved: true)
        _ = try await second.setBookmark(experienceID: common.id, saved: true)
        _ = try await second.setBookmark(experienceID: onlySecond.id, saved: true)
        let shared = try await first.sharedWants(with: secondID)
        XCTAssertEqual(shared.map(\.experience.id), [common.id])
        _ = try await second.setBookmark(experienceID: common.id, saved: false)
        let afterChange = try await first.sharedWants(with: secondID)
        XCTAssertTrue(afterChange.isEmpty, "Either list's change refreshes the intersection")
    }

    func testFollowerPagesAreStableAndAnonymousCallersAreDenied() async throws {
        let (owner, _) = try await newMember(handlePrefix: "po")
        let ownerID = try await id(owner)
        for _ in 0..<31 {
            let (follower, _) = try await newMember(handlePrefix: "pq")
            try await befriend(follower, owner)
        }
        let page1 = try await owner.followers(of: ownerID, query: "", cursor: nil)
        XCTAssertEqual(page1.items.count, 30)
        let page2 = try await owner.followers(of: ownerID, query: "", cursor: page1.nextCursor)
        XCTAssertEqual(page2.items.count, 1)
        XCTAssertTrue(Set(page1.items.map(\.id)).isDisjoint(with: page2.items.map(\.id)))
        let (status, _) = try await rest("rest/v1/rpc/feed", method: "POST", body: Data("{}".utf8))
        XCTAssertTrue(status == 401 || status == 403, "Anonymous feed reads are denied (HTTP \(status))")
    }
}
