import CoreLocation
import Foundation
import MapKit

// Feature service boundaries (SPEC "Service protocols isolate Auth, places, ranking, memory/media,
// lists, people/feed, notifications and geography from SwiftUI"). Two implementations exist:
// SupabaseBackend (real local/hosted backend) and FixtureBackend (Debug/test builds only).

// MARK: Auth

enum AuthProviderKind: String, Codable, Hashable, Sendable {
    case email
    case apple
}

struct AuthSession: Hashable, Sendable {
    let userID: UUID
    var email: String?
    var providers: [AuthProviderKind]
}

enum SignUpOutcome: Hashable, Sendable {
    case confirmationRequired(email: String)
    case signedIn(AuthSession)
}

enum AuthCallbackResult: Hashable, Sendable {
    case signedIn(AuthSession)
    case passwordRecovery(AuthSession)
}

protocol AuthService: AnyObject, Sendable {
    func restoreSession() async throws -> AuthSession?
    func sessionChanges() -> AsyncStream<AuthSession?>
    func signUp(email: String, password: String) async throws -> SignUpOutcome
    func verifySignUp(email: String, code: String) async throws -> AuthSession
    func resendConfirmation(email: String) async throws
    func signIn(email: String, password: String) async throws -> AuthSession
    func signInWithApple(idToken: String, rawNonce: String) async throws -> AuthSession
    func requestPasswordReset(email: String) async throws
    func verifyRecovery(email: String, code: String) async throws -> AuthSession
    func handleCallback(_ url: URL) async throws -> AuthCallbackResult
    func updatePassword(_ newPassword: String) async throws
    func reauthenticate(password: String) async throws
    func signOut() async
}

// MARK: Profiles

enum HandleAvailability: Hashable, Sendable {
    case available
    case taken
    case invalid(ValidationIssue)
}

struct ProfileUpdate: Hashable, Sendable {
    var displayName: String
    var handle: String
    var bio: String
    var homeCity: Destination?
    var avatarPath: String?
}

protocol ProfileService: AnyObject, Sendable {
    func ownProfile() async throws -> OwnProfile?
    func checkHandle(_ handle: String) async throws -> HandleAvailability
    func createProfile(displayName: String, handle: String) async throws -> OwnProfile
    func updateProfile(_ update: ProfileUpdate) async throws -> OwnProfile
    func setSetupCheckpoint(_ checkpoint: SetupCheckpoint) async throws -> OwnProfile
    func markBeenIntroSeen() async throws
    func publicProfile(userID: UUID) async throws -> PublicProfile
    func suggestedMembers(limit: Int) async throws -> [MemberRow]
}

// MARK: Places and experiences

struct GeoBounds: Hashable, Sendable, Codable {
    var minLatitude: Double
    var maxLatitude: Double
    var minLongitude: Double
    var maxLongitude: Double

    init(region: MKCoordinateRegion) {
        minLatitude = max(-90, region.center.latitude - region.span.latitudeDelta / 2)
        maxLatitude = min(90, region.center.latitude + region.span.latitudeDelta / 2)
        minLongitude = region.center.longitude - region.span.longitudeDelta / 2
        maxLongitude = region.center.longitude + region.span.longitudeDelta / 2
    }

    init(minLatitude: Double, maxLatitude: Double, minLongitude: Double, maxLongitude: Double) {
        self.minLatitude = minLatitude
        self.maxLatitude = maxLatitude
        self.minLongitude = minLongitude
        self.maxLongitude = maxLongitude
    }

    func contains(latitude: Double, longitude: Double) -> Bool {
        guard latitude >= minLatitude && latitude <= maxLatitude else { return false }
        var lon = longitude
        if maxLongitude > 180 && lon < minLongitude { lon += 360 }
        if minLongitude < -180 && lon > maxLongitude { lon -= 360 }
        return lon >= minLongitude && lon <= maxLongitude
    }
}

protocol PlaceSearchProviding: AnyObject, Sendable {
    func searchPlaces(query: String, around destination: Destination?) async throws -> [PlaceCandidate]
    func searchDestinations(query: String) async throws -> [Destination]
    func pointsOfInterest(in region: MKCoordinateRegion, category: ExperienceCategory?) async throws -> [PlaceCandidate]
    func destination(for coordinate: CLLocationCoordinate2D) async throws -> Destination?
    /// States and provinces named like the search (Ontario, Kerala), framed to their whole area.
    func searchRegions(query: String) async throws -> [Destination]
}

