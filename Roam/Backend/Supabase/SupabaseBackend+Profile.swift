import Foundation
import Supabase

extension SupabaseBackend: ProfileService {
    func ownProfile() async throws -> OwnProfile? {
        let profile: OwnProfile? = try await rpc("my_profile")
        return profile
    }

    func checkHandle(_ handle: String) async throws -> HandleAvailability {
        if let issue = Validation.handle(handle) { return .invalid(issue) }
        let result: String = try await rpc("check_handle", ["p_handle": RPC.string(handle)])
        switch result {
        case "available": return .available
        case "taken": return .taken
        default: return .invalid(.invalidCharacters)
        }
    }

    func createProfile(displayName: String, handle: String) async throws -> OwnProfile {
        try await rpc("create_profile", ["p_display_name": RPC.string(displayName.trimmingCharacters(in: .whitespacesAndNewlines)),
                                         "p_handle": RPC.string(handle)])
    }

    func updateProfile(_ update: ProfileUpdate) async throws -> OwnProfile {
        try await rpc("update_profile", [
            "p_display_name": RPC.string(update.displayName.trimmingCharacters(in: .whitespacesAndNewlines)),
            "p_handle": RPC.string(update.handle),
            "p_bio": RPC.string(update.bio),
            "p_home_city": try RPC.json(update.homeCity),
            "p_avatar_path": RPC.string(update.avatarPath),
        ])
    }

    func setSetupCheckpoint(_ checkpoint: SetupCheckpoint) async throws -> OwnProfile {
        try await rpc("set_setup_checkpoint", ["p_checkpoint": RPC.string(checkpoint.rawValue)])
    }

    func markBeenIntroSeen() async throws {
        try await rpcVoid("mark_been_intro_seen", RPCParams())
    }

    func publicProfile(userID: UUID) async throws -> PublicProfile {
        try await rpc("public_profile", ["p_user_id": RPC.uuid(userID)])
    }

    func suggestedMembers(limit: Int) async throws -> [MemberRow] {
        try await rpc("suggested_members", ["p_limit": RPC.int(limit)])
    }
}
