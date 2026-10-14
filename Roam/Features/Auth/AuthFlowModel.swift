import AuthenticationServices
import CryptoKit
import Foundation
import Observation

enum AuthRoute: Hashable {
    case signUp
    case signIn
    case verify
    case forgot
    case resetCode
}

/// Drives welcome/sign-up/sign-in/recovery. Keeps the typed email (non-sensitive) across restarts;
/// passwords live only in memory.
@MainActor
@Observable
final class AuthFlowModel {
    var email: String {
        didSet { UserDefaults.standard.set(email, forKey: Self.emailKey) }
    }
    var password = ""
    var code = ""
    var busy = false
    var error: String?
    var info: String?
    var path: [AuthRoute] = []
    /// Raw nonce for the in-flight Apple request; only its SHA-256 goes to Apple.
    private var appleNonce: String?

    private static let emailKey = "roam.lastEmail"
    private let services: AppServices
    private let session: SessionStore

    init(services: AppServices, session: SessionStore) {
        self.services = services
        self.session = session
        self.email = UserDefaults.standard.string(forKey: Self.emailKey) ?? ""
    }

    var emailIssue: ValidationIssue? { Validation.email(email) }
    var passwordIssue: ValidationIssue? { Validation.password(password) }

    func clearMessages() {
        error = nil
        info = nil
    }

    func signUp() async {
        await run {
            switch try await self.services.auth.signUp(email: self.email.trimmingCharacters(in: .whitespaces), password: self.password) {
            case .confirmationRequired:
                self.password = ""
                self.code = ""
                self.info = "We sent a 6-digit code to \(self.email). It expires in an hour."
                self.path.append(.verify)
            case .signedIn(let auth):
                self.password = ""
                await self.session.didAuthenticate(auth)
            }
        }
    }

    func verifySignUp() async {
        await run {
            let auth = try await self.services.auth.verifySignUp(email: self.email.trimmingCharacters(in: .whitespaces), code: self.code)
            self.code = ""
            await self.session.didAuthenticate(auth)
        }
    }

    func resendCode() async {
        await run {
            try await self.services.auth.resendConfirmation(email: self.email.trimmingCharacters(in: .whitespaces))
            self.info = "We sent a new code to \(self.email)."
        }
    }

    func signIn() async {
        await run {
            let auth = try await self.services.auth.signIn(email: self.email.trimmingCharacters(in: .whitespaces), password: self.password)
            self.password = ""
            await self.session.didAuthenticate(auth)
        }
    }

    /// Never reveals whether an account exists for the address.
    func requestReset() async {
        await run {
            try await self.services.auth.requestPasswordReset(email: self.email.trimmingCharacters(in: .whitespaces))
            self.code = ""
            self.info = "If an account uses \(self.email), we sent it a 6-digit reset code."
            self.path.append(.resetCode)
        }
    }

    func verifyReset() async {
        await run {
            let auth = try await self.services.auth.verifyRecovery(email: self.email.trimmingCharacters(in: .whitespaces), code: self.code)
            self.code = ""
            self.session.isRecoveringPassword = true
            await self.session.didAuthenticate(auth)
        }
    }

    // MARK: Sign in with Apple

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        appleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    func completeApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let failure):
            // Cancelling leaves the member signed out without an alarm.
            if let authError = failure as? ASAuthorizationError, authError.code == .canceled { return }
            error = "Sign in with Apple didn't complete. Try again or continue with email."
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken, let token = String(data: tokenData, encoding: .utf8),
                  let nonce = appleNonce else {
                error = "Sign in with Apple didn't return a valid identity. Try again."
                return
            }
            if let name = credential.fullName {
                let formatted = PersonNameComponentsFormatter.localizedString(from: name, style: .default)
                if !formatted.trimmingCharacters(in: .whitespaces).isEmpty { session.pendingAppleName = formatted }
            }
            await run {
                let auth = try await self.services.auth.signInWithApple(idToken: token, rawNonce: nonce)
                await self.session.didAuthenticate(auth)
            }
            appleNonce = nil
        }
    }

    private func run(_ work: @escaping () async throws -> Void) async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await work()
        } catch {
            self.error = error.roamMessage
        }
    }

    nonisolated static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset[Int(generator.next() % UInt64(charset.count))] })
    }

    nonisolated static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
