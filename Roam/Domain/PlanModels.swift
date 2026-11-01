import Foundation

/// Who can see a visit, its note, its photos and its rating.
enum Audience: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case friends
    case onlyMe = "only_me"
    case `public`

    var id: String { rawValue }

    var title: String {
        switch self {
        case .friends: return "Friends"
        case .onlyMe: return "Only me"
        case .public: return "Public"
        }
    }
}

enum TripStatus: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case planning
    case upcoming
    case ongoing
    case past

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct TripSummary: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var owner: MemberSummary
    var name: String
    var description: String
    var startDate: LocalDate?
    var endDate: LocalDate?
    var status: TripStatus
    var isOwn: Bool
    var plannedCount: Int
    var visitedCount: Int
    var stops: [String]
}

/// One place on a trip. Planned and visited are independent: a past trip can keep unvisited plans,
/// and a visit logged to the trip counts even if it was never planned.
struct TripPlace: Codable, Hashable, Identifiable, Sendable {
    var experience: ExperienceSummary
    var stop: String
    var isPlanned: Bool
    var isVisited: Bool

    var id: UUID { experience.id }
    var state: PlaceState { isVisited ? .visited : .planned }
}

struct TripDetail: Codable, Hashable, Sendable {
    var summary: TripSummary
    var places: [TripPlace]

    private enum CodingKeys: String, CodingKey { case places }

    init(summary: TripSummary, places: [TripPlace]) {
        self.summary = summary
        self.places = places
    }

    init(from decoder: Decoder) throws {
        summary = try TripSummary(from: decoder)
        places = try decoder.container(keyedBy: CodingKeys.self).decode([TripPlace].self, forKey: .places)
    }

    func encode(to encoder: Encoder) throws {
        try summary.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(places, forKey: .places)
    }

    var placesByStop: [(stop: String, places: [TripPlace])] {
        let groups = Dictionary(grouping: places, by: \.stop)
        return groups.keys.sorted().map { ($0, groups[$0] ?? []) }
    }
}

struct TripDraft: Hashable, Sendable {
    var id: UUID?
    var name = ""
    var description = ""
    var startDate: LocalDate?
    var endDate: LocalDate?
    var status: TripStatus = .planning

    var validationMessage: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Give this trip a name." }
        if let startDate, let endDate, startDate > endDate { return "The trip can't end before it starts." }
        return nil
    }
}

struct PlaceList: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var owner: MemberSummary
    var title: String
    var description: String
    var isOwn: Bool
    var itemCount: Int
}

struct PlaceListItem: Codable, Hashable, Identifiable, Sendable {
    var experience: ExperienceSummary
    var note: String

    var id: UUID { experience.id }
}

struct PlaceListDetail: Codable, Hashable, Sendable {
    var summary: PlaceList
    var items: [PlaceListItem]

    private enum CodingKeys: String, CodingKey { case items }

    init(summary: PlaceList, items: [PlaceListItem]) {
        self.summary = summary
        self.items = items
    }

    init(from decoder: Decoder) throws {
        summary = try PlaceList(from: decoder)
        items = try decoder.container(keyedBy: CodingKeys.self).decode([PlaceListItem].self, forKey: .items)
    }

    func encode(to encoder: Encoder) throws {
        try summary.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(items, forKey: .items)
    }
}

/// A rated place on Discover: everyone's score, the friends behind it and a cover picture.
struct DiscoverPlace: Codable, Hashable, Identifiable, Sendable {
    var experience: ExperienceSummary
    var communityScore: Score
    var communityCount: Int
    var friendNames: [String]
    var coverPath: String?

    var id: UUID { experience.id }

    /// "Theo rated this", "Theo and Sam rated this" or "Theo and 2 others rated this".
    var friendEvidence: String? {
        guard let first = friendNames.first?.split(separator: " ").first.map(String.init) else { return nil }
        switch friendNames.count {
        case 1: return "\(first) rated this"
        case 2: return "\(first) and \(friendNames[1].split(separator: " ").first.map(String.init) ?? friendNames[1]) rated this"
        default: return "\(first) and \(friendNames.count - 1) others rated this"
        }
    }
}

/// A city worth browsing: built only from places people actually rated there.
struct DiscoverCity: Hashable, Identifiable, Sendable {
    var destination: Destination
    var placeCount: Int
    var friendNames: [String]
    var bestScore: Score
    var coverPath: String?
    var coverURL: URL? = nil
    var coverCredit: String? = nil

    var id: String { destination.id }

