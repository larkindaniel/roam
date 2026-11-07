#if ROAM_FIXTURES
import Foundation

/// The fixture backend's copy of the server's suggestions (`supabase/migrations/20261107000100_suggestions.sql`), so UI
/// journeys and screenshots show realistic orders and reason lines. The database is the source of truth: its weights
/// are `app_private.suggestion_weights()`, and `08_suggestions_test.sql` holds the fixed orders. Keep these in step.
enum FixtureSuggestionWeights {
    static let sentFirst = 40.0, sentSecond = 20.0, sharedList = 25.0
    static let staleAfterDays = 90.0, staleFactor = 0.5
    static let friendLiked = 15.0, friendFine = 5.0, friendDisliked = -10.0, friendBeen = 5.0
    static let tasteMax = 10.0, tasteMinLiked = 3, tasteTypeMinLiked = 2
    static let popular = 5.0, popularPriorCount = 5.0, popularPriorScore = 6.0, popularMinScore = 7.0
    static let cityTopPlaces = 5, cityOnTrip = 30.0, cityInTripCountry = 15.0, citySaved = 10.0
}

extension FixtureBackend {
    private typealias W = FixtureSuggestionWeights

    private func isActiveFriend(_ viewer: UUID, _ other: UUID) -> Bool {
        viewer != other && follows[Pair(a: viewer, b: other)] != nil && isVisibleMember(other, to: viewer)
    }

    /// A rating takes the audience of its owner's latest visit, as on the server.
    func ratingAudience(_ row: RatingRow) -> Audience {
        visits.values.filter { $0.owner == row.owner && $0.experience == row.experience }
            .max { $0.createdAt < $1.createdAt }?.audience ?? .friends
    }

    private func cityKey(_ candidate: PlaceCandidate) -> String? {
        guard let locality = candidate.locality, !candidate.isLocality else { return nil }
        return GeographyKey.cityKey(countryCode: candidate.countryCode, region: candidate.region, locality: locality)
    }

    func fixtureCityID(_ key: String) -> UUID {
        if let id = fixtureCityIDs[key] { return id }
        let id = UUID()
        fixtureCityIDs[key] = id
        return id
    }

    private func appleType(of experienceID: UUID) -> String? {
        experiences[experienceID].flatMap { places[$0.placeID] }?.candidate.providerCategory
    }

    private struct Scored {
        var experience: UUID
        var candidate: PlaceCandidate
        var points: Double
        var evidence: SuggestionEvidence
    }

