import Foundation

enum VisitDatePrecision: String, Codable, Hashable, Sendable {
    case day
    case unknown
}

/// Optional visit date stored as a calendar day plus the time zone that defined "today".
struct VisitDate: Codable, Hashable, Sendable {
    var date: LocalDate?
    var timeZoneIdentifier: String?

    var precision: VisitDatePrecision { date == nil ? .unknown : .day }

    static let unknown = VisitDate(date: nil, timeZoneIdentifier: nil)

    /// Today in the destination time zone when known, else the device zone.
    static func today(destinationTimeZone: String?, now: Date = Date()) -> VisitDate {
        let zone = destinationTimeZone.flatMap(TimeZone.init(identifier:)) ?? .current
        return VisitDate(date: LocalDate.today(in: zone, now: now), timeZoneIdentifier: zone.identifier)
    }

    var displayString: String { date?.displayString ?? "Date unknown" }
}

struct MediaRef: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var path: String
    var width: Int
    var height: Int
    var position: Int
}

struct Visit: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var experienceID: UUID
    var ownerID: UUID
    var visitDate: VisitDate
    var publicNote: String
    var media: [MediaRef]
    var createdAt: Date
    var updatedAt: Date
    var audience: Audience = .friends
    var tripID: UUID? = nil
    var companions: [MemberSummary]? = nil

    /// Newest by visit date, unknown dates last, stable ID tie-break.
    static func historyOrder(_ lhs: Visit, _ rhs: Visit) -> Bool {
        switch (lhs.visitDate.date, rhs.visitDate.date) {
        case let (l?, r?) where l != r: return l > r
        case (nil, _?): return false
        case (_?, nil): return true
        default:
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

/// Public Visit content survives removal of its ranking-linked activity.
struct PublicMemory: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var author: MemberSummary
    var experienceID: UUID
    var visitDate: VisitDate
    var publicNote: String
    var media: [MediaRef]
    var createdAt: Date
    var updatedAt: Date
    var isOwn: Bool
    /// A friend's current score for this place, when they ranked it.
    var score: Score? = nil
    var companions: [MemberSummary]? = nil
}

struct PrivateNote: Codable, Hashable, Sendable {
    var experienceID: UUID
    var text: String
    var updatedAt: Date
}

struct MyRating: Codable, Hashable, Sendable {
    let ratingID: UUID
    var category: ExperienceCategory
    var sentiment: Sentiment
    var score: Score
    var rank: Int
    var groupSize: Int
    var categoryCount: Int
    var firstRatedAt: Date
}

enum ProviderStatus: String, Codable, Hashable, Sendable {
    case active
    case unavailable
}

/// Everything the experience detail screen (S06) shows.
struct ExperienceDetail: Codable, Hashable, Sendable {
    var summary: ExperienceSummary
    var address: String?
    var phone: String?
    var website: URL?
    var timeZoneIdentifier: String?
    var provider: PlaceProviderKind
    var providerStatus: ProviderStatus
    var isLocality: Bool
    var categoryLocked: Bool
    var myRating: MyRating?
    var myVisits: [Visit]
    var hasPrivateNote: Bool
    var publicLogs: [ActivityItem]
}

/// A row in Been / Wishlist / Shared Wishlist.
struct ListEntry: Codable, Hashable, Identifiable, Sendable {
    var experience: ExperienceSummary
    /// Owner's category score and rank (owner may be another member on public lists).
    var ownerCategory: ExperienceCategory?
    var ownerSentiment: Sentiment?
    var ownerScore: Score?
    var ownerRank: Int?
    var ownerFirstRatedAt: Date?
    var isRanked: Bool
    var latestVisitDate: LocalDate?
    var latestVisitAt: Date?
    var savedAt: Date?
    var viewerSavedAt: Date?
    var cityKey: String?
    var cityName: String?

    var id: UUID { experience.id }
}

// MARK: - Social

enum ActivityType: String, Codable, Hashable, Sendable {
    case rating
    case revisit
    case rerank

    var verb: String {
        switch self {
        case .rating: return "visited"
        case .revisit: return "went back to"
        case .rerank: return "updated their rating for"
        }
    }
}

struct ActivityTrip: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let name: String
}

