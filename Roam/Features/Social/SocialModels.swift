import Foundation
import Observation

/// Posts changed on one screen (like, comment count, removal) are reflected on the others.
@MainActor
@Observable
final class ActivityChangeStore {
    private(set) var updated: [UUID: ActivityItem] = [:]
    private(set) var removed: Set<UUID> = []
    private(set) var revision = 0
    /// Follow, mute and block change who appears in the feed; it refreshes when shown next.
    private(set) var feedStale = false

    func publish(_ item: ActivityItem) { updated[item.id] = item; revision += 1 }
    func publishRemoval(_ id: UUID) { removed.insert(id); updated[id] = nil; revision += 1 }
    func markFeedStale() { feedStale = true; revision += 1 }
    func consumeFeedStale() -> Bool { defer { feedStale = false }; return feedStale }
    func reset() { updated = [:]; removed = []; feedStale = false; revision += 1 }
}

private func uniqueByID<Item: Identifiable>(_ items: [Item]) -> [Item] where Item.ID: Hashable {
    var seen = Set<Item.ID>()
    return items.filter { seen.insert($0.id).inserted }
}

/// S02: own and followed members' posts by server publication time. Refresh and paging never
/// blank acknowledged content; likes are optimistic with rollback.
@MainActor
@Observable
final class FeedModel {
    private(set) var items: [ActivityItem] = []
    private(set) var hasLoaded = false
    private(set) var isLoading = false
    private(set) var loadingMore = false
    private(set) var error: String?
    private(set) var pageError: String?
    private(set) var actionError: String?
    private(set) var nextCursor: String?
    private(set) var likePending: Set<UUID> = []
    private(set) var unreadCount = 0
    private(set) var authError: RoamError?
    private let service: any FeedService
    private let notifications: any NotificationService
    private let load: (String?) async throws -> Page<ActivityItem>
    private var generation = 0

    /// `source` defaults to the home feed; profiles pass their own activity page.
    init(service: any FeedService, notifications: any NotificationService,
         source: ((String?) async throws -> Page<ActivityItem>)? = nil) {
        self.service = service
        self.notifications = notifications
        self.load = source ?? { try await service.feed(cursor: $0) }
    }

    func refresh() async {
        generation += 1
        let token = generation
        isLoading = true
        defer { if token == generation { isLoading = false } }
        do {
            let page = try await load(nil)
            guard token == generation, !Task.isCancelled else { return }
            items = uniqueByID(page.items)
            nextCursor = page.nextCursor
            hasLoaded = true
            error = nil
            pageError = nil
        } catch {
            guard token == generation, !(error is CancellationError) else { return }
            record(error, into: \.error)
        }
    }

    func loadMore() async {
        guard !loadingMore, !isLoading, let cursor = nextCursor else { return }
        let token = generation
        loadingMore = true
        defer { if token == generation { loadingMore = false } }
        do {
            let page = try await load(cursor)
            guard token == generation, nextCursor == cursor, !Task.isCancelled else { return }
            items = uniqueByID(items + page.items)
            nextCursor = page.nextCursor
            pageError = nil
        } catch {
            guard token == generation, !(error is CancellationError) else { return }
            record(error, into: \.pageError)
        }
    }

    func refreshUnreadCount() async {
        if let count = try? await notifications.unreadCount() { unreadCount = count }
    }

    func setLike(_ id: UUID, liked: Bool) async {
        guard !likePending.contains(id), let index = items.firstIndex(where: { $0.id == id }), items[index].likedByViewer != liked else { return }
        let before = items[index]
        likePending.insert(id)
        defer { likePending.remove(id) }
        items[index].likedByViewer = liked
        items[index].likeCount = max(0, before.likeCount + (liked ? 1 : -1))
        actionError = nil
        do {
            let persisted = try await service.setLike(activityID: id, liked: liked)
            if persisted != liked, let current = items.firstIndex(where: { $0.id == id }) {
                items[current].likedByViewer = persisted
                items[current].likeCount = before.likeCount
            }
        } catch {
            if let current = items.firstIndex(where: { $0.id == id }) { items[current] = before }
            if (error as? RoamError) == .unavailable { remove(id) }
            record(error, into: \.actionError)
        }
    }

