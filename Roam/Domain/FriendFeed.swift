import Foundation

/// The Friends tab's raw material: friends' visits you may see, newest logged first, and the countries you live in.
struct FriendsFeed: Codable, Hashable, Sendable {
    var myHomeCountries: [String]
    var visits: [FriendFeedVisit]
}

struct FriendFeedVisit: Codable, Hashable, Sendable {
    var author: MemberSummary
    var tripID: UUID?
    var tripName: String?
    /// The countries the author lives in.
    var homeCountries: [String]
    var entry: TripFeedEntry
}

/// One card on the Friends tab: a friend's trip, one city, or one country.
struct FriendFeedGroup: Hashable, Identifiable, Sendable {
    enum Kind: Hashable, Sendable {
        case trip(name: String)
        case city(name: String, countryCode: String?, countryName: String?)
        case country(code: String?, name: String?)
    }

    let id: String
    let author: MemberSummary
    let kind: Kind
    /// Every visit, latest visit first.
    let entries: [TripFeedEntry]

    /// Each place once, from its latest visit.
    var places: [TripFeedEntry] {
        var seen = Set<UUID>()
        return entries.filter { seen.insert($0.experience.id).inserted }
    }

    /// The card's three: their best-ranked places, then the latest.
    var preview: [TripFeedEntry] {
        Array(places.enumerated().sorted { a, b in
            switch (a.element.score, b.element.score) {
            case let (x?, y?) where x != y: return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.offset < b.offset
            }
        }.prefix(3).map(\.element))
    }

    var firstVisit: LocalDate? { entries.compactMap(\.visitDate.date).min() }
    var lastVisit: LocalDate? { entries.compactMap(\.visitDate.date).max() }
    /// When it last happened, for ordering cards: the latest visit date, else when it was logged.
    var latest: Date { lastVisit?.date() ?? entries.map(\.createdAt).max() ?? .distantPast }

    /// Its places by city, in the order they first went to each.
    var cities: [(name: String, countryCode: String?, countryName: String?, places: [TripFeedEntry])] {
        let ordered = places.sorted { a, b in
            guard let x = a.visitDate.date, let y = b.visitDate.date else { return a.visitDate.date != nil }
            return x < y
        }
        var order: [String] = []
        var byCity: [String: [TripFeedEntry]] = [:]
        for place in ordered {
            let key = FriendFeedGrouping.cityKey(place.experience)
            if byCity[key] == nil { order.append(key) }
            byCity[key, default: []].append(place)
        }
        return order.compactMap { key in
            guard let places = byCity[key], let first = places.first?.experience else { return nil }
            return (first.locality ?? first.countryName ?? "Elsewhere", first.countryCode, first.countryName, places)
        }
    }
}

/// How friends' visits become cards: a trip's visits stay together, even across countries; in a country either of you
/// lives in, each city is its own card; anywhere else it's one card per country, shown as its city when it's all one.
/// A visit logged without a date isn't on the Friends tab at all; everything else is in order of when it happened.
enum FriendFeedGrouping {
    static func groups(_ feed: FriendsFeed) -> [FriendFeedGroup] {
        let mine = Set(feed.myHomeCountries.map { $0.uppercased() })
        var order: [String] = []
        var buckets: [String: (author: MemberSummary, visits: [FriendFeedVisit])] = [:]
        for visit in feed.visits where visit.entry.visitDate.date != nil {
            let key = groupKey(visit, homes: mine)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: (visit.author, [])].visits.append(visit)
        }
        return order.compactMap { key -> FriendFeedGroup? in
            guard let bucket = buckets[key], let first = bucket.visits.first else { return nil }
            let entries = bucket.visits.map(\.entry).sorted(by: newer)
            return FriendFeedGroup(id: key, author: bucket.author, kind: kind(first, entries: entries), entries: entries)
        }
        .sorted { $0.latest > $1.latest }
    }

    static func cityKey(_ place: ExperienceSummary) -> String {
        "\(place.countryCode?.uppercased() ?? "-")|\(place.locality?.lowercased() ?? "-")"
    }

    private static func groupKey(_ visit: FriendFeedVisit, homes mine: Set<String>) -> String {
        let author = visit.author.id.uuidString
        if let trip = visit.tripID { return "\(author)|trip|\(trip)" }
        let place = visit.entry.experience
        let country = place.countryCode?.uppercased()
        let theirs = Set(visit.homeCountries.map { $0.uppercased() })
        if let country, mine.contains(country) || theirs.contains(country) {
            return "\(author)|city|\(cityKey(place))"
        }
        return "\(author)|country|\(country ?? "-")"
    }

    private static func kind(_ first: FriendFeedVisit, entries: [TripFeedEntry]) -> FriendFeedGroup.Kind {
        if first.tripID != nil { return .trip(name: first.tripName ?? "Trip") }
        let place = first.entry.experience
        let localities = Set(entries.map { $0.experience.locality?.lowercased() })
        if localities.count == 1, let city = place.locality, !city.isEmpty {
            return .city(name: city, countryCode: place.countryCode, countryName: place.countryName)
        }
        return .country(code: place.countryCode, name: place.countryName)
    }

    private static func newer(_ a: TripFeedEntry, _ b: TripFeedEntry) -> Bool {
        switch (a.visitDate.date, b.visitDate.date) {
        case let (x?, y?) where x != y: return x > y
        case (nil, _?): return false
        case (_?, nil): return true
        default: return a.createdAt > b.createdAt
        }
    }
}
