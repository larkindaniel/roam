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
        }
        let items = try await run(MKLocalSearch(request: request))
        return items.compactMap(Self.candidate(from:))
    }

    func searchDestinations(query: String) async throws -> [Destination] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address]
        let items = try await run(MKLocalSearch(request: request))
        var seen = Set<String>()
        return items.compactMap(Self.destination(from:)).filter { seen.insert($0.id).inserted }
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
        guard let placemark = placemarks.first, let locality = placemark.locality ?? placemark.subAdministrativeArea else { return nil }
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

    static func candidate(from item: MKMapItem) -> PlaceCandidate? {
        let placemark = item.placemark
        let coordinate = placemark.coordinate
        guard CLLocationCoordinate2DIsValid(coordinate), let name = item.name, !name.isEmpty else { return nil }
        let poi = item.pointOfInterestCategory
        let isStreetAddress = placemark.thoroughfare != nil || placemark.subThoroughfare != nil
        let isLocality = poi == nil && !isStreetAddress && (placemark.locality != nil || placemark.subAdministrativeArea != nil)
        // Plain street addresses are not experiences; MapKit POIs, physical features and localities are.
        if poi == nil && isStreetAddress { return nil }
        return PlaceCandidate(
            provider: .mapkit,
            providerPlaceID: item.identifier?.rawValue,
            name: name,
            address: formattedAddress(placemark),
            locality: placemark.locality ?? (isLocality ? name : nil),
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
            suggestedCategory: PlaceCategoryMapper.suggestedCategory(for: poi, isLocality: isLocality)
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