    /// Cities your friends have been to come first, then the best rated.
    static func cities(from places: [DiscoverPlace]) -> [DiscoverCity] {
        let groups = Dictionary(grouping: places.filter { $0.experience.locality != nil }) {
            "\($0.experience.locality ?? "")|\($0.experience.region ?? "")|\($0.experience.countryCode ?? "")"
        }
        return groups.values.compactMap { group -> DiscoverCity? in
            guard let first = group.first?.experience, let name = first.locality,
                  let best = group.max(by: { $0.communityScore < $1.communityScore }) else { return nil }
            let count = Double(group.count)
            let destination = Destination(name: name, region: first.region, countryCode: first.countryCode, countryName: first.countryName,
                                          latitude: group.reduce(0) { $0 + $1.experience.latitude } / count,
                                          longitude: group.reduce(0) { $0 + $1.experience.longitude } / count, radiusMeters: 15_000)
            let cover = best.coverPath ?? group.compactMap(\.coverPath).first
            let linked = best.experience.photoURL != nil ? best : group.first { $0.experience.photoURL != nil }
            return DiscoverCity(destination: destination, placeCount: group.count,
                                friendNames: Array(Set(group.flatMap(\.friendNames))).sorted(), bestScore: best.communityScore, coverPath: cover,
                                coverURL: linked?.experience.photoURL, coverCredit: linked?.experience.photoCredit)
        }.sorted { lhs, rhs in
            if lhs.friendNames.isEmpty != rhs.friendNames.isEmpty { return !lhs.friendNames.isEmpty }
            if lhs.bestScore != rhs.bestScore { return lhs.bestScore > rhs.bestScore }
            return lhs.destination.name < rhs.destination.name
        }
    }
}

/// One thing someone did on a trip.
struct TripFeedEntry: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var experience: ExperienceSummary
    var publicNote: String
    var visitDate: VisitDate
    var media: [MediaRef]
    var createdAt: Date
    var score: Score?
    var activityID: UUID?
}

/// One person's trip on the Friends tab. A nil trip is Home: everything not attributed to a trip.
struct TripFeedCard: Codable, Hashable, Identifiable, Sendable {
    var author: MemberSummary
    var tripID: UUID?
    var tripName: String?
    var visitCount: Int
    var latestAt: Date
    var isOwn: Bool
    var entries: [TripFeedEntry]

    var id: String { "\(author.id.uuidString)-\(tripID?.uuidString ?? "home")" }
    var title: String { tripName ?? "Home" }
}

enum ShareTarget: Hashable, Sendable {
    case place(UUID)
    case list(UUID)
    case trip(UUID)
}

/// Something a friend deliberately sent. It stays until the friendship ends.
struct DirectShare: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var sender: MemberSummary
    var message: String
    var createdAt: Date
    var experience: ExperienceSummary?
    var list: PlaceList?
    var trip: TripSummary?

    var title: String { experience?.name ?? list?.title ?? trip?.name ?? "" }
}

/// Declared preferences only. Roam never presents these as something it learned.
struct TasteProfile: Codable, Hashable, Sendable {
    var atmosphere: String?
    var budget: String?
    var crowds: String?
    var novelty: String?
    var pace: String?

    static let empty = TasteProfile()

    struct Question: Identifiable, Hashable, Sendable {
        let keyPath: WritableKeyPath<TasteProfile, String?>
        let title: String
        let options: [String]

        var id: String { title }
    }

    static let questions = [
        Question(keyPath: \.atmosphere, title: "What atmosphere do you like?", options: ["Quiet", "Lively", "Local"]),
        Question(keyPath: \.budget, title: "What's your usual budget?", options: ["Low", "Mid", "High"]),
        Question(keyPath: \.crowds, title: "How do you feel about crowds?", options: ["Avoid them", "Don't mind", "Love the buzz"]),
        Question(keyPath: \.novelty, title: "Familiar or adventurous?", options: ["Familiar", "A bit of both", "Adventurous"]),
        Question(keyPath: \.pace, title: "What pace do you travel at?", options: ["Slow", "Steady", "Packed"]),
    ]
}

enum ResearchBrief {
    /// An editable starting point. It holds only the destination, declared tastes and the places the
    /// member names here, never private notes or friends' identities.
    static func text(destination: Destination, taste: TasteProfile, liked: [String]) -> String {
        var lines = ["I'm planning time in \(destination.displayName). Recommend places I'd enjoy."]
        let answers = [("Atmosphere", taste.atmosphere), ("Budget", taste.budget), ("Crowds", taste.crowds),
                       ("Novelty", taste.novelty), ("Pace", taste.pace)]
            .compactMap { label, value in value.map { "- \(label): \($0)" } }
        if !answers.isEmpty { lines += ["", "What I like:"] + answers }
        if !liked.isEmpty { lines += ["", "Places I've enjoyed:"] + liked.map { "- \($0)" } }
        lines += ["", "For each suggestion, explain why it fits me and check that it's currently open."]
        return lines.joined(separator: "\n")
    }
}
