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

    func testLocalityWithoutCountryCannotReuseIdenticalPOIFallback() async throws {
        let maya = try await signedIn("maya@roam.test")
        let token = UUID().uuidString.prefix(8)
        var poi = candidate(id: nil, name: "Unkeyed \(token)", address: "1 Identity Lane \(token)", lat: 21.125, lon: 44.25)
        poi.countryCode = nil
        poi.countryName = nil
        poi.region = nil
        poi.locality = nil
        var locality = poi
        locality.isLocality = true
        locality.suggestedCategory = .dayTrips
        XCTAssertFalse(PlaceIdentity.isSamePlace(poi, locality), "The client also keeps POI and unidentified locality kinds separate")
        XCTAssertNotEqual(poi.id, locality.id, "Mixed search results need separate enrichment keys for the POI and locality")

        let business = try await maya.resolve(poi)
        let before = try await maya.matches(for: [locality])
        XCTAssertTrue(before.isEmpty, "Matching a locality must never use the business address fallback")
        let destination = try await maya.resolve(locality)
        XCTAssertNotEqual(destination.id, business.id)
        XCTAssertEqual(destination.category, .dayTrips)
        let detail = try await maya.detail(experienceID: destination.id)
        XCTAssertTrue(detail.isLocality)
        let repeated = try await maya.resolve(locality)
        XCTAssertNotEqual(repeated.id, destination.id, "Without provider or canonical city identity, retain a distinct unresolved record")
        let after = try await maya.matches(for: [locality])
        XCTAssertTrue(after.isEmpty, "Resolving an unkeyed locality does not invent a canonical match")
        let poiMatch = try await maya.matches(for: [poi])
        XCTAssertEqual(poiMatch[poi.id]?.id, business.id)
        let batch = try await maya.matches(for: [poi, locality])
        XCTAssertEqual(batch[poi.id]?.id, business.id)
        XCTAssertNil(batch[locality.id], "POI enrichment cannot be reused for the locality in a mixed batch")
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

    func testMemberSearchIsCaseInsensitiveAndReturnsEmptyTerminalPages() async throws {
        let maya = try await signedIn("maya@roam.test")
        let page = try await maya.searchMembers(query: "THEO", cursor: nil)
        XCTAssertEqual(page.items.first?.member.handle, "theowanders")
        XCTAssertEqual(page.items.first?.friendState, .friends)
        let empty = try await maya.searchMembers(query: "zz-nobody-zz", cursor: nil)
        XCTAssertTrue(empty.items.isEmpty)
        XCTAssertNil(empty.nextCursor)
        let blank = try await maya.searchMembers(query: "   ", cursor: nil)
        XCTAssertTrue(blank.items.isEmpty)
        XCTAssertNil(blank.nextCursor)
    }

    func testMemberSearchTreatsHandleAndDisplayNameMetacharactersLiterally() async throws {
        // Namespaces isolate the test from previous integration runs without deleting their rows.
        let token = UUID().uuidString.prefix(8).lowercased()
        let query = "m3_\(token)_"
        let (viewer, _) = try await newMember(handlePrefix: "sv")
        let (target, _) = try await newMember(handlePrefix: query)
        let (collision, _) = try await newMember(handlePrefix: "sc\(token)")
        let targetOwn = try await target.ownProfile()
        let collisionOwn = try await collision.ownProfile()
        let targetProfile = try XCTUnwrap(targetOwn)
        let collisionProfile = try XCTUnwrap(collisionOwn)

        _ = try await collision.updateProfile(ProfileUpdate(
            displayName: "Test b\(query.replacingOccurrences(of: "_", with: "x"))member",
            handle: collisionProfile.handle, bio: "", homeCity: nil, avatarPath: nil))
        let handlePage = try await viewer.searchMembers(query: "  \(query.uppercased())  ", cursor: nil)
        XCTAssertEqual(handlePage.items.map(\.id), [targetProfile.id], "An underscore must also be literal in the display-name predicate")
        XCTAssertNil(handlePage.nextCursor)
        for suffix in ["%", "\\"] {
            let absent = try await viewer.searchMembers(query: query + suffix, cursor: nil)
            XCTAssertTrue(absent.items.isEmpty, "Handle queries must preserve \(suffix)")
            XCTAssertNil(absent.nextCursor)
        }

        let names = [
            ("Under\(token)_Member", "Under\(token)xMember"),
            ("Percent\(token)%Member", "Percent\(token)Member"),
            ("Slash\(token)\\Member", "Slash\(token)Member"),
            ("Mixed\(token)_\\%Member", "Mixed\(token)x%Member"),
        ]
        for (literal, lookalike) in names {
            _ = try await target.updateProfile(ProfileUpdate(displayName: literal, handle: targetProfile.handle,
                                                             bio: "", homeCity: nil, avatarPath: nil))
            _ = try await collision.updateProfile(ProfileUpdate(displayName: lookalike, handle: collisionProfile.handle,
                                                                bio: "", homeCity: nil, avatarPath: nil))
            let page = try await viewer.searchMembers(query: literal.uppercased(), cursor: nil)
            XCTAssertEqual(page.items.map(\.id), [targetProfile.id], "The query must match the literal display name: \(literal)")
            XCTAssertNil(page.nextCursor)
        }
    }

    func testMemberSearchPaginatesThirtyRowsWithoutGapsAndReplaysCursors() async throws {
        let query = "pg\(UUID().uuidString.prefix(8).lowercased())_"
        let (viewer, email) = try await newMember(handlePrefix: query)
        let viewerOwn = try await viewer.ownProfile()
        let viewerProfile = try XCTUnwrap(viewerOwn)
        var members: [OwnProfile] = []
        var firstMember: SupabaseBackend?
        for _ in 0..<35 {
            let (member, _) = try await newMember(handlePrefix: query)
            if firstMember == nil { firstMember = member }
            let memberOwn = try await member.ownProfile()
            members.append(try XCTUnwrap(memberOwn))
        }
        let followed = try XCTUnwrap(members.first)
        let followingMember = try XCTUnwrap(firstMember)
        try await befriend(followingMember, viewer)

        let expected = members.sorted { $0.handle < $1.handle }
        let first = try await viewer.searchMembers(query: query.uppercased(), cursor: nil)
        XCTAssertEqual(first.items.count, 30)
        XCTAssertEqual(first.items.map(\.id), expected.prefix(30).map(\.id))
        let cursor = try XCTUnwrap(first.nextCursor, "More than thirty matches must produce a second-page cursor")
        XCTAssertEqual(cursor, expected[29].handle)
        let second = try await viewer.searchMembers(query: query, cursor: cursor)
        XCTAssertEqual(second.items.count, 5)
        XCTAssertEqual(second.items.map(\.id), expected.suffix(5).map(\.id))
        XCTAssertNil(second.nextCursor)

        let combined = first.items + second.items
        XCTAssertEqual(Set(combined.map(\.id)).count, 35, "No duplicate or missing members across the page boundary")
        XCTAssertTrue(combined.allSatisfy { !$0.isSelf && $0.id != viewerProfile.id }, "Self is excluded before page slicing")
        let relationship = try XCTUnwrap(combined.first { $0.id == followed.id })
        XCTAssertEqual(relationship.friendState, .friends)

        // A fresh client and repeated requests exercise the persisted cursor contract, including refresh.
        let relaunched = try await signedIn(email, password: "integration-pass-123")
        let refreshed = try await relaunched.searchMembers(query: query, cursor: nil)
        XCTAssertEqual(refreshed, first)
        let retried = try await relaunched.searchMembers(query: query, cursor: cursor)
        XCTAssertEqual(retried, second)
        let terminal = try await relaunched.searchMembers(query: query, cursor: query + "zzzzzzzzz")
        XCTAssertTrue(terminal.items.isEmpty)
        XCTAssertNil(terminal.nextCursor)
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