struct ActivityItem: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var type: ActivityType
    var author: MemberSummary
    var experience: ExperienceSummary
    var category: ExperienceCategory
    var scoreSnapshot: Score?
    var rankSnapshot: Int?
    var sentimentSnapshot: Sentiment?
    var visitID: UUID?
    var visitDate: VisitDate
    var note: String
    var media: [MediaRef]
    var publishedAt: Date
    var likeCount: Int
    var commentCount: Int
    var likedByViewer: Bool
    var isOwn: Bool
    var trip: ActivityTrip? = nil
    var companions: [MemberSummary]? = nil
    /// Friends who logged the same place together with the author (they tagged each other with "With"), so their logs
    /// show as this one card. Set on the Friends tab, never by the server.
    var together: [MemberSummary] = []

    private enum CodingKeys: String, CodingKey {
        case id, type, author, experience, category, scoreSnapshot, rankSnapshot, sentimentSnapshot, visitID, visitDate, note,
             media, publishedAt, likeCount, commentCount, likedByViewer, isOwn, trip, companions
    }

    /// Everyone on the card: the author, then whoever went with them.
    var authors: [MemberSummary] { [author] + together }
}

extension Array where Element == ActivityItem {
    /// Logs of the same place by friends who went together (one tagged the other with "With") become one card: the newest
    /// log, with everyone's names and all their photos. Likes and comments stay on that newest log.
    func mergingTogether() -> [ActivityItem] {
        var groupOf = [Int](indices)
        func root(_ i: Int) -> Int { var i = i; while groupOf[i] != i { i = groupOf[i] }; return i }
        for i in indices {
            for j in indices where j > i && self[i].experience.id == self[j].experience.id && self[i].author.id != self[j].author.id {
                let a = self[i], b = self[j]
                let tagged = (a.companions ?? []).contains { $0.id == b.author.id } || (b.companions ?? []).contains { $0.id == a.author.id }
                if tagged { groupOf[root(j)] = root(i) }
            }
        }
        var merged: [Int: ActivityItem] = [:]
        var order: [Int] = []
        for i in indices {
            let r = root(i)
            guard var card = merged[r] else { merged[r] = self[i]; order.append(r); continue }
            let other = self[i]
            if !card.authors.contains(where: { $0.id == other.author.id }) { card.together.append(other.author) }
            let offset = (card.media.map(\.position).max() ?? -1) + 1
            card.media += other.media.sorted { $0.position < $1.position }.enumerated().map { index, ref in
                var ref = ref; ref.position = offset + index; return ref
            }
            merged[r] = card
        }
        return order.compactMap { merged[$0] }
    }
}

struct Comment: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var visitID: UUID
    var author: MemberSummary
    var body: String
    var createdAt: Date
    var isOwn: Bool
}

struct MemberRow: Codable, Hashable, Identifiable, Sendable {
    var member: MemberSummary
    var friendState: FriendState
    var isSelf: Bool

    var id: UUID { member.id }
}

struct Page<Item: Hashable & Sendable>: Hashable, Sendable {
    var items: [Item]
    var nextCursor: String?

    static var empty: Page { Page(items: [], nextCursor: nil) }
}

enum NotificationType: String, Codable, Hashable, Sendable {
    case follow
    case friendRequest = "friend_request"
    case friendAccept = "friend_accept"
    case like
    case comment
}

struct AppNotification: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var type: NotificationType
    var actor: MemberSummary
    var visitID: UUID?
    var experienceName: String?
    var commentPreview: String?
    var createdAt: Date
    var readAt: Date?
    var targetAvailable: Bool

    var isUnread: Bool { readAt == nil }
}

enum ReportReason: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case incorrectPlaceOrCategory = "incorrect_place_category"
    case spam
    case inappropriate
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .incorrectPlaceOrCategory: return "Incorrect place or category"
        case .spam: return "Spam"
        case .inappropriate: return "Inappropriate content"
        case .other: return "Other"
        }
    }
}

enum ReportTarget: Hashable, Sendable {
    case experience(UUID)
    case comment(UUID)
    case media(UUID)
    case member(UUID)
    /// A log: its note and photos.
    case visit(UUID)

