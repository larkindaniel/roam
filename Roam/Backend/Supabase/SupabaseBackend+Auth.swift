import Foundation
import Supabase

extension SupabaseBackend: AuthService {
    static let recoveryCallbackURL = URL(string: "roam://auth-callback/recovery")!

    private func authSession(_ session: Session) -> AuthSession {
        authSession(user: session.user)
    }

    private func authSession(user: User) -> AuthSession {
        var providers: [AuthProviderKind] = []
        if case let .array(values)? = user.appMetadata["providers"] {
            for value in values {
                if case let .string(name) = value, let kind = AuthProviderKind(rawValue: name) { providers.append(kind) }
            }
        }
        if providers.isEmpty, case let .string(name)? = user.appMetadata["provider"], let kind = AuthProviderKind(rawValue: name) {
            providers = [kind]
        }
        return AuthSession(userID: user.id, email: user.email, providers: providers.isEmpty ? [.email] : providers)
    }

    func restoreSession() async throws -> AuthSession? {
        do {
            let session = try await client.auth.session
            return authSession(session)
        } catch AuthError.sessionMissing {
            return nil
        } catch {
            let mapped = Self.map(error)
            if case RoamError.sessionExpired = mapped { return nil }
            throw mapped
        }
    }

    func sessionChanges() -> AsyncStream<AuthSession?> {
        let auth = client.auth
        return AsyncStream { continuation in
            let task = Task {
                for await (event, session) in auth.authStateChanges {
                    switch event {
                    case .signedOut, .userDeleted:
                        continuation.yield(nil)
                    case .initialSession, .signedIn, .tokenRefreshed, .userUpdated, .passwordRecovery, .mfaChallengeVerified:
                        continuation.yield(session.map { self.authSession($0) })
                    @unknown default:
                        break
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func signUp(email: String, password: String) async throws -> SignUpOutcome {
        if let issue = Validation.email(email) { throw RoamError.validation(issue.localizedDescription) }
        if let issue = Validation.password(password) { throw RoamError.validation(issue.localizedDescription) }
        do {
            let response = try await client.auth.signUp(email: email, password: password, redirectTo: AppConfig.authCallbackURL)
            switch response {
            case .session(let session): return .signedIn(authSession(session))
            case .user: return .confirmationRequired(email: email)
            }
        } catch {
            throw Self.map(error)
        }
    }

    func verifySignUp(email: String, code: String) async throws -> AuthSession {
        do {
            let response = try await client.auth.verifyOTP(email: email, token: code, type: .signup)
            guard case .session(let session) = response else { throw RoamError.validation("That code is invalid or has expired. Request a new one.") }
            return authSession(session)
        } catch {
            throw Self.map(error)
        }
    }

    func resendConfirmation(email: String) async throws {
        do {
            try await client.auth.resend(email: email, type: .signup, emailRedirectTo: AppConfig.authCallbackURL)
        } catch {
            throw Self.map(error)
        }
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        do {
            return authSession(try await client.auth.signIn(email: email, password: password))
        } catch {
            throw Self.map(error)
        }
    }

    func signInWithApple(idToken: String, rawNonce: String) async throws -> AuthSession {
        do {
            let session = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: rawNonce))
            return authSession(session)
        } catch {
            throw Self.map(error)
        }
    }

    func requestPasswordReset(email: String) async throws {
        do {
            try await client.auth.resetPasswordForEmail(email, redirectTo: Self.recoveryCallbackURL)
        } catch {
            // Never reveal whether the email has an account; only surface transport problems.
            let mapped = Self.map(error)
            if case RoamError.offline = mapped { throw mapped }
            if case RoamError.timeout = mapped { throw mapped }
        }
    }

    func verifyRecovery(email: String, code: String) async throws -> AuthSession {
        do {
            let response = try await client.auth.verifyOTP(email: email, token: code, type: .recovery)
            guard case .session(let session) = response else { throw RoamError.validation("That code is invalid or has expired. Request a new one.") }
            return authSession(session)
        } catch {
            throw Self.map(error)
        }
    }

    func handleCallback(_ url: URL) async throws -> AuthCallbackResult {
        do {
            let session = try await client.auth.session(from: url)
            let auth = authSession(session)
            return url.path.contains("recovery") || url.absoluteString.contains("type=recovery") ? .passwordRecovery(auth) : .signedIn(auth)
        } catch {
            throw Self.map(error)
        }
    }

    func updatePassword(_ newPassword: String) async throws {
        if let issue = Validation.password(newPassword) { throw RoamError.validation(issue.localizedDescription) }
        do {
            _ = try await client.auth.update(user: UserAttributes(password: newPassword))
        } catch {
            throw Self.map(error)
        }
    }

    func reauthenticate(password: String) async throws {
        guard let email = client.auth.currentUser?.email else { throw RoamError.notSignedIn }
        do {
            _ = try await client.auth.signIn(email: email, password: password)
        } catch {
            let mapped = Self.map(error)
            if case RoamError.validation = mapped { throw RoamError.validation("That password is incorrect.") }
            throw mapped
        }
    }

    func signOut() async {
        try? await client.auth.signOut(scope: .local)
    }
}
