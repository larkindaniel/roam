import Observation
import SwiftUI

enum AppTab: String, CaseIterable, Hashable, Sendable {
    case forYou = "foryou"
    case friends
    case myPlaces = "myplaces"

    var title: String {
        switch self {
        case .forYou: return "Discover"
        case .friends: return "Friends"
        case .myPlaces: return "My Places"
        }
    }

    var symbolName: String {
        switch self {
        case .forYou: return "safari"
        case .friends: return "person.2"
        case .myPlaces: return "mappin.and.ellipse"
        }
    }
}

enum ListKind: String, Hashable, Sendable, CaseIterable, Identifiable {
    case been
    case want

    var id: String { rawValue }
    var title: String { self == .been ? "Been there" : "Wishlist" }
}

enum FollowSegment: String, Hashable, Sendable, CaseIterable, Identifiable {
    case friends
    case requests

    var id: String { rawValue }
    var title: String { self == .friends ? "Friends" : "Requests" }
}

/// Stable-ID routes pushed onto a tab's navigation stack. Deferred features have no case here.
enum AppRoute: Hashable, Sendable {
    case experience(UUID)
    case search
    case explore
    case ownProfile
    case trip(UUID)
    case tripUpdates(ownerID: UUID, tripID: UUID?, title: String)
    case lists
    case list(UUID)
    case taste
    case member(UUID)
    case activity(UUID)
    case notifications
    case followGraph(UUID, FollowSegment)
    case memberList(UUID, ListKind)
    case sharedWants(UUID)
    case globe(UUID)
    case newThisYear(UUID, Int)
    /// S19 with a Travel Profile row selected (category, city or country).
    case travelFilter(UUID, TravelFilter)
    case gallery(experienceID: UUID, visitID: UUID?)
    case settings
    case editProfile
    case safetyList(SafetyListKind)
    case reportHistory
    case help(HelpTopic)
    case deleteAccount
}

enum SafetyListKind: String, Hashable, Sendable {
    case blocked
    case muted
}

enum HelpTopic: String, Hashable, Sendable, CaseIterable, Identifiable {
    case ranking
    case privacy
    case terms
    case support

    var id: String { rawValue }
}

/// Modal presentations; dismissing returns to the invoker.
enum SheetRoute: Identifiable, Hashable {
    case log(LogRequest)
    case logPlace
    case destinationPicker(DestinationPickerPurpose)
    case addToTrip(experienceID: UUID, name: String)
    case addToList(experienceID: UUID, name: String)
    case share(ShareTarget, title: String)
    case researchBrief(Destination)

    var id: String {
        switch self {
        case .log(let request): return "log-\(request.id)"
        case .logPlace: return "log-place"
        case .destinationPicker(let purpose): return "destination-\(purpose.rawValue)"
        case .addToTrip(let id, _): return "trip-\(id)"
        case .addToList(let id, _): return "list-\(id)"
        case .share(let target, _): return "share-\(target)"
        case .researchBrief(let destination): return "research-\(destination.id)"
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
    /// Opens on the visit details, with ranking offered rather than required.
    var startsWithDetails = false
}

@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab
    var paths: [AppTab: [AppRoute]] = [:]
    var sheet: SheetRoute?
    /// Requests the Search tab to show a segment (e.g. Find people → Members).
    var searchSegmentRequest: SearchSegment?

    init(initialTab: AppTab = .forYou) {
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
        openSearch()
    }

    /// Search and Explore are screens within a tab, not tabs of their own.
    func openSearch() { push(.search) }

    func openExplore() { push(.explore) }

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
