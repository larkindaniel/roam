import Foundation
import Supabase

/// `{items, nextCursor}` keyset pages returned by the M6 RPCs.
private struct PageWire<Item: Decodable>: Decodable {
    let items: [Item]
    let nextCursor: String?
}

extension SupabaseBackend {
    fileprivate func page<Item: Decodable & Hashable & Sendable>(_ function: String, _ params: RPCParams) async throws -> Page<Item> {
        let wire: PageWire<Item> = try await rpc(function, params)
        return Page(items: wire.items, nextCursor: wire.nextCursor)
    }
}

extension SupabaseBackend: SocialService {
    func friendAction(userID: UUID, action: FriendAction) async throws -> FriendState {
        try await rpc("friend_action", ["p_user_id": RPC.uuid(userID), "p_action": RPC.string(action.rawValue)])
    }

    func incomingFriendRequests(cursor: String?) async throws -> Page<MemberRow> {
        try await page("incoming_friend_requests", ["p_cursor": RPC.string(cursor)])
    }

    func followers(of userID: UUID, query: String, cursor: String?) async throws -> Page<MemberRow> {
        try await page("followers", ["p_user_id": RPC.uuid(userID), "p_query": RPC.string(query), "p_cursor": RPC.string(cursor)])
    }

    func following(of userID: UUID, query: String, cursor: String?) async throws -> Page<MemberRow> {
        try await page("following", ["p_user_id": RPC.uuid(userID), "p_query": RPC.string(query), "p_cursor": RPC.string(cursor)])
    }

    func setMute(userID: UUID, muted: Bool) async throws {
        let _: Bool = try await rpc("set_mute", ["p_user_id": RPC.uuid(userID), "p_muted": RPC.bool(muted)])
    }

    func setBlock(userID: UUID, blocked: Bool) async throws {
        let _: Bool = try await rpc("set_block", ["p_user_id": RPC.uuid(userID), "p_blocked": RPC.bool(blocked)])
    }

    func blockedMembers() async throws -> [MemberSummary] { try await rpc("blocked_members") }

    func mutedMembers() async throws -> [MemberSummary] { try await rpc("muted_members") }
}

extension SupabaseBackend: FeedService {
    func friendsActivity(cursor: String?) async throws -> Page<ActivityItem> {
        try await page("friends_activity", ["p_cursor": RPC.string(cursor)])
    }

    func feed(cursor: String?) async throws -> Page<ActivityItem> {
        try await page("feed", ["p_cursor": RPC.string(cursor)])
    }

    func profileActivity(userID: UUID, cursor: String?) async throws -> Page<ActivityItem> {
        try await page("profile_activity", ["p_user_id": RPC.uuid(userID), "p_cursor": RPC.string(cursor)])
    }

    func activity(id: UUID) async throws -> ActivityItem {
        try await rpc("activity", ["p_activity_id": RPC.uuid(id)])
    }

    func setLike(activityID: UUID, liked: Bool) async throws -> Bool {
        try await rpc("set_like", ["p_activity_id": RPC.uuid(activityID), "p_liked": RPC.bool(liked)])
    }

    func comments(activityID: UUID, cursor: String?) async throws -> Page<Comment> {
        try await page("comments", ["p_activity_id": RPC.uuid(activityID), "p_cursor": RPC.string(cursor)])
    }

    func postComment(activityID: UUID, body: String, operationID: UUID) async throws -> Comment {
        try await rpc("post_comment", ["p_activity_id": RPC.uuid(activityID), "p_body": RPC.string(body), "p_operation_id": RPC.uuid(operationID)])
    }

    func deleteComment(id: UUID) async throws {
        let _: Bool = try await rpc("delete_comment", ["p_comment_id": RPC.uuid(id)])
    }
}

extension SupabaseBackend: NotificationService {
    func notifications(cursor: String?) async throws -> Page<AppNotification> {
        try await page("notifications", ["p_cursor": RPC.string(cursor)])
    }

    func unreadCount() async throws -> Int { try await rpc("unread_notification_count") }

    func markRead(id: UUID) async throws {
        try await rpcVoid("mark_notification_read", ["p_notification_id": RPC.uuid(id)])
    }

    func markAllRead() async throws {
        try await rpcVoid("mark_all_notifications_read", [String: AnyJSON]())
    }
}
