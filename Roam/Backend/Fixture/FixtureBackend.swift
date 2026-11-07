#if ROAM_FIXTURES
import Foundation
import UIKit

/// In-memory backend for deterministic Debug/UI-test runs. It mirrors the server's rules
/// (ranking replay, receipts, block/mute visibility, lifecycle cascades) closely enough for
/// journeys and screenshots, but it is never a substitute for the database tests and is
/// compiled out of Release builds.
actor FixtureBackend {
    struct Member {
        var id: UUID
        var handle: String?
        var displayName: String?
        var bio: String
        var email: String
        var password: String
        var avatarPath: String?
        var homeCity: Destination?
        var setupCheckpoint: SetupCheckpoint?
        var hasSeenBeenIntro: Bool
        var createdAt: Date
        var emailConfirmed: Bool
        var providers: [AuthProviderKind]
        var deleted = false
    }

    struct PlaceRow {
        var id: UUID
        var candidate: PlaceCandidate
        var status: ProviderStatus
    }

    struct ExperienceRow {
        var id: UUID
        var placeID: UUID
        var category: ExperienceCategory?
        var categoryLocked: Bool
        var createdAt: Date
    }

    struct VisitRow {
        var id: UUID
        var owner: UUID
        var experience: UUID
        var date: LocalDate?
        var timeZone: String?
        var note: String
        var mediaIDs: [UUID]
        var createdAt: Date
        var updatedAt: Date
        /// Seeded entries were published to all members; new entries come from the log sheet.
        var audience: Audience = .public
        var tripID: UUID? = nil
    }

    struct RatingRow {
        var id: UUID
        var owner: UUID
        var experience: UUID
        var category: ExperienceCategory
        var sentiment: Sentiment
        var group: Int
        var firstRatedAt: Date
        var updatedAt: Date
    }

    struct ActivityRow {
        var id: UUID
        var author: UUID
        var type: ActivityType
        var experience: UUID
        var visit: UUID?
        var rating: UUID?
        var category: ExperienceCategory
        var score: Score?
        var rank: Int?
        var sentiment: Sentiment?
        var publishedAt: Date
    }

    struct CommentRow {
        var id: UUID
        var activity: UUID
        var author: UUID
        var body: String
        var createdAt: Date
        var operationID: UUID
    }

    struct NotificationRow {
        var id: UUID
        var recipient: UUID
        var actor: UUID
        var type: NotificationType
        var activity: UUID?
        var comment: UUID?
        var eventKey: String
        var createdAt: Date
        var readAt: Date?
    }

    struct MediaRow {
        var id: UUID
        var owner: UUID
        var visit: UUID?
        var purpose: MediaPurpose
        var path: String
        var width: Int
        var height: Int
        var position: Int
        var attached: Bool
        var createdAt: Date
        var data: Data?
        var seedHue: Double
    }

    struct Pair: Hashable {
        let a: UUID
        let b: UUID
    }

    // MARK: State

    var members: [UUID: Member] = [:]
    var places: [UUID: PlaceRow] = [:]
    var experiences: [UUID: ExperienceRow] = [:]
    var visits: [UUID: VisitRow] = [:]
    var ratings: [UUID: RatingRow] = [:]
    var bookmarks: [Pair: Date] = [:]
    var privateNotes: [Pair: PrivateNote] = [:]
    var media: [UUID: MediaRow] = [:]
    var activities: [UUID: ActivityRow] = [:]
    var trips: [UUID: TripRow] = [:]
    var fixtureHomeCities: [UUID: [Destination]] = [:]
    var fixtureVisitedCities: [UUID: [Destination]] = [:]
    var placeLists: [UUID: ListRow] = [:]
    var shares: [UUID: ShareRow] = [:]
    var tastes: [UUID: TasteProfile] = [:]
    /// Places and cities hidden with Not interested.
    var hiddenSuggestions: Set<UUID> = []
    var fixtureCityIDs: [String: UUID] = [:]
    var follows: [Pair: Date] = [:]
    /// Pending requests: a asked b.
    var friendRequests: [Pair: Date] = [:]
    var likes: [Pair: Date] = [:]
    var comments: [UUID: CommentRow] = [:]
    var notifications: [UUID: NotificationRow] = [:]
    var blocks: Set<Pair> = []
    var mutes: Set<Pair> = []
    var reports: [UUID: (reporter: UUID, receipt: ReportReceipt, targetID: UUID, text: String?)] = [:]
    var settingsByUser: [UUID: UserSettings] = [:]
    var revisions: [String: Int] = [:]
    var receipts: [String: (hash: String, result: Any)] = [:]
    var uploadAttempts: [String: (hash: String, mediaID: UUID)] = [:]
    var injectedContentFaults: Set<String> = []
    var mediaUploadCallCount = 0
    var pendingCodes: [String: String] = [:]
    var currentUserID: UUID?
    var recoveryUserID: UUID?
    var deletionStatus: [UUID: AccountDeletionStatus] = [:]
    /// When each member last signed in or reauthenticated (the token's `amr` time on the server).
    var authenticatedAt: [UUID: Date] = [:]

    let latency: UInt64
    let scenario: String
    nonisolated let sessionBroadcaster = SessionBroadcaster()
    nonisolated let catalog: FixturePlaceCatalog

    init(scenario: String, signedInHandle: String?, latencyMilliseconds: Int) {
        self.scenario = scenario
        self.latency = UInt64(max(0, latencyMilliseconds)) * 1_000_000
        self.catalog = FixturePlaceCatalog()
        var seeded = FixtureState()
        seeded.seed(scenario: scenario, catalog: catalog)
        members = seeded.members
        var seededPlaces = seeded.places, seededExperiences = seeded.experiences
        var seededShares: [UUID: ShareRow] = [:], seededLists: [UUID: ListRow] = [:], seededTrips: [UUID: TripRow] = [:]
        if scenario != "empty" && scenario != "new-account" {
            Self.seedSuggestionSignals(places: &seededPlaces, experiences: &seededExperiences, shares: &seededShares, lists: &seededLists,
                                       trips: &seededTrips, catalog: catalog)
        }
        places = seededPlaces
        experiences = seededExperiences
        shares = seededShares
        placeLists = seededLists
        trips = seededTrips
        visits = seeded.visits
        ratings = seeded.ratings
        bookmarks = seeded.bookmarks
        media = seeded.media
        activities = seeded.activities
        follows = seeded.follows
        friendRequests = seeded.friendRequests
        likes = seeded.likes
        comments = seeded.comments
        notifications = seeded.notifications
        revisions = seeded.revisions
        if let handle = signedInHandle {
            currentUserID = seeded.members.values.first(where: { $0.handle == handle })?.id
                ?? seeded.members.values.first(where: { $0.handle?.hasPrefix(handle) == true })?.id
                ?? (handle == "newcomer" ? FixtureIDs.newcomer : nil)
        }
    }

    // MARK: Helpers

    /// Test seam: makes every recorded sign-in `seconds` older (the server checks the token's sign-in time).
    func ageAuthentication(by seconds: TimeInterval) {
        for (id, date) in authenticatedAt { authenticatedAt[id] = date.addingTimeInterval(-seconds) }
    }

    func pause() async {
        if latency > 0 { try? await Task.sleep(nanoseconds: latency) }
    }

    func requireUser() throws -> UUID {
        guard let id = currentUserID, let member = members[id] else { throw RoamError.notSignedIn }
        // Like the server's `account_disabled`: a deactivated account's token can no longer act.
        guard !member.deleted else { throw RoamError.forbidden }
        return id
    }

    func requireProfile() throws -> UUID {
        let id = try requireUser()
        guard members[id]?.handle != nil else { throw RoamError.forbidden }
        return id
    }

    func authenticatedActor() async throws -> UUID {
        let actor = try requireProfile()
        await pause()
        guard currentUserID == actor else { throw RoamError.sessionExpired }
        try Task.checkCancellation()
        _ = try requireProfile()
        return actor
    }

    func isBlockedEitherWay(_ a: UUID, _ b: UUID) -> Bool {
        blocks.contains(Pair(a: a, b: b)) || blocks.contains(Pair(a: b, b: a))
    }

    func isVisibleMember(_ id: UUID, to viewer: UUID) -> Bool {
        guard let member = members[id], !member.deleted, member.handle != nil else { return false }
        return !isBlockedEitherWay(id, viewer)
    }

    func memberSummary(_ id: UUID) -> MemberSummary {
        let member = members[id]
        return MemberSummary(id: id, handle: member?.handle ?? "unknown", displayName: member?.displayName ?? "Roam member", avatarPath: member?.avatarPath)
    }

    func revisionKey(_ owner: UUID, _ category: ExperienceCategory) -> String { "\(owner.uuidString)|\(category.rawValue)" }

    func ranking(owner: UUID, category: ExperienceCategory) -> CategoryRanking {
        let rows = ratings.values.filter { $0.owner == owner && $0.category == category }
        var ranking = CategoryRanking(category: category, revision: revisions[revisionKey(owner, category)] ?? 0)
        for sentiment in Sentiment.partitionOrder {
            let grouped = Dictionary(grouping: rows.filter { $0.sentiment == sentiment }, by: \.group)
            let groups = grouped.keys.sorted().map { key in
                TieGroup(entries: grouped[key]!.map { row in
                    RankedEntry(ratingID: row.id, experienceID: row.experience, name: placeName(row.experience),
                                locality: places[experiences[row.experience]?.placeID ?? UUID()]?.candidate.locality, firstRatedAt: row.firstRatedAt)
                })
            }
            ranking.setGroups(groups, for: sentiment)
        }
        return ranking
    }

    /// Rewrites stored rating rows for one owner/category from a computed ranking.
    func store(_ ranking: CategoryRanking, owner: UUID, now: Date) {
        for sentiment in Sentiment.partitionOrder {
            for (index, group) in ranking.groups(for: sentiment).enumerated() {
                for entry in group.entries {
                    if var row = ratings[entry.ratingID] {
                        row.sentiment = sentiment
                        row.group = index
                        row.category = ranking.category
                        ratings[entry.ratingID] = row
                    } else {
                        ratings[entry.ratingID] = RatingRow(id: entry.ratingID, owner: owner, experience: entry.experienceID, category: ranking.category,
                                                            sentiment: sentiment, group: index, firstRatedAt: entry.firstRatedAt, updatedAt: now)
                    }
                }
            }
        }
    }

    func placeName(_ experienceID: UUID) -> String {
        guard let experience = experiences[experienceID], let place = places[experience.placeID] else { return "Unknown place" }
        return place.candidate.name
    }

    func placement(owner: UUID, experience: UUID) -> Placement? {
        guard let rating = ratings.values.first(where: { $0.owner == owner && $0.experience == experience }) else { return nil }
        return ranking(owner: owner, category: rating.category).placement(forExperience: experience)
    }

    func audienceAllows(owner: UUID, audience: Audience, viewer: UUID) -> Bool {
        if owner == viewer { return true }
        guard audience != .onlyMe, isVisibleMember(owner, to: viewer) else { return false }
        return audience == .public || follows[Pair(a: viewer, b: owner)] != nil
    }

    func activityAllowed(_ row: ActivityRow, viewer: UUID) -> Bool {
        guard let visitID = row.visit, let visit = visits[visitID] else { return audienceAllows(owner: row.author, audience: .public, viewer: viewer) }
        return audienceAllows(owner: visit.owner, audience: visit.audience, viewer: viewer)
    }

    func followingScore(for experienceID: UUID, viewer: UUID) -> (Score?, Int) {
        let followed = follows.keys.filter { $0.a == viewer }.map(\.b)
        let scores = followed.filter { $0 != viewer && !isBlockedEitherWay($0, viewer) && members[$0]?.deleted == false }
            .filter { owner in ratings.values.first { $0.owner == owner && $0.experience == experienceID }
                .map { audienceAllows(owner: owner, audience: ratingAudience($0), viewer: viewer) } ?? false }
            .compactMap { placement(owner: $0, experience: experienceID)?.score }
        return (ScoreMath.mean(of: scores), scores.count)
    }

    func summary(_ experienceID: UUID, viewer: UUID?) -> ExperienceSummary? {
        guard let experience = experiences[experienceID], let place = places[experience.placeID] else { return nil }
        var viewerState = ViewerExperienceState.none
        var following: (Score?, Int) = (nil, 0)
        if let viewer {
            let mine = placement(owner: viewer, experience: experienceID)
            viewerState = ViewerExperienceState(
                isBookmarked: bookmarks[Pair(a: viewer, b: experienceID)] != nil,
                myRatingCategory: ratings.values.first(where: { $0.owner == viewer && $0.experience == experienceID })?.category,
                myScore: mine?.score, myRank: mine?.rank,
                hasVisits: visits.values.contains { $0.owner == viewer && $0.experience == experienceID })
            following = followingScore(for: experienceID, viewer: viewer)
        }
        let c = place.candidate
        return ExperienceSummary(id: experienceID, placeID: place.id, name: c.name, category: experience.category, locality: c.locality,
                                 region: c.region, countryCode: c.countryCode, countryName: c.countryName, latitude: c.latitude,
                                 longitude: c.longitude, providerPlaceID: c.providerPlaceID, followingScore: following.0,
                                 followingCount: following.1, viewer: viewerState, providerCategory: c.providerCategory)
    }

    func visitModel(_ row: VisitRow) -> Visit {
        let mediaRefs = row.mediaIDs.compactMap { media[$0] }.sorted { $0.position < $1.position }
            .map { MediaRef(id: $0.id, path: $0.path, width: $0.width, height: $0.height, position: $0.position) }
        return Visit(id: row.id, experienceID: row.experience, ownerID: row.owner,
                     visitDate: VisitDate(date: row.date, timeZoneIdentifier: row.timeZone), publicNote: row.note,
                     media: mediaRefs, createdAt: row.createdAt, updatedAt: row.updatedAt, audience: row.audience, tripID: row.tripID)
    }

    func activityItem(_ row: ActivityRow, viewer: UUID) -> ActivityItem? {
        guard let summary = summary(row.experience, viewer: viewer) else { return nil }
        let visit = row.visit.flatMap { visits[$0] }
        let mediaRefs = visit.map(visitModel)?.media ?? []
        return ActivityItem(id: row.id, type: row.type, author: memberSummary(row.author), experience: summary, category: row.category,
                            scoreSnapshot: row.score, rankSnapshot: row.rank, sentimentSnapshot: row.sentiment, visitID: row.visit,
                            visitDate: VisitDate(date: visit?.date, timeZoneIdentifier: visit?.timeZone), note: visit?.note ?? "",
                            media: mediaRefs, publishedAt: row.publishedAt,
                            likeCount: likes.keys.filter { $0.b == row.id && isVisibleMember($0.a, to: viewer) }.count,
                            commentCount: comments.values.filter { $0.activity == row.id && isVisibleMember($0.author, to: viewer) }.count,
                            likedByViewer: likes[Pair(a: viewer, b: row.id)] != nil, isOwn: row.author == viewer)
    }

    func canSeeActivity(_ row: ActivityRow, viewer: UUID) -> Bool {
        (isVisibleMember(row.author, to: viewer) || row.author == viewer) && activityAllowed(row, viewer: viewer)
    }

    static func cursor(date: Date, id: UUID) -> String { "\(date.timeIntervalSince1970)|\(id.uuidString)" }

    static func parseCursor(_ cursor: String?) -> (Date, UUID)? {
        guard let cursor else { return nil }
        let parts = cursor.split(separator: "|")
        guard parts.count == 2, let seconds = Double(parts[0]), let id = UUID(uuidString: String(parts[1])) else { return nil }
        return (Date(timeIntervalSince1970: seconds), id)
    }

    /// `(publishedAt DESC, id DESC)` keyset pagination over activity rows.
    func page(of rows: [ActivityRow], cursor: String?, viewer: UUID) -> Page<ActivityItem> {
        let sorted = rows.sorted { ($0.publishedAt, $0.id.uuidString) > ($1.publishedAt, $1.id.uuidString) }
        var remaining = sorted
        if let (date, id) = Self.parseCursor(cursor) {
            remaining = sorted.filter { ($0.publishedAt, $0.id.uuidString) < (date, id.uuidString) }
        }
        let slice = Array(remaining.prefix(Limits.pageSize))
        let next = remaining.count > Limits.pageSize ? slice.last.map { Self.cursor(date: $0.publishedAt, id: $0.id) } : nil
        return Page(items: slice.compactMap { activityItem($0, viewer: viewer) }, nextCursor: next)
    }

    func notify(recipient: UUID, actor: UUID, type: NotificationType, activity: UUID?, comment: UUID?, eventKey: String, now: Date) {
        guard recipient != actor, !isBlockedEitherWay(recipient, actor) else { return }
        let prefs = settingsByUser[recipient] ?? .defaults
        switch type {
        case .follow where !prefs.notifyFollows, .friendRequest where !prefs.notifyFollows, .friendAccept where !prefs.notifyFollows: return
        case .like where !prefs.notifyLikes: return
        case .comment where !prefs.notifyComments: return
        default: break
        }
        guard !notifications.values.contains(where: { $0.eventKey == eventKey }) else { return }
        let id = UUID()
        notifications[id] = NotificationRow(id: id, recipient: recipient, actor: actor, type: type, activity: activity, comment: comment,
                                            eventKey: eventKey, createdAt: now, readAt: nil)
    }

    func deleteActivityCascade(_ id: UUID) {
        activities[id] = nil
        likes = likes.filter { $0.key.b != id }
        let commentIDs = comments.values.filter { $0.activity == id }.map(\.id)
        commentIDs.forEach { comments[$0] = nil }
        notifications = notifications.filter { $0.value.activity != id }
    }
}

/// Fan-out of session changes to any number of listeners.
final class SessionBroadcaster: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<AuthSession?>.Continuation] = [:]

    func stream() -> AsyncStream<AuthSession?> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.continuations[id] = nil
                self.lock.unlock()
            }
        }
    }

    func send(_ session: AuthSession?) {
        lock.lock()
        let targets = Array(continuations.values)
        lock.unlock()
        targets.forEach { $0.yield(session) }
    }
}
#endif