    func apply(_ changes: ActivityChangeStore) {
        items.removeAll { changes.removed.contains($0.id) }
        for index in items.indices { if let updated = changes.updated[items[index].id] { items[index] = updated } }
    }

    func remove(_ id: UUID) { items.removeAll { $0.id == id } }

    private func record(_ error: Error, into keyPath: ReferenceWritableKeyPath<FeedModel, String?>) {
        self[keyPath: keyPath] = error.roamMessage
        if let error = error as? RoamError, error == .sessionExpired || error == .notSignedIn { authError = error }
    }
}

/// S23: one post with likes and a flat chronological comment list. A failed comment keeps its
/// text and operation UUID, so a retry can never post twice.
@MainActor
@Observable
final class ActivityDetailModel {
    let activityID: UUID
    private(set) var item: ActivityItem?
    private(set) var isLoading = false
    private(set) var loadError: String?
    private(set) var isUnavailable = false
    private(set) var comments: [Comment] = []
    private(set) var commentsLoaded = false
    private(set) var commentsError: String?
    private(set) var commentsCursor: String?
    private(set) var loadingMoreComments = false
    var draft = "" { didSet { if draft != pending?.body { pending = nil } } }
    private(set) var pending: (operationID: UUID, body: String)?
    private(set) var isPosting = false
    private(set) var postError: String?
    private(set) var likePending = false
    private(set) var actionError: String?
    private(set) var deletingCommentID: UUID?
    private(set) var isRemoving = false
    private(set) var wasRemoved = false
    private(set) var authError: RoamError?
    private let service: any FeedService
    private var generation = 0

    var canPost: Bool {
        !isPosting && item != nil && Validation.comment(draft) == nil
    }

    init(activityID: UUID, service: any FeedService) {
        self.activityID = activityID
        self.service = service
    }

    func load() async {
        generation += 1
        let token = generation
        isLoading = true
        defer { if token == generation { isLoading = false } }
        do {
            let loaded = try await service.activity(id: activityID)
            guard token == generation else { return }
            item = loaded
            loadError = nil
            isUnavailable = false
            let page = try await service.comments(activityID: activityID, cursor: nil)
            guard token == generation else { return }
            comments = uniqueByID(page.items)
            commentsCursor = page.nextCursor
            commentsLoaded = true
            commentsError = nil
        } catch {
            guard token == generation, !(error is CancellationError) else { return }
            if let roam = error as? RoamError, roam == .unavailable || roam == .notFound || roam == .forbidden {
                // A removed or blocked post never keeps showing its cached text.
                isUnavailable = true
                item = nil
                comments = []
                pending = nil
                return
            }
            if item == nil { loadError = error.roamMessage } else { commentsError = error.roamMessage }
            authCheck(error)
        }
    }

    func loadMoreComments() async {
        guard !loadingMoreComments, let cursor = commentsCursor else { return }
        loadingMoreComments = true
        defer { loadingMoreComments = false }
        do {
            let page = try await service.comments(activityID: activityID, cursor: cursor)
            guard commentsCursor == cursor else { return }
            comments = uniqueByID(comments + page.items)
            commentsCursor = page.nextCursor
            commentsError = nil
        } catch {
            commentsError = error.roamMessage
            authCheck(error)
        }
    }

    func post() async -> Bool {
        guard canPost else { return false }
        let body = draft
        let operation = pending?.body == body ? pending!.operationID : UUID()
        pending = (operation, body)
        isPosting = true
        postError = nil
        defer { isPosting = false }
        do {
            let comment = try await service.postComment(activityID: activityID, body: body, operationID: operation)
            comments = uniqueByID(comments + [comment])
            if var current = item, !comments.dropLast().contains(where: { $0.id == comment.id }) {
                current.commentCount = max(current.commentCount, comments.count)
                item = current
            }
            pending = nil
            draft = ""
            return true
        } catch {
            postError = error.roamMessage
            if let roam = error as? RoamError {
                if roam == .unavailable { isUnavailable = true; item = nil; comments = [] }
                if !roam.isRetryable { pending = nil }
            }
            authCheck(error)
            return false
        }
    }

