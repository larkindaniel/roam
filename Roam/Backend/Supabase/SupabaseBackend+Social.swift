import Foundation
import Supabase

extension SupabaseBackend {
    /// Desired-state follow; retries are safe.
    func setFollow(userID: UUID, following: Bool) async throws -> Bool {
        try await rpc("set_follow", ["p_user_id": RPC.uuid(userID), "p_following": RPC.bool(following)])
    }
}
