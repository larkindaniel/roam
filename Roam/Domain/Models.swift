import CoreLocation
import Foundation

// MARK: - Geography

/// A searched or chosen destination (city/locality). Changing it never counts as a visit.
struct Destination: Codable, Hashable, Identifiable, Sendable {
    var name: String
    var region: String?
    var countryCode: String?
    var countryName: String?
    var latitude: Double
    var longitude: Double
    /// Approximate radius used to build a search region, in metres.
    var radiusMeters: Double

    var id: String { GeographyKey.cityKey(countryCode: countryCode, region: region, locality: name) ?? "\(name)|\(latitude)|\(longitude)" }

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    /// "Portland, Oregon, United States" style disambiguation.
    var subtitle: String {
        [region, countryName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var displayName: String {
        subtitle.isEmpty ? name : "\(name), \(subtitle)"
    }
}

enum PlaceProviderKind: String, Codable, Hashable, Sendable {
    case mapkit
    /// Deterministic fictional places for tests/debug only; never produced in Release builds.
    case fixture
    /// Added by a member because no provider had it.
    case custom
}

/// A place returned by a provider before (or after) it becomes a Roam experience.
struct PlaceCandidate: Codable, Hashable, Identifiable, Sendable {
    var provider: PlaceProviderKind
    var providerPlaceID: String?
    var name: String
    var address: String?
    var locality: String?
    var region: String?
    var countryCode: String?
    var countryName: String?
    var latitude: Double
    var longitude: Double
    var phone: String?
    var website: URL?
    var providerCategory: String?
    var timeZoneIdentifier: String?
    /// True when the candidate is a city/locality (Day Trip destination) rather than a point of interest.
    var isLocality: Bool
    var suggestedCategory: ExperienceCategory?

    var id: String {
        if let providerPlaceID { return "\(provider.rawValue):\(providerPlaceID)" }
        if isLocality {
            let key = PlaceIdentity.localityKey(self) ?? PlaceIdentity.fallbackKey(name: name, address: address, latitude: latitude, longitude: longitude)
            return "\(provider.rawValue):locality:\(key)"
        }
        return "\(provider.rawValue):poi:\(PlaceIdentity.fallbackKey(name: name, address: address, latitude: latitude, longitude: longitude))"
    }

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    var areaLine: String {
        [locality, region, countryName].compactMap { $0 }.filter { !$0.isEmpty }.uniqued().joined(separator: ", ")
    }
}

// MARK: - Members

struct MemberSummary: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var handle: String
    var displayName: String
    var avatarPath: String?
}

enum SetupCheckpoint: String, Codable, Hashable, Sendable, Comparable {
    case profileCreated = "profile_created"
    case optionalDetails = "optional_details"
    case complete

    private var order: Int {
        switch self {
        case .profileCreated: return 0
        case .optionalDetails: return 1
        case .complete: return 2
        }
    }

    static func < (lhs: SetupCheckpoint, rhs: SetupCheckpoint) -> Bool { lhs.order < rhs.order }
}

/// The signed-in member's own profile.
struct OwnProfile: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var handle: String
    var displayName: String
    var bio: String
    var avatarPath: String?
    var homeCity: Destination?
    var setupCheckpoint: SetupCheckpoint
    var hasSeenBeenIntro: Bool
    var createdAt: Date

    var summary: MemberSummary { MemberSummary(id: id, handle: handle, displayName: displayName, avatarPath: avatarPath) }
}

/// Where the viewer stands with another member. Friendship is two-way: a request stays
/// pending until the other member accepts.
enum FriendState: String, Codable, Hashable, Sendable {
    case none
    case sent
    case received
    case friends
}

enum FriendAction: String, Codable, Hashable, Sendable {
    case request
    case accept
    case decline
    case cancel
    case remove
}

extension FriendState {
    /// What tapping the friend button does in this state.
    var primaryAction: FriendAction {
        switch self {
        case .none: return .request
        case .sent: return .cancel
        case .received: return .accept
        case .friends: return .remove
        }
    }