    func deleteComment(_ comment: Comment) async {
        guard comment.isOwn, deletingCommentID == nil else { return }
        deletingCommentID = comment.id
        defer { deletingCommentID = nil }
        do {
            try await service.deleteComment(id: comment.id)
            comments.removeAll { $0.id == comment.id }
            if var current = item { current.commentCount = max(0, current.commentCount - 1); item = current }
            actionError = nil
        } catch {
            actionError = error.roamMessage
            authCheck(error)
        }
    }

    func setLike(_ liked: Bool) async {
        guard !likePending, var current = item, current.likedByViewer != liked else { return }
        let before = current
        likePending = true
        defer { likePending = false }
        current.likedByViewer = liked
        current.likeCount = max(0, before.likeCount + (liked ? 1 : -1))
        item = current
        do {
            let persisted = try await service.setLike(activityID: activityID, liked: liked)
            if persisted != liked { item = before }
        } catch {
            item = before
            actionError = error.roamMessage
            authCheck(error)
        }
    }

    /// Removes only this post; the Rating and Visit stay.
    func removePost() async -> Bool {
        guard item?.isOwn == true, !isRemoving else { return false }
        isRemoving = true
        defer { isRemoving = false }
        do {
            try await service.deleteActivity(id: activityID)
            wasRemoved = true
            return true
        } catch {
            actionError = error.roamMessage
            authCheck(error)
            return false
        }
    }

    private func authCheck(_ error: Error) {
        if let error = error as? RoamError, error == .sessionExpired || error == .notSignedIn { authError = error }
    }
}

/// S25: Unread / Earlier, read-on-open, safe routing for removed targets.
@MainActor
@Observable
final class NotificationsModel {
    private(set) var items: [AppNotification] = []
    private(set) var hasLoaded = false
    private(set) var isLoading = false
    private(set) var loadingMore = false
    private(set) var error: String?
    private(set) var pageError: String?
    private(set) var actionError: String?
    private(set) var nextCursor: String?
    private(set) var authError: RoamError?
    private let service: any NotificationService
    private let now: () -> Date
    private var generation = 0

    var unread: [AppNotification] { items.filter(\.isUnread) }
    var earlier: [AppNotification] { items.filter { !$0.isUnread } }

    init(service: any NotificationService, now: @escaping () -> Date = Date.init) {
        self.service = service
        self.now = now
    }

    func load() async {
        generation += 1
        let token = generation
        isLoading = true
        defer { if token == generation { isLoading = false } }
        do {
            let page = try await service.notifications(cursor: nil)
            guard token == generation else { return }
            items = uniqueByID(page.items)
            nextCursor = page.nextCursor
            hasLoaded = true
            error = nil
            pageError = nil
        } catch {
            guard token == generation, !(error is CancellationError) else { return }
            self.error = error.roamMessage
            authCheck(error)
        }
    }

    func loadMore() async {
        guard !loadingMore, !isLoading, let cursor = nextCursor else { return }
        let token = generation
        loadingMore = true
        defer { if token == generation { loadingMore = false } }
        do {
            let page = try await service.notifications(cursor: cursor)
            guard token == generation, nextCursor == cursor else { return }
            items = uniqueByID(items + page.items)
            nextCursor = page.nextCursor
            pageError = nil
        } catch {
            guard token == generation else { return }
            pageError = error.roamMessage
            authCheck(error)
        }
    }

    func markAllRead() async {
        let before = items
        let stamp = now()
        for index in items.indices where items[index].readAt == nil { items[index].readAt = stamp }
        do { try await service.markAllRead(); actionError = nil }
        catch { items = before; actionError = error.roamMessage; authCheck(error) }
    }

    /// Marks the notification read and returns where it should open, or nil if its target is gone.
    func open(_ notification: AppNotification) async -> AppRoute? {
        if let index = items.firstIndex(where: { $0.id == notification.id }), items[index].readAt == nil {
            items[index].readAt = now()
            do { try await service.markRead(id: notification.id) }
            catch { items[index].readAt = nil; actionError = error.roamMessage; authCheck(error) }
        }
        guard notification.targetAvailable else {
            actionError = "This is no longer available."
            return nil
        }
        switch notification.type {
        case .follow: return .member(notification.actor.id)
        case .like, .comment: return notification.activityID.map(AppRoute.activity)
        }
    }

