import Observation
import SwiftUI

enum AppTab: String, CaseIterable, Hashable, Sendable {
    case feed
    case lists
    case search
    case explore
    case profile

    var title: String {
        switch self {
        case .feed: return "Feed"
        case .lists: return "Your Lists"
        case .search: return "Search"
        case .explore: return "Explore"
        case .profile: return "Profile"
        }
    }

    var symbolName: String {
        switch self {
        case .feed: return "house"
        case .lists: return "list.bullet"
        case .search: return "magnifyingglass"
        case .explore: return "map"
        case .profile: return "person.crop.circle"
        }
    }
}

enum ListKind: String, Hashable, Sendable, CaseIterable, Identifiable {
    case been
    case want

    var id: String { rawValue }
    var title: String { self == .been ? "Been" : "Want to Go" }
}

enum FollowSegment: String, Hashable, Sendable, CaseIterable, Identifiable {
    case followers
    case following

    var id: String { rawValue }
    var title: String { self == .followers ? "Followers" : "Following" }
}

/// Stable-ID routes pushed onto a tab's navigation stack. Deferred features have no case here.
enum AppRoute: Hashable, Sendable {
    case experience(UUID)
    case member(UUID)
    case activity(UUID)
    case notifications
    case followGraph(UUID, FollowSegment)
    case memberList(UUID, ListKind)
    case sharedWants(UUID)
    case globe(UUID)
    case newThisYear(UUID, Int)
    case gallery(experienceID: UUID, visitID: UUID?)
    case settings
    case findPeople
}

/// Modal presentations; dismissing returns to the invoker.
enum SheetRoute: Identifiable, Hashable {
    case log(LogRequest)
    case destinationPicker(DestinationPickerPurpose)

    var id: String {
        switch self {
        case .log(let request): return "log-\(request.id)"
        case .destinationPicker(let purpose): return "destination-\(purpose.rawValue)"
        }
    }
}

enum DestinationPickerPurpose: String, Hashable, Sendable {
    case search
    case explore
    case homeCity
}

/// What a Log/Rank again/Add visit sheet was opened for.
struct LogRequest: Hashable, Identifiable, Sendable {
    enum Mode: String, Codable, Hashable, Sendable {
        case firstLog
        case rerank
        case addVisit
    }

    let id = UUID()
    let experience: ExperienceSummary
    let mode: Mode
    var suggestedCategory: ExperienceCategory?
    var destinationTimeZone: String?
    var categoryLocked = false
    var existingVisit: Visit? = nil
}

@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab
    var paths: [AppTab: [AppRoute]] = [:]
    var sheet: SheetRoute?
    /// Requests the Search tab to show a segment (e.g. Find people → Members).
    var searchSegmentRequest: SearchSegment?

    init(initialTab: AppTab = .feed) {
        self.selectedTab = initialTab
    }

    func path(for tab: AppTab) -> [AppRoute] { paths[tab] ?? [] }

    func binding(for tab: AppTab) -> Binding<[AppRoute]> {
        Binding(get: { self.paths[tab] ?? [] }, set: { self.paths[tab] = $0 })
    }

    func push(_ route: AppRoute, on tab: AppTab? = nil) {
        let target = tab ?? selectedTab
        paths[target, default: []].append(route)
    }

    func popToRoot(_ tab: AppTab? = nil) {
        paths[tab ?? selectedTab] = []
    }

    func showFindPeople() {
        searchSegmentRequest = .members
        selectedTab = .search
    }

    func reset(initialTab: AppTab) {
        paths = [:]
        sheet = nil
        selectedTab = initialTab
    }
}

enum SearchSegment: String, Hashable, Sendable, CaseIterable, Identifiable {
    case experiences
    case members

    var id: String { rawValue }
    var title: String { self == .experiences ? "Experiences" : "Members" }
}
