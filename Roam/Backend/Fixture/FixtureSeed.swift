#if ROAM_FIXTURES
import Foundation

/// Deterministic fictional seed data. Every person, place and note here is invented for Roam;
/// none comes from reference captures. Places sit at real-world coordinates so the globe,
/// geography counts and antimeridian handling can be exercised.
enum FixtureIDs {
    static func uuid(_ kind: Int, _ number: Int) -> UUID {
        UUID(uuidString: String(format: "%08d-0000-4000-8000-%012d", kind, number))!
    }

    static let maya = uuid(10, 1)
    static let theo = uuid(10, 2)
    static let priya = uuid(10, 3)
    static let jonas = uuid(10, 4)
    static let lena = uuid(10, 5)
    static let sam = uuid(10, 6)
    static let newcomer = uuid(10, 7)
}

struct FixturePlaceSeed {
    let key: String
    let name: String
    let category: ExperienceCategory?
    let address: String?
    let locality: String?
    let region: String?
    let countryCode: String
    let countryName: String
    let latitude: Double
    let longitude: Double
    let timeZone: String
    var phone: String? = nil
    var website: String? = nil
    var isLocality = false
    var providerCategory: String? = nil
}

struct FixtureMemberSeed {
    let id: UUID
    let handle: String
    let displayName: String
    let bio: String
    let email: String
    let homeCityKey: String?
    let joined: Date
}

/// (owner, place key, sentiment, group position within sentiment, visit date or nil, note, days ago published)
struct FixtureRatingSeed {
    let owner: UUID
    let place: String
    let sentiment: Sentiment
    let group: Int
    let visitDate: String?
    let note: String
    let publishedDaysAgo: Double
    var photos = 0
}

enum FixtureSeed {
    static let password = "roam-fixture-pass"

    static let referenceDate: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 13
        components.hour = 18
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    static func daysAgo(_ days: Double) -> Date { referenceDate.addingTimeInterval(-days * 86_400) }

    static let members: [FixtureMemberSeed] = [
        FixtureMemberSeed(id: FixtureIDs.maya, handle: "mayaroams", displayName: "Maya Chen",
                          bio: "Collecting quiet trails, harbour cafés and late jazz sets.", email: "maya@roam.test",
                          homeCityKey: "pt|lisboa|lisbon", joined: daysAgo(420)),
        FixtureMemberSeed(id: FixtureIDs.theo, handle: "theowanders", displayName: "Theo Park",
                          bio: "Slow travel, fast noodles.", email: "theo@roam.test", homeCityKey: nil, joined: daysAgo(380)),
        FixtureMemberSeed(id: FixtureIDs.priya, handle: "priyaplans", displayName: "Priya Nair",
                          bio: "Spreadsheets for every itinerary.", email: "priya@roam.test", homeCityKey: nil, joined: daysAgo(300)),
        FixtureMemberSeed(id: FixtureIDs.jonas, handle: "jonashikes", displayName: "Jonas Weber",
                          bio: "Ridge lines and mountain huts.", email: "jonas@roam.test", homeCityKey: nil, joined: daysAgo(250)),
        FixtureMemberSeed(id: FixtureIDs.lena, handle: "lenaeats", displayName: "Lena Ortiz",
                          bio: "", email: "lena@roam.test", homeCityKey: nil, joined: daysAgo(200)),
        FixtureMemberSeed(id: FixtureIDs.sam, handle: "samexplores", displayName: "Sam Rivera",
                          bio: "Weekend explorer.", email: "sam@roam.test", homeCityKey: nil, joined: daysAgo(120)),
    ]

