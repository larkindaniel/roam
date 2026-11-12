import Foundation
import Supabase

extension SupabaseBackend: SettingsService {
    func settings() async throws -> UserSettings { try await rpc("my_settings") }

    /// Desired state: the whole settings object is replaced, so a retried save is harmless.
    func update(_ settings: UserSettings) async throws -> UserSettings {
        try await rpc("update_settings", ["p_settings": try RPC.json(settings)])
    }
}

extension SupabaseBackend: TravelService {
    func travelProfile(userID: UUID, year: Int) async throws -> TravelProfile {
        try await rpc("travel_profile", ["p_user_id": RPC.uuid(userID), "p_year": RPC.int(year)])
    }
}

extension SupabaseBackend: AccountService {
    /// Needs a sign-in within the last 10 minutes (`reauthenticate`). The server hides the account,
    /// revokes every session and queues the deletion job at once.
    func requestDeletion() async throws -> AccountDeletionStatus { try await rpc("request_account_deletion") }

    /// The one-use Apple code is sent only to the server. The client never receives Apple's
    /// access/refresh token or the private signing key.
    func requestDeletion(appleAuthorizationCode: String) async throws -> AccountDeletionStatus {
        let snapshot = try await requestSnapshot()
        guard snapshot.userID != nil else { throw RoamError.notSignedIn }
        var request = URLRequest(url: config.supabaseURL.appendingPathComponent("functions/v1/delete-account"))
        request.httpMethod = "POST"
        snapshot.headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["authorizationCode": appleAuthorizationCode])
        do {
            let (body, response) = try await send(request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                if status == 401 { throw RoamError.reauthenticationRequired }
                throw RoamError.server("Apple account deletion is unavailable. Try again.")
            }
            return try RoamJSON.decoder.decode(AccountDeletionStatus.self, from: body)
        } catch { throw Self.map(error) }
    }

    func deletionStatus() async throws -> AccountDeletionStatus? {
        let status: AccountDeletionStatus? = try await rpc("account_deletion_status")
        return status
    }
}
