import CoreLocation
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

    func setTripCity(tripID: UUID, city: Destination, present: Bool) async throws {
        try await rpcVoid("set_trip_city", ["p_trip_id": RPC.uuid(tripID), "p_city": try RPC.json(city), "p_present": RPC.bool(present)])
    }

    func homeCities() async throws -> [Destination] { try await rpc("my_home_cities") }

    func setHomeCity(_ city: Destination, present: Bool) async throws -> [Destination] {
        try await rpc("set_home_city", ["p_city": try RPC.json(city), "p_present": RPC.bool(present)])
    }

    func setCityVisited(_ city: Destination, present: Bool) async throws {
        try await rpcVoid("set_city_visited", ["p_city": try RPC.json(city), "p_present": RPC.bool(present)])
    }

    func passport(ownerID: UUID) async throws -> [PassportCountry] {
        try await rpc("passport", ["p_owner": RPC.uuid(ownerID)])
    }

    func refreshGoogleDetails(experienceIDs: [UUID]) async -> Bool {
        guard !experienceIDs.isEmpty, let snapshot = try? await requestSnapshot(), snapshot.userID != nil else { return false }
        var request = URLRequest(url: config.supabaseURL.appendingPathComponent("functions/v1/google-place"))
        request.httpMethod = "POST"
        snapshot.headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["experienceIDs": experienceIDs.prefix(30).map { $0.uuidString.lowercased() }])
        guard let (body, response) = try? await send(request), (response as? HTTPURLResponse)?.statusCode == 200,
              let result = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let updated = result["updated"] as? [String] else { return false }
        return !updated.isEmpty
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

    func searchRoamPlaces(query: String) async throws -> [ExperienceSummary] {
        try await rpc("search_roam_places", ["p_query": RPC.string(query)])
    }

    func addCustomPlace(name: String, coordinate: CLLocationCoordinate2D, category: ExperienceCategory, area: Destination?) async throws -> ExperienceSummary {
        try await rpc("add_custom_place", [
            "p_name": RPC.string(name), "p_latitude": .double(coordinate.latitude), "p_longitude": .double(coordinate.longitude),
            "p_category": RPC.string(category.rawValue), "p_locality": RPC.string(area?.name), "p_region": RPC.string(area?.region),
            "p_country_code": RPC.string(area?.countryCode), "p_country_name": RPC.string(area?.countryName),
        ] as RPCParams)
    }

    func setVisitAudience(visitID: UUID, audience: Audience) async throws {
        let _: String = try await rpc("set_visit_audience", ["p_visit_id": RPC.uuid(visitID), "p_audience": RPC.string(audience.rawValue)])
    }

    func tripFeed() async throws -> [TripFeedCard] { try await rpc("trip_feed") }

    func countryFeed() async throws -> [CountryFeedCard] { try await rpc("country_feed") }

    func countryUpdates(ownerID: UUID, countryCode: String?) async throws -> [TripFeedEntry] {
        try await rpc("country_updates", ["p_owner": RPC.uuid(ownerID), "p_country_code": RPC.string(countryCode)])
    }

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
