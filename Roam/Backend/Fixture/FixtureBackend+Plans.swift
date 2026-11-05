#if ROAM_FIXTURES
import CoreLocation
import Foundation

extension FixtureBackend: PlanService {
    struct TripRow {
        var id: UUID
        var owner: UUID
        var draft: TripDraft
        var createdAt: Date
        var places: [(experience: UUID, stop: String)] = []
        var cities: [Destination] = []
    }

    struct ListRow {
        var id: UUID
        var owner: UUID
        var title: String
        var description: String
        var createdAt: Date
        var items: [(experience: UUID, note: String)] = []
    }

    struct ShareRow {
        var id: UUID
        var sender: UUID
        var recipient: UUID
        var target: ShareTarget
        var message: String
        var createdAt: Date
        var operationID: UUID
    }

    private func areFriends(_ a: UUID, _ b: UUID) -> Bool { follows[Pair(a: a, b: b)] != nil }

    private func canReadTrip(_ row: TripRow, viewer: UUID) -> Bool {
        row.owner == viewer || (areFriends(viewer, row.owner)
            && shares.values.contains { $0.recipient == viewer && $0.target == .trip(row.id) })
    }

    private func canReadList(_ row: ListRow, viewer: UUID) -> Bool {
        row.owner == viewer || (areFriends(viewer, row.owner)
            && shares.values.contains { $0.recipient == viewer && $0.target == .list(row.id) })
    }

    private func visibleTripVisits(_ tripID: UUID, viewer: UUID) -> [VisitRow] {
        visits.values.filter { $0.tripID == tripID && audienceAllows(owner: $0.owner, audience: $0.audience, viewer: viewer) }
    }

    private func tripSummary(_ row: TripRow, viewer: UUID) -> TripSummary {
        TripSummary(id: row.id, owner: memberSummary(row.owner), name: row.draft.name, description: row.draft.description,
                    startDate: row.draft.startDate, endDate: row.draft.endDate, status: row.draft.status, isOwn: row.owner == viewer,
                    plannedCount: row.places.count, visitedCount: Set(visibleTripVisits(row.id, viewer: viewer).map(\.experience)).count,
                    stops: Array(Set(row.places.map(\.stop).filter { !$0.isEmpty })).sorted(), cities: row.cities)
    }

    private func listSummary(_ row: ListRow, viewer: UUID) -> PlaceList {
        PlaceList(id: row.id, owner: memberSummary(row.owner), title: row.title, description: row.description,
                  isOwn: row.owner == viewer, itemCount: row.items.count)
    }

    func myTrips() async throws -> [TripSummary] {
        let me = try await authenticatedActor()
        return trips.values.filter { $0.owner == me }.sorted { $0.createdAt > $1.createdAt }.map { tripSummary($0, viewer: me) }
    }

    func trip(id: UUID) async throws -> TripDetail {
        let me = try await authenticatedActor()
        guard let row = trips[id], canReadTrip(row, viewer: me) else { throw RoamError.notFound }
        let visited = Set(visibleTripVisits(id, viewer: me).map(\.experience))
        let stops = Dictionary(row.places.map { ($0.experience, $0.stop) }, uniquingKeysWith: { first, _ in first })
        let places = Array(visited.union(stops.keys)).compactMap { experience -> TripPlace? in
            summary(experience, viewer: me).map {
                TripPlace(experience: $0, stop: stops[experience] ?? "", isPlanned: stops[experience] != nil, isVisited: visited.contains(experience))
            }
        }.sorted { $0.experience.name < $1.experience.name }
        return TripDetail(summary: tripSummary(row, viewer: me), places: places)
    }

    func saveTrip(_ draft: TripDraft) async throws -> TripSummary {
        let me = try await authenticatedActor()
        if let message = draft.validationMessage { throw RoamError.validation(message) }
        if let id = draft.id {
            guard trips[id]?.owner == me else { throw RoamError.notFound }
            trips[id]?.draft = draft
            return tripSummary(trips[id]!, viewer: me)
        }
        let id = UUID()
        var stored = draft
        stored.id = id
        trips[id] = TripRow(id: id, owner: me, draft: stored, createdAt: Date())
        return tripSummary(trips[id]!, viewer: me)
    }

    func deleteTrip(id: UUID) async throws {
        let me = try await authenticatedActor()
        guard trips[id]?.owner == me else { return }
        trips[id] = nil
        for visit in visits.values where visit.tripID == id { visits[visit.id]?.tripID = nil }
        shares = shares.filter { $0.value.target != .trip(id) }
    }

