import Foundation

/// The facts behind a suggestion, worked out on the server from what you're allowed to see. Only me entries, blocked
/// people and former friends are never in here. Points and weights live in the database (`suggestion_weights`); the app
/// only turns these facts into a reason line and keeps the server's order.
struct SuggestionEvidence: Codable, Hashable, Sendable {
    struct SharedList: Codable, Hashable, Sendable {
        var owner: String
        var title: String
    }

    /// Friends who sent you this place (or a place in this city), most recent first.
    var sentBy: [String]?
    /// The newest shared list it's on.
    var list: SharedList?
    var friendsLoved: [String]?
    var friendsBeen: [String]?
    var friendsFine: Int?
    var friendsDisliked: Int?
    var communityCount: Int?
    var communityScore: Score?
    /// How many places in this category you liked, once you've liked enough to have a lean.
    var likedInCategory: Int?
    var isPopular: Bool?
    /// A city on one of your upcoming trips.
    var tripName: String?

    static let empty = SuggestionEvidence()
}

/// One short line saying why something is suggested. The strongest fact wins, in a fixed order:
/// sent to you → on a friend's list → friends loved it → a friend has been → like places you loved → popular on Roam.
/// Google's rating is never a reason line: the card already shows its stars.
enum SuggestionReason {
    /// How many places you need to have liked in a category before "Like places you loved" shows.
    static let tasteMinimumLiked = 3

    static func place(_ evidence: SuggestionEvidence) -> String? {
        if let senders = nonEmpty(evidence.sentBy) { return "\(people(senders)) sent you this" }
        if let list = evidence.list { return listLine(list) }
        if let loved = nonEmpty(evidence.friendsLoved) { return lovedLine(loved, suffix: "") }
        if let been = nonEmpty(evidence.friendsBeen) { return beenLine(been) }
        if (evidence.likedInCategory ?? 0) >= tasteMinimumLiked { return "Like places you loved" }
        if evidence.isPopular == true { return "Popular on Roam" }
        return nil
    }

    static func city(_ evidence: SuggestionEvidence) -> String? {
        if let trip = evidence.tripName?.trimmingCharacters(in: .whitespaces), !trip.isEmpty {
            return trip.localizedCaseInsensitiveContains("trip") ? "On your \(trip)" : "On your \(trip) trip"
        }
        if let senders = nonEmpty(evidence.sentBy) {
            return senders.count == 1 ? "\(firstName(senders[0])) sent you a place here" : "\(people(senders)) sent you places here"
        }
        if let list = evidence.list { return listLine(list) }
        if let loved = nonEmpty(evidence.friendsLoved) { return lovedLine(loved, suffix: " here") }
        if let been = nonEmpty(evidence.friendsBeen) { return beenLine(been) }
        if evidence.isPopular == true { return "Popular on Roam" }
        return nil
    }

    // MARK: Wording

    static func firstName(_ name: String) -> String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    /// "Theo", "Theo and Maya", "Theo and 2 others".
    private static func people(_ names: [String]) -> String {
        let first = names.map(firstName)
        switch first.count {
        case 1: return first[0]
        case 2: return "\(first[0]) and \(first[1])"
        default: return "\(first[0]) and \(first.count - 1) others"
        }
    }

    private static func listLine(_ list: SuggestionEvidence.SharedList) -> String {
        let title = list.title.trimmingCharacters(in: .whitespaces)
        let owner = firstName(list.owner)
        return title.localizedCaseInsensitiveContains("list") ? "On \(owner)'s \(title)" : "On \(owner)'s \(title) list"
    }

    /// One or two friends by name, then a count.
    private static func lovedLine(_ names: [String], suffix: String) -> String {
        names.count <= 2 ? "\(people(names)) loved it\(suffix)" : "\(names.count) friends loved it\(suffix)"
    }

    private static func beenLine(_ names: [String]) -> String {
        names.count == 1 ? "\(firstName(names[0])) has been" : "\(people(names)) have been"
    }

    private static func nonEmpty(_ names: [String]?) -> [String]? {
        guard let names, !names.isEmpty else { return nil }
        return names
    }
}

/// The server's order, kept on the device too so a list that changes locally (a place hidden or logged) stays in the
/// same order: most points first, then Google's rating, then name.
enum SuggestionOrder {
    static func places(_ places: [DiscoverPlace]) -> [DiscoverPlace] {
        places.sorted { lhs, rhs in
            let left = lhs.points ?? 0, right = rhs.points ?? 0
            if left != right { return left > right }
            let leftGoogle = lhs.experience.googleRating ?? -1, rightGoogle = rhs.experience.googleRating ?? -1
            if leftGoogle != rightGoogle { return leftGoogle > rightGoogle }
            if lhs.experience.name != rhs.experience.name { return lhs.experience.name < rhs.experience.name }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    static func cities(_ cities: [DiscoverCity]) -> [DiscoverCity] {
        cities.sorted { lhs, rhs in
            if lhs.points != rhs.points { return lhs.points > rhs.points }
            return lhs.destination.name < rhs.destination.name
        }
    }
}

/// What your own rankings say you lean towards: the categories you've liked most, for the Plan with AI prompt.
enum TasteLean {
    static func categories(liked: [ExperienceCategory], minimum: Int = SuggestionReason.tasteMinimumLiked) -> [ExperienceCategory] {
        guard liked.count >= minimum else { return [] }
        let counts = Dictionary(grouping: liked, by: { $0 }).mapValues(\.count)
        return counts.sorted { lhs, rhs in
            lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key.rawValue < rhs.key.rawValue
        }
        .prefix(3).map(\.key)
    }
}
