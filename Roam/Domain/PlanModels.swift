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
    /// The cities the trip covers: the ones named for it, then the cities of its places.
    var cities: [Destination] = []
    /// Whole countries named for the trip, as ISO codes, before any of their cities are picked.
    var countries: [String] = []

    private enum CodingKeys: String, CodingKey {
        case id, owner, name, description, startDate, endDate, status, isOwn, plannedCount, visitedCount, stops, cities, countries
    }

    /// Whether the trip goes to this country: named for it, or one of its cities is there.
    func covers(country code: String) -> Bool {
        countries.contains { $0.uppercased() == code.uppercased() } || cities.contains { $0.countryCode?.uppercased() == code.uppercased() }
    }
}

extension TripSummary {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        owner = try c.decode(MemberSummary.self, forKey: .owner)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decode(String.self, forKey: .description)
        startDate = try c.decodeIfPresent(LocalDate.self, forKey: .startDate)
        endDate = try c.decodeIfPresent(LocalDate.self, forKey: .endDate)
        status = try c.decode(TripStatus.self, forKey: .status)
        isOwn = try c.decode(Bool.self, forKey: .isOwn)
        plannedCount = try c.decode(Int.self, forKey: .plannedCount)
        visitedCount = try c.decode(Int.self, forKey: .visitedCount)
        stops = try c.decodeIfPresent([String].self, forKey: .stops) ?? []
        cities = try c.decodeIfPresent([Destination].self, forKey: .cities) ?? []
        countries = try c.decodeIfPresent([String].self, forKey: .countries) ?? []
    }

    /// Where the trip sits on your timeline, from its dates when it has them.
    func phase(today: LocalDate) -> TripPhase {
        if let end = endDate, end < today { return .past }
        if let start = startDate { return start > today ? .upcoming : .now }
        if endDate != nil { return .upcoming }
        return status == .past ? .past : .planning
    }

    /// The city to picture the trip by: the one it's named after, else its first.
    var coverCity: Destination? {
        cities.first { GeographyKey.normalize($0.name) == GeographyKey.normalize(name) } ?? cities.first
    }

    /// "Tokyo, Kyoto", or the countries when it spans more than one.
    var placeLine: String {
        let countries = cities.compactMap(\.countryName).uniqued()
        if countries.count > 1 { return countries.joined(separator: ", ") }
        return cities.map(\.name).uniqued().joined(separator: ", ")
    }

    /// The status a trip is saved with for its dates.
    static func status(start: LocalDate?, end: LocalDate?, today: LocalDate) -> TripStatus {
        if let end, end < today { return .past }
        if let start, start <= today { return .ongoing }
        return start == nil && end == nil ? .planning : .upcoming
    }
}

enum TripPhase: Hashable {
    case now
    case upcoming
    case planning
    case past
}

/// A city in someone's passport. Friends see every city, but open only the places shared with them.
struct PassportCity: Codable, Hashable, Identifiable, Sendable {
    var city: Destination
    var placeCount: Int
    var visibleCount: Int
    var firstVisit: LocalDate?
    var lastVisit: LocalDate?
    var isMarked: Bool
    var isHome: Bool

    var id: String { city.id }
}

/// A country in someone's passport, with its cities.
struct PassportCountry: Codable, Hashable, Identifiable, Sendable {
    var code: String
    var name: String
    var cities: [PassportCity]
    var otherPlaceCount: Int
    var otherVisibleCount: Int

    var id: String { code }
    var title: String { CountryTitle.text(name: name, code: code) }
    var placeCount: Int { cities.map(\.placeCount).reduce(otherPlaceCount, +) }

    private enum CodingKeys: String, CodingKey { case code, name, cities, otherPlaceCount, otherVisibleCount }