extension PlaceSearchProviding {
    func searchRegions(query: String) async throws -> [Destination] { [] }
}

protocol ExperienceService: AnyObject, Sendable {
    /// Resolves/upserts a provider place into its one Place + Experience (first save/log only).
    func resolve(_ candidate: PlaceCandidate) async throws -> ExperienceSummary
    /// Existing Roam experiences for provider candidates, keyed by `PlaceCandidate.id`.
    func matches(for candidates: [PlaceCandidate]) async throws -> [String: ExperienceSummary]
    func detail(experienceID: UUID) async throws -> ExperienceDetail
    func experiences(in bounds: GeoBounds, category: ExperienceCategory?) async throws -> [ExperienceSummary]
}

// MARK: Lists

struct UserLibrary: Hashable, Sendable {
    var bookmarked: Set<UUID>
    var rated: [UUID: ExperienceCategory]
    var visited: Set<UUID>

    static let empty = UserLibrary(bookmarked: [], rated: [:], visited: [])
}

protocol ListService: AnyObject, Sendable {
    func library() async throws -> UserLibrary
    /// Desired-state bookmark write; safe to retry. Returns the persisted state.
    func setBookmark(experienceID: UUID, saved: Bool) async throws -> Bool
    func been(ownerID: UUID) async throws -> [ListEntry]
    func want(ownerID: UUID) async throws -> [ListEntry]
    func sharedWants(with otherUserID: UUID) async throws -> [ListEntry]
}

// MARK: Ranking

enum RatingIntent: String, Codable, Hashable, Sendable {
    case firstLog = "first_log"
    case rerank
}

struct VisitPayload: Codable, Hashable, Sendable {
    var date: LocalDate?
    var timeZoneIdentifier: String?
    var publicNote: String
    var mediaIDs: [UUID]
    /// Nil keeps a visit's current audience; a new visit then defaults to friends on the server.
    var audience: Audience? = nil
    var tripID: UUID? = nil
}

struct RatingCommitRequest: Codable, Hashable, Sendable {
    let operationID: UUID
    let intent: RatingIntent
    let experienceID: UUID
    let category: ExperienceCategory
    let sentiment: Sentiment
    let baseRevision: Int
    let answers: [ComparisonAnswer]
    let visit: VisitPayload?
}

struct RatingCommitResult: Codable, Hashable, Sendable {
    let ratingID: UUID
    let visitID: UUID?
    let activityID: UUID
    let category: ExperienceCategory
    let sentiment: Sentiment
    let score: Score
    let rank: Int
    let groupSize: Int
    let categoryCount: Int
    let revision: Int
}

struct AddVisitRequest: Codable, Hashable, Sendable {
    let operationID: UUID
    let experienceID: UUID
    let visit: VisitPayload
    /// Required only when the member logs a place they haven't ranked.
    var category: ExperienceCategory? = nil
}

struct AddVisitResult: Codable, Hashable, Sendable {
    let visitID: UUID
    let activityID: UUID
}

struct DeleteVisitResult: Codable, Hashable, Sendable {
    let removedRating: Bool
}

protocol RankingService: AnyObject, Sendable {
    func categoryRanking(_ category: ExperienceCategory) async throws -> CategoryRanking
    func commitRating(_ request: RatingCommitRequest) async throws -> RatingCommitResult
    func addVisit(_ request: AddVisitRequest) async throws -> AddVisitResult
    func removeRating(experienceID: UUID, operationID: UUID) async throws
    func deleteVisit(visitID: UUID, operationID: UUID, allowRatingRemoval: Bool) async throws -> DeleteVisitResult
}

extension RankingService {
    func deleteVisit(visitID: UUID, operationID: UUID) async throws -> DeleteVisitResult {
        try await deleteVisit(visitID: visitID, operationID: operationID, allowRatingRemoval: false)
    }
}

// MARK: Memories and media

enum MediaPurpose: String, Codable, Hashable, Sendable {
    case visit
    case avatar
}

struct StagedMedia: Codable, Hashable, Sendable {
    let id: UUID
    let path: String
    let width: Int
    let height: Int
    var expiresAt: Date? = nil
}

