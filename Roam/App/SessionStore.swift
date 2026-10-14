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

    func completeSetup(_ profile: OwnProfile) {
        self.profile = profile
        justCompletedSetup = true
        phase = .ready
    }

    func consumeJustCompletedSetup() -> Bool {
        defer { justCompletedSetup = false }
        return justCompletedSetup
    }

    /// Marks the session expired: drafts stay, nothing submits until the same member signs in again.
    func markSessionExpired() {
        sessionExpired = true
    }

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
