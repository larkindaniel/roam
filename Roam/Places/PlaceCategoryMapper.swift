import Foundation
import MapKit

/// Suggests one of the seven categories from provider metadata. The first logger confirms it.
enum PlaceCategoryMapper {
    static func suggestedCategory(for poi: MKPointOfInterestCategory?, isLocality: Bool) -> ExperienceCategory? {
        if isLocality { return .dayTrips }
        guard let poi else { return nil }
        return table[poi]
    }

    static func suggestedCategory(rawProviderCategory: String?, isLocality: Bool) -> ExperienceCategory? {
        suggestedCategory(for: rawProviderCategory.map { MKPointOfInterestCategory(rawValue: $0) }, isLocality: isLocality)
    }

    /// MapKit point-of-interest categories used by Explore for each Roam category.
    static func pointOfInterestCategories(for category: ExperienceCategory) -> [MKPointOfInterestCategory] {
        table.filter { $0.value == category }.map(\.key).sorted { $0.rawValue < $1.rawValue }
    }

    private static let table: [MKPointOfInterestCategory: ExperienceCategory] = {
        var map: [MKPointOfInterestCategory: ExperienceCategory] = [:]
        for poi: MKPointOfInterestCategory in [.restaurant, .cafe, .bakery, .brewery, .winery, .foodMarket, .distillery] { map[poi] = .foodDrink }
        for poi: MKPointOfInterestCategory in [.park, .nationalPark, .beach, .hiking, .kayaking, .surfing, .skiing, .rockClimbing, .fishing, .swimming, .marina] { map[poi] = .outdoors }
        for poi: MKPointOfInterestCategory in [.museum, .theater, .library, .landmark, .castle, .fortress, .nationalMonument, .planetarium] { map[poi] = .culture }
        for poi: MKPointOfInterestCategory in [.nightlife, .musicVenue] { map[poi] = .nightlife }
        for poi: MKPointOfInterestCategory in [.amusementPark, .aquarium, .zoo, .stadium, .movieTheater, .bowling, .miniGolf, .goKart, .golf, .skatePark, .skating, .spa, .fairground, .tennis, .baseball, .basketball, .soccer, .volleyball] { map[poi] = .activities }
        for poi: MKPointOfInterestCategory in [.hotel, .campground, .rvPark] { map[poi] = .stays }
        return map
    }()
}
