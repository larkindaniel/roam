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
        // Every request is timed for the beta's latency numbers (see NetworkRecorder).
        let networkSession = URLSession(configuration: sessionConfiguration, delegate: NetworkRecorder.shared, delegateQueue: nil)
        self.rpcFetch = rpcFetch ?? { try await networkSession.data(for: $0) }
        client = SupabaseClient(
            supabaseURL: config.supabaseURL,
            supabaseKey: config.publishableKey,
            options: SupabaseClientOptions(
                db: .init(encoder: RoamJSON.encoder, decoder: RoamJSON.decoder),
                auth: .init(storage: authStorage ?? defaultAuthStorage(),
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
            let value: T = try await scoped.rpc(function, params: params).execute().value
            Self.logAction(function, params)
            return value
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
            Self.logAction(function, params)
        } catch {
            throw Self.map(error)
        }
    }

    /// What the member did, in plain words, for the beta's trail: logged when a call that changes something succeeds.
    static let actionNames: [String: String] = [
        "commit_rating": "place.logged", "add_visit": "visit.added", "update_visit": "visit.edited",
        "delete_visit": "visit.deleted", "remove_rating": "rating.removed", "set_visit_audience": "visit.audience_changed",
        "set_visit_trip": "visit.trip_changed", "remove_my_visit_tag": "visit.tag_removed", "add_custom_place": "place.added",
        "save_private_note": "note.saved", "delete_private_note": "note.deleted",
        "set_bookmark": "wishlist.changed", "set_city_saved": "city.saved_changed", "set_country_saved": "country.saved_changed",
        "set_region_saved": "region.saved_changed", "set_city_visited": "city.visited_changed", "mark_city_visited": "city.marked_visited",
        "log_city": "city.logged", "set_home_city": "home.changed",
        "save_trip": "trip.saved", "delete_trip": "trip.deleted", "set_trip_dates": "trip.dates_changed",
        "set_trip_membership": "trip.membership_changed", "set_trip_place": "trip.place_changed",
        "set_trip_country": "trip.country_changed", "set_trip_city": "trip.city_changed",
        "save_list": "list.saved", "delete_list": "list.deleted", "set_list_item": "list.place_changed",
        "revoke_list_share": "list.share_revoked", "send_share": "share.sent",
        "friend_action": "friend.action", "set_block": "member.block_changed", "set_mute": "member.mute_changed",
        "set_like": "like.changed", "post_comment": "comment.posted", "delete_comment": "comment.deleted",
        "submit_report": "content.reported", "hide_suggestion": "suggestion.hidden",
        "create_profile": "profile.created", "update_profile": "profile.updated", "set_setup_checkpoint": "setup.checkpoint",
        "save_taste": "taste.saved", "update_settings": "settings.updated", "request_account_deletion": "account.deletion_requested",
        "mark_all_notifications_read": "notifications.read_all",
    ]

    /// Logs the action with the call's ids, switches and numbers. Text (notes, names, messages) never goes in.
    static func logAction(_ function: String, _ params: some Encodable) {
        guard let action = actionNames[function] else { return }
        let textKeys: Set<String> = ["handle", "display_name", "displayName", "note", "privateNote", "caption", "bio", "message", "text", "query", "title",
                                     "description", "comment", "body", "email", "password", "reason_text", "details"]
        var props: [String: String] = [:]
        if let data = try? RoamJSON.encoder.encode(params),
           let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            // Ids, switches, numbers and short codes, one level into anything sent as a bundle (a log, a city).
            func add(_ key: String, _ value: Any, depth: Int) {
                let name = key.hasPrefix("p_") ? String(key.dropFirst(2)) : key
                let leaf = name.split(separator: ".").last.map(String.init) ?? name
                if textKeys.contains(leaf) || props.count >= 24 { return }
                switch value {
                case let flag as Bool: props[name] = flag ? "true" : "false"
                case let number as NSNumber: props[name] = number.stringValue
                case let nested as [String: Any] where depth == 0:
                    let prefix = (name == "request" || name == "payload") ? "" : "\(name)."
                    for (k, v) in nested { add(prefix + k, v, depth: 1) }
                case let text as String where leaf == "name" && depth == 1 && text.count <= 60:
                    // A place's or city's name says which one it was (a list's name, typed by the member, isn't kept).
                    props[name] = text
                case let text as String where leaf != "name" && (UUID(uuidString: text) != nil || text.count <= 24 && text.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" })):
                    // Ids and short codes ("liked", "friends", "CA", "2026-11-15"), not free text.
                    props[name] = text
                default: break
                }
            }
            for (key, value) in object { add(key, value, depth: 0) }
        }
        Log.action(action, props)
    }

    /// Maps transport, auth and `roam:`-prefixed database errors to user-presentable errors.
    static func map(_ error: Error) -> Error {
        if error is CancellationError { return error }
        logFailure(error)
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

    /// The real reason a call failed, for the beta's trail: the server's code and message, the network error, or what
    /// didn't decode. The member only ever sees the friendly version.
    static func logFailure(_ error: Error) {
        var props: [String: String] = ["type": String(describing: type(of: error))]
        switch error {
        case let roam as RoamError: props["roam"] = String(describing: roam)
        case let url as URLError:
            props["code"] = "\(url.code.rawValue)"
            props["url"] = url.failingURL.flatMap { NetworkRecorder.name(for: $0, method: nil) } ?? ""
        case let postgrest as PostgrestError:
            props["code"] = postgrest.code ?? ""
            props["message"] = postgrest.message
            props["detail"] = postgrest.detail ?? ""
            props["hint"] = postgrest.hint ?? ""
        case let auth as AuthError:
            props["detail"] = String(describing: auth)
        case let storage as StorageError:
            props["code"] = storage.statusCode ?? ""
            props["message"] = storage.message
        case let decoding as DecodingError:
            props["detail"] = Self.describe(decoding)
        default:
            props["detail"] = String(describing: error)
        }
        Log.error("backend", nil, props)
    }

    /// Which field didn't decode and why, without the payload.
    private static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String { context.codingPath.map(\.stringValue).joined(separator: ".") }
        switch error {
        case .keyNotFound(let key, let context): return "missing \(key.stringValue) at \(path(context))"
        case .typeMismatch(let type, let context): return "expected \(type) at \(path(context)): \(context.debugDescription)"
        case .valueNotFound(let type, let context): return "no \(type) at \(path(context))"
        case .dataCorrupted(let context): return "corrupted at \(path(context)): \(context.debugDescription)"
        @unknown default: return String(describing: error)
        }
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

private func defaultAuthStorage() -> any AuthLocalStorage {
    #if DEBUG && targetEnvironment(simulator)
    // Command-line simulator builds are unsigned, and an unsigned app can't use the Keychain.
    SimulatorAuthStorage()
    #else
    KeychainLocalStorage(service: "com.daniellarkin.roam.auth")
    #endif
}

#if DEBUG && targetEnvironment(simulator)
private struct SimulatorAuthStorage: AuthLocalStorage {
    func store(key: String, value: Data) throws { UserDefaults.standard.set(value, forKey: "roam.auth." + key) }
    func retrieve(key: String) throws -> Data? { UserDefaults.standard.data(forKey: "roam.auth." + key) }
    func remove(key: String) throws { UserDefaults.standard.removeObject(forKey: "roam.auth." + key) }
}
#endif
