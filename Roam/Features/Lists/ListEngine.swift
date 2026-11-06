import CoreLocation
import Foundation

/// Which part of Been a list shows: all categories or one category's ranking.
enum BeenScope: Hashable, Sendable {
    case all
    case category(ExperienceCategory)
}

enum ListSort: String, CaseIterable, Identifiable, Sendable {
    case categoryRank
    case recentVisit
    case savedDate
    case name
    case distance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .categoryRank: return "Rank"
        case .recentVisit: return "Most recent visit"
        case .savedDate: return "Date saved"
        case .name: return "Name"
        case .distance: return "Distance"
        }
    }
}

/// Staged filter facets: OR within a facet, AND across facets.
struct ListFilter: Equatable, Sendable {
    var categories: Set<ExperienceCategory> = []
    var cityKeys: Set<String> = []
    var countryCodes: Set<String> = []
    /// Been only: show retained memories without a current rating instead of ranked entries.
    var unrankedMemories = false

    var activeCount: Int {
        (categories.isEmpty ? 0 : 1) + (cityKeys.isEmpty ? 0 : 1) + (countryCodes.isEmpty ? 0 : 1) + (unrankedMemories ? 1 : 0)
    }

    var isEmpty: Bool { activeCount == 0 }
}

struct DistanceReference: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case currentLocation
        case destination(String)
    }

    var latitude: Double
    var longitude: Double
    var source: Source

    var label: String {
        switch source {
        case .currentLocation: return "from your location"
        case .destination(let name): return "from \(name)"
        }
    }

    func distance(to entry: ListEntry) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: entry.experience.latitude, longitude: entry.experience.longitude))
    }
}

struct FacetOption: Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let count: Int
}

/// Pure filtering/sorting shared by own and other-member lists.
enum ListEngine {
    static func availableSorts(kind: ListKind, scope: BeenScope) -> [ListSort] {
        switch (kind, scope) {
        case (.been, .category): return [.categoryRank, .recentVisit, .name, .distance]
        // Scores are category-relative, so All has no score/rank sort.
        case (.been, .all): return [.recentVisit, .name, .distance]
        case (.want, _): return [.savedDate, .name, .distance]
        }
    }

    static func defaultSort(kind: ListKind, scope: BeenScope) -> ListSort {
        switch (kind, scope) {
        case (.been, .category): return .categoryRank
        case (.been, .all): return .recentVisit
        case (.want, _): return .savedDate
        }
    }

    static func apply(_ entries: [ListEntry], kind: ListKind, scope: BeenScope, filter: ListFilter, query: String,
                      sort: ListSort, reference: DistanceReference?) -> [ListEntry] {
        let needle = GeographyKey.normalize(query)
        let filtered = entries.filter { entry in
            if kind == .been {
                if filter.unrankedMemories { guard !entry.isRanked else { return false } } else { guard entry.isRanked else { return false } }
                if case .category(let category) = scope, entry.ownerCategory != category { return false }
            }
            let category = entry.ownerCategory ?? entry.experience.category
            if !filter.categories.isEmpty, !(category.map(filter.categories.contains) ?? false) { return false }
            if !filter.cityKeys.isEmpty, !(entry.cityKey.map(filter.cityKeys.contains) ?? false) { return false }
            if !filter.countryCodes.isEmpty, !(entry.experience.countryCode.map(filter.countryCodes.contains) ?? false) { return false }
            if !needle.isEmpty {
                let haystack = GeographyKey.normalize("\(entry.experience.name) \(entry.experience.locality ?? "") \(entry.experience.region ?? "")")
                if !haystack.contains(needle) { return false }
            }
            return true
        }
        return filtered.sorted { compare($0, $1, sort: sort, reference: reference) }
    }

    private static func compare(_ a: ListEntry, _ b: ListEntry, sort: ListSort, reference: DistanceReference?) -> Bool {
        func tie(_ a: ListEntry, _ b: ListEntry) -> Bool {
            let name = a.experience.name.localizedCaseInsensitiveCompare(b.experience.name)
            if name != .orderedSame { return name == .orderedAscending }
            return a.id.uuidString < b.id.uuidString
        }
        switch sort {
        case .categoryRank:
            let ra = a.ownerRank ?? Int.max, rb = b.ownerRank ?? Int.max
            if ra != rb { return ra < rb }
            // Stable within-tie order: first rated, then UUID.
            switch (a.ownerFirstRatedAt, b.ownerFirstRatedAt) {
            case let (x?, y?) where x != y: return x < y
            default: return a.id.uuidString.lowercased() < b.id.uuidString.lowercased()
            }
        case .recentVisit:
            switch (a.latestVisitDate, b.latestVisitDate) {
            case let (x?, y?) where x != y: return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            default:
                if a.latestVisitAt != b.latestVisitAt { return (a.latestVisitAt ?? .distantPast) > (b.latestVisitAt ?? .distantPast) }
                return tie(a, b)
            }
        case .savedDate:
            if a.savedAt != b.savedAt { return (a.savedAt ?? .distantPast) > (b.savedAt ?? .distantPast) }
            return a.id.uuidString < b.id.uuidString
        case .name:
            return tie(a, b)
        case .distance:
            // Missing distance (no reference point) sorts last.
            guard let reference else { return tie(a, b) }
            let da = reference.distance(to: a), db = reference.distance(to: b)
            if da != db { return da < db }
            return tie(a, b)
        }
    }

    static func cityFacets(_ entries: [ListEntry]) -> [FacetOption] {
        let grouped = Dictionary(grouping: entries.filter { $0.cityKey != nil }, by: { $0.cityKey! })
        return grouped.map { key, items in
            let first = items[0]
            return FacetOption(id: key, title: first.cityName ?? first.experience.locality ?? key,
                               subtitle: [first.experience.region, first.experience.countryName].compactMap { $0 }.joined(separator: ", "),
                               count: items.count)
        }.sorted { ($0.title, $0.subtitle ?? "") < ($1.title, $1.subtitle ?? "") }
    }

    static func countryFacets(_ entries: [ListEntry]) -> [FacetOption] {
        let grouped = Dictionary(grouping: entries.filter { $0.experience.countryCode != nil }, by: { $0.experience.countryCode! })
        return grouped.map { code, items in
            FacetOption(id: code, title: items[0].experience.countryName ?? code, subtitle: nil, count: items.count)
        }.sorted { $0.title < $1.title }
    }
}
