import Foundation
import MapKit

// Real-backend services that later milestones replace with RPC-backed implementations.
// Until then they fail honestly with `RoamError.unavailable` rather than fabricating data.

extension SupabaseBackend: ExperienceService {
    func resolve(_ candidate: PlaceCandidate) async throws -> ExperienceSummary { throw RoamError.unavailable }
    func matches(for candidates: [PlaceCandidate]) async throws -> [String: ExperienceSummary] { throw RoamError.unavailable }
    func detail(experienceID: UUID) async throws -> ExperienceDetail { throw RoamError.unavailable }
    func experiences(in bounds: GeoBounds, category: ExperienceCategory?) async throws -> [ExperienceSummary] { throw RoamError.unavailable }
}

extension SupabaseBackend: ListService {
    func library() async throws -> UserLibrary { throw RoamError.unavailable }
    func setBookmark(experienceID: UUID, saved: Bool) async throws -> Bool { throw RoamError.unavailable }
    func been(ownerID: UUID) async throws -> [ListEntry] { throw RoamError.unavailable }
    func want(ownerID: UUID) async throws -> [ListEntry] { throw RoamError.unavailable }
    func sharedWants(with otherUserID: UUID) async throws -> [ListEntry] { throw RoamError.unavailable }
}

extension SupabaseBackend: RankingService {
    func categoryRanking(_ category: ExperienceCategory) async throws -> CategoryRanking { throw RoamError.unavailable }
    func commitRating(_ request: RatingCommitRequest) async throws -> RatingCommitResult { throw RoamError.unavailable }
    func addVisit(_ request: AddVisitRequest) async throws -> AddVisitResult { throw RoamError.unavailable }
    func removeRating(experienceID: UUID, operationID: UUID) async throws { throw RoamError.unavailable }
    func deleteVisit(visitID: UUID, operationID: UUID) async throws -> DeleteVisitResult { throw RoamError.unavailable }
}

extension SupabaseBackend: MemoryService {
    func updateVisit(visitID: UUID, note: String, date: VisitDate, mediaIDs: [UUID]) async throws -> Visit { throw RoamError.unavailable }
    func privateNote(experienceID: UUID) async throws -> PrivateNote? { throw RoamError.unavailable }
    func savePrivateNote(experienceID: UUID, text: String) async throws -> PrivateNote { throw RoamError.unavailable }
    func deletePrivateNote(experienceID: UUID) async throws { throw RoamError.unavailable }
}

extension SupabaseBackend: SocialService {
    func followers(of userID: UUID, query: String, cursor: String?) async throws -> Page<MemberRow> { throw RoamError.unavailable }
    func following(of userID: UUID, query: String, cursor: String?) async throws -> Page<MemberRow> { throw RoamError.unavailable }
    func searchMembers(query: String, cursor: String?) async throws -> Page<MemberRow> { throw RoamError.unavailable }
    func setMute(userID: UUID, muted: Bool) async throws { throw RoamError.unavailable }
    func setBlock(userID: UUID, blocked: Bool) async throws { throw RoamError.unavailable }
    func blockedMembers() async throws -> [MemberSummary] { throw RoamError.unavailable }
    func mutedMembers() async throws -> [MemberSummary] { throw RoamError.unavailable }
    func report(target: ReportTarget, reason: ReportReason, text: String?, operationID: UUID) async throws -> ReportReceipt { throw RoamError.unavailable }
    func myReports() async throws -> [ReportReceipt] { throw RoamError.unavailable }
}

extension SupabaseBackend: FeedService {
    func feed(cursor: String?) async throws -> Page<ActivityItem> { throw RoamError.unavailable }
    func profileActivity(userID: UUID, cursor: String?) async throws -> Page<ActivityItem> { throw RoamError.unavailable }
    func activity(id: UUID) async throws -> ActivityItem { throw RoamError.unavailable }
    func setLike(activityID: UUID, liked: Bool) async throws -> Bool { throw RoamError.unavailable }
    func comments(activityID: UUID, cursor: String?) async throws -> Page<Comment> { throw RoamError.unavailable }
    func postComment(activityID: UUID, body: String, operationID: UUID) async throws -> Comment { throw RoamError.unavailable }
    func deleteComment(id: UUID) async throws { throw RoamError.unavailable }
    func deleteActivity(id: UUID) async throws { throw RoamError.unavailable }
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
