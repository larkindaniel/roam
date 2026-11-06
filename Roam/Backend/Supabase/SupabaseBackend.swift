import Foundation
import Supabase

/// Real backend: local (or later hosted) Supabase. All durable writes go through RPCs that
/// derive the actor from the JWT; the client never sends actor IDs, final scores or times.
final class SupabaseBackend: @unchecked Sendable {
    let client: SupabaseClient
    let config: AppConfig
    private let rpcFetch: PostgrestClient.FetchHandler

    /// `authStorage` defaults to the Keychain; tests inject isolated in-memory storage per client.
    init(config: AppConfig, authStorage: (any AuthLocalStorage)? = nil, rpcFetch: PostgrestClient.FetchHandler? = nil) {
        self.config = config
        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.timeoutIntervalForRequest = 20
        sessionConfiguration.timeoutIntervalForResource = 60
        sessionConfiguration.waitsForConnectivity = false
        let networkSession = URLSession(configuration: sessionConfiguration)
        self.rpcFetch = rpcFetch ?? { try await networkSession.data(for: $0) }
        client = SupabaseClient(
            supabaseURL: config.supabaseURL,
            supabaseKey: config.publishableKey,
            options: SupabaseClientOptions(
                db: .init(encoder: RoamJSON.encoder, decoder: RoamJSON.decoder),
                auth: .init(storage: authStorage ?? KeychainLocalStorage(service: "com.daniellarkin.roam.auth"),
                            redirectToURL: AppConfig.authCallbackURL,
                            flowType: .pkce,
                            emitLocalSessionAsInitialSession: true),
                global: .init(session: networkSession)
            )
        )
    }

    // MARK: RPC helpers

    /// Freeze the authenticated session per request. SupabaseClient's default adapter fetches
    /// the current token at transport time, which can otherwise change actor after an account switch.
    func requestSnapshot() async throws -> BackendRequestSnapshot {
        let snapshot = client.auth.currentSession
        let token: String
        if let snapshot {
            let session = try await client.auth.session
            guard session.user.id == snapshot.user.id, client.auth.currentSession?.user.id == snapshot.user.id else { throw RoamError.sessionExpired }
            token = session.accessToken
        } else { token = config.publishableKey }
        return BackendRequestSnapshot(userID: snapshot?.user.id,
                                      headers: ["apikey": config.publishableKey, "Authorization": "Bearer \(token)"])
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) { try await rpcFetch(request) }

    private func requestClient() async throws -> PostgrestClient {
        let snapshot = try await requestSnapshot()
        return PostgrestClient(url: config.supabaseURL.appendingPathComponent("rest/v1"),
                               headers: snapshot.headers,
                               logger: nil, fetch: rpcFetch, encoder: RoamJSON.encoder, decoder: RoamJSON.decoder)
    }

    func rpc<T: Decodable>(_ function: String, _ params: some Encodable) async throws -> T {
        do {
            let scoped = try await requestClient()
            return try await scoped.rpc(function, params: params).execute().value
        } catch {
            throw Self.map(error)
        }
    }

    func rpc<T: Decodable>(_ function: String) async throws -> T {
        do {
            let scoped = try await requestClient()
            return try await scoped.rpc(function).execute().value
        } catch {
            throw Self.map(error)
        }
    }

    func rpcVoid(_ function: String, _ params: some Encodable) async throws {
        do {
            let scoped = try await requestClient()
            try await scoped.rpc(function, params: params).execute()
        } catch {
            throw Self.map(error)
        }
    }