    init(code: String, name: String, cities: [PassportCity], otherPlaceCount: Int, otherVisibleCount: Int) {
        self.code = code
        self.name = name
        self.cities = PassportCountry.merged(cities)
        self.otherPlaceCount = otherPlaceCount
        self.otherVisibleCount = otherVisibleCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(code: try c.decode(String.self, forKey: .code), name: try c.decode(String.self, forKey: .name),
                  cities: try c.decode([PassportCity].self, forKey: .cities),
                  otherPlaceCount: try c.decode(Int.self, forKey: .otherPlaceCount), otherVisibleCount: try c.decode(Int.self, forKey: .otherVisibleCount))
    }

    /// One entry per city name: the same city can be stored under more than one region spelling.
    static func merged(_ cities: [PassportCity]) -> [PassportCity] {
        var order: [String] = []
        var byName: [String: PassportCity] = [:]
        for city in cities {
            let key = GeographyKey.normalize(city.city.name)
            guard var existing = byName[key] else { order.append(key); byName[key] = city; continue }
            if existing.city.latitude == 0 && existing.city.longitude == 0 { existing.city = city.city }
            existing.placeCount += city.placeCount
            existing.visibleCount += city.visibleCount
            existing.firstVisit = [existing.firstVisit, city.firstVisit].compactMap { $0 }.min()
            existing.lastVisit = [existing.lastVisit, city.lastVisit].compactMap { $0 }.max()
            existing.isMarked = existing.isMarked || city.isMarked
            existing.isHome = existing.isHome || city.isHome
            byName[key] = existing
        }
        return order.compactMap { byName[$0] }.sorted { $0.placeCount != $1.placeCount ? $0.placeCount > $1.placeCount : $0.city.name < $1.city.name }
    }
}

/// One place on a trip. Planned and visited are independent: a past trip can keep unvisited plans,
/// and a visit logged to the trip counts even if it was never planned.
struct TripPlace: Codable, Hashable, Identifiable, Sendable {
    var experience: ExperienceSummary
    var stop: String
    var isPlanned: Bool
    var isVisited: Bool

    var id: UUID { experience.id }
    /// Places aren't planned any more: one on a trip that you haven't been to yet reads as saved.
    var state: PlaceState { isVisited ? .visited : .wishlist }
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
    /// Nil until someone rates it; a visit alone gives no score.
    var communityScore: Score?
    var communityCount: Int
    var friendNames: [String]
    var coverPath: String?

    var id: UUID { experience.id }