    private func scoredPlaces(viewer me: UUID, bounds: GeoBounds?, country: String?) -> [Scored] {
        let now = Date()
        let stale = { (date: Date) in now.timeIntervalSince(date) > W.staleAfterDays * 86_400 ? W.staleFactor : 1 }
        let myLiked = ratings.values.filter { $0.owner == me && $0.sentiment == .liked }
        let likedByCategory = Dictionary(grouping: myLiked, by: \.category).mapValues(\.count)
        let likedByType = Dictionary(grouping: myLiked.compactMap { appleType(of: $0.experience) }, by: { $0 }).mapValues(\.count)
        let incoming = shares.values.filter { $0.recipient == me }
        return experiences.values.compactMap { experience -> Scored? in
            guard let place = places[experience.placeID], place.status == .active, !place.candidate.isLocality else { return nil }
            let c = place.candidate
            if let bounds, !bounds.contains(latitude: c.latitude, longitude: c.longitude) { return nil }
            if let country, c.countryCode?.uppercased() != country.uppercased() { return nil }
            let id = experience.id
            if visits.values.contains(where: { $0.owner == me && $0.experience == id })
                || ratings.values.contains(where: { $0.owner == me && $0.experience == id })
                || bookmarks[Pair(a: me, b: id)] != nil || hiddenSuggestions.contains(id) { return nil }

            let sent = incoming.filter { $0.target == .place(id) && isActiveFriend(me, $0.sender) }.sorted { $0.createdAt > $1.createdAt }
            let senders = sent.map(\.sender).uniqued()
            let listed = incoming.compactMap { share -> (ListRow, Date)? in
                guard case .list(let listID) = share.target, let list = placeLists[listID], isActiveFriend(me, list.owner),
                      list.items.contains(where: { $0.experience == id }) else { return nil }
                return (list, share.createdAt)
            }.max { $0.1 < $1.1 }
            let friendRatings = ratings.values.filter { $0.experience == id && isActiveFriend(me, $0.owner)
                && audienceAllows(owner: $0.owner, audience: ratingAudience($0), viewer: me) }
            let visitors = Set(visits.values.filter { $0.experience == id && isActiveFriend(me, $0.owner)
                && audienceAllows(owner: $0.owner, audience: $0.audience, viewer: me) }.map(\.owner))
                .union(friendRatings.map(\.owner))
            let community = ratings.values.filter { $0.experience == id && $0.owner != me
                && audienceAllows(owner: $0.owner, audience: ratingAudience($0), viewer: me) }
                .compactMap { placement(owner: $0.owner, experience: id)?.score }
            let communityScore = ScoreMath.mean(of: community)
            let smoothed = (Double(community.map(\.tenths).reduce(0, +)) / 10 + W.popularPriorCount * W.popularPriorScore)
                / (Double(community.count) + W.popularPriorCount)
            let isPopular = !community.isEmpty && smoothed >= W.popularMinScore

            let liked = friendRatings.filter { $0.sentiment == .liked }.count
            let fine = friendRatings.filter { $0.sentiment == .fine }.count
            let disliked = friendRatings.filter { $0.sentiment == .disliked }.count
            let beenOnly = visitors.count - friendRatings.count
            let friendPoints = Double(liked) * W.friendLiked + Double(fine) * W.friendFine + Double(disliked) * W.friendDisliked + Double(beenOnly) * W.friendBeen
            guard !sent.isEmpty || listed != nil || !visitors.isEmpty || !community.isEmpty else { return nil }
            guard friendPoints >= 0 || !sent.isEmpty || listed != nil else { return nil }

            var points = 0.0
            if let latest = sent.first?.createdAt {
                points += (senders.count >= 1 ? W.sentFirst : 0) + (senders.count >= 2 ? W.sentSecond : 0)
                points *= stale(latest)
            }
            if let listed { points += W.sharedList * stale(listed.1) }
            points += friendPoints
            let likedHere = experience.category.flatMap { likedByCategory[$0] } ?? 0
            let type = c.providerCategory
            let likedOfType = type.flatMap { likedByType[$0] } ?? 0
            let hasLean = myLiked.count >= W.tasteMinLiked
            if hasLean { points += (Double(likedHere) + Double(likedOfType)) / Double(myLiked.count) / 2 * W.tasteMax }
            let typeClaim = hasLean && likedOfType >= W.tasteTypeMinLiked
            if isPopular { points += W.popular }
            guard points >= 0 else { return nil }

            let names = { (ids: [UUID]) in ids.map { self.memberSummary($0).displayName } }
            let evidence = SuggestionEvidence(
                sentBy: senders.isEmpty ? nil : names(senders),
                list: listed.map { SuggestionEvidence.SharedList(owner: memberSummary($0.0.owner).displayName, title: $0.0.title) },
                friendsLoved: visitors.isEmpty ? nil : names(friendRatings.filter { $0.sentiment == .liked }.map(\.owner)).sorted(),
                friendsBeen: visitors.isEmpty ? nil : names(Array(visitors)).sorted(),
                friendsFine: visitors.isEmpty ? nil : fine, friendsDisliked: visitors.isEmpty ? nil : disliked,
                communityCount: community.isEmpty ? nil : community.count, communityScore: communityScore,
                likedInCategory: hasLean ? likedHere : nil, likedType: typeClaim ? type : nil, likedInType: typeClaim ? likedOfType : nil,
                isPopular: isPopular)
            return Scored(experience: id, candidate: c, points: (points * 10).rounded() / 10, evidence: evidence)
        }
    }