protocol MemoryService: AnyObject, Sendable {
    func visit(visitID: UUID) async throws -> Visit
    func publicMemories(experienceID: UUID, cursor: String?) async throws -> Page<PublicMemory>
    func updateVisit(visitID: UUID, note: String, date: VisitDate, mediaIDs: [UUID], operationID: UUID) async throws -> Visit
    func privateNote(experienceID: UUID) async throws -> PrivateNote?
    func savePrivateNote(experienceID: UUID, text: String, operationID: UUID) async throws -> PrivateNote
    func deletePrivateNote(experienceID: UUID, operationID: UUID) async throws
}

extension MemoryService {
    func updateVisit(visitID: UUID, note: String, date: VisitDate, mediaIDs: [UUID]) async throws -> Visit {
        try await updateVisit(visitID: visitID, note: note, date: date, mediaIDs: mediaIDs, operationID: UUID())
    }
    func savePrivateNote(experienceID: UUID, text: String) async throws -> PrivateNote {
        try await savePrivateNote(experienceID: experienceID, text: text, operationID: UUID())
    }
    func deletePrivateNote(experienceID: UUID) async throws {
        try await deletePrivateNote(experienceID: experienceID, operationID: UUID())
    }
}

protocol MediaService: AnyObject, Sendable {
    func stage(jpegData: Data, width: Int, height: Int, purpose: MediaPurpose, uploadAttemptID: UUID) async throws -> StagedMedia
    func discardStaged(mediaID: UUID) async throws
    func imageData(path: String) async throws -> Data
}

extension MediaService {
    func stage(jpegData: Data, width: Int, height: Int, purpose: MediaPurpose) async throws -> StagedMedia {
        try await stage(jpegData: jpegData, width: width, height: height, purpose: purpose, uploadAttemptID: UUID())
    }
}

// MARK: People, feed and notifications

protocol SocialService: AnyObject, Sendable {
    /// Desired-state friend change; safe to retry. Returns the resulting state.
    func friendAction(userID: UUID, action: FriendAction) async throws -> FriendState
    func incomingFriendRequests(cursor: String?) async throws -> Page<MemberRow>
    func followers(of userID: UUID, query: String, cursor: String?) async throws -> Page<MemberRow>
    func following(of userID: UUID, query: String, cursor: String?) async throws -> Page<MemberRow>
    func searchMembers(query: String, cursor: String?) async throws -> Page<MemberRow>
    func setMute(userID: UUID, muted: Bool) async throws
    func setBlock(userID: UUID, blocked: Bool) async throws
    func blockedMembers() async throws -> [MemberSummary]
    func mutedMembers() async throws -> [MemberSummary]
    func report(target: ReportTarget, reason: ReportReason, text: String?, operationID: UUID) async throws -> ReportReceipt
    func myReports() async throws -> [ReportReceipt]
}

protocol FeedService: AnyObject, Sendable {
    func feed(cursor: String?) async throws -> Page<ActivityItem>
    func profileActivity(userID: UUID, cursor: String?) async throws -> Page<ActivityItem>
    func activity(id: UUID) async throws -> ActivityItem
    func setLike(activityID: UUID, liked: Bool) async throws -> Bool
    func comments(activityID: UUID, cursor: String?) async throws -> Page<Comment>
    func postComment(activityID: UUID, body: String, operationID: UUID) async throws -> Comment
    func deleteComment(id: UUID) async throws
    func deleteActivity(id: UUID) async throws
}

protocol NotificationService: AnyObject, Sendable {
    func notifications(cursor: String?) async throws -> Page<AppNotification>
    func unreadCount() async throws -> Int
    func markRead(id: UUID) async throws
    func markAllRead() async throws
}

// MARK: Trips, lists, direct shares and taste