    func setTripPlace(tripID: UUID, experienceID: UUID, stop: String, present: Bool) async throws {
        let me = try await authenticatedActor()
        guard trips[tripID]?.owner == me else { throw RoamError.notFound }
        trips[tripID]?.places.removeAll { $0.experience == experienceID }
        if present { trips[tripID]?.places.append((experienceID, stop)) }
    }

    func setTripCountry(tripID: UUID, code: String, name: String, present: Bool) async throws {
        let me = try await authenticatedActor()
        guard trips[tripID]?.owner == me else { throw RoamError.notFound }
    }

    func setTripCity(tripID: UUID, city: Destination, present: Bool) async throws {
        let me = try await authenticatedActor()
        guard trips[tripID]?.owner == me else { throw RoamError.notFound }
        trips[tripID]?.cities.removeAll { $0.id == city.id }
        if present { trips[tripID]?.cities.append(city) }
    }

    func homeCities() async throws -> [Destination] {
        let me = try await authenticatedActor()
        return fixtureHomeCities[me] ?? []
    }

    func setHomeCity(_ city: Destination, present: Bool) async throws -> [Destination] {
        let me = try await authenticatedActor()
        fixtureHomeCities[me, default: []].removeAll { $0.id == city.id }
        if present { fixtureHomeCities[me, default: []].append(city) }
        return fixtureHomeCities[me] ?? []
    }

    func setCityVisited(_ city: Destination, present: Bool) async throws {
        let me = try await authenticatedActor()
        fixtureVisitedCities[me, default: []].removeAll { $0.id == city.id }
        if present { fixtureVisitedCities[me, default: []].append(city) }
    }

    func markCityVisited(_ city: Destination, start: LocalDate?, end: LocalDate?) async throws {
        try await setCityVisited(city, present: true)
    }

    func savedCities() async throws -> [Destination] { [] }

    func setCitySaved(_ city: Destination, present: Bool) async throws -> [Destination] { [] }

    func savedCountries() async throws -> [String] { [] }

    func setCountrySaved(code: String, name: String, present: Bool) async throws -> [String] { [] }

    func passport(ownerID: UUID) async throws -> [PassportCountry] {
        _ = try await authenticatedActor()
        let cities = (fixtureVisitedCities[ownerID] ?? []) + (fixtureHomeCities[ownerID] ?? [])
        return Dictionary(grouping: cities) { $0.countryCode ?? "" }.map { code, cities in
            PassportCountry(code: code, name: cities.first?.countryName ?? code,
                            cities: cities.uniqued().map { PassportCity(city: $0, placeCount: 0, visibleCount: 0, isMarked: true, isHome: false) },
                            otherPlaceCount: 0, otherVisibleCount: 0)
        }.sorted { $0.name < $1.name }
    }

    func refreshGoogleDetails(experienceIDs: [UUID]) async -> Bool { false }

    func countryPhoto(code: String, name: String) async -> (url: URL, credit: String?)? { nil }

    func myLists() async throws -> [PlaceList] {
        let me = try await authenticatedActor()
        return placeLists.values.filter { $0.owner == me }.sorted { $0.createdAt > $1.createdAt }.map { listSummary($0, viewer: me) }
    }

    func list(id: UUID) async throws -> PlaceListDetail {
        let me = try await authenticatedActor()
        guard let row = placeLists[id], canReadList(row, viewer: me) else { throw RoamError.notFound }
        let items = row.items.compactMap { item in summary(item.experience, viewer: me).map { PlaceListItem(experience: $0, note: item.note) } }
        return PlaceListDetail(summary: listSummary(row, viewer: me), items: items)
    }