    static let places: [FixturePlaceSeed] = [
        // One per category (SPEC R00 fixtures)
        FixturePlaceSeed(key: "harbor", name: "Harbor Lantern Café", category: .foodDrink, address: "12 Rua do Cais, Lisbon, Portugal",
                         locality: "Lisbon", region: "Lisboa", countryCode: "PT", countryName: "Portugal", latitude: 38.7072, longitude: -9.1366,
                         timeZone: "Europe/Lisbon", phone: "+351 21 000 0101", website: "https://example.com/harbor-lantern", providerCategory: "MKPOICategoryCafe"),
        FixturePlaceSeed(key: "cedar", name: "Cedar Ridge Trail", category: .outdoors, address: "Cedar Ridge Trailhead, Banff, AB, Canada",
                         locality: "Banff", region: "Alberta", countryCode: "CA", countryName: "Canada", latitude: 51.1801, longitude: -115.5653,
                         timeZone: "America/Edmonton", providerCategory: "MKPOICategoryHiking"),
        FixturePlaceSeed(key: "willow", name: "Willow Bay", category: .dayTrips, address: nil,
                         locality: "Willow Bay", region: "Wellington", countryCode: "NZ", countryName: "New Zealand", latitude: -41.2189, longitude: 174.9031,
                         timeZone: "Pacific/Auckland", isLocality: true),
        FixturePlaceSeed(key: "quay", name: "North Quay Gallery", category: .culture, address: "4 Nordkajen, Copenhagen, Denmark",
                         locality: "Copenhagen", region: "Capital Region", countryCode: "DK", countryName: "Denmark", latitude: 55.6879, longitude: 12.5986,
                         timeZone: "Europe/Copenhagen", website: "https://example.com/north-quay", providerCategory: "MKPOICategoryMuseum"),
        FixturePlaceSeed(key: "moonline", name: "Moonline Jazz Room", category: .nightlife, address: "3-8 Shibuya, Tokyo, Japan",
                         locality: "Tokyo", region: "Tokyo", countryCode: "JP", countryName: "Japan", latitude: 35.6597, longitude: 139.7006,
                         timeZone: "Asia/Tokyo", phone: "+81 3 0000 0202", providerCategory: "MKPOICategoryNightlife"),
        FixturePlaceSeed(key: "kite", name: "Blue Kite Workshop", category: .activities, address: "18 Bree Street, Cape Town, South Africa",
                         locality: "Cape Town", region: "Western Cape", countryCode: "ZA", countryName: "South Africa", latitude: -33.9206, longitude: 18.4187,
                         timeZone: "Africa/Johannesburg", providerCategory: "MKPOICategoryFairground"),
        FixturePlaceSeed(key: "aster", name: "Aster House", category: .stays, address: "55 Gion-machi, Kyoto, Japan",
                         locality: "Kyoto", region: "Kyoto", countryCode: "JP", countryName: "Japan", latitude: 35.0037, longitude: 135.7788,
                         timeZone: "Asia/Tokyo", website: "https://example.com/aster-house", providerCategory: "MKPOICategoryHotel"),
        // Supporting places for comparisons, geography edge cases and lists
        FixturePlaceSeed(key: "saltmarsh", name: "Saltmarsh Oyster Bar", category: .foodDrink, address: "88 Avenida Ribeira, Lisbon, Portugal",
                         locality: "Lisbon", region: "Lisboa", countryCode: "PT", countryName: "Portugal", latitude: 38.7101, longitude: -9.1432,
                         timeZone: "Europe/Lisbon", providerCategory: "MKPOICategoryRestaurant"),
        FixturePlaceSeed(key: "tidewater", name: "Tidewater Noodle House", category: .foodDrink, address: "2-1 Ebisu, Tokyo, Japan",
                         locality: "Tokyo", region: "Tokyo", countryCode: "JP", countryName: "Japan", latitude: 35.6467, longitude: 139.7101,
                         timeZone: "Asia/Tokyo", providerCategory: "MKPOICategoryRestaurant"),
        FixturePlaceSeed(key: "gull", name: "Gull & Pine Tavern", category: .foodDrink, address: "40 Fore Street, Portland, ME, United States",
                         locality: "Portland", region: "Maine", countryCode: "US", countryName: "United States", latitude: 43.6563, longitude: -70.2524,
                         timeZone: "America/New_York", providerCategory: "MKPOICategoryRestaurant"),
        FixturePlaceSeed(key: "rosebud", name: "Rosebud Supper Club", category: .nightlife, address: "711 SW Alder St, Portland, OR, United States",
                         locality: "Portland", region: "Oregon", countryCode: "US", countryName: "United States", latitude: 45.5202, longitude: -122.6806,
                         timeZone: "America/Los_Angeles", providerCategory: "MKPOICategoryNightlife"),
        FixturePlaceSeed(key: "lookout", name: "Lantern Hill Lookout", category: .outdoors, address: "Higashiyama Trail, Kyoto, Japan",
                         locality: "Kyoto", region: "Kyoto", countryCode: "JP", countryName: "Japan", latitude: 35.0097, longitude: 135.7952,
                         timeZone: "Asia/Tokyo", providerCategory: "MKPOICategoryPark"),
        FixturePlaceSeed(key: "fjord", name: "Ice Fjord Overlook", category: .outdoors, address: nil,
                         locality: nil, region: nil, countryCode: "GL", countryName: "Greenland", latitude: 69.1675, longitude: -50.9821,
                         timeZone: "America/Nuuk", providerCategory: "MKPOICategoryNationalPark"),
        FixturePlaceSeed(key: "coral", name: "Coral Rest Lodge", category: .stays, address: "Matei Road, Taveuni, Fiji",
                         locality: "Matei", region: "Northern", countryCode: "FJ", countryName: "Fiji", latitude: -16.6900, longitude: -179.8820,
                         timeZone: "Pacific/Fiji", providerCategory: "MKPOICategoryHotel"),
        FixturePlaceSeed(key: "lumen", name: "Lumen Street Hawker Hall", category: .foodDrink, address: "9 Lumen Street, Singapore",
                         locality: "Singapore", region: nil, countryCode: "SG", countryName: "Singapore", latitude: 1.2838, longitude: 103.8500,
                         timeZone: "Asia/Singapore", providerCategory: "MKPOICategoryFoodMarket"),
        FixturePlaceSeed(key: "fig", name: "Fig & Ember Bakery", category: .foodDrink, address: "21 Jægersborggade, Copenhagen, Denmark",
                         locality: "Copenhagen", region: "Capital Region", countryCode: "DK", countryName: "Denmark", latitude: 55.6925, longitude: 12.5450,
                         timeZone: "Europe/Copenhagen", providerCategory: "MKPOICategoryBakery"),
        FixturePlaceSeed(key: "lagoon", name: "Glass Lagoon Baths", category: .activities, address: "Lagoon Road, Reykjavík, Iceland",
                         locality: "Reykjavík", region: "Capital Region", countryCode: "IS", countryName: "Iceland", latitude: 64.1356, longitude: -21.8954,
                         timeZone: "Atlantic/Reykjavik", providerCategory: "MKPOICategorySpa"),
        FixturePlaceSeed(key: "juniper", name: "Juniper Peak Hut", category: .stays, address: "Juniper Track, Queenstown, New Zealand",
                         locality: "Queenstown", region: "Otago", countryCode: "NZ", countryName: "New Zealand", latitude: -45.0312, longitude: 168.6626,
                         timeZone: "Pacific/Auckland", providerCategory: "MKPOICategoryCampground"),
        FixturePlaceSeed(key: "mill", name: "Old Mill Cinema", category: .culture, address: "7 Mill Lane, Edinburgh, United Kingdom",
                         locality: "Edinburgh", region: "Scotland", countryCode: "GB", countryName: "United Kingdom", latitude: 55.9486, longitude: -3.1999,
                         timeZone: "Europe/London", providerCategory: "MKPOICategoryMovieTheater"),
        FixturePlaceSeed(key: "drift", name: "Driftwood Kayak Co.", category: .outdoors, address: "Harbour Quay, Wellington, New Zealand",
                         locality: "Wellington", region: "Wellington", countryCode: "NZ", countryName: "New Zealand", latitude: -41.2865, longitude: 174.7762,
                         timeZone: "Pacific/Auckland", providerCategory: "MKPOICategoryKayaking"),
        FixturePlaceSeed(key: "terrace", name: "Terrace Steps Café", category: nil, address: "3 Escadinhas, Lisbon, Portugal",
                         locality: "Lisbon", region: "Lisboa", countryCode: "PT", countryName: "Portugal", latitude: 38.7139, longitude: -9.1334,
                         timeZone: "Europe/Lisbon", providerCategory: "MKPOICategoryCafe"),
    ]