    /// Maps transport, auth and `roam:`-prefixed database errors to user-presentable errors.
    static func map(_ error: Error) -> Error {
        if error is CancellationError { return error }
        if let roam = error as? RoamError { return roam }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dataNotAllowed:
                return RoamError.offline
            case .timedOut:
                return RoamError.timeout
            case .cancelled:
                return CancellationError()
            default:
                return RoamError.server("Couldn't reach Roam. Try again.")
            }
        }
        if let postgrest = error as? PostgrestError {
            return mapDatabaseMessage(postgrest.message, code: postgrest.code)
        }
        if let auth = error as? AuthError {
            switch auth {
            case .sessionMissing: return RoamError.notSignedIn
            case .api(let message, let code, _, _):
                switch code {
                case .invalidCredentials, .userNotFound: return RoamError.validation("Email or password is incorrect.")
                case .emailNotConfirmed: return RoamError.validation("Confirm your email first. Check your inbox for the code.")
                case .sessionExpired, .sessionNotFound, .refreshTokenNotFound, .refreshTokenAlreadyUsed, .badJWT: return RoamError.sessionExpired
                case .otpExpired: return RoamError.validation("That code is invalid or has expired. Request a new one.")
                case .weakPassword: return RoamError.validation("Choose a password of at least \(Limits.passwordMin) characters.")
                case .overRequestRateLimit, .overEmailSendRateLimit: return RoamError.server("Too many attempts. Wait a moment and try again.")
                case .samePassword: return RoamError.validation("Choose a password different from your current one.")
                case .flowStateExpired, .flowStateNotFound, .badCodeVerifier: return RoamError.validation("This link has expired. Request a new one from the app.")
                default: return RoamError.server(message.isEmpty ? "Sign-in failed. Try again." : message)
                }
            case .weakPassword: return RoamError.validation("Choose a password of at least \(Limits.passwordMin) characters.")
            case .pkceGrantCodeExchange: return RoamError.validation("This link has expired. Request a new one from the app.")
            default: return RoamError.server("Sign-in failed. Try again.")
            }
        }
        if let storage = error as? StorageError {
            if storage.statusCode == "403" || storage.statusCode == "401" { return RoamError.forbidden }
            if storage.statusCode == "404" { return RoamError.notFound }
            if storage.statusCode == "413" { return RoamError.validation("This photo is too large to upload.") }
            return RoamError.server("Photo storage is unavailable right now.")
        }
        if error is DecodingError { return RoamError.server("Roam received an unexpected response.") }
        return RoamError.server("Something went wrong. Try again.")
    }

    static func mapDatabaseMessage(_ message: String, code: String?) -> RoamError {
        if code == "PGRST301" || code == "PGRST303" || message.localizedCaseInsensitiveContains("JWT expired") {
            return .sessionExpired
        }
        guard message.hasPrefix("roam:") else {
            if code == "42501" { return .forbidden }
            if code == "23505" { return .conflict("That already exists.") }
            return .server("Something went wrong. Try again.")
        }
        let body = String(message.dropFirst(5))
        let parts = body.split(separator: ":", maxSplits: 1).map(String.init)
        let key = parts.first ?? ""
        let detail = parts.count > 1 ? parts[1] : nil
        switch key {
        case "not_signed_in": return .notSignedIn
        case "not_found": return .notFound
        case "forbidden": return .forbidden
        case "unavailable": return .unavailable
        case "stale_revision": return .staleRevision
        case "already_rated": return .alreadyRated
        case "confirm_last_visit": return .lastVisitConfirmationRequired
        case "media_expired": return .mediaExpired
        case "operation_conflict": return .conflict("This save was already used for a different change.")
        case "handle_taken": return .conflict("That handle is taken. Try another.")
        case "validation": return .validation(detail ?? "Check your entry and try again.")
        case "account_disabled": return .forbidden
        case "reauthentication_required": return .reauthenticationRequired
        default: return .server(detail ?? "Something went wrong. Try again.")
        }
    }

    func health() async -> Bool {
        struct Health: Decodable { let service: String }
        let result: Health? = try? await rpc("roam_health")
        return result?.service == "roam"
    }
}

struct BackendRequestSnapshot: Sendable {
    let userID: UUID?
    let headers: [String: String]
}
