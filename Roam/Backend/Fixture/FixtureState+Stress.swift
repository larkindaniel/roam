#if ROAM_FIXTURES
import Foundation

extension FixtureState {
    static let stressDisplayName = "Maximiliana Alexandra Constantinople-Featherstone"
    static let stressLongPlace = "The Extraordinarily Long-Named Harbourside Tea Room and Botanical Garden Café of the Old Lisbon Waterfront"

    /// M8 layout stress (`-roam-fixture-scenario stress`): Maya's display name at the 50-character
    /// limit's edge, a very long place name, and a 13-place Food & Drink tie group (Harbor plus 12).
    mutating func seedStress() {
        members[FixtureIDs.maya]?.displayName = Self.stressDisplayName
        let names = [Self.stressLongPlace] + (1...11).map { "Tie Test Kitchen \($0)" }
        var stressRatings: [(rating: UUID, visit: UUID, experience: UUID, published: Date)] = []
        for (index, name) in names.enumerated() {
            let placeID = nextID(20), experienceID = nextID(30)
            let candidate = PlaceCandidate(provider: .fixture, providerPlaceID: "fixture-stress-\(index)", name: name,
                                           address: "\(index + 1) Rua da Prata, Lisbon, Portugal", locality: "Lisbon", region: "Lisboa",
                                           countryCode: "PT", countryName: "Portugal", latitude: 38.7100 + Double(index) * 0.0007,
                                           longitude: -9.1370, phone: nil, website: nil, providerCategory: "MKPOICategoryCafe",
                                           timeZoneIdentifier: "Europe/Lisbon", isLocality: false, suggestedCategory: .foodDrink)
            places[placeID] = FixtureBackend.PlaceRow(id: placeID, candidate: candidate, status: .active)
            experiences[experienceID] = FixtureBackend.ExperienceRow(id: experienceID, placeID: placeID, category: .foodDrink, categoryLocked: true,
                                                                     createdAt: FixtureSeed.daysAgo(120))
            let ratingID = nextID(40), visitID = nextID(50)
            let published = FixtureSeed.daysAgo(index == 0 ? 0.05 : 60 - Double(index))
            ratings[ratingID] = FixtureBackend.RatingRow(id: ratingID, owner: FixtureIDs.maya, experience: experienceID, category: .foodDrink,
                                                         sentiment: .liked, group: 0, firstRatedAt: published, updatedAt: published)
            visits[visitID] = FixtureBackend.VisitRow(id: visitID, owner: FixtureIDs.maya, experience: experienceID,
                                                      date: LocalDate(isoString: "2026-0\(1 + index % 9)-1\(index % 10)"), timeZone: "Europe/Lisbon",
                                                      note: index == 0 ? "Long names must wrap, never push the score or actions off screen." : "",
                                                      mediaIDs: [], createdAt: published, updatedAt: published)
            stressRatings.append((ratingID, visitID, experienceID, published))
            revisions["\(FixtureIDs.maya.uuidString)|\(ExperienceCategory.foodDrink.rawValue)", default: 0] += 1
        }
        // The long-named place's automatic post leads the feed, with its score at posting time.
        if let long = stressRatings.first,
           let placement = rankingSnapshot(owner: FixtureIDs.maya, category: .foodDrink).placement(forExperience: long.experience) {
            let activityID = nextID(70)
            activities[activityID] = FixtureBackend.ActivityRow(id: activityID, author: FixtureIDs.maya, type: .rating, experience: long.experience,
                                                                visit: long.visit, rating: long.rating, category: .foodDrink,
                                                                score: placement.score, rank: placement.rank, sentiment: .liked,
                                                                publishedAt: long.published)
        }
    }
}
#endif