    /// Ratings with one dated visit each. Group numbers order tie groups within a sentiment
    /// (equal numbers are ties).
    static let ratings: [FixtureRatingSeed] = [
        // Maya — Food & Drink: liked [harbor] [saltmarsh], fine [tidewater], disliked [gull]
        FixtureRatingSeed(owner: FixtureIDs.maya, place: "harbor", sentiment: .liked, group: 0, visitDate: "2026-06-14",
                          note: "Custard tarts and a lantern-lit terrace over the water. Go just before sunset.", publishedDaysAgo: 2.2, photos: 2),
        FixtureRatingSeed(owner: FixtureIDs.maya, place: "saltmarsh", sentiment: .liked, group: 1, visitDate: "2026-06-15",
                          note: "", publishedDaysAgo: 30),
        FixtureRatingSeed(owner: FixtureIDs.maya, place: "tidewater", sentiment: .fine, group: 0, visitDate: "2025-11-02",
                          note: "Solid broth, long queue.", publishedDaysAgo: 200),
        FixtureRatingSeed(owner: FixtureIDs.maya, place: "gull", sentiment: .disliked, group: 0, visitDate: "2024-08-20",
                          note: "", publishedDaysAgo: 400),
        // Maya — Outdoors: liked tie [cedar, fjord], fine [lookout]
        FixtureRatingSeed(owner: FixtureIDs.maya, place: "cedar", sentiment: .liked, group: 0, visitDate: "2026-08-03",
                          note: "Larches turning gold near the top. Bring layers.", publishedDaysAgo: 5, photos: 1),
        FixtureRatingSeed(owner: FixtureIDs.maya, place: "fjord", sentiment: .liked, group: 0, visitDate: nil,
                          note: "Icebergs the size of city blocks.", publishedDaysAgo: 150),
        FixtureRatingSeed(owner: FixtureIDs.maya, place: "lookout", sentiment: .fine, group: 0, visitDate: "2025-04-09",
                          note: "", publishedDaysAgo: 180),
        // Maya — one each elsewhere
        FixtureRatingSeed(owner: FixtureIDs.maya, place: "willow", sentiment: .liked, group: 0, visitDate: "2026-02-21",
                          note: "Ferry over, picnic on the point, back by dusk.", publishedDaysAgo: 60),
        FixtureRatingSeed(owner: FixtureIDs.maya, place: "quay", sentiment: .liked, group: 0, visitDate: "2026-09-12",
                          note: "", publishedDaysAgo: 12),
        FixtureRatingSeed(owner: FixtureIDs.maya, place: "rosebud", sentiment: .liked, group: 0, visitDate: "2025-07-19",
                          note: "", publishedDaysAgo: 250),
        FixtureRatingSeed(owner: FixtureIDs.maya, place: "moonline", sentiment: .fine, group: 0, visitDate: "2026-03-30",
                          note: "Great trio, cramped room.", publishedDaysAgo: 90),
        FixtureRatingSeed(owner: FixtureIDs.maya, place: "kite", sentiment: .disliked, group: 0, visitDate: "2025-12-28",
                          note: "", publishedDaysAgo: 100),
        FixtureRatingSeed(owner: FixtureIDs.maya, place: "aster", sentiment: .liked, group: 0, visitDate: "2026-04-02",
                          note: "Paper lanterns, cedar bath, the quietest night of the trip.", publishedDaysAgo: 80),
        FixtureRatingSeed(owner: FixtureIDs.maya, place: "coral", sentiment: .liked, group: 1, visitDate: "2023-05-10",
                          note: "", publishedDaysAgo: 700),
        // Theo
        FixtureRatingSeed(owner: FixtureIDs.theo, place: "harbor", sentiment: .liked, group: 0, visitDate: "2026-09-30",
                          note: "Maya was right about the tarts.", publishedDaysAgo: 1.1, photos: 1),
        FixtureRatingSeed(owner: FixtureIDs.theo, place: "fig", sentiment: .liked, group: 1, visitDate: "2026-08-21",
                          note: "Cardamom buns worth the cycle.", publishedDaysAgo: 3.5),
        FixtureRatingSeed(owner: FixtureIDs.theo, place: "moonline", sentiment: .liked, group: 0, visitDate: "2026-07-07",
                          note: "", publishedDaysAgo: 20),
        // Jonas
        FixtureRatingSeed(owner: FixtureIDs.jonas, place: "cedar", sentiment: .liked, group: 0, visitDate: "2026-09-01",
                          note: "Sunrise start, empty summit.", publishedDaysAgo: 0.6),
        FixtureRatingSeed(owner: FixtureIDs.jonas, place: "harbor", sentiment: .fine, group: 0, visitDate: "2026-05-05",
                          note: "", publishedDaysAgo: 40),
        // Lena and Priya
        FixtureRatingSeed(owner: FixtureIDs.lena, place: "quay", sentiment: .liked, group: 0, visitDate: "2026-09-20",
                          note: "The tide-pool room alone is worth it.", publishedDaysAgo: 4),
        FixtureRatingSeed(owner: FixtureIDs.priya, place: "aster", sentiment: .liked, group: 0, visitDate: "2026-04-11",
                          note: "", publishedDaysAgo: 70),
        FixtureRatingSeed(owner: FixtureIDs.sam, place: "drift", sentiment: .liked, group: 0, visitDate: "2026-01-15",
                          note: "Paddled past seals.", publishedDaysAgo: 9),
    ]

