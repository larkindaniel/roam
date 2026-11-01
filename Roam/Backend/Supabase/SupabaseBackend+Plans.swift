import Foundation
import Supabase

extension SupabaseBackend: PlanService {
    func myTrips() async throws -> [TripSummary] { try await rpc("my_trips") }

    func trip(id: UUID) async throws -> TripDetail {
        try await rpc("trip_detail", ["p_trip_id": RPC.uuid(id)])
    }

    func saveTrip(_ draft: TripDraft) async throws -> TripSummary {
        try await rpc("save_trip", [
            "p_trip_id": RPC.uuid(draft.id), "p_name": RPC.string(draft.name), "p_description": RPC.string(draft.description),
            "p_start": RPC.date(draft.startDate), "p_end": RPC.date(draft.endDate), "p_status": RPC.string(draft.status.rawValue),
        ])
    }

    func deleteTrip(id: UUID) async throws {
        try await rpcVoid("delete_trip", ["p_trip_id": RPC.uuid(id)])
    }

    func setTripPlace(tripID: UUID, experienceID: UUID, stop: String, present: Bool) async throws {
        try await rpcVoid("set_trip_place", ["p_trip_id": RPC.uuid(tripID), "p_experience_id": RPC.uuid(experienceID),
                                             "p_stop": RPC.string(stop), "p_present": RPC.bool(present)])
    }

    func myLists() async throws -> [PlaceList] { try await rpc("my_lists") }

    func list(id: UUID) async throws -> PlaceListDetail {
        try await rpc("list_detail", ["p_list_id": RPC.uuid(id)])
    }

    func saveList(id: UUID?, title: String, description: String) async throws -> PlaceList {
        try await rpc("save_list", ["p_list_id": RPC.uuid(id), "p_title": RPC.string(title), "p_description": RPC.string(description)])
    }

    func deleteList(id: UUID) async throws {
        try await rpcVoid("delete_list", ["p_list_id": RPC.uuid(id)])
    }

    func setListItem(listID: UUID, experienceID: UUID, note: String, present: Bool) async throws {
        try await rpcVoid("set_list_item", ["p_list_id": RPC.uuid(listID), "p_experience_id": RPC.uuid(experienceID),
                                            "p_note": RPC.string(note), "p_present": RPC.bool(present)])
    }

    func share(_ target: ShareTarget, with recipient: UUID, message: String, operationID: UUID) async throws {
        var place: UUID?, list: UUID?, trip: UUID?
        switch target {
        case .place(let id): place = id
        case .list(let id): list = id
        case .trip(let id): trip = id
        }
        let _: UUID = try await rpc("send_share", [
            "p_recipient": RPC.uuid(recipient), "p_experience_id": RPC.uuid(place), "p_list_id": RPC.uuid(list), "p_trip_id": RPC.uuid(trip),
            "p_message": RPC.string(message), "p_operation_id": RPC.uuid(operationID),
        ])
    }

    func sharedWithMe() async throws -> [DirectShare] { try await rpc("shared_with_me") }

    func tripFeed() async throws -> [TripFeedCard] { try await rpc("trip_feed") }

    func tripUpdates(ownerID: UUID, tripID: UUID?) async throws -> [TripFeedEntry] {
        try await rpc("trip_updates", ["p_owner": RPC.uuid(ownerID), "p_trip_id": RPC.uuid(tripID)])
    }

    func discoverPlaces(in bounds: GeoBounds?) async throws -> [DiscoverPlace] {
        try await rpc("discover_places", [
            "p_min_lat": bounds.map { .double($0.minLatitude) } ?? .null, "p_max_lat": bounds.map { .double($0.maxLatitude) } ?? .null,
            "p_min_lon": bounds.map { .double($0.minLongitude) } ?? .null, "p_max_lon": bounds.map { .double($0.maxLongitude) } ?? .null,
        ] as RPCParams)
    }

    func friendMemories(experienceID: UUID) async throws -> [PublicMemory] {
        try await rpc("friend_memories", ["p_experience_id": RPC.uuid(experienceID)])
    }

    func taste() async throws -> TasteProfile { try await rpc("my_taste") }

    func saveTaste(_ taste: TasteProfile) async throws -> TasteProfile {
        try await rpc("save_taste", ["p_answers": try RPC.json(taste)])
    }
}
