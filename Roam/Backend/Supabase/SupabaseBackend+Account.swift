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

    func deletionStatus() async throws -> AccountDeletionStatus? {
        let status: AccountDeletionStatus? = try await rpc("account_deletion_status")
        return status
    }
}
