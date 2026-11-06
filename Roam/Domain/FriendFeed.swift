import Foundation

/// One of a friend's visits you may see, for the Friends tab.
struct FriendFeedVisit: Codable, Hashable, Sendable {
    var author: MemberSummary
    var entry: TripFeedEntry
}

/// One card on the Friends tab: a friend's places in one city.
struct FriendFeedGroup: Hashable, Identifiable, Sendable {
    let id: String
    let author: MemberSummary
    let city: String
    let region: String?
    let countryCode: String?
    let countryName: String?
    /// Every visit, latest visit first.
    let entries: [TripFeedEntry]

    /// Each place once, from its latest visit.
    var places: [TripFeedEntry] {
        var seen = Set<UUID>()
        return entries.filter { seen.insert($0.experience.id).inserted }
    }

    var firstVisit: LocalDate? { entries.compactMap(\.visitDate.date).min() }
    var lastVisit: LocalDate? { entries.compactMap(\.visitDate.date).max() }
}

/// Friends' visits become a card per friend and city, newest first by when they were there. A visit logged without a
/// date isn't on the Friends tab at all.
enum FriendFeedGrouping {
    static func groups(_ visits: [FriendFeedVisit]) -> [FriendFeedGroup] {
        var order: [String] = []
        var buckets: [String: [FriendFeedVisit]] = [:]
        for visit in visits where visit.entry.visitDate.date != nil {
            let place = visit.entry.experience
            let key = "\(visit.author.id.uuidString)|\(place.countryCode?.uppercased() ?? "-")|\(place.locality?.lowercased() ?? "-")"
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(visit)
        }
        return order.compactMap { key -> FriendFeedGroup? in
            guard let visits = buckets[key], let first = visits.first else { return nil }
            let place = first.entry.experience
            let entries = visits.map(\.entry).sorted { newer($0.visitDate.date, $0.createdAt, than: $1.visitDate.date, $1.createdAt) }
            return FriendFeedGroup(id: key, author: first.author, city: place.locality ?? place.countryName ?? "Elsewhere", region: place.region,
                                   countryCode: place.countryCode, countryName: place.countryName, entries: entries)
        }
        .sorted { newer($0.lastVisit, $0.entries.first?.createdAt ?? .distantPast, than: $1.lastVisit, $1.entries.first?.createdAt ?? .distantPast) }
    }

    /// Later visit date first; on the same day, the one logged later.
    private static func newer(_ date: LocalDate?, _ logged: Date, than other: LocalDate?, _ otherLogged: Date) -> Bool {
        switch (date, other) {
        case let (x?, y?) where x != y: return x > y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return logged > otherLogged
        }
    }
}
