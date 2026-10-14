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
    private var listenTask: Task<Void, Never>?

    init(services: AppServices) {
        self.services = services
    }

    var userID: UUID? { session?.userID }

    /// Bounded session restore: falls back to retry/sign-in instead of spinning forever.
    func bootstrap() async {
        guard services.isConfigured else {
            phase = .notConfigured
            return
        }
        phase = .launching
        startListening()
        do {
            let restored = try await withTimeout(seconds: 12) { try await self.services.auth.restoreSession() }
            if let restored {
                await didAuthenticate(restored)
            } else {
                phase = .signedOut
            }
        } catch {
            phase = .restoreFailed(error.roamMessage)
        }
    }

    private func startListening() {
        guard listenTask == nil else { return }
        listenTask = Task { [weak self] in
            guard let stream = self?.services.auth.sessionChanges() else { return }
            for await change in stream {
                guard let self else { return }
                if change == nil, self.session != nil, self.phase != .signedOut {
                    await self.handleSignedOutExternally()
                }
            }
        }
    }

    func didAuthenticate(_ session: AuthSession) async {
        if let expiredUserID, expiredUserID != session.userID {
            // A different member signed in after expiry: the old route intent is not theirs.
            pendingRouteAfterReauth = nil
        }
        expiredUserID = nil
        self.session = session
        sessionExpired = false
        do {
            let profile = try await services.profiles.ownProfile()
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
            phase = .restoreFailed(error.roamMessage)
        }
    }

    func profileUpdated(_ profile: OwnProfile) {
        self.profile = profile
    }

    /// Routes an error from any feature: an expired session keeps drafts and asks for sign-in.
    @discardableResult
    func handle(_ error: Error, routeIntent: AppRoute? = nil) -> String {
        if case RoamError.sessionExpired = error { markSessionExpired(routeIntent: routeIntent) }
        return error.roamMessage
    }

    func markBeenIntroSeen() async {
        guard var current = profile, !current.hasSeenBeenIntro else { return }
        current.hasSeenBeenIntro = true
        profile = current
        try? await services.profiles.markBeenIntroSeen()
    }

    func completeSetup(_ profile: OwnProfile) {
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
        guard phase == .ready else { return }
        sessionExpired = true
        pendingRouteAfterReauth = routeIntent
        let expiredUser = session?.userID
        Task {
            await services.auth.signOut()
            self.session = nil
            self.profile = nil
            self.services.images.clear()
            self.expiredUserID = expiredUser
            self.phase = .signedOut
        }
    }

    /// The account whose session expired (drafts are kept for it).
    private(set) var expiredUserID: UUID?

    func signOut() async {
        let userID = session?.userID
        await services.auth.signOut()
        clearLocalState(for: userID)
        phase = .signedOut
    }

    func accountDeleted() {
        let userID = session?.userID
        clearLocalState(for: userID)
        phase = .signedOut
    }

    private func handleSignedOutExternally() async {
        if case .ready = phase {
            sessionExpired = true
            return
        }
        clearLocalState(for: session?.userID)
        phase = .signedOut
    }

    private func clearLocalState(for userID: UUID?) {
        if let userID { services.storage.clearAccount(userID) }
        pendingAppleName = nil
        services.images.clear()
        session = nil
        profile = nil
        isRecoveringPassword = false
        sessionExpired = false
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
