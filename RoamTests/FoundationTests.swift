import MapKit
import XCTest
@testable import Roam

final class GeographyTests: XCTestCase {
    func testSameNameCitiesHaveDistinctKeys() {
        let oregon = GeographyKey.cityKey(countryCode: "US", region: "Oregon", locality: "Portland")
        let maine = GeographyKey.cityKey(countryCode: "US", region: "Maine", locality: "Portland")
        XCTAssertNotNil(oregon)
        XCTAssertNotEqual(oregon, maine)
        XCTAssertEqual(oregon, "us|oregon|portland")
    }

    func testRemotePlaceWithoutLocalityHasNoCity() {
        XCTAssertNil(GeographyKey.cityKey(countryCode: "GL", region: nil, locality: nil))
        XCTAssertNil(GeographyKey.cityKey(countryCode: nil, region: "Otago", locality: "Queenstown"))
    }

    func testNormalizationFoldsCaseAccentsAndPunctuation() {
        XCTAssertEqual(GeographyKey.normalize("  Reykjavík,  Capital Region "), "reykjavik capital region")
        XCTAssertEqual(GeographyKey.normalize("Fig & Ember"), "fig ember")
    }
}

final class PlaceIdentityTests: XCTestCase {
    private func candidate(_ name: String, address: String?, lat: Double, lon: Double, id: String? = nil) -> PlaceCandidate {
        PlaceCandidate(provider: .mapkit, providerPlaceID: id, name: name, address: address, locality: "Lisbon", region: nil,
                       countryCode: "PT", countryName: "Portugal", latitude: lat, longitude: lon, phone: nil, website: nil,
                       providerCategory: nil, timeZoneIdentifier: nil, isLocality: false, suggestedCategory: .foodDrink)
    }

    func testProviderIdentifierDecidesIdentity() {
        let a = candidate("Café A", address: "1 Rua", lat: 1, lon: 1, id: "I1")
        let renamed = candidate("Café A (renamed)", address: "1 Rua", lat: 1.0001, lon: 1, id: "I1")
        let other = candidate("Café A", address: "1 Rua", lat: 1, lon: 1, id: "I2")
        XCTAssertTrue(PlaceIdentity.isSamePlace(a, renamed))
        XCTAssertFalse(PlaceIdentity.isSamePlace(a, other))
    }

    func testSameNameDifferentAddressNeverMerges() {
        let first = candidate("Morning Tide Bakery", address: "5 Rua Nova, Lisbon", lat: 38.7110, lon: -9.1400)
        let second = candidate("Morning Tide Bakery", address: "77 Rua Velha, Lisbon", lat: 38.7201, lon: -9.1502)
        XCTAssertFalse(PlaceIdentity.isSamePlace(first, second))
    }

    func testFallbackRequiresExactNormalizedNameAddressAndSixDecimalCoordinate() {
        let first = candidate("Morning Tide Bakery", address: "5 Rua Nova, Lisbon", lat: 38.7110001, lon: -9.1400004)
        let same = candidate("morning tide  bakery", address: "5 rua nova lisbon", lat: 38.7109999, lon: -9.1399996)
        let moved = candidate("Morning Tide Bakery", address: "5 Rua Nova, Lisbon", lat: 38.711002, lon: -9.14)
        XCTAssertTrue(PlaceIdentity.isSamePlace(first, same))
        XCTAssertFalse(PlaceIdentity.isSamePlace(first, moved))
    }

    func testNameAloneIsNeverEnough() {
        let noAddress = candidate("Harbor", address: nil, lat: 1, lon: 1)
        XCTAssertFalse(PlaceIdentity.isSamePlace(noAddress, noAddress))
    }
}

final class CountryGeometryTests: XCTestCase {
    private let geometry = CountryGeometry(bundle: Bundle(for: AppServices.self))

    func testBundledGeometryUsesISOCodesIncludingFranceAndNorway() {
        XCTAssertNotNil(geometry.shape(for: "FR"), "ISO_A2_EH mapping must give France a code")
        XCTAssertNotNil(geometry.shape(for: "NO"))
        XCTAssertGreaterThan(geometry.allCodes.count, 170)
    }

    func testMissingSmallCountryGeometryReturnsNoShading() {
        // Singapore is below 1:110m resolution: pins still render, but no country is shaded.
        XCTAssertNil(geometry.shape(for: "SG"))
        XCTAssertTrue(geometry.polygons(for: ["SG"]).isEmpty)
    }