    /// Unranked retained memory (rating removed earlier, visit kept).
    static let unrankedVisits: [(owner: UUID, place: String, date: String?, note: String)] = [
        (FixtureIDs.maya, "lumen", "2026-01-08", "Laksa stall #14."),
    ]

    /// Repeat visits under an existing rating.
    static let repeatVisits: [(owner: UUID, place: String, date: String, note: String, publishedDaysAgo: Double)] = [
        (FixtureIDs.maya, "harbor", "2026-09-28", "Back again: still the best terrace in town.", 0.9),
    ]

    static let bookmarks: [(owner: UUID, place: String, savedDaysAgo: Double)] = [
        (FixtureIDs.maya, "lagoon", 3), (FixtureIDs.maya, "juniper", 10), (FixtureIDs.maya, "fig", 25),
        (FixtureIDs.theo, "lagoon", 2), (FixtureIDs.theo, "juniper", 6), (FixtureIDs.theo, "mill", 8),
        (FixtureIDs.jonas, "juniper", 4),
    ]

    /// follower → followee
    static let follows: [(UUID, UUID)] = [
        (FixtureIDs.maya, FixtureIDs.theo), (FixtureIDs.theo, FixtureIDs.maya),
        (FixtureIDs.maya, FixtureIDs.jonas),
        (FixtureIDs.lena, FixtureIDs.maya),
        (FixtureIDs.sam, FixtureIDs.maya),
    ]
}
#endif
