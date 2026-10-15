import Foundation
import Observation

/// Owns the signed-in state, profile setup checkpoint and account-scoped cleanup.
@MainActor
@Observable
final class SessionStore {
    enum Phase: Equatable {
        case launching
        case signedOut
        case needsProfile(AuthSession)
        case ready
        case restoreFailed(String)
        case notConfigured
    }

    private(set) var phase: Phase = .launching
    private(set) var session: AuthSession?
    private(set) var profile: OwnProfile?
    /// Set after a recovery code/link; the UI asks for a new password before continuing.
    var isRecoveringPassword = false
    /// True only for the session in which setup was completed (lands in Your Lists).
    private(set) var justCompletedSetup = false
    /// Non-sensitive route intent kept across an expired session.
    var pendingRouteAfterReauth: AppRoute?
    private(set) var sessionExpired = false
    /// Error from an auth callback link (expired/invalid), shown on the welcome screen.
    var callbackError: String?
    /// Name Apple supplies on first authorization only; pre-fills profile setup.
    var pendingAppleName: String?

    let services: AppServices
    private let auth: any AuthService
    private let loadProfile: () async throws -> OwnProfile?
    private var listenTask: Task<Void, Never>?
    private var generation = 0

    init(services: AppServices, authOverride: (any AuthService)? = nil,
         profileLoader: (() async throws -> OwnProfile?)? = nil) {
        self.services = services
        auth = authOverride ?? services.auth
        loadProfile = profileLoader ?? { try await services.profiles.ownProfile() }
    }

    var userID: UUID? { session?.userID }

    /// Bounded session restore: falls back to retry/sign-in instead of spinning forever.
    func bootstrap() async {
        guard services.isConfigured else {
            phase = .notConfigured
            return
        }
        generation += 1
        let token = generation
        phase = .launching
        startListening()
        do {
            let auth = auth
            let restored = try await withTimeout(seconds: 12) { try await auth.restoreSession() }
            guard token == generation else { return }
            if let restored {
                await didAuthenticate(restored)
            } else {
                phase = .signedOut
            }
        } catch {
            guard token == generation else { return }
            phase = .restoreFailed(error.roamMessage)
        }
    }

    private func startListening() {
        guard listenTask == nil else { return }
        listenTask = Task { [weak self] in
            guard let stream = self?.auth.sessionChanges() else { return }
            for await change in stream {
                guard let self else { return }
                if change == nil, self.session != nil, self.phase != .signedOut {
                    await self.handleSignedOutExternally()
                } else if let change, let current = self.userID, current != change.userID {
                    let token = self.generation
                    let restored = try? await self.auth.restoreSession()
                    guard token == self.generation else { continue }
                    if restored?.userID == change.userID { await self.didAuthenticate(change) }
                }
            }
        }
    }

    func didAuthenticate(_ session: AuthSession) async {
        generation += 1
        let token = generation
        if self.session?.userID != session.userID { services.images.clear() }
        if let expiredUserID, expiredUserID != session.userID {
            // A different member signed in after expiry: the old route intent is not theirs.
            pendingRouteAfterReauth = nil
        }
        expiredUserID = nil
        deletionNotice = nil
        self.session = session
        self.profile = nil
        sessionExpired = false
        phase = .launching
        do {
            let profile = try await loadProfile()
            guard token == generation, self.userID == session.userID else { return }
            guard profile == nil || profile?.id == session.userID else {
                markSessionExpired()
                return
            }
            if let profile, profile.setupCheckpoint == .complete {
                self.profile = profile
                phase = .ready
            } else if let profile {
                self.profile = profile
                phase = .needsProfile(session)
            } else {
                self.profile = nil
                phase = .needsProfile(session)
            }
        } catch {
            guard token == generation, self.userID == session.userID else { return }
            if error as? RoamError == .sessionExpired || error as? RoamError == .notSignedIn {
                markSessionExpired()
                return
            }
            phase = .restoreFailed(error.roamMessage)
        }
    }

    func profileUpdated(_ profile: OwnProfile) {
        guard profile.id == userID else { return }
        self.profile = profile
    }

    /// Routes an error from any feature: an expired session keeps drafts and asks for sign-in.
    @discardableResult
    func handle(_ error: Error, routeIntent: AppRoute? = nil) -> String {
        if error as? RoamError == .sessionExpired || error as? RoamError == .notSignedIn {
            markSessionExpired(routeIntent: routeIntent)
        }
        return error.roamMessage
    }

    func markBeenIntroSeen() async {
        guard var current = profile, !current.hasSeenBeenIntro else { return }
        current.hasSeenBeenIntro = true
        profile = current
        try? await services.profiles.markBeenIntroSeen()
    }

    func completeSetup(_ profile: OwnProfile) {
        guard profile.id == userID else { return }
        self.profile = profile
        justCompletedSetup = true
        phase = .ready
    }

    func consumeJustCompletedSetup() -> Bool {
        defer { justCompletedSetup = false }
        return justCompletedSetup
    }

    /// Marks the session expired: drafts stay on disk (scoped to that account), nothing submits,
    /// and the member signs in again. Another account never sees them.
    func markSessionExpired(routeIntent: AppRoute? = nil) {
        guard let expiredUser = userID else { return }
        generation += 1
        let token = generation
        pendingRouteAfterReauth = routeIntent
        enterExpiredState(owner: expiredUser)
        Task {
            guard token == self.generation else { return }
            await self.auth.signOut()
            // An older sign-out completion never clears a newly authenticated account.
            guard token == self.generation else { return }
        }
    }

    /// The account whose session expired (drafts are kept for it).
    private(set) var expiredUserID: UUID?

    func signOut() async {
        generation += 1
        let token = generation
        let userID = session?.userID ?? expiredUserID
        clearLocalState(for: userID)
        phase = .signedOut
        await auth.signOut()
        guard token == generation else { return }
    }

    /// Shown on the welcome screen after a deletion request; it says what is still pending.
    var deletionNotice: String?

    /// The server already revoked every session; this drops the local copy and every cache.
    func accountDeleted(notice: String) async {
        generation += 1
        let token = generation
        let userID = session?.userID
        clearLocalState(for: userID)
        deletionNotice = notice
        phase = .signedOut
        await auth.signOut()
        guard token == generation else { return }
    }

    private func handleSignedOutExternally() async {
        let token = generation
        guard let owner = userID else { return }
        // A queued nil from an older sign-out can arrive after a newer login. Check the
        // auth service's current snapshot before expiring that newly authenticated account.
        let restored = try? await auth.restoreSession()
        guard token == generation, userID == owner else { return }
        if let restored {
            if restored.userID != owner { await didAuthenticate(restored) }
            return
        }
        generation += 1
        enterExpiredState(owner: owner)
    }

    private func enterExpiredState(owner: UUID) {
        services.images.clear()
        expiredUserID = owner
        session = nil
        profile = nil
        pendingAppleName = nil
        isRecoveringPassword = false
        justCompletedSetup = false
        sessionExpired = true
        phase = .signedOut
    }

    private func clearLocalState(for userID: UUID?) {
        if let userID { services.storage.clearAccount(userID) }
        pendingAppleName = nil
        services.images.clear()
        session = nil
        profile = nil
        isRecoveringPassword = false
        justCompletedSetup = false
        sessionExpired = false
        expiredUserID = nil
        pendingRouteAfterReauth = nil
    }
}

enum TimeoutError: Error {
    case timedOut
}

func withTimeout<T: Sendable>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw RoamError.timeout
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
