import Foundation
import MapKit

// Real-backend services that later milestones replace with RPC-backed implementations.
// Until then they fail honestly with `RoamError.unavailable` rather than fabricating data.

extension SupabaseBackend: SocialService {
    func followers(of userID: UUID, query: String, cursor: String?) async throws -> Page<MemberRow> { throw RoamError.unavailable }
    func following(of userID: UUID, query: String, cursor: String?) async throws -> Page<MemberRow> { throw RoamError.unavailable }
    func setMute(userID: UUID, muted: Bool) async throws { throw RoamError.unavailable }
    func setBlock(userID: UUID, blocked: Bool) async throws { throw RoamError.unavailable }
    func blockedMembers() async throws -> [MemberSummary] { throw RoamError.unavailable }
    func mutedMembers() async throws -> [MemberSummary] { throw RoamError.unavailable }
}

extension SupabaseBackend: FeedService {
    func feed(cursor: String?) async throws -> Page<ActivityItem> { throw RoamError.unavailable }
    func profileActivity(userID: UUID, cursor: String?) async throws -> Page<ActivityItem> { throw RoamError.unavailable }
    func activity(id: UUID) async throws -> ActivityItem { throw RoamError.unavailable }
    func setLike(activityID: UUID, liked: Bool) async throws -> Bool { throw RoamError.unavailable }
    func comments(activityID: UUID, cursor: String?) async throws -> Page<Comment> { throw RoamError.unavailable }
    func postComment(activityID: UUID, body: String, operationID: UUID) async throws -> Comment { throw RoamError.unavailable }
    func deleteComment(id: UUID) async throws { throw RoamError.unavailable }
}

extension SupabaseBackend: NotificationService {
    func notifications(cursor: String?) async throws -> Page<AppNotification> { throw RoamError.unavailable }
    func unreadCount() async throws -> Int { throw RoamError.unavailable }
    func markRead(id: UUID) async throws { throw RoamError.unavailable }
    func markAllRead() async throws { throw RoamError.unavailable }
}

extension SupabaseBackend: SettingsService {
    func settings() async throws -> UserSettings { throw RoamError.unavailable }
    func update(_ settings: UserSettings) async throws -> UserSettings { throw RoamError.unavailable }
}

extension SupabaseBackend: TravelService {
    func travelProfile(userID: UUID, year: Int) async throws -> TravelProfile { throw RoamError.unavailable }
}

extension SupabaseBackend: AccountService {
    func requestDeletion() async throws -> AccountDeletionStatus { throw RoamError.unavailable }
    func deletionStatus() async throws -> AccountDeletionStatus? { throw RoamError.unavailable }
}
