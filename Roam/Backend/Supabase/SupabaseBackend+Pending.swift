import Foundation
import MapKit

// Real-backend services that later milestones replace with RPC-backed implementations.
// Until then they fail honestly with `RoamError.unavailable` rather than fabricating data.

extension SupabaseBackend: SettingsService {
    func settings() async throws -> UserSettings { throw RoamError.unavailable }
    func update(_ settings: UserSettings) async throws -> UserSettings { throw RoamError.unavailable }
}

extension SupabaseBackend: TravelService {
    func travelProfile(userID: UUID, year: Int) async throws -> TravelProfile { throw RoamError.unavailable }
}

extension SupabaseBackend: AccountService {
    func requestDeletion() async throws -> AccountDeletionStatus { throw RoamError.unavailable }
    func deletionStatus() async throws -> AccountDeletionStatus? { throw RoamError.unavailable }
}