    func saveList(id: UUID?, title: String, description: String) async throws -> PlaceList {
        let me = try await authenticatedActor()
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RoamError.validation("Give this list a title.") }
        if let id {
            guard placeLists[id]?.owner == me else { throw RoamError.notFound }
            placeLists[id]?.title = title
            placeLists[id]?.description = description
            return listSummary(placeLists[id]!, viewer: me)
        }
        let newID = UUID()
        placeLists[newID] = ListRow(id: newID, owner: me, title: title, description: description, createdAt: Date())
        return listSummary(placeLists[newID]!, viewer: me)
    }

    func deleteList(id: UUID) async throws {
        let me = try await authenticatedActor()
        guard placeLists[id]?.owner == me else { return }
        placeLists[id] = nil
        shares = shares.filter { $0.value.target != .list(id) }
    }

    func setListItem(listID: UUID, experienceID: UUID, note: String, present: Bool) async throws {
        let me = try await authenticatedActor()
        guard placeLists[listID]?.owner == me else { throw RoamError.notFound }
        placeLists[listID]?.items.removeAll { $0.experience == experienceID }
        if present { placeLists[listID]?.items.append((experienceID, note)) }
    }

    func share(_ target: ShareTarget, with recipient: UUID, message: String, operationID: UUID) async throws {
        let me = try await authenticatedActor()
        guard areFriends(me, recipient) else { throw RoamError.forbidden }
        switch target {
        case .place: break
        case .list(let id): guard placeLists[id]?.owner == me else { throw RoamError.notFound }
        case .trip(let id): guard trips[id]?.owner == me else { throw RoamError.notFound }
        }
        guard !shares.values.contains(where: { $0.sender == me && $0.operationID == operationID }) else { return }
        let id = UUID()
        shares[id] = ShareRow(id: id, sender: me, recipient: recipient, target: target, message: message, createdAt: Date(), operationID: operationID)
    }

    func sharedWithMe() async throws -> [DirectShare] {
        let me = try await authenticatedActor()
        return shares.values.filter { $0.recipient == me && areFriends(me, $0.sender) }
            .sorted { $0.createdAt > $1.createdAt }
            .map { row in
                var share = DirectShare(id: row.id, sender: memberSummary(row.sender), message: row.message, createdAt: row.createdAt)
                switch row.target {
                case .place(let id): share.experience = summary(id, viewer: me)
                case .list(let id): share.list = placeLists[id].map { listSummary($0, viewer: me) }
                case .trip(let id): share.trip = trips[id].map { tripSummary($0, viewer: me) }
                }
                return share
            }
    }

    private func tripFeedEntry(_ row: VisitRow, viewer: UUID) -> TripFeedEntry? {
        guard let place = summary(row.experience, viewer: viewer) else { return nil }
        let visit = visitModel(row)
        let category = ratings.values.first { $0.owner == row.owner && $0.experience == row.experience }?.category
        return TripFeedEntry(id: row.id, experience: place, publicNote: row.note, visitDate: visit.visitDate, media: visit.media, createdAt: row.createdAt,
                             score: category.flatMap { ranking(owner: row.owner, category: $0).placement(forExperience: row.experience)?.score },
                             activityID: activities.values.filter { $0.visit == row.id }.max { $0.publishedAt < $1.publishedAt }?.id)
    }

    func searchRoamPlaces(query: String) async throws -> [ExperienceSummary] {
        let me = try await authenticatedActor()
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return [] }
        return experiences.keys.compactMap { summary($0, viewer: me) }.filter { $0.name.lowercased().contains(needle) }.sorted { $0.name < $1.name }
    }

    func addCustomPlace(name: String, coordinate: CLLocationCoordinate2D, category: ExperienceCategory, area: Destination?) async throws -> ExperienceSummary {
        _ = try await authenticatedActor()
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw RoamError.validation("Give this place a name.") }
        return try await resolve(PlaceCandidate(provider: .fixture, providerPlaceID: "custom-\(name.lowercased())", name: name, address: nil, locality: area?.name,
                                                region: area?.region, countryCode: area?.countryCode, countryName: area?.countryName,
                                                latitude: coordinate.latitude, longitude: coordinate.longitude, phone: nil, website: nil, providerCategory: nil,
                                                timeZoneIdentifier: nil, isLocality: false, suggestedCategory: category))
    }

    func setVisitAudience(visitID: UUID, audience: Audience) async throws {
        let me = try await authenticatedActor()
        guard visits[visitID]?.owner == me else { throw RoamError.notFound }
        visits[visitID]?.audience = audience
    }

    func tripFeed() async throws -> [TripFeedCard] {
        let me = try await authenticatedActor()
        let visible = visits.values.filter {
            audienceAllows(owner: $0.owner, audience: $0.audience, viewer: me)
                && ($0.owner == me || (areFriends(me, $0.owner) && !mutes.contains(Pair(a: me, b: $0.owner))))
        }
        struct Key: Hashable { let owner: UUID; let trip: UUID? }
        return Dictionary(grouping: visible) { Key(owner: $0.owner, trip: $0.tripID) }.compactMap { key, rows -> TripFeedCard? in
            let sorted = rows.sorted { $0.createdAt > $1.createdAt }
            guard let latest = sorted.first else { return nil }
            return TripFeedCard(author: memberSummary(key.owner), tripID: key.trip, tripName: key.trip.flatMap { trips[$0]?.draft.name }, visitCount: rows.count,
                                latestAt: latest.createdAt, isOwn: key.owner == me, entries: sorted.prefix(5).compactMap { tripFeedEntry($0, viewer: me) },
                                locations: Array(Set(rows.compactMap { summary($0.experience, viewer: me) }.map { TripLocation(city: $0.locality, countryCode: $0.countryCode, country: $0.countryName) })))
        }.sorted { $0.latestAt > $1.latestAt }
    }

    func countryFeed() async throws -> [CountryFeedCard] {
        let me = try await authenticatedActor()
        let visible = visits.values.filter {
            audienceAllows(owner: $0.owner, audience: $0.audience, viewer: me)
                && ($0.owner == me || (areFriends(me, $0.owner) && !mutes.contains(Pair(a: me, b: $0.owner))))
        }
        struct Key: Hashable { let owner: UUID; let country: String? }
        return Dictionary(grouping: visible) { Key(owner: $0.owner, country: summary($0.experience, viewer: me)?.countryCode) }.compactMap { key, rows -> CountryFeedCard? in
            let sorted = rows.sorted { $0.createdAt > $1.createdAt }
            guard let latest = sorted.first else { return nil }
            return CountryFeedCard(author: memberSummary(key.owner), countryCode: key.country, countryName: summary(latest.experience, viewer: me)?.countryName,
                                   placeCount: Set(rows.map(\.experience)).count, latestAt: latest.createdAt, isOwn: key.owner == me,
                                   entries: sorted.prefix(5).compactMap { tripFeedEntry($0, viewer: me) })
        }.sorted { $0.latestAt > $1.latestAt }
    }

    func countryUpdates(ownerID: UUID, countryCode: String?) async throws -> [TripFeedEntry] {
        let me = try await authenticatedActor()
        return visits.values.filter {
            $0.owner == ownerID && summary($0.experience, viewer: me)?.countryCode == countryCode && audienceAllows(owner: $0.owner, audience: $0.audience, viewer: me)
        }.sorted { $0.createdAt > $1.createdAt }.compactMap { tripFeedEntry($0, viewer: me) }
    }

    func tripUpdates(ownerID: UUID, tripID: UUID?) async throws -> [TripFeedEntry] {
        let me = try await authenticatedActor()
        return visits.values.filter { $0.owner == ownerID && $0.tripID == tripID && audienceAllows(owner: $0.owner, audience: $0.audience, viewer: me) }
            .sorted { $0.createdAt > $1.createdAt }.compactMap { tripFeedEntry($0, viewer: me) }
    }

    func discoverPlaces(in bounds: GeoBounds?) async throws -> [DiscoverPlace] {
        let me = try await authenticatedActor()
        return Set(ratings.values.map(\.experience)).compactMap { experience -> DiscoverPlace? in
            guard let place = summary(experience, viewer: me),
                  bounds?.contains(latitude: place.latitude, longitude: place.longitude) ?? true else { return nil }
            let raters = ratings.values.filter { $0.experience == experience && isVisibleMember($0.owner, to: me) || $0.experience == experience && $0.owner == me }
            let scores = raters.compactMap { ranking(owner: $0.owner, category: $0.category).placement(forExperience: experience)?.score.tenths }
            guard !scores.isEmpty else { return nil }
            let friends = raters.filter { $0.owner != me && areFriends(me, $0.owner) }.map { memberSummary($0.owner).displayName }.sorted()
            let cover = visits.values.filter { $0.experience == experience && audienceAllows(owner: $0.owner, audience: $0.audience, viewer: me) }
                .sorted { $0.createdAt > $1.createdAt }.compactMap { visitModel($0).media.first?.path }.first
            return DiscoverPlace(experience: place, communityScore: Score(tenths: scores.reduce(0, +) / scores.count), communityCount: scores.count,
                                 friendNames: friends, coverPath: cover)
        }.sorted { ($0.communityScore?.tenths ?? -1) > ($1.communityScore?.tenths ?? -1) }
    }

    func friendMemories(experienceID: UUID) async throws -> [PublicMemory] {
        let me = try await authenticatedActor()
        return visits.values
            .filter { $0.experience == experienceID && $0.owner != me && areFriends(me, $0.owner) && audienceAllows(owner: $0.owner, audience: $0.audience, viewer: me) }
            .sorted { ($0.createdAt, $0.id.uuidString) > ($1.createdAt, $1.id.uuidString) }
            .map { row in
                let visit = visitModel(row)
                let category = ratings.values.first { $0.owner == row.owner && $0.experience == experienceID }?.category
                let score = category.flatMap { ranking(owner: row.owner, category: $0).placement(forExperience: experienceID)?.score }
                return PublicMemory(id: visit.id, author: memberSummary(row.owner), experienceID: experienceID, visitDate: visit.visitDate,
                                    publicNote: visit.publicNote, media: visit.media, createdAt: visit.createdAt, updatedAt: visit.updatedAt,
                                    isOwn: false, score: score)
            }
    }

    func taste() async throws -> TasteProfile {
        let me = try await authenticatedActor()
        return tastes[me] ?? .empty
    }

    func saveTaste(_ taste: TasteProfile) async throws -> TasteProfile {
        let me = try await authenticatedActor()
        tastes[me] = taste
        return taste
    }
}
#endif