    private func authCheck(_ error: Error) {
        if let error = error as? RoamError, error == .sessionExpired || error == .notSignedIn { authError = error }
    }
}

/// S21: followers/following with server-side literal filtering and stable handle pages.
@MainActor
@Observable
final class FollowListModel {
    let userID: UUID
    var segment: FollowSegment
    private(set) var rows: [MemberRow] = []
    private(set) var hasLoaded = false
    private(set) var isLoading = false
    private(set) var loadingMore = false
    private(set) var error: String?
    private(set) var pageError: String?
    private(set) var actionError: String?
    private(set) var nextCursor: String?
    private(set) var pendingFollow: Set<UUID> = []
    private(set) var loadedQuery = ""
    private(set) var authError: RoamError?
    private let service: any SocialService
    private var generation = 0

    init(userID: UUID, segment: FollowSegment, service: any SocialService) {
        self.userID = userID
        self.segment = segment
        self.service = service
    }

    private func fetch(_ query: String, _ cursor: String?) async throws -> Page<MemberRow> {
        segment == .followers ? try await service.followers(of: userID, query: query, cursor: cursor)
                              : try await service.following(of: userID, query: query, cursor: cursor)
    }

    /// Latest query wins; an older response never overwrites a newer one.
    func load(query: String) async {
        generation += 1
        let token = generation
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        isLoading = true
        defer { if token == generation { isLoading = false } }
        do {
            let page = try await fetch(trimmed, nil)
            guard token == generation, !Task.isCancelled else { return }
            rows = uniqueByID(page.items)
            nextCursor = page.nextCursor
            loadedQuery = trimmed
            hasLoaded = true
            error = nil
            pageError = nil
        } catch {
            guard token == generation, !(error is CancellationError) else { return }
            self.error = error.roamMessage
            authCheck(error)
        }
    }

    func loadMore() async {
        guard !loadingMore, !isLoading, let cursor = nextCursor else { return }
        let token = generation
        loadingMore = true
        defer { if token == generation { loadingMore = false } }
        do {
            let page = try await fetch(loadedQuery, cursor)
            guard token == generation, nextCursor == cursor else { return }
            rows = uniqueByID(rows + page.items)
            nextCursor = page.nextCursor
            pageError = nil
        } catch {
            guard token == generation else { return }
            pageError = error.roamMessage
            authCheck(error)
        }
    }

    func setFollow(_ row: MemberRow, following: Bool) async {
        guard !row.isSelf, !pendingFollow.contains(row.id), let index = rows.firstIndex(where: { $0.id == row.id }) else { return }
        let before = rows[index]
        pendingFollow.insert(row.id)
        defer { pendingFollow.remove(row.id) }
        rows[index].isFollowing = following
        do {
            let persisted = try await service.setFollow(userID: row.id, following: following)
            if let current = rows.firstIndex(where: { $0.id == row.id }) { rows[current].isFollowing = persisted }
            actionError = nil
        } catch {
            if let current = rows.firstIndex(where: { $0.id == row.id }) { rows[current] = before }
            actionError = error.roamMessage
            authCheck(error)
        }
    }

    private func authCheck(_ error: Error) {
        if let error = error as? RoamError, error == .sessionExpired || error == .notSignedIn { authError = error }
    }
}

/// S22: the exact intersection of two Want to Go lists. A failed refresh keeps the last results.
@MainActor
@Observable
final class SharedWantsModel {
    let otherID: UUID
    private(set) var entries: [ListEntry] = []
    private(set) var hasLoaded = false
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var authError: RoamError?
    private let service: any ListService
    private var generation = 0

    init(otherID: UUID, service: any ListService) {
        self.otherID = otherID
        self.service = service
    }

    func load() async {
        generation += 1
        let token = generation
        isLoading = true
        defer { if token == generation { isLoading = false } }
        do {
            let loaded = try await service.sharedWants(with: otherID)
            guard token == generation else { return }
            entries = loaded
            hasLoaded = true
            error = nil
        } catch {
            guard token == generation, !(error is CancellationError) else { return }
            self.error = error.roamMessage
            if let error = error as? RoamError, error == .sessionExpired || error == .notSignedIn { authError = error }
        }
    }
}