    func testAntimeridianCountriesAreSplitNotWrapped() throws {
        for code in ["FJ", "RU", "US"] {
            let shape = try XCTUnwrap(geometry.shape(for: code), code)
            for polygon in shape.polygons {
                XCTAssertLessThan(CountryGeometry.longitudeSpan(of: polygon), 180, "\(code) ring wraps across the globe")
            }
        }
        let fiji = try XCTUnwrap(geometry.shape(for: "FJ"))
        let longitudes = fiji.polygons.flatMap { polygon in
            (0..<polygon.pointCount).map { polygon.points()[$0].coordinate.longitude }
        }
        XCTAssertTrue(longitudes.contains { $0 > 170 } && longitudes.contains { $0 < -170 }, "Fiji has rings on both sides of 180°")
    }

    func testGlobePinSelectionAcrossAntimeridianUsesAnnotationIdentity() {
        let east = GlobePin(experienceID: UUID(), name: "East", category: .stays, latitude: -16.7, longitude: 179.9, countryCode: "FJ", cityKey: nil)
        let west = GlobePin(experienceID: UUID(), name: "West", category: .stays, latitude: -16.7, longitude: -179.9, countryCode: "FJ", cityKey: nil)
        let annotations = [east, west].map(ExperiencePinAnnotation.init(pin:))
        XCTAssertEqual(annotations.map(\.pin.id), [east.id, west.id])
        XCTAssertNotEqual(annotations[0].coordinate.longitude, annotations[1].coordinate.longitude)
    }
}

final class ValidationTests: XCTestCase {
    func testHandleRules() {
        XCTAssertNil(Validation.handle("maya_roams1"))
        XCTAssertEqual(Validation.handle("ab"), .tooShort(minimum: 3))
        XCTAssertEqual(Validation.handle(String(repeating: "a", count: 21)), .tooLong(maximum: 20))
        XCTAssertEqual(Validation.handle("Maya"), .invalidCharacters)
        XCTAssertEqual(Validation.handle("maya.roams"), .invalidCharacters)
        XCTAssertEqual(Validation.handle("mayá"), .invalidCharacters)
    }

    func testPasswordLengthOnlyRules() {
        XCTAssertEqual(Validation.password("short"), .tooShort(minimum: 12))
        XCTAssertNil(Validation.password("twelve chars"))
        XCTAssertNil(Validation.password("alllowercaseletters"))
        XCTAssertEqual(Validation.password(String(repeating: "x", count: 129)), .tooLong(maximum: 128))
    }

    func testTextLimits() {
        XCTAssertNil(Validation.displayName("M"))
        XCTAssertEqual(Validation.displayName("   "), .required)
        XCTAssertNotNil(Validation.bio(String(repeating: "b", count: 161)))
        XCTAssertNil(Validation.publicNote(String(repeating: "n", count: 5_000)))
        XCTAssertNotNil(Validation.publicNote(String(repeating: "n", count: 5_001)))
        XCTAssertNotNil(Validation.privateNote(String(repeating: "p", count: 10_001)))
        XCTAssertEqual(Validation.comment(" \n "), .required)
        XCTAssertNotNil(Validation.comment(String(repeating: "c", count: 2_001)))
    }

    func testFutureCompletedVisitIsRejectedButTodayAndUnknownAllowed() {
        let today = LocalDate(year: 2026, month: 10, day: 13)!
        XCTAssertNil(Validation.visitDate(today, today: today))
        XCTAssertNil(Validation.visitDate(nil, today: today))
        XCTAssertEqual(Validation.visitDate(today.adding(days: 1), today: today), .futureDate)
    }
}

final class LocalDateTests: XCTestCase {
    func testDateOnlyDoesNotShiftAcrossTimeZones() throws {
        // 23:30 in Tokyo on Oct 13 is still Oct 13 there, even though it's Oct 13 14:30 UTC.
        let tokyo = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-13T14:30:00Z"))
        XCTAssertEqual(LocalDate(date: instant, timeZone: tokyo).isoString, "2026-10-13")
        let honolulu = try XCTUnwrap(TimeZone(identifier: "Pacific/Honolulu"))
        XCTAssertEqual(LocalDate(date: instant, timeZone: honolulu).isoString, "2026-10-13")
        let lateTokyo = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-13T15:30:00Z"))
        XCTAssertEqual(LocalDate(date: lateTokyo, timeZone: tokyo).isoString, "2026-10-14")
    }

