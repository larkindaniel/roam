import Contacts
import CoreLocation
import Foundation
import MapKit

/// Place provider used by every non-fixture build. Results always come from MapKit.
final class MapKitPlaceSearchProvider: PlaceSearchProviding, @unchecked Sendable {
    func searchPlaces(query: String, around destination: Destination?) async throws -> [PlaceCandidate] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.pointOfInterest, .address, .physicalFeature]
        if let destination {
            request.region = MKCoordinateRegion(center: destination.coordinate,
                                                latitudinalMeters: destination.radiusMeters * 2,
                                                longitudinalMeters: destination.radiusMeters * 2)
        } else if let nearby = await Self.nearbyRegion() {
            // Like Apple Maps: nearby matches first, with famous places elsewhere still found.
            request.region = nearby
        } else {
            // Without a region, results depend on device location and can come back empty.
            request.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
                                                span: MKCoordinateSpan(latitudeDelta: 140, longitudeDelta: 359))
        }
        let items = try await run(MKLocalSearch(request: request))
        // Towns and cities aren't places to log (they'd come out as Day Trips): they have their own city results and pages.
        return items.compactMap(Self.candidate(from:)).filter { !$0.isLocality }
    }

    @MainActor private static let locationManager = CLLocationManager()

    /// About 60 km around where you are, when Roam may use your location.
    @MainActor static func nearbyRegion() -> MKCoordinateRegion? {
        let status = locationManager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways, let location = locationManager.location else { return nil }
        return MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 60_000, longitudinalMeters: 60_000)
    }

    func searchDestinations(query: String) async throws -> [Destination] {
        let completer = await DestinationCompleter()
        let completions: [MKLocalSearchCompletion]
        do {
            completions = try await completer.completions(for: query)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw RoamError.server("Destination search is unavailable right now.")
        }
        // Resolve the top suggestions to coordinates and canonical region/country in parallel.
        let resolved = try await withThrowingTaskGroup(of: (Int, Destination?).self) { group in
            for (index, completion) in completions.prefix(6).enumerated() {
                group.addTask {
                    let request = MKLocalSearch.Request(completion: completion)
                    request.resultTypes = .address
                    let items = (try? await self.run(MKLocalSearch(request: request))) ?? []
                    return (index, items.first.flatMap(Self.destination(from:)))
                }
            }
            var found: [(Int, Destination)] = []
            for try await (index, destination) in group {
                if let destination { found.append((index, destination)) }
            }
            return found.sorted { $0.0 < $1.0 }.map(\.1)
        }
        var seen = Set<String>()
        return resolved.filter { seen.insert($0.id).inserted }
    }

    func pointsOfInterest(in region: MKCoordinateRegion, category: ExperienceCategory?) async throws -> [PlaceCandidate] {
        let request = MKLocalPointsOfInterestRequest(coordinateRegion: region)
        if let category {
            let pois = PlaceCategoryMapper.pointOfInterestCategories(for: category)
            if category == .dayTrips || pois.isEmpty { return [] }
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: pois)
        } else {
            let all = ExperienceCategory.allCases.flatMap(PlaceCategoryMapper.pointOfInterestCategories(for:))
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: all)
        }
        let items = try await run(MKLocalSearch(request: request))
        return items.compactMap(Self.candidate(from:))
    }

    func destination(for coordinate: CLLocationCoordinate2D) async throws -> Destination? {
        let placemarks = try await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        guard let placemark = placemarks.first, let locality = Self.town(placemark) else { return nil }
        return Destination(name: locality, region: placemark.administrativeArea, countryCode: placemark.isoCountryCode,
                           countryName: placemark.country, latitude: coordinate.latitude, longitude: coordinate.longitude,
                           radiusMeters: 12_000)
    }

    private func run(_ search: MKLocalSearch) async throws -> [MKMapItem] {
        try await withTaskCancellationHandler {
            do {
                return try await search.start().mapItems
            } catch let error as MKError where error.code == .placemarkNotFound {
                return []
            } catch {
                if Task.isCancelled { throw CancellationError() }
                throw RoamError.server("Place search is unavailable right now.")
            }
        } onCancel: {
            search.cancel()
        }
    }

    // MARK: - Mapping

    /// The town a place is in. Mountains and lakes out in the country have no locality, so they take their municipality
    /// ("Lom Municipality" → "Lom") instead.
    static func town(_ placemark: CLPlacemark) -> String? {
        if let locality = placemark.locality { return locality }
        guard var area = placemark.subAdministrativeArea else { return nil }
        for suffix in [" Municipality", " County", " District"] where area.hasSuffix(suffix) { area.removeLast(suffix.count) }
        return area
    }


    static func candidate(from item: MKMapItem) -> PlaceCandidate? {
        let placemark = item.placemark
        let coordinate = placemark.coordinate
        guard CLLocationCoordinate2DIsValid(coordinate), let name = item.name, !name.isEmpty else { return nil }
        let poi = item.pointOfInterestCategory
        let isStreetAddress = placemark.thoroughfare != nil || placemark.subThoroughfare != nil
        // A town only when the result is the town itself (its name is the locality's); an untyped result with some other
        // name is a natural feature, like a mountain ridge or a lake.
        let isLocality = poi == nil && !isStreetAddress && [placemark.locality, placemark.subAdministrativeArea, town(placemark)].contains { $0 == name }
        // A country, state or province is no place to log either, and not a mountain. Apple gives them a country but no
        // town or municipality (Ontario's state reads "ON"); huge features like Lake Superior or Everest have no country.
        let isRegion = poi == nil && !isStreetAddress && !isLocality
            && ([placemark.country, placemark.administrativeArea].contains { $0 == name }
                || (placemark.locality == nil && placemark.subAdministrativeArea == nil && placemark.country != nil))
        let isFeature = poi == nil && !isStreetAddress && !isLocality
        // Plain street addresses and regions are not experiences; MapKit POIs, physical features and localities are.
        if poi == nil && isStreetAddress || isRegion { return nil }
        return PlaceCandidate(
            provider: .mapkit,
            providerPlaceID: item.identifier?.rawValue,
            name: name,
            address: formattedAddress(placemark),
            locality: isLocality ? name : town(placemark),
            region: placemark.administrativeArea,
            countryCode: placemark.isoCountryCode,
            countryName: placemark.country,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            phone: item.phoneNumber,
            website: item.url,
            providerCategory: poi?.rawValue,
            timeZoneIdentifier: item.timeZone?.identifier,
            isLocality: isLocality,
            suggestedCategory: isFeature ? .outdoors : PlaceCategoryMapper.suggestedCategory(for: poi, isLocality: isLocality)
        )
    }

    static func destination(from item: MKMapItem) -> Destination? {
        let placemark = item.placemark
        guard let locality = placemark.locality ?? (placemark.thoroughfare == nil ? item.name : nil) else { return nil }
        guard placemark.thoroughfare == nil else { return nil }
        return Destination(name: locality, region: placemark.administrativeArea, countryCode: placemark.isoCountryCode,
                           countryName: placemark.country, latitude: placemark.coordinate.latitude,
                           longitude: placemark.coordinate.longitude, radiusMeters: 15_000)
    }

    static func formattedAddress(_ placemark: MKPlacemark) -> String? {
        if let postal = placemark.postalAddress {
            let lines = CNPostalAddressFormatter.string(from: postal, style: .mailingAddress)
                .split(whereSeparator: \.isNewline).map(String.init)
            let joined = lines.joined(separator: ", ")
            return joined.isEmpty ? nil : joined
        }
        let parts = [placemark.subThoroughfare, placemark.thoroughfare, placemark.locality, placemark.administrativeArea,
                     placemark.postalCode, placemark.country].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