    /// "Theo has been", "Theo and Sam have been" or "Theo and 2 others have been".
    var friendEvidence: String? {
        guard let first = friendNames.first?.split(separator: " ").first.map(String.init) else { return nil }
        switch friendNames.count {
        case 1: return "\(first) has been"
        case 2: return "\(first) and \(friendNames[1].split(separator: " ").first.map(String.init) ?? friendNames[1]) have been"
        default: return "\(first) and \(friendNames.count - 1) others have been"
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
                  let best = group.max(by: { ($0.communityScore?.tenths ?? -1) < ($1.communityScore?.tenths ?? -1) }) else { return nil }
            let count = Double(group.count)
            let destination = Destination(name: name, region: first.region, countryCode: first.countryCode, countryName: first.countryName,
                                          latitude: group.reduce(0) { $0 + $1.experience.latitude } / count,
                                          longitude: group.reduce(0) { $0 + $1.experience.longitude } / count, radiusMeters: 15_000)
            let cover = best.coverPath ?? group.compactMap(\.coverPath).first
            let linked = best.experience.photoURL != nil ? best : group.first { $0.experience.photoURL != nil }
            return DiscoverCity(destination: destination, placeCount: group.count,
                                friendNames: Array(Set(group.flatMap(\.friendNames))).sorted(), bestScore: best.communityScore ?? Score(tenths: 0), coverPath: cover,
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

/// Where one visit on a trip was.
struct TripLocation: Codable, Hashable, Sendable {
    var city: String?
    var countryCode: String?
    var country: String?
}

enum TripTitle {
    static func flag(_ countryCode: String?) -> String? {
        guard let code = countryCode?.uppercased(), code.count == 2 else { return nil }
        let scalars = code.unicodeScalars.compactMap { UnicodeScalar(127_397 + $0.value) }
        guard scalars.count == 2, code.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        return String(String.UnicodeScalarView(scalars))
    }

    /// One city reads "Tokyo 🇯🇵", several cities in a country read "Japan 🇯🇵", and several countries list each.
    /// Nil when the visits don't say where they were.
    static func from(_ locations: [TripLocation]) -> String? {
        let cities = Set(locations.compactMap(\.city))
        var seen = Set<String>()
        let countries = locations.filter { $0.country != nil && seen.insert($0.country ?? "").inserted }
            .sorted { ($0.country ?? "") < ($1.country ?? "") }
        func labelled(_ name: String, _ code: String?) -> String { [name, flag(code)].compactMap { $0 }.joined(separator: " ") }
        if cities.count == 1, countries.count <= 1, let city = cities.first {
            return labelled(city, countries.first?.countryCode)
        }
        guard !countries.isEmpty else { return nil }
        return countries.map { labelled($0.country ?? "", $0.countryCode) }.joined(separator: " · ")
    }
}

/// One person's places in one country on the Friends tab.
struct CountryFeedCard: Codable, Hashable, Identifiable, Sendable {
    var author: MemberSummary
    var countryCode: String?
    var countryName: String?
    var placeCount: Int
    var latestAt: Date
    var isOwn: Bool
    var entries: [TripFeedEntry]

    var id: String { "\(author.id.uuidString)-\(countryCode ?? "none")" }
    var title: String { CountryTitle.text(name: countryName, code: countryCode) }
    /// When they were there: the span of their visit dates here.
    var firstVisit: LocalDate? { entries.compactMap(\.visitDate.date).min() }
    var lastVisit: LocalDate? { entries.compactMap(\.visitDate.date).max() }
}

/// A state or province on your wishlist.
struct SavedRegion: Codable, Hashable, Identifiable, Sendable {
    var countryCode: String
    var region: String
    var name: String
    var latitude: Double?
    var longitude: Double?
    var radiusMeters: Double?
    var id: String { "\(countryCode)|\(region)" }

    /// Its page, when it was saved with where it is.
    var destination: Destination? {
        guard let latitude, let longitude else { return nil }
        return Destination(name: name, region: region, countryCode: countryCode, countryName: CountryName.display(code: countryCode),
                           latitude: latitude, longitude: longitude, radiusMeters: radiusMeters ?? 200_000)
    }
}

enum CountryTitle {
    static func text(name: String?, code: String?) -> String {
        [CountryName.display(name, code: code) ?? "Other places", TripTitle.flag(code)].compactMap { $0 }.joined(separator: " ")
    }
}

/// A country's everyday name. Anywhere with its own flag counts as its own country (Hong Kong too), so the qualifiers
/// Apple and providers add go: "China mainland" is China, "Hong Kong SAR, China" is Hong Kong.
enum CountryName {
    static func display(_ name: String?, code: String?) -> String? {
        let code = code?.uppercased()
        guard let base = name ?? code.flatMap({ Locale.current.localizedString(forRegionCode: $0) }) else { return nil }
        if code == "CN" || base == "China mainland" || base == "Mainland China" { return "China" }
        for suffix in [" SAR, China", " SAR China", " (China)", " SAR"] where base.hasSuffix(suffix) {
            return String(base.dropLast(suffix.count))
        }
        return base
    }

    /// The name for a country code alone.
    static func display(code: String) -> String { display(nil, code: code) ?? code }
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
    var locations: [TripLocation] = []

    var id: String { "\(author.id.uuidString)-\(tripID?.uuidString ?? "home")" }
    var title: String {
        guard tripID != nil else { return "Home" }
        return TripTitle.from(locations) ?? tripName ?? "Trip"
    }
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