    func testRoundTripAndInvalidDates() {
        XCTAssertEqual(LocalDate(isoString: "2026-02-28")?.adding(days: 1).isoString, "2026-03-01")
        XCTAssertNil(LocalDate(isoString: "2026-02-30"))
        XCTAssertNil(LocalDate(isoString: "yesterday"))
    }
}

final class JSONDecodingTests: XCTestCase {
    func testPostgresTimestampsWithMicroseconds() throws {
        let date = try XCTUnwrap(RoamJSON.parseDate("2026-10-14T01:34:48.601868+00:00"))
        XCTAssertEqual(date.timeIntervalSince1970, 1_791_941_688.601, accuracy: 0.001)
        XCTAssertNotNil(RoamJSON.parseDate("2026-10-14T01:34:48Z"))
        XCTAssertNotNil(RoamJSON.parseDate("2026-10-14 01:34:48.6+00"))
        XCTAssertNil(RoamJSON.parseDate("not a date"))
    }

    func testScoreDecodesFromNumericAndString() throws {
        struct Wrapper: Decodable { let score: Score }
        let fromNumber = try JSONDecoder().decode(Wrapper.self, from: Data(#"{"score": 8.4}"#.utf8))
        let fromString = try JSONDecoder().decode(Wrapper.self, from: Data(#"{"score": "6.7"}"#.utf8))
        XCTAssertEqual(fromNumber.score.tenths, 84)
        XCTAssertEqual(fromString.score.tenths, 67)
        XCTAssertThrowsError(try JSONDecoder().decode(Wrapper.self, from: Data(#"{"score": 10.5}"#.utf8)))
    }
}

final class PlaceCategoryMapperTests: XCTestCase {
    func testSuggestionsCoverEachCategory() {
        XCTAssertEqual(PlaceCategoryMapper.suggestedCategory(for: .cafe, isLocality: false), .foodDrink)
        XCTAssertEqual(PlaceCategoryMapper.suggestedCategory(for: .hiking, isLocality: false), .outdoors)
        XCTAssertEqual(PlaceCategoryMapper.suggestedCategory(for: nil, isLocality: true), .dayTrips)
        XCTAssertEqual(PlaceCategoryMapper.suggestedCategory(for: .museum, isLocality: false), .culture)
        XCTAssertEqual(PlaceCategoryMapper.suggestedCategory(for: .nightlife, isLocality: false), .nightlife)
        XCTAssertEqual(PlaceCategoryMapper.suggestedCategory(for: .aquarium, isLocality: false), .activities)
        XCTAssertEqual(PlaceCategoryMapper.suggestedCategory(for: .hotel, isLocality: false), .stays)
        XCTAssertNil(PlaceCategoryMapper.suggestedCategory(for: .bank, isLocality: false), "Unsupported POIs stay uncategorized")
    }

    func testEveryCategoryExceptDayTripsHasExplorePOIs() {
        for category in ExperienceCategory.allCases where category != .dayTrips {
            XCTAssertFalse(PlaceCategoryMapper.pointOfInterestCategories(for: category).isEmpty, category.title)
        }
    }
}

final class LocalityIdentityTests: XCTestCase {
    private func locality(_ name: String, region: String, country: String) -> PlaceCandidate {
        PlaceCandidate(provider: .mapkit, providerPlaceID: nil, name: name, address: nil, locality: name, region: region,
                       countryCode: country, countryName: nil, latitude: 35.2, longitude: 139.0, phone: nil, website: nil,
                       providerCategory: nil, timeZoneIdentifier: nil, isLocality: true, suggestedCategory: .dayTrips)
    }

    func testLocalitiesWithoutIdentifiersDedupeByCanonicalCityKey() {
        XCTAssertTrue(PlaceIdentity.isSamePlace(locality("Hakone", region: "Kanagawa", country: "JP"),
                                                locality("Hakone", region: "Kanagawa", country: "JP")))
        XCTAssertFalse(PlaceIdentity.isSamePlace(locality("Portland", region: "Oregon", country: "US"),
                                                 locality("Portland", region: "Maine", country: "US")))
    }
}