    var kind: String {
        switch self {
        case .experience: return "experience"
        case .comment: return "comment"
        case .media: return "media"
        case .member: return "member"
        case .visit: return "visit"
        }
    }

    var targetID: UUID {
        switch self {
        case .experience(let id), .comment(let id), .media(let id), .member(let id), .visit(let id): return id
        }
    }
}

struct ReportReceipt: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var targetKind: String
    var reason: ReportReason
    var status: String
    var createdAt: Date
}

// MARK: - Settings and travel

enum DistanceUnit: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case kilometres = "km"
    case miles = "mi"

    var id: String { rawValue }
    var title: String { self == .kilometres ? "Kilometres" : "Miles" }
}

struct UserSettings: Codable, Hashable, Sendable {
    var distanceUnit: DistanceUnit
    var hapticsEnabled: Bool
    var notifyFollows: Bool
    var notifyLikes: Bool
    var notifyComments: Bool

    static let defaults = UserSettings(distanceUnit: .kilometres, hapticsEnabled: true, notifyFollows: true, notifyLikes: true, notifyComments: true)
}

struct GlobePin: Codable, Hashable, Identifiable, Sendable {
    let experienceID: UUID
    var name: String
    var category: ExperienceCategory?
    var latitude: Double
    var longitude: Double
    var countryCode: String?
    var cityKey: String?
    var countryName: String? = nil
    var cityName: String? = nil
    /// Earliest known visit date; nil when every visit has an unknown date.
    var firstVisitDate: LocalDate? = nil
    var visitCount: Int = 1

    var id: UUID { experienceID }

    /// "Portland, United States", "Greenland" or "" for list rows.
    var areaLine: String {
        [cityName, countryName ?? countryCode].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// A Travel Profile selection: it narrows the owner's visited experiences, never the all-time totals.
enum TravelFilter: Hashable, Sendable {
    case category(ExperienceCategory?)
    case city(key: String, name: String)
    case country(code: String, name: String)

    var title: String {
        switch self {
        case .category(let category): return category?.title ?? "Uncategorized"
        case .city(_, let name): return name
        case .country(_, let name): return name
        }
    }

    func matches(_ pin: GlobePin) -> Bool {
        switch self {
        case .category(let category): return pin.category == category
        case .city(let key, _): return pin.cityKey == key
        case .country(let code, _): return pin.countryCode == code
        }
    }
}

struct CategoryCount: Codable, Hashable, Identifiable, Sendable {
    var category: ExperienceCategory?
    var count: Int
    var id: String { category?.rawValue ?? "uncategorized" }
}

struct CityCount: Codable, Hashable, Identifiable, Sendable {
    var cityKey: String
    var name: String
    var region: String?
    var countryCode: String
    var countryName: String?
    var count: Int
    var id: String { cityKey }
}

struct CountryCount: Codable, Hashable, Identifiable, Sendable {
    var countryCode: String
    var name: String
    var count: Int
    var id: String { countryCode }
}

struct NewThisYear: Codable, Hashable, Sendable {
    var year: Int
    var count: Int
    var unknownDateCount: Int
    var experienceIDs: [UUID]
}

/// Visited geography derived from persisted Visits only.
struct TravelProfile: Codable, Hashable, Sendable {
    var pins: [GlobePin]
    var countryCount: Int
    var cityCount: Int
    var categories: [CategoryCount]
    var cities: [CityCount]
    var countries: [CountryCount]
    var placesWithoutCity: Int
    var newThisYear: NewThisYear

    static func empty(year: Int) -> TravelProfile {
        TravelProfile(pins: [], countryCount: 0, cityCount: 0, categories: [], cities: [], countries: [], placesWithoutCity: 0,
                      newThisYear: NewThisYear(year: year, count: 0, unknownDateCount: 0, experienceIDs: []))
    }
}

enum AccountDeletionState: String, Codable, Hashable, Sendable {
    case pending
    case processing
    case completed
    case failed
}

struct AccountDeletionStatus: Codable, Hashable, Sendable {
    var state: AccountDeletionState
    var appleRevocation: String
    var storageCleanup: String
    var updatedAt: Date
}