    func suggestedPlaces(in bounds: GeoBounds) async throws -> [DiscoverPlace] {
        let me = try await authenticatedActor()
        let found = scoredPlaces(viewer: me, bounds: bounds, country: nil).compactMap { scored -> DiscoverPlace? in
            guard let summary = summary(scored.experience, viewer: me) else { return nil }
            let cover = visits.values.filter { $0.experience == scored.experience && audienceAllows(owner: $0.owner, audience: $0.audience, viewer: me) }
                .sorted { $0.createdAt > $1.createdAt }.compactMap { visitModel($0).media.first?.path }.first
            return DiscoverPlace(experience: summary, communityScore: scored.evidence.communityScore, communityCount: scored.evidence.communityCount ?? 0,
                                 friendNames: scored.evidence.friendsBeen ?? [], coverPath: cover, points: scored.points, evidence: scored.evidence)
        }
        return Array(SuggestionOrder.places(found).prefix(40))
    }

    func suggestedCities(countryCode: String?) async throws -> [DiscoverCity] {
        let me = try await authenticatedActor()
        let today = LocalDate.today()
        let upcoming = trips.values.filter { $0.owner == me && $0.draft.status != .past && ($0.draft.endDate.map { $0 >= today } ?? true) }
        let homes = (fixtureHomeCities[me] ?? []) + [members[me]?.homeCity].compactMap { $0 }
        let beenKeys = Set(homes.map(\.id) + (fixtureVisitedCities[me] ?? []).map(\.id)
            + visits.values.filter { $0.owner == me }.compactMap { experiences[$0.experience].flatMap { places[$0.placeID] }.flatMap { cityKey($0.candidate) } })
        let scored = scoredPlaces(viewer: me, bounds: nil, country: countryCode)
        let byCity = Dictionary(grouping: scored.compactMap { s in cityKey(s.candidate).map { ($0, s) } }, by: \.0).mapValues { $0.map(\.1) }
        var candidates: [String: Destination] = [:]
        for (key, group) in byCity {
            let c = group[0].candidate
            candidates[key] = Destination(name: c.locality ?? "", region: c.region, countryCode: c.countryCode, countryName: c.countryName,
                                          latitude: group.map(\.candidate.latitude).reduce(0, +) / Double(group.count),
                                          longitude: group.map(\.candidate.longitude).reduce(0, +) / Double(group.count), radiusMeters: 15_000)
        }
        for trip in upcoming {
            for city in trip.cities where countryCode == nil || city.countryCode?.uppercased() == countryCode?.uppercased() {
                candidates[city.id] = candidates[city.id] ?? city
            }
        }
        let cities = candidates.compactMap { key, destination -> DiscoverCity? in
            let cityID = fixtureCityID(key)
            guard !beenKeys.contains(key), !hiddenSuggestions.contains(cityID) else { return nil }
            let best = (byCity[key] ?? []).sorted { $0.points > $1.points }
            let top = Array(best.prefix(W.cityTopPlaces))
            let trip = upcoming.first { $0.cities.contains { $0.id == key } }
            var points = top.map(\.points).reduce(0, +)
            if trip != nil { points += W.cityOnTrip }
            let evidence = SuggestionEvidence(
                sentBy: Self.distinct(best.flatMap { $0.evidence.sentBy ?? [] }),
                list: best.compactMap(\.evidence.list).first,
                friendsLoved: Self.distinct(best.flatMap { $0.evidence.friendsLoved ?? [] }),
                friendsBeen: Self.distinct(best.flatMap { $0.evidence.friendsBeen ?? [] }),
                communityCount: Self.positive(best.map { $0.evidence.communityCount ?? 0 }.reduce(0, +)),
                isPopular: best.contains { $0.evidence.isPopular == true },
                tripName: trip?.draft.name)
            let topSummary = top.first.flatMap { summary($0.experience, viewer: me) }
            return DiscoverCity(cityID: cityID, destination: destination, points: (points * 10).rounded() / 10, evidence: evidence,
                                placeCount: best.count, coverURL: topSummary?.photoURL)
        }
        return Array(SuggestionOrder.cities(cities).prefix(30))
    }

    private static func distinct(_ names: [String]) -> [String]? {
        let unique = Array(Set(names)).sorted()
        return unique.isEmpty ? nil : unique
    }

    private static func positive(_ value: Int) -> Int? { value > 0 ? value : nil }

    func hideSuggestion(experienceID: UUID?, cityID: UUID?, hidden: Bool) async throws {
        _ = try await authenticatedActor()
        guard let id = experienceID ?? cityID, (experienceID == nil) != (cityID == nil) else { throw RoamError.validation("Choose a place or a city.") }
        if hidden { hiddenSuggestions.insert(id) } else { hiddenSuggestions.remove(id) }
    }

