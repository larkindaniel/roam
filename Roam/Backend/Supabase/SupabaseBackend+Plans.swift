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

    func setTripCountry(tripID: UUID, code: String, name: String, present: Bool) async throws {
        try await rpcVoid("set_trip_country", ["p_trip_id": RPC.uuid(tripID), "p_code": RPC.string(code), "p_name": RPC.string(name),
                                               "p_present": RPC.bool(present)])
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

    func markCityVisited(_ city: Destination, start: LocalDate?, end: LocalDate?) async throws {
        try await rpcVoid("mark_city_visited", ["p_city": try RPC.json(city), "p_start": RPC.date(start), "p_end": RPC.date(end)])
    }

    func logCity(_ city: Destination, start: LocalDate?, end: LocalDate?, sentiment: Sentiment?, note: String, mediaIDs: [UUID]) async throws {
        try await rpcVoid("log_city", ["p_city": try RPC.json(city), "p_start": RPC.date(start), "p_end": RPC.date(end),
                                       "p_sentiment": RPC.string(sentiment?.rawValue), "p_note": RPC.string(note),
                                       "p_media_ids": RPC.uuids(mediaIDs)])
    }

    func savedCities() async throws -> [Destination] { try await rpc("my_saved_cities") }

    func setCitySaved(_ city: Destination, present: Bool) async throws -> [Destination] {
        try await rpc("set_city_saved", ["p_city": try RPC.json(city), "p_present": RPC.bool(present)])
    }

    func savedCountries() async throws -> [String] { try await rpc("my_saved_countries") }

    func setCountrySaved(code: String, name: String, present: Bool) async throws -> [String] {
        try await rpc("set_country_saved", ["p_code": RPC.string(code), "p_name": RPC.string(name), "p_present": RPC.bool(present)])
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

    func savedRegions() async throws -> [String] { try await rpc("my_saved_regions") }

    func myPhotos(experienceID: UUID?, country: String?, region: String?, regionName: String?, city: String?) async -> [String] {
        (try? await rpc("my_photos", ["p_experience": RPC.uuid(experienceID), "p_country": RPC.string(country),
                                      "p_region": RPC.string(region), "p_region_name": RPC.string(regionName),
                                      "p_city": RPC.string(city)])) ?? []
    }

    func savedRegionList() async throws -> [SavedRegion] { try await rpc("my_saved_region_list") }

    func setRegionSaved(country: String, region: String, name: String, area: Destination?, present: Bool) async throws -> [String] {
        try await rpc("set_region_saved", ["p_country": RPC.string(country), "p_region": RPC.string(region), "p_name": RPC.string(name),
                                           "p_present": RPC.bool(present),
                                           "p_latitude": area.map { .double($0.latitude) } ?? .null,
                                           "p_longitude": area.map { .double($0.longitude) } ?? .null,
                                           "p_radius": area.map { .double($0.radiusMeters) } ?? .null])
    }

    func countryPhoto(code: String, region: String?, name: String) async -> (url: URL, credit: String?)? {
        var body = ["country": code, "name": name]
        if let region { body["region"] = region }
        return await areaPhoto(body)
    }

    func cityPhoto(fullName: String) async -> (url: URL, credit: String?)? {
        await areaPhoto(["city": fullName, "name": fullName])
    }

    /// Asks the google-place function for an area's photo (it keeps each for a week).
    private func areaPhoto(_ body: [String: String]) async -> (url: URL, credit: String?)? {
        guard let snapshot = try? await requestSnapshot(), snapshot.userID != nil else { return nil }
        var request = URLRequest(url: config.supabaseURL.appendingPathComponent("functions/v1/google-place"))
        request.httpMethod = "POST"
        snapshot.headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (body, response) = try? await send(request), (response as? HTTPURLResponse)?.statusCode == 200,
              let result = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let photo = (result["photoURL"] as? String).flatMap(URL.init(string:)) else { return nil }
        return (photo, result["photoCredit"] as? String)
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

    func setVisitTrip(visitID: UUID, tripID: UUID?) async throws {
        try await rpcVoid("set_visit_trip", ["p_visit_id": RPC.uuid(visitID), "p_trip_id": RPC.uuid(tripID)])
    }

    func tripFeed() async throws -> [TripFeedCard] { try await rpc("trip_feed") }

    func friendsFeed() async throws -> [FriendFeedVisit] { try await rpc("friends_feed") }

    func tripUpdates(ownerID: UUID, tripID: UUID?) async throws -> [TripFeedEntry] {
        try await rpc("trip_updates", ["p_owner": RPC.uuid(ownerID), "p_trip_id": RPC.uuid(tripID)])
    }

    func suggestedPlaces(in bounds: GeoBounds) async throws -> [DiscoverPlace] {
        try await rpc("suggested_places", [
            "p_min_lat": .double(bounds.minLatitude), "p_max_lat": .double(bounds.maxLatitude),
            "p_min_lon": .double(bounds.minLongitude), "p_max_lon": .double(bounds.maxLongitude),
        ] as RPCParams)
    }

    func suggestedCities(countryCode: String?) async throws -> [DiscoverCity] {
        try await rpc("suggested_cities", ["p_country": RPC.string(countryCode)])
    }

    func hideSuggestion(experienceID: UUID?, cityID: UUID?, hidden: Bool) async throws {
        let _: Bool = try await rpc("hide_suggestion", ["p_experience_id": RPC.uuid(experienceID), "p_city_id": RPC.uuid(cityID),
                                                        "p_hidden": .bool(hidden)] as RPCParams)
    }

    func onboardingPlaces(in bounds: GeoBounds) async throws -> [ExperienceSummary] {
        try await rpc("onboarding_places", [
            "p_min_lat": .double(bounds.minLatitude), "p_max_lat": .double(bounds.maxLatitude),
            "p_min_lon": .double(bounds.minLongitude), "p_max_lon": .double(bounds.maxLongitude),
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
