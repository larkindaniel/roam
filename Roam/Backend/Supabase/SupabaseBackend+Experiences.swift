import Foundation
import Supabase

extension SupabaseBackend: ExperienceService {
    func resolve(_ candidate: PlaceCandidate) async throws -> ExperienceSummary {
        guard candidate.provider == .mapkit else { throw RoamError.validation("Places must come from Apple Maps.") }
        return try await rpc("resolve_place", ["p_candidate": try RPC.json(candidate)])
    }

    func matches(for candidates: [PlaceCandidate]) async throws -> [String: ExperienceSummary] {
        guard !candidates.isEmpty else { return [:] }
        struct Wire: Encodable {
            let id: String
            let provider: PlaceProviderKind
            let providerPlaceID: String?
            let name: String
            let address: String?
            let locality: String?
            let region: String?
            let countryCode: String?
            let latitude: Double
            let longitude: Double
            let isLocality: Bool
        }
        let wire = candidates.map {
            Wire(id: $0.id, provider: $0.provider, providerPlaceID: $0.providerPlaceID, name: $0.name, address: $0.address,
                 locality: $0.locality, region: $0.region, countryCode: $0.countryCode, latitude: $0.latitude,
                 longitude: $0.longitude, isLocality: $0.isLocality)
        }
        return try await rpc("match_experiences", ["p_candidates": try RPC.json(wire)])
    }

    func detail(experienceID: UUID) async throws -> ExperienceDetail {
        try await rpc("experience_detail", ["p_experience_id": RPC.uuid(experienceID)])
    }

    func experiences(in bounds: GeoBounds, category: ExperienceCategory?) async throws -> [ExperienceSummary] {
        var minLon = bounds.minLongitude
        var maxLon = bounds.maxLongitude
        if minLon < -180 { minLon += 360 }
        if maxLon > 180 { maxLon -= 360 }
        return try await rpc("experiences_in_bounds", [
            "p_min_lat": .double(bounds.minLatitude), "p_max_lat": .double(bounds.maxLatitude),
            "p_min_lon": .double(minLon), "p_max_lon": .double(maxLon),
            "p_category": RPC.string(category?.rawValue),
        ])
    }
}

extension SupabaseBackend: ListService {
    func library() async throws -> UserLibrary {
        struct Wire: Decodable {
            let bookmarked: [UUID]
            let rated: [String: ExperienceCategory]
            let visited: [UUID]
        }
        let wire: Wire = try await rpc("my_library")
        var rated: [UUID: ExperienceCategory] = [:]
        for (key, value) in wire.rated { if let id = UUID(uuidString: key) { rated[id] = value } }
        return UserLibrary(bookmarked: Set(wire.bookmarked), rated: rated, visited: Set(wire.visited))
    }

    func setBookmark(experienceID: UUID, saved: Bool) async throws -> Bool {
        try await rpc("set_bookmark", ["p_experience_id": RPC.uuid(experienceID), "p_saved": RPC.bool(saved)])
    }

    func been(ownerID: UUID) async throws -> [ListEntry] {
        try await rpc("been_list", ["p_owner": RPC.uuid(ownerID)])
    }

    func want(ownerID: UUID) async throws -> [ListEntry] {
        try await rpc("want_list", ["p_owner": RPC.uuid(ownerID)])
    }

    func sharedWants(with otherUserID: UUID) async throws -> [ListEntry] {
        try await rpc("shared_wants", ["p_other": RPC.uuid(otherUserID)])
    }
}

extension SupabaseBackend {
    func searchMembers(query: String, cursor: String?) async throws -> Page<MemberRow> {
        struct Wire: Decodable {
            let items: [MemberRow]
            let nextCursor: String?
        }
        let wire: Wire = try await rpc("search_members", ["p_query": RPC.string(query), "p_cursor": RPC.string(cursor)])
        return Page(items: wire.items, nextCursor: wire.nextCursor)
    }

    func report(target: ReportTarget, reason: ReportReason, text: String?, operationID: UUID) async throws -> ReportReceipt {
        try await rpc("submit_report", [
            "p_operation_id": RPC.uuid(operationID), "p_target_type": RPC.string(target.kind), "p_target_id": RPC.uuid(target.targetID),
            "p_reason": RPC.string(reason.rawValue), "p_body": RPC.string(text),
        ])
    }

    func myReports() async throws -> [ReportReceipt] {
        try await rpc("my_reports")
    }
}