protocol PlanService: AnyObject, Sendable {
    func myTrips() async throws -> [TripSummary]
    func trip(id: UUID) async throws -> TripDetail
    func saveTrip(_ draft: TripDraft) async throws -> TripSummary
    func deleteTrip(id: UUID) async throws
    func setTripPlace(tripID: UUID, experienceID: UUID, stop: String, present: Bool) async throws
    func setTripCity(tripID: UUID, city: Destination, present: Bool) async throws
    /// Adds a whole country to a trip (or takes it off), before any of its cities are picked.
    func setTripCountry(tripID: UUID, code: String, name: String, present: Bool) async throws
    func homeCities() async throws -> [Destination]
    func setHomeCity(_ city: Destination, present: Bool) async throws -> [Destination]
    func setCityVisited(_ city: Destination, present: Bool) async throws
    /// Marks a city as been, with when you were there (either date optional).
    func markCityVisited(_ city: Destination, start: LocalDate?, end: LocalDate?) async throws
    /// Logs a city like a place: been, with when, how it was and a note (all optional).
    func logCity(_ city: Destination, start: LocalDate?, end: LocalDate?, sentiment: Sentiment?, note: String, mediaIDs: [UUID]) async throws
    /// Cities on your wishlist, saved as a whole.
    func savedCities() async throws -> [Destination]
    func setCitySaved(_ city: Destination, present: Bool) async throws -> [Destination]
    /// Countries on your wishlist, as ISO codes.
    func savedCountries() async throws -> [String]
    func setCountrySaved(code: String, name: String, present: Bool) async throws -> [String]
    func passport(ownerID: UUID) async throws -> [PassportCountry]
    /// Looks places up on Google for a photo and star rating, at most about once a week each. True when any changed.
    func refreshGoogleDetails(experienceIDs: [UUID]) async -> Bool
    /// A country's photo from its own Google entry, with its credit; nil when there isn't one.
    func countryPhoto(code: String, region: String?, name: String) async -> (url: URL, credit: String?)?
    /// A town or city's photo from its own Google entry; `fullName` is "Waterloo, Ontario, Canada".
    func cityPhoto(fullName: String) async -> (url: URL, credit: String?)?
    /// States and provinces on your wishlist, each as "CA|ON".
    func savedRegions() async throws -> [String]
    /// Your own photos (storage paths, newest first) for a place, or rolled up for a city, state or country.
    func myPhotos(experienceID: UUID?, country: String?, region: String?, regionName: String?, city: String?) async -> [String]
    func savedRegionList() async throws -> [SavedRegion]
    /// `area` is the state itself (its middle and size), kept so it can open from a list.
    func setRegionSaved(country: String, region: String, name: String, area: Destination?, present: Bool) async throws -> [String]
    func myLists() async throws -> [PlaceList]
    func list(id: UUID) async throws -> PlaceListDetail
    func saveList(id: UUID?, title: String, description: String) async throws -> PlaceList
    func deleteList(id: UUID) async throws
    func setListItem(listID: UUID, experienceID: UUID, note: String, present: Bool) async throws
    func share(_ target: ShareTarget, with recipient: UUID, message: String, operationID: UUID) async throws
    func sharedWithMe() async throws -> [DirectShare]
    func searchRoamPlaces(query: String) async throws -> [ExperienceSummary]
    func addCustomPlace(name: String, coordinate: CLLocationCoordinate2D, category: ExperienceCategory, area: Destination?) async throws -> ExperienceSummary
    func setVisitAudience(visitID: UUID, audience: Audience) async throws
    /// Which of your trips a visit was part of; nil for none.
    func setVisitTrip(visitID: UUID, tripID: UUID?) async throws
    func tripFeed() async throws -> [TripFeedCard]
    func friendsFeed() async throws -> [FriendFeedVisit]
    func tripUpdates(ownerID: UUID, tripID: UUID?) async throws -> [TripFeedEntry]
    func discoverPlaces(in bounds: GeoBounds?) async throws -> [DiscoverPlace]
    func friendMemories(experienceID: UUID) async throws -> [PublicMemory]
    func taste() async throws -> TasteProfile
    func saveTaste(_ taste: TasteProfile) async throws -> TasteProfile
}

// MARK: Settings, travel and account

protocol SettingsService: AnyObject, Sendable {
    func settings() async throws -> UserSettings
    func update(_ settings: UserSettings) async throws -> UserSettings
}

protocol TravelService: AnyObject, Sendable {
    func travelProfile(userID: UUID, year: Int) async throws -> TravelProfile
}

protocol AccountService: AnyObject, Sendable {
    func requestDeletion() async throws -> AccountDeletionStatus
    func requestDeletion(appleAuthorizationCode: String) async throws -> AccountDeletionStatus
    func deletionStatus() async throws -> AccountDeletionStatus?
}

extension AccountService {
    func requestDeletion(appleAuthorizationCode: String) async throws -> AccountDeletionStatus {
        try await requestDeletion()
    }
}