    func onboardingPlaces(in bounds: GeoBounds) async throws -> [ExperienceSummary] {
        let me = try await authenticatedActor()
        let rows = experiences.values.compactMap { experience -> (ExperienceSummary, Int, Int)? in
            guard let place = places[experience.placeID], place.status == .active, !place.candidate.isLocality,
                  bounds.contains(latitude: place.candidate.latitude, longitude: place.candidate.longitude),
                  !visits.values.contains(where: { $0.owner == me && $0.experience == experience.id }),
                  !ratings.values.contains(where: { $0.owner == me && $0.experience == experience.id }),
                  let summary = summary(experience.id, viewer: me) else { return nil }
            let friends = Set(visits.values.filter { $0.experience == experience.id && isActiveFriend(me, $0.owner)
                && audienceAllows(owner: $0.owner, audience: $0.audience, viewer: me) }.map(\.owner)).count
            let raters = ratings.values.filter { $0.experience == experience.id && $0.owner != me
                && audienceAllows(owner: $0.owner, audience: ratingAudience($0), viewer: me) }.count
            return (summary, friends, raters)
        }
        return rows.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            if lhs.2 != rhs.2 { return lhs.2 > rhs.2 }
            return lhs.0.name < rhs.0.name
        }.prefix(12).map(\.0)
    }

    /// A place Theo sent Maya, Sam's Wellington list shared with her, and an upcoming Iceland trip, so Discover and city
    /// pages show every kind of reason line in the default fixture scenario.
    static func seedSuggestionSignals(places: inout [UUID: PlaceRow], experiences: inout [UUID: ExperienceRow], shares: inout [UUID: ShareRow],
                                      lists: inout [UUID: ListRow], trips: inout [UUID: TripRow], catalog: FixturePlaceCatalog) {
        func ensure(_ key: String, number: Int) -> UUID? {
            guard let candidate = catalog.candidate(key: key) else { return nil }
            if let place = places.values.first(where: { $0.candidate.providerPlaceID == candidate.providerPlaceID }),
               let id = experiences.values.first(where: { $0.placeID == place.id })?.id { return id }
            let placeID = FixtureIDs.uuid(21, number), experienceID = FixtureIDs.uuid(31, number)
            places[placeID] = PlaceRow(id: placeID, candidate: candidate, status: .active)
            experiences[experienceID] = ExperienceRow(id: experienceID, placeID: placeID, category: candidate.suggestedCategory, categoryLocked: true,
                                                      createdAt: FixtureSeed.daysAgo(300))
            return experienceID
        }
        if let mill = ensure("mill", number: 1) {
            let id = FixtureIDs.uuid(90, 1)
            shares[id] = ShareRow(id: id, sender: FixtureIDs.theo, recipient: FixtureIDs.maya, target: .place(mill),
                                  message: "The Sunday double bill is the best night out in Edinburgh.", createdAt: FixtureSeed.daysAgo(6), operationID: id)
        }
        if let drift = ensure("drift", number: 2) {
            let listID = FixtureIDs.uuid(91, 1)
            lists[listID] = ListRow(id: listID, owner: FixtureIDs.sam, title: "Wellington", description: "", createdAt: FixtureSeed.daysAgo(40),
                                    items: [(experience: drift, note: "")])
            let id = FixtureIDs.uuid(90, 2)
            shares[id] = ShareRow(id: id, sender: FixtureIDs.sam, recipient: FixtureIDs.maya, target: .list(listID), message: "",
                                  createdAt: FixtureSeed.daysAgo(14), operationID: id)
        }
        if let reykjavik = catalog.destinations.first(where: { $0.name == "Reykjavík" }) {
            let tripID = FixtureIDs.uuid(92, 1)
            let start = LocalDate.today().adding(days: 45), end = LocalDate.today().adding(days: 52)
            trips[tripID] = TripRow(id: tripID, owner: FixtureIDs.maya,
                                    draft: TripDraft(id: tripID, name: "Iceland trip", startDate: start, endDate: end, status: .upcoming),
                                    createdAt: FixtureSeed.daysAgo(10), cities: [reykjavik])
        }
    }
}
#endif
