import Foundation
import XCTest
@testable import Roam

final class M3PlacesIntegrationTests: BackendTestCase {
    private func candidate(id: String?, name: String, address: String?, lat: Double, lon: Double, locality: Bool = false) -> PlaceCandidate {
        PlaceCandidate(provider: .mapkit, providerPlaceID: id, name: name, address: address, locality: locality ? name : "Lisbon",
                       region: "Lisboa", countryCode: "PT", countryName: "Portugal", latitude: lat, longitude: lon, phone: nil, website: nil,
                       providerCategory: "MKPOICategoryCafe", timeZoneIdentifier: "Europe/Lisbon", isLocality: locality,
                       suggestedCategory: locality ? .dayTrips : .foodDrink)
    }

    func testConcurrentResolutionOfOnePlaceYieldsOneExperience() async throws {
        let maya = try await signedIn("maya@roam.test")
        let theo = try await signedIn("theo@roam.test")
        let place = candidate(id: "I-INT-\(UUID().uuidString.prefix(8))", name: "Integration Café", address: "1 Rua Teste, Lisbon", lat: 38.71, lon: -9.13)
        async let a = maya.resolve(place)
        async let b = theo.resolve(place)
        let (first, second) = try await (a, b)
        XCTAssertEqual(first.id, second.id, "Concurrent upserts converge on one Place/Experience")
        let matches = try await maya.matches(for: [place])
        XCTAssertEqual(matches[place.id]?.id, first.id)
    }

    func testSameNameDistinctBusinessesStayDistinct() async throws {
        let maya = try await signedIn("maya@roam.test")
        let suffix = UUID().uuidString.prefix(6)
        let a = try await maya.resolve(candidate(id: nil, name: "Twin Bakery \(suffix)", address: "5 Rua A, Lisbon", lat: 38.7111, lon: -9.1401))
        let b = try await maya.resolve(candidate(id: nil, name: "Twin Bakery \(suffix)", address: "9 Rua B, Lisbon", lat: 38.7211, lon: -9.1501))
        XCTAssertNotEqual(a.id, b.id)
        let again = try await maya.resolve(candidate(id: nil, name: "twin  bakery \(suffix)", address: "5 rua a lisbon", lat: 38.71110004, lon: -9.14009996))
        XCTAssertEqual(again.id, a.id, "Exact normalized name + address + 6-decimal coordinate reuses the place")
    }

    func testBookmarkPersistsAcrossFreshClientAndHasNoSideEffects() async throws {
        let (member, email) = try await newMember(handlePrefix: "bm")
        let place = try await member.resolve(candidate(id: "I-BM-\(UUID().uuidString.prefix(8))", name: "Bookmark Spot", address: "2 Rua, Lisbon", lat: 38.7, lon: -9.1))
        let firstWrite = try await member.setBookmark(experienceID: place.id, saved: true)
        let duplicateWrite = try await member.setBookmark(experienceID: place.id, saved: true)
        XCTAssertTrue(firstWrite)
        XCTAssertTrue(duplicateWrite)
        // A new client (equivalent to a relaunch) sees the persisted bookmark.
        let relaunched = try await signedIn(email, password: "integration-pass-123")
        let library = try await relaunched.library()
        XCTAssertTrue(library.bookmarked.contains(place.id))
        XCTAssertTrue(library.visited.isEmpty, "Saving creates no visit")
        let own = try await relaunched.ownProfile()
        let me = try XCTUnwrap(own).id
        let profile = try await relaunched.publicProfile(userID: me)
        XCTAssertEqual(profile.wantCount, 1)
        XCTAssertEqual(profile.countryCount + profile.cityCount + profile.rankedCount, 0, "No geography or ranking effect")
        let removed = try await relaunched.setBookmark(experienceID: place.id, saved: false)
        XCTAssertFalse(removed)
    }

    func testOtherMembersListsAreReadableWithViewerState() async throws {
        let theo = try await signedIn("theo@roam.test")
        let mayaWant = try await theo.want(ownerID: Self.maya)
        XCTAssertFalse(mayaWant.isEmpty)
        // Viewer state reflects Theo, owner fields reflect Maya.
        let lagoon = try XCTUnwrap(mayaWant.first { $0.experience.name == "Glass Lagoon Baths" })
        XCTAssertNotNil(lagoon.savedAt)
        XCTAssertTrue(lagoon.experience.viewer.isBookmarked, "Theo also saved Glass Lagoon Baths")
    }

    func testMemberSearchIsCaseInsensitiveAndPaginates() async throws {
        let maya = try await signedIn("maya@roam.test")
        let page = try await maya.searchMembers(query: "THEO", cursor: nil)
        XCTAssertEqual(page.items.first?.member.handle, "theowanders")
        XCTAssertEqual(page.items.first?.isFollowing, true)
        let empty = try await maya.searchMembers(query: "zz-nobody-zz", cursor: nil)
        XCTAssertTrue(empty.items.isEmpty)
    }

    func testDetailShowsFactualMetadataAndMemories() async throws {
        let maya = try await signedIn("maya@roam.test")
        let lumen = try await maya.detail(experienceID: UUID(uuidString: "00000030-0000-4000-8000-000000000015")!)
        XCTAssertEqual(lumen.summary.name, "Lumen Street Hawker Hall")
        XCTAssertEqual(lumen.myVisits.count, 1, "Unranked memory retained")
        XCTAssertNil(lumen.myRating)
        XCTAssertNil(lumen.phone, "Unknown metadata is omitted, never invented")
    }
}
