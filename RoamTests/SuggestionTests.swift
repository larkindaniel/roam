import XCTest
@testable import Roam

/// Reason lines, the on-device order and the taste lean (#4). The weights and the authoritative orders are proven in
/// `supabase/tests/08_suggestions_test.sql`; these cover what the app does with the server's facts.
final class SuggestionReasonTests: XCTestCase {
    private typealias E = SuggestionEvidence

    func testTheStrongestFactWins() {
        let everything = E(sentBy: ["Theo Park"], list: .init(owner: "Maya Ito", title: "Lisbon"), friendsLoved: ["Sam Rivera"],
                           friendsBeen: ["Sam Rivera", "Jo Bell"], likedInCategory: 5, isPopular: true)
        XCTAssertEqual(SuggestionReason.place(everything), "Theo sent you this")
        var noSend = everything; noSend.sentBy = nil
        XCTAssertEqual(SuggestionReason.place(noSend), "On Maya's Lisbon list")
        var noList = noSend; noList.list = nil
        XCTAssertEqual(SuggestionReason.place(noList), "Sam loved it")
        var noLove = noList; noLove.friendsLoved = []
        XCTAssertEqual(SuggestionReason.place(noLove), "Sam and Jo have been")
        var noFriends = noLove; noFriends.friendsBeen = nil
        XCTAssertEqual(SuggestionReason.place(noFriends), "Like places you loved")
        var noTaste = noFriends; noTaste.likedInCategory = 2
        XCTAssertEqual(SuggestionReason.place(noTaste), "Popular on Roam")
        noTaste.isPopular = false
        XCTAssertNil(SuggestionReason.place(noTaste), "nothing honest to say means no line, never a made-up one")
    }

    func testNamesUseFirstNamesThenCounts() {
        XCTAssertEqual(SuggestionReason.place(E(sentBy: ["Theo Park", "Maya Ito"])), "Theo and Maya sent you this")
        XCTAssertEqual(SuggestionReason.place(E(sentBy: ["Theo Park", "Maya Ito", "Sam Rivera"])), "Theo and 2 others sent you this")
        XCTAssertEqual(SuggestionReason.place(E(friendsLoved: ["Maya Ito", "Theo Park"])), "Maya and Theo loved it")
        XCTAssertEqual(SuggestionReason.place(E(friendsLoved: ["A", "B", "C"])), "3 friends loved it")
        XCTAssertEqual(SuggestionReason.place(E(friendsBeen: ["Maya Ito"])), "Maya has been")
        XCTAssertEqual(SuggestionReason.place(E(friendsBeen: ["A b", "C d", "E f"])), "A and 2 others have been")
    }

    func testAListNamedListIsNotSaidTwice() {
        XCTAssertEqual(SuggestionReason.place(E(list: .init(owner: "Maya Ito", title: "Coffee list"))), "On Maya's Coffee list")
        XCTAssertEqual(SuggestionReason.place(E(list: .init(owner: "Maya Ito", title: "Weekend picks"))), "On Maya's Weekend picks list")
    }

    func testTasteNeedsEnoughLikedPlaces() {
        XCTAssertNil(SuggestionReason.place(E(likedInCategory: SuggestionReason.tasteMinimumLiked - 1)))
        XCTAssertEqual(SuggestionReason.place(E(likedInCategory: SuggestionReason.tasteMinimumLiked)), "Like places you loved")
    }

    func testCityLinesLeadWithYourTrip() {
        XCTAssertEqual(SuggestionReason.city(E(sentBy: ["Theo Park"], tripName: "Japan trip")), "On your Japan trip")
        XCTAssertEqual(SuggestionReason.city(E(tripName: "Golden Week")), "On your Golden Week trip")
        XCTAssertEqual(SuggestionReason.city(E(sentBy: ["Theo Park"])), "Theo sent you a place here")
        XCTAssertEqual(SuggestionReason.city(E(sentBy: ["Theo Park", "Maya Ito"])), "Theo and Maya sent you places here")
        XCTAssertEqual(SuggestionReason.city(E(friendsLoved: ["Maya Ito"])), "Maya loved it here")
        XCTAssertEqual(SuggestionReason.city(E(friendsBeen: ["Maya Ito"])), "Maya has been")
        XCTAssertEqual(SuggestionReason.city(E(isPopular: true)), "Popular on Roam")
        XCTAssertNil(SuggestionReason.city(.empty))
    }

    func testEvidenceDecodesTheServersShape() throws {
        let json = #"{"sentBy":["Theo Park"],"list":{"owner":"Maya Ito","title":"Lisbon"},"friendsLoved":[],"communityScore":7.3,"isPopular":true}"#
        let evidence = try JSONDecoder().decode(SuggestionEvidence.self, from: Data(json.utf8))
        XCTAssertEqual(evidence.sentBy, ["Theo Park"])
        XCTAssertEqual(evidence.list?.title, "Lisbon")
        XCTAssertEqual(evidence.communityScore, Score(tenths: 73))
        XCTAssertEqual(SuggestionReason.place(evidence), "Theo sent you this")
    }

