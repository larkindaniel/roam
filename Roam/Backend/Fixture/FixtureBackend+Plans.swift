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
        var countries: [String] = []
        var participants: [UUID: Bool] = [:]
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

    func areFriends(_ a: UUID, _ b: UUID) -> Bool {
        a != b && follows[Pair(a: a, b: b)] != nil && isVisibleMember(b, to: a)
    }

    func canEditTrip(_ row: TripRow, viewer: UUID) -> Bool {
        row.owner == viewer || (areFriends(viewer, row.owner) && row.participants[viewer] == true)
    }

    func canReadTrip(_ row: TripRow, viewer: UUID) -> Bool {
        canEditTrip(row, viewer: viewer) || (areFriends(viewer, row.owner)
            && shares.values.contains { $0.sender == row.owner && $0.recipient == viewer && $0.target == .trip(row.id) })
    }

    private func canReadList(_ row: ListRow, viewer: UUID) -> Bool {
        row.owner == viewer || (areFriends(viewer, row.owner)
            && shares.values.contains { $0.sender == row.owner && $0.recipient == viewer && $0.target == .list(row.id) })
    }

    private func visibleTripVisits(_ tripID: UUID, viewer: UUID) -> [VisitRow] {
        visits.values.filter { $0.tripID == tripID && audienceAllows(owner: $0.owner, audience: $0.audience, viewer: viewer) }
    }

    private func tripSummary(_ row: TripRow, viewer: UUID) -> TripSummary {
        TripSummary(id: row.id, owner: memberSummary(row.owner), name: row.draft.name, description: row.draft.description,
                    startDate: row.draft.startDate, endDate: row.draft.endDate, status: row.draft.status, isOwn: row.owner == viewer,
                    plannedCount: row.places.count, visitedCount: Set(visibleTripVisits(row.id, viewer: viewer).map(\.experience)).count,
                    stops: Array(Set(row.places.map(\.stop).filter { !$0.isEmpty })).sorted(), cities: row.cities,
                    countries: row.countries, canEdit: canEditTrip(row, viewer: viewer))
    }

    private func listSummary(_ row: ListRow, viewer: UUID) -> PlaceList {
        PlaceList(id: row.id, owner: memberSummary(row.owner), title: row.title, description: row.description,
                  isOwn: row.owner == viewer, itemCount: row.items.count)
    }

    func myTrips() async throws -> [TripSummary] {
        let me = try await authenticatedActor()
        return trips.values.filter { canEditTrip($0, viewer: me) }.sorted { $0.createdAt > $1.createdAt }.map { tripSummary($0, viewer: me) }
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
        let members = row.participants.compactMap { id, accepted -> TripMember? in
            guard (id == me || isVisibleMember(id, to: me)), areFriends(row.owner, id),
                  row.owner == me || (accepted && canEditTrip(row, viewer: me)) else { return nil }
            return TripMember(member: memberSummary(id), accepted: accepted)
        }.sorted { $0.member.handle < $1.member.handle }
        return TripDetail(summary: tripSummary(row, viewer: me), places: places, members: members)
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

    func setTripDates(_ draft: TripDraft) async throws -> TripSummary {
        let me = try await authenticatedActor()
        guard let id = draft.id, var row = trips[id], canEditTrip(row, viewer: me) else { throw RoamError.notFound }
        row.draft.startDate = draft.startDate
        row.draft.endDate = draft.endDate
        row.draft.status = draft.status
        if let message = row.draft.validationMessage { throw RoamError.validation(message) }
        trips[id] = row
        return tripSummary(row, viewer: me)
    }

    func tripInvitations() async throws -> [TripInvitation] {
        let me = try await authenticatedActor()
        return trips.values.filter { $0.participants[me] == false && areFriends(me, $0.owner) }
            .sorted { $0.createdAt > $1.createdAt }
            .map { row in
                TripInvitation(id: row.id, name: row.draft.name, owner: memberSummary(row.owner),
                               startDate: row.draft.startDate, endDate: row.draft.endDate)
            }
    }

    func setTripMembership(tripID: UUID, memberID: UUID, action: TripMembershipAction) async throws {
        let me = try await authenticatedActor()
        guard var trip = trips[tripID], trip.owner != memberID else { throw RoamError.notFound }
        switch action {
        case .invite:
            guard trip.owner == me, areFriends(me, memberID) else { throw RoamError.forbidden }
            if trip.participants[memberID] == nil { trip.participants[memberID] = false }
        case .accept:
            guard memberID == me, areFriends(me, trip.owner) else { throw RoamError.forbidden }
            guard trip.participants[me] != nil else { throw RoamError.notFound }
            trip.participants[me] = true
        case .decline, .leave, .remove:
            guard action == .remove ? trip.owner == me : memberID == me else { throw RoamError.forbidden }
            if action == .decline && trip.participants[memberID] != false { return }
            if action == .leave && trip.participants[memberID] != true { return }
            trip.participants[memberID] = nil
            detachVisits(tripID: tripID, memberID: memberID)
        }
        trips[tripID] = trip
    }

    private func detachVisits(tripID: UUID, memberID: UUID) {
        for row in visits.values where row.tripID == tripID && row.owner == memberID { visits[row.id]?.tripID = nil }
    }

    func revokeFriendAccess(_ a: UUID, _ b: UUID) {
        shares = shares.filter { _, row in
            !((row.sender == a && row.recipient == b) || (row.sender == b && row.recipient == a))
        }
        for row in trips.values where row.owner == a || row.owner == b {
            let member = row.owner == a ? b : a
            if row.participants[member] != nil {
                trips[row.id]?.participants[member] = nil
                detachVisits(tripID: row.id, memberID: member)
            }
        }
        for row in visits.values where row.owner == a || row.owner == b {
            let member = row.owner == a ? b : a
            visits[row.id]?.companionIDs.removeAll { $0 == member }
        }
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
        guard let row = trips[tripID], row.owner == me else { throw RoamError.notFound }
        trips[tripID]?.places.removeAll { $0.experience == experienceID }
        if present { trips[tripID]?.places.append((experienceID, stop)) }
    }

    func setTripCountry(tripID: UUID, code: String, name: String, present: Bool) async throws {
        let me = try await authenticatedActor()
        guard let row = trips[tripID], canEditTrip(row, viewer: me) else { throw RoamError.notFound }
        trips[tripID]?.countries.removeAll { $0 == code }
        if present { trips[tripID]?.countries.append(code) }
    }

    func setTripCity(tripID: UUID, city: Destination, present: Bool) async throws {
        let me = try await authenticatedActor()
        guard let row = trips[tripID], canEditTrip(row, viewer: me) else { throw RoamError.notFound }
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

    func logCity(_ city: Destination, start: LocalDate?, end: LocalDate?, sentiment: Sentiment?, note: String, mediaIDs: [UUID]) async throws {
        try await setCityVisited(city, present: true)
    }

    func savedCities() async throws -> [Destination] { [] }

    func setCitySaved(_ city: Destination, present: Bool) async throws -> [Destination] { [] }

    func savedCountries() async throws -> [String] { [] }

    func setCountrySaved(code: String, name: String, present: Bool) async throws -> [String] { [] }

    func passport(ownerID: UUID) async throws -> [PassportCountry] {
        let me = try await authenticatedActor()
        guard ownerID == me || areFriends(me, ownerID) else { throw RoamError.notFound }
        let marked = fixtureVisitedCities[ownerID] ?? []
        let homes = fixtureHomeCities[ownerID] ?? []
        let entries = visits.values.filter { $0.owner == ownerID && audienceAllows(owner: ownerID, audience: $0.audience, viewer: me) }
            .compactMap { visit in summary(visit.experience, viewer: me).map { (place: $0, date: visit.date) } }
        let codes = Set((marked + homes).compactMap(\.countryCode) + entries.compactMap { $0.place.countryCode })
        return codes.map { code in
            let local = entries.filter { $0.place.countryCode == code }
            let visitsByCity = Dictionary(grouping: local.filter { $0.place.locality?.isEmpty == false }) {
                GeographyKey.normalize($0.place.locality ?? "")
            }
            let markedHere = marked.filter { $0.countryCode == code }
            let homesHere = homes.filter { $0.countryCode == code }
            let known = Dictionary((markedHere + homesHere).map { (GeographyKey.normalize($0.name), $0) },
                                   uniquingKeysWith: { first, _ in first })
            let cities = Set(known.keys).union(visitsByCity.keys).sorted().compactMap { key -> PassportCity? in
                let rows = visitsByCity[key] ?? []
                let destination = known[key] ?? rows.first.flatMap { row in
                    row.place.locality.map { name in
                        Destination(name: name, region: row.place.region, countryCode: code, countryName: row.place.countryName,
                                    latitude: row.place.latitude, longitude: row.place.longitude, radiusMeters: 15_000)
                    }
                }
                guard let destination else { return nil }
                let count = Set(rows.map { $0.place.id }).count
                let dates = rows.compactMap(\.date)
                return PassportCity(city: destination, placeCount: count, visibleCount: count, firstVisit: dates.min(), lastVisit: dates.max(),
                                    isMarked: markedHere.contains { GeographyKey.normalize($0.name) == key },
                                    isHome: homesHere.contains { GeographyKey.normalize($0.name) == key })
            }
            let other = Set(local.filter { $0.place.locality?.isEmpty != false }.map { $0.place.id }).count
            let name = local.first?.place.countryName ?? (markedHere + homesHere).first?.countryName ?? code
            return PassportCountry(code: code, name: name, cities: cities, otherPlaceCount: other, otherVisibleCount: other)
        }.sorted { $0.name < $1.name }
    }

    func refreshGoogleDetails(experienceIDs: [UUID]) async -> Bool { false }

    func countryPhoto(code: String, region: String?, name: String) async -> (url: URL, credit: String?)? { nil }

    func cityPhoto(fullName: String) async -> (url: URL, credit: String?)? { nil }

    func savedRegions() async throws -> [String] { [] }

    func myPhotos(experienceID: UUID?, country: String?, region: String?, regionName: String?, city: String?) async -> [String] { [] }

    func savedRegionList() async throws -> [SavedRegion] { [] }

    func setRegionSaved(country: String, region: String, name: String, area: Destination?, present: Bool) async throws -> [String] { [] }

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

    func listRecipients(listID: UUID) async throws -> [MemberSummary] {
        let me = try await authenticatedActor()
        guard placeLists[listID]?.owner == me else { throw RoamError.notFound }
        return Set(shares.values.filter { $0.sender == me && $0.target == .list(listID) && areFriends(me, $0.recipient) }
            .map(\.recipient)).map(memberSummary).sorted { $0.handle < $1.handle }
    }

    func revokeListShare(listID: UUID, recipientID: UUID) async throws {
        let me = try await authenticatedActor()
        guard placeLists[listID]?.owner == me else { throw RoamError.notFound }
        shares = shares.filter { $0.value.sender != me || $0.value.recipient != recipientID || $0.value.target != .list(listID) }
    }

    func removeMyVisitTag(visitID: UUID) async throws {
        let me = try await authenticatedActor()
        visits[visitID]?.companionIDs.removeAll { $0 == me }
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
        let visit = visitModel(row, viewer: viewer)
        let category = ratings.values.first { $0.owner == row.owner && $0.experience == row.experience }?.category
        return TripFeedEntry(id: row.id, experience: place, publicNote: row.note, visitDate: visit.visitDate, media: visit.media, createdAt: row.createdAt,
                             score: category.flatMap { ranking(owner: row.owner, category: $0).placement(forExperience: row.experience)?.score },
                             activityID: activities.values.filter { $0.visit == row.id }.max { $0.publishedAt < $1.publishedAt }?.id,
                             author: memberSummary(row.owner), companions: visit.companions)
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

    func setVisitTrip(visitID: UUID, tripID: UUID?) async throws {
        let me = try await authenticatedActor()
        guard visits[visitID]?.owner == me else { throw RoamError.notFound }
        if let tripID {
            guard let trip = trips[tripID], canEditTrip(trip, viewer: me) else { throw RoamError.notFound }
        }
        visits[visitID]?.tripID = tripID
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
            let trip = key.trip.flatMap { trips[$0] }.flatMap { canReadTrip($0, viewer: me) ? $0 : nil }
            return TripFeedCard(author: memberSummary(key.owner), tripID: trip?.id, tripName: trip?.draft.name, visitCount: rows.count,
                                latestAt: latest.createdAt, isOwn: key.owner == me, entries: sorted.prefix(5).compactMap { tripFeedEntry($0, viewer: me) },
                                locations: Array(Set(rows.compactMap { summary($0.experience, viewer: me) }.map { TripLocation(city: $0.locality, countryCode: $0.countryCode, country: $0.countryName) })))
        }.sorted { $0.latestAt > $1.latestAt }
    }

    func friendsFeed() async throws -> [FriendFeedVisit] {
        let me = try await authenticatedActor()
        let visible = visits.values.filter {
            $0.owner != me && $0.date != nil && audienceAllows(owner: $0.owner, audience: $0.audience, viewer: me)
                && areFriends(me, $0.owner) && !mutes.contains(Pair(a: me, b: $0.owner))
        }.sorted { $0.createdAt > $1.createdAt }
        return visible.compactMap { row in tripFeedEntry(row, viewer: me).map { FriendFeedVisit(author: memberSummary(row.owner), entry: $0) } }
    }

    func tripUpdates(ownerID: UUID, tripID: UUID?) async throws -> [TripFeedEntry] {
        let me = try await authenticatedActor()
        if let tripID {
            guard let row = trips[tripID], canReadTrip(row, viewer: me) else { throw RoamError.notFound }
        }
        return visits.values.filter { $0.owner == ownerID && $0.tripID == tripID && audienceAllows(owner: $0.owner, audience: $0.audience, viewer: me) }
            .sorted { $0.createdAt > $1.createdAt }.compactMap { tripFeedEntry($0, viewer: me) }
    }

    func tripVisits(tripID: UUID) async throws -> [TripFeedEntry] {
        let me = try await authenticatedActor()
        guard let row = trips[tripID], canReadTrip(row, viewer: me) else { throw RoamError.notFound }
        return visibleTripVisits(tripID, viewer: me).sorted { $0.createdAt > $1.createdAt }
            .compactMap { tripFeedEntry($0, viewer: me) }
    }

    func friendAreaActivity(in area: FriendVisitArea, friendID: UUID?) async throws -> [FriendAreaActivity] {
        let me = try await authenticatedActor()
        let cityKey = area.cityName.map(GeographyKey.normalize)
        let eligible = visits.values.compactMap { visit -> (visit: VisitRow, city: Destination)? in
            guard friendID == nil || visit.owner == friendID,
                  areFriends(me, visit.owner), audienceAllows(owner: visit.owner, audience: visit.audience, viewer: me),
                  let experience = experiences[visit.experience], let place = places[experience.placeID]?.candidate,
                  let city = place.locality, !GeographyKey.normalize(city).isEmpty,
                  place.countryCode?.uppercased() == area.countryCode,
                  area.regions.isEmpty || area.regions.contains(GeographyKey.normalize(place.region ?? "")),
                  cityKey == nil || GeographyKey.normalize(city) == cityKey else { return nil }
            return (visit, Destination(name: city, region: place.region, countryCode: place.countryCode,
                                       countryName: place.countryName, latitude: place.latitude, longitude: place.longitude,
                                       radiusMeters: 15_000))
        }
        let sorted = eligible.sorted {
            ($0.visit.date?.isoString ?? "", $0.visit.createdAt, $0.visit.id.uuidString)
                > ($1.visit.date?.isoString ?? "", $1.visit.createdAt, $1.visit.id.uuidString)
        }
        let byFriend = Dictionary(grouping: sorted) { $0.visit.owner }
        return sorted.map { $0.visit.owner }.uniqued().compactMap { id in
            guard let entries = byFriend[id] else { return nil }
            var seenCities = Set<String>()
            let cities = entries.map(\.city).filter { seenCities.insert($0.id).inserted }
            let placeIDs = entries.map { $0.visit.experience }.uniqued()
            let places = friendID != nil && cityKey != nil ? placeIDs.compactMap { summary($0, viewer: me) } : []
            return FriendAreaActivity(member: memberSummary(id), cities: cities, placeCount: placeIDs.count, places: places)
        }
    }

    func friendMemories(experienceID: UUID) async throws -> [PublicMemory] {
        let me = try await authenticatedActor()
        return visits.values
            .filter { $0.experience == experienceID && $0.owner != me && areFriends(me, $0.owner) && audienceAllows(owner: $0.owner, audience: $0.audience, viewer: me) }
            .sorted { ($0.createdAt, $0.id.uuidString) > ($1.createdAt, $1.id.uuidString) }
            .map { row in
                let visit = visitModel(row, viewer: me)
                let category = ratings.values.first { $0.owner == row.owner && $0.experience == experienceID }?.category
                let score = category.flatMap { ranking(owner: row.owner, category: $0).placement(forExperience: experienceID)?.score }
                return PublicMemory(id: visit.id, author: memberSummary(row.owner), experienceID: experienceID, visitDate: visit.visitDate,
                                    publicNote: visit.publicNote, media: visit.media, createdAt: visit.createdAt, updatedAt: visit.updatedAt,
                                    isOwn: false, score: score, companions: visit.companions)
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
