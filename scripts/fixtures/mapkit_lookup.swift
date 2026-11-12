// Looks places up in Apple Maps the way the app does (MapKitPlaceSearchProvider) and prints the place candidate the app
// would send to resolve_place, so seeded places are the same places people find in search.
//
// Input on stdin: a JSON array of {"id", "q", "city"} where city reads "Town, Country", searched near that city; with
// "kind": "city", q itself is looked up as a city instead. Output on stdout: a JSON object
// keyed by id, with the candidate or null when nothing usable was found. Runs on macOS 15 or later:
//   swift scripts/fixtures/mapkit_lookup.swift < queries.json > candidates.json
import Contacts
import CoreLocation
import Foundation
import MapKit

struct Query: Decodable { let id: String; let q: String; let city: String; let kind: String? }

/// A city the way the app's destination search returns one (MapKitPlaceSearchProvider.destination(from:)).
func destination(_ item: MKMapItem) -> [String: Any]? {
    let placemark = item.placemark
    guard placemark.thoroughfare == nil, let name = placemark.locality ?? item.name else { return nil }
    var out: [String: Any] = ["name": name, "latitude": placemark.coordinate.latitude, "longitude": placemark.coordinate.longitude]
    out["region"] = placemark.administrativeArea
    out["countryCode"] = placemark.isoCountryCode
    out["countryName"] = placemark.country
    return out
}

// Kept in step with Roam/Places/PlaceCategoryMapper.swift.
let categories: [MKPointOfInterestCategory: String] = {
    var map: [MKPointOfInterestCategory: String] = [:]
    for poi: MKPointOfInterestCategory in [.restaurant, .cafe, .bakery, .brewery, .winery, .foodMarket, .distillery] { map[poi] = "food_drink" }
    for poi: MKPointOfInterestCategory in [.park, .nationalPark, .beach, .hiking, .kayaking, .surfing, .skiing, .rockClimbing, .fishing, .swimming, .marina] { map[poi] = "outdoors" }
    for poi: MKPointOfInterestCategory in [.museum, .theater, .library, .landmark, .castle, .fortress, .nationalMonument, .planetarium] { map[poi] = "culture" }
    for poi: MKPointOfInterestCategory in [.nightlife, .musicVenue] { map[poi] = "nightlife" }
    for poi: MKPointOfInterestCategory in [.amusementPark, .aquarium, .zoo, .stadium, .movieTheater, .bowling, .miniGolf, .goKart, .golf, .skatePark, .skating, .spa, .fairground, .tennis, .baseball, .basketball, .soccer, .volleyball] { map[poi] = "activities" }
    for poi: MKPointOfInterestCategory in [.hotel, .campground, .rvPark] { map[poi] = "stays" }
    return map
}()

func town(_ placemark: CLPlacemark) -> String? {
    if let locality = placemark.locality { return locality }
    guard var area = placemark.subAdministrativeArea else { return nil }
    for suffix in [" Municipality", " County", " District"] where area.hasSuffix(suffix) { area.removeLast(suffix.count) }
    return area
}

func formattedAddress(_ placemark: MKPlacemark) -> String? {
    if let postal = placemark.postalAddress {
        let joined = CNPostalAddressFormatter.string(from: postal, style: .mailingAddress)
            .split(whereSeparator: \.isNewline).map(String.init).joined(separator: ", ")
        return joined.isEmpty ? nil : joined
    }
    let parts = [placemark.subThoroughfare, placemark.thoroughfare, placemark.locality, placemark.administrativeArea,
                 placemark.postalCode, placemark.country].compactMap { $0 }
    return parts.isEmpty ? nil : parts.joined(separator: ", ")
}

/// The same rules as MapKitPlaceSearchProvider.candidate(from:); towns are dropped like search does.
/// Whether a result's name shares a word with what was searched for ("Kongens Have" → "Kongens Have").
func nameMatches(_ name: String, _ query: String) -> Bool {
    func words(_ text: String) -> Set<String> {
        Set(text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 4 })
    }
    return !words(name).isDisjoint(with: words(query))
}