    func testACitySuggestionDecodesWithAnEmptyEvidenceObject() throws {
        let json = #"[{"cityID":"6f1c6c2e-8a0e-4c9b-9a2b-6a3f8f0d1e2a","destination":{"name":"Tokyo","region":null,"countryCode":"JP","countryName":"Japan","latitude":35.68,"longitude":139.69,"radiusMeters":15000},"points":30,"evidence":{"tripName":"Japan trip"},"placeCount":0,"coverURL":null,"coverPath":null}]"#
        let cities = try JSONDecoder().decode([DiscoverCity].self, from: Data(json.utf8))
        XCTAssertEqual(cities.first?.reason, "On your Japan trip")
        XCTAssertEqual(cities.first?.points, 30)
    }
}

final class SuggestionOrderTests: XCTestCase {
    private func place(_ name: String, points: Double?, google: Double? = nil) -> DiscoverPlace {
        var summary = ExperienceSummary(id: UUID(), placeID: UUID(), name: name, latitude: 0, longitude: 0, followingCount: 0,
                                        viewer: ViewerExperienceState(isBookmarked: false, hasVisits: false))
        summary.googleRating = google
        return DiscoverPlace(experience: summary, communityScore: nil, communityCount: 0, friendNames: [], coverPath: nil, points: points)
    }

    func testMostPointsFirstThenGoogleThenName() {
        let ordered = SuggestionOrder.places([place("B", points: 5, google: 4.5), place("A", points: 5, google: 4.5), place("C", points: 5, google: 4.8),
                                              place("D", points: 50), place("E", points: nil, google: 5)])
        XCTAssertEqual(ordered.map(\.experience.name), ["D", "C", "A", "B", "E"])
    }

    func testGoogleIsOnlyATiebreaker() {
        XCTAssertEqual(SuggestionOrder.places([place("Stars", points: 5, google: 5), place("Friend", points: 15, google: 3)]).map(\.experience.name),
                       ["Friend", "Stars"])
    }

    func testCitiesByPointsThenName() {
        let city = { (name: String, points: Double) in
            DiscoverCity(destination: Destination(name: name, region: nil, countryCode: "PT", countryName: "Portugal", latitude: 0, longitude: 0,
                                                  radiusMeters: 1), points: points)
        }
        XCTAssertEqual(SuggestionOrder.cities([city("Porto", 10), city("Lisbon", 125), city("Braga", 10)]).map(\.destination.name),
                       ["Lisbon", "Braga", "Porto"])
    }
}

final class TasteLeanTests: XCTestCase {
    private func liked(_ category: ExperienceCategory?, _ type: String? = nil) -> TasteLean.Liked { .init(category: category, appleType: type) }

    func testNoLeanUntilEnoughLikedPlaces() {
        XCTAssertTrue(TasteLean.labels(liked: [liked(.foodDrink), liked(.foodDrink)]).isEmpty)
    }

    func testKindsOfPlaceComeBeforeBroadCategories() {
        let labels = TasteLean.labels(liked: [liked(.foodDrink, "MKPOICategoryCafe"), liked(.foodDrink, "MKPOICategoryCafe"),
                                              liked(.foodDrink, "MKPOICategoryRestaurant"), liked(.culture, "MKPOICategoryMuseum"),
                                              liked(.culture)])
        XCTAssertEqual(labels, ["cafés", "food & drink", "culture"], "one restaurant or museum isn't a lean; two cafés are")
    }

    func testTypesWithoutWordsFallBackToCategories() {
        XCTAssertEqual(TasteLean.labels(liked: [liked(.activities, "MKPOICategoryBank"), liked(.activities, "MKPOICategoryBank"), liked(.activities)]),
                       ["activities"])
    }

    func testThePlanWithAIPromptIncludesTheLean() {
        let lisbon = Destination(name: "Lisbon", region: nil, countryCode: "PT", countryName: "Portugal", latitude: 0, longitude: 0, radiusMeters: 1)
        let text = ResearchBrief.text(destination: lisbon, taste: .empty, liked: [], leanings: ["cafés", "museums"])
        XCTAssertTrue(text.contains("Places I tend to love: cafés, museums"))
        XCTAssertFalse(ResearchBrief.text(destination: lisbon, taste: .empty, liked: []).contains("tend to love"))
    }
}

final class PlaceTypeReasonTests: XCTestCase {
    func testAKindOfPlaceYouLovedBeatsTheBroadCategory() {
        let evidence = SuggestionEvidence(likedInCategory: 6, likedType: "MKPOICategoryBakery", likedInType: 2, isPopular: true)
        XCTAssertEqual(SuggestionReason.place(evidence), "Like the bakeries you loved")
    }

    func testOneOfAKindIsNotALean() {
        XCTAssertEqual(SuggestionReason.place(SuggestionEvidence(likedInCategory: 4, likedType: "MKPOICategoryCafe", likedInType: 1)),
                       "Like places you loved")
    }

    func testTypesWithNoWordingFallBack() {
        XCTAssertEqual(SuggestionReason.place(SuggestionEvidence(likedInCategory: 3, likedType: "MKPOICategoryParking", likedInType: 5)),
                       "Like places you loved")
    }

    func testFriendsStillComeFirst() {
        XCTAssertEqual(SuggestionReason.place(SuggestionEvidence(friendsBeen: ["Maya Ito"], likedType: "MKPOICategoryCafe", likedInType: 4)),
                       "Maya has been")
    }

    func testWordsForCommonTypes() {
        XCTAssertEqual(PlaceType.plural("MKPOICategoryCafe"), "cafés")
        XCTAssertEqual(PlaceType.plural("MKPOICategoryWinery"), "wineries")
        XCTAssertNil(PlaceType.plural(nil))
    }
}