    /// The state to show while `action` is in flight.
    func applying(_ action: FriendAction) -> FriendState {
        switch action {
        case .request: return self == .received ? .friends : (self == .none ? .sent : self)
        case .accept: return self == .received ? .friends : self
        case .decline: return self == .received ? .none : self
        case .cancel: return self == .sent ? .none : self
        case .remove: return self == .friends ? .none : self
        }
    }
}

struct Relationship: Codable, Hashable, Sendable {
    var isSelf: Bool
    var friendState: FriendState
    var isMuted: Bool
    var isBlocked: Bool

    static let selfRelationship = Relationship(isSelf: true, friendState: .none, isMuted: false, isBlocked: false)
    static let none = Relationship(isSelf: false, friendState: .none, isMuted: false, isBlocked: false)
}

/// Public profile header data; every count is a server-derived all-time total.
struct PublicProfile: Codable, Hashable, Identifiable, Sendable {
    var member: MemberSummary
    var bio: String
    var homeCityName: String?
    var joinedAt: Date
    var followerCount: Int
    var followingCount: Int
    var rankedCount: Int
    var wantCount: Int
    var countryCount: Int
    var cityCount: Int
    var relationship: Relationship

    var id: UUID { member.id }
}

// MARK: - Experiences

struct ViewerExperienceState: Codable, Hashable, Sendable {
    var isBookmarked: Bool
    var myRatingCategory: ExperienceCategory?
    var myScore: Score?
    var myRank: Int?
    var hasVisits: Bool

    var isRated: Bool { myScore != nil }

    static let none = ViewerExperienceState(isBookmarked: false, myRatingCategory: nil, myScore: nil, myRank: nil, hasVisits: false)
}

/// Compact experience data used by rows, cards and pins.
struct ExperienceSummary: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var placeID: UUID
    var name: String
    var category: ExperienceCategory?
    var locality: String?
    var region: String?
    var countryCode: String?
    var countryName: String?
    var latitude: Double
    var longitude: Double
    var providerPlaceID: String?
    var followingScore: Score?
    var followingCount: Int
    var viewer: ViewerExperienceState
    /// A linked photo and its required credit, loaded from its source.
    var photoURL: URL? = nil
    var photoCredit: String? = nil

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    var areaLine: String {
        [locality, countryName].compactMap { $0 }.filter { !$0.isEmpty }.uniqued().joined(separator: ", ")
    }
}

// MARK: - Errors

/// User-presentable failure categories shared by every service implementation.
enum RoamError: Error, Equatable, LocalizedError {
    case offline
    case notSignedIn
    case sessionExpired
    case notFound
    case forbidden
    case unavailable
    case validation(String)
    case conflict(String)
    case staleRevision
    case alreadyRated
    case lastVisitConfirmationRequired
    case mediaExpired
    case server(String)
    case timeout
    /// Account deletion needs a sign-in within the last few minutes.
    case reauthenticationRequired

    var errorDescription: String? {
        switch self {
        case .offline: return "You're offline. Your draft is kept; saving needs a connection."
        case .notSignedIn: return "Sign in to continue."
        case .sessionExpired: return "Your session expired. Sign in again to continue; your draft is kept."
        case .notFound: return "This is no longer available."
        case .forbidden: return "You don't have access to this."
        case .unavailable: return "This content isn't available."
        case .validation(let message): return message
        case .conflict(let message): return message
        case .staleRevision: return "Your list changed since you started. Refresh the comparisons to place this experience."
        case .alreadyRated: return "Already been — add a visit instead."
        case .lastVisitConfirmationRequired: return "This is now your last visit. Confirm deleting it and its ranking before continuing."
        case .mediaExpired: return "This upload expired. Your photo is kept; retry uploads it again."
        case .server(let message): return message
        case .timeout: return "This is taking longer than expected. Check your connection and try again."
        case .reauthenticationRequired: return "For your security, confirm it's you again before deleting your account."
        }
    }

    var isRetryable: Bool {
        switch self {
        case .offline, .timeout, .server: return true
        default: return false
        }
    }
}

extension Error {
    var roamMessage: String {
        if let roam = self as? RoamError { return roam.errorDescription ?? "Something went wrong." }
        if let local = self as? LocalizedError, let description = local.errorDescription { return description }
        return "Something went wrong. Try again."
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