/// On macOS, Apple Maps often leaves a place's type empty, so a park reads as its street address and the app's rule would
/// drop it. Such a result is kept when it has Apple's place identifier and its name matches the search.
func candidate(_ item: MKMapItem, query: String) -> [String: Any]? {
    let placemark = item.placemark
    let coordinate = placemark.coordinate
    guard CLLocationCoordinate2DIsValid(coordinate), let name = item.name, !name.isEmpty else { return nil }
    let poi = item.pointOfInterestCategory
    let isStreetAddress = placemark.thoroughfare != nil || placemark.subThoroughfare != nil
    let isLocality = poi == nil && !isStreetAddress && [placemark.locality, placemark.subAdministrativeArea, town(placemark)].contains { $0 == name }
    let isRegion = poi == nil && !isStreetAddress && !isLocality
        && ([placemark.country, placemark.administrativeArea].contains { $0 == name }
            || (placemark.locality == nil && placemark.subAdministrativeArea == nil && placemark.country != nil))
    let isFeature = poi == nil && !isStreetAddress && !isLocality
    let untypedButNamed = poi == nil && isStreetAddress && item.identifier != nil && nameMatches(name, query)
    if poi == nil && isStreetAddress && !untypedButNamed || isRegion || isLocality { return nil }
    var out: [String: Any] = ["provider": "mapkit", "name": name, "latitude": coordinate.latitude, "longitude": coordinate.longitude,
                              "isLocality": false]
    out["providerPlaceID"] = item.identifier?.rawValue
    out["address"] = formattedAddress(placemark)
    out["locality"] = town(placemark)
    out["region"] = placemark.administrativeArea
    out["countryCode"] = placemark.isoCountryCode
    out["countryName"] = placemark.country
    out["phone"] = item.phoneNumber
    out["website"] = item.url?.absoluteString
    out["providerCategory"] = poi?.rawValue
    out["timeZoneIdentifier"] = item.timeZone?.identifier
    out["suggestedCategory"] = isFeature && !untypedButNamed ? "outdoors" : poi.flatMap { categories[$0] }
    return out
}

func search(_ request: MKLocalSearch.Request) async -> [MKMapItem] {
    for attempt in 0..<3 {
        do { return try await MKLocalSearch(request: request).start().mapItems } catch {
            // Apple throttles bursts of searches (about 50 a minute); wait and try again. "Not found" is not retried.
            if (error as? MKError)?.code == .placemarkNotFound { return [] }
            FileHandle.standardError.write("  retrying \(request.naturalLanguageQuery ?? ""): \(error.localizedDescription)\n".data(using: .utf8)!)
            try? await Task.sleep(for: .seconds(15 * (attempt + 1)))
        }
    }
    return []
}

nonisolated(unsafe) var cityCenters: [String: CLLocationCoordinate2D] = [:]
func center(of city: String) async -> CLLocationCoordinate2D? {
    if let known = cityCenters[city] { return known }
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = city
    request.resultTypes = [.address, .physicalFeature]
    let found = await search(request).first?.placemark.coordinate
    cityCenters[city] = found
    return found
}

let queries = try JSONDecoder().decode([Query].self, from: FileHandle.standardInput.readDataToEndOfFile())
var results: [String: Any] = [:]
for query in queries {
    if query.kind == "city" {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query.q
        request.resultTypes = .address
        let found = await search(request).lazy.compactMap(destination).first
        results[query.id] = found ?? NSNull()
        FileHandle.standardError.write("\(query.id): \(found?["name"] ?? "—"), \(found?["region"] ?? "") \(found?["countryCode"] ?? "")\n".data(using: .utf8)!)
        try? await Task.sleep(for: .milliseconds(1300))
        continue
    }
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = query.q
    request.resultTypes = [.pointOfInterest, .physicalFeature, .address]
    let cityCenter = await center(of: query.city)
    if let cityCenter {
        request.region = MKCoordinateRegion(center: cityCenter, latitudinalMeters: 60_000, longitudinalMeters: 60_000)
    }
    var found = await search(request).lazy.compactMap { candidate($0, query: query.q) }.first
    // How far the match is from the city it was listed under, so wrong-town matches stand out.
    var km = -1
    if let cityCenter, let place = found, let lat = place["latitude"] as? Double, let lon = place["longitude"] as? Double {
        km = Int(CLLocation(latitude: lat, longitude: lon).distance(from: CLLocation(latitude: cityCenter.latitude, longitude: cityCenter.longitude)) / 1000)
        found?["distanceKm"] = km
    }
    results[query.id] = found ?? NSNull()
    FileHandle.standardError.write("\(query.id): \(found?["name"] ?? "—") · \(found?["locality"] ?? "") \(found?["countryCode"] ?? "") [\(found?["suggestedCategory"] ?? "?")] \(km)km\n".data(using: .utf8)!)
    try? await Task.sleep(for: .milliseconds(1300))
}
let data = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(data)
