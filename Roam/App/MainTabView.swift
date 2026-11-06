import SwiftUI

/// Five tabs, each with its own navigation stack. Tab views stay alive, so query, filter and
/// scroll state persist for the session.
struct MainTabView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            Tab(AppTab.feed.title, systemImage: AppTab.feed.symbolName, value: AppTab.feed) {
                stack(.feed) { FeedRootView() }
            }
            .accessibilityIdentifier("tab-feed")
            Tab(AppTab.lists.title, systemImage: AppTab.lists.symbolName, value: AppTab.lists) {
                stack(.lists) { ListsRootView() }
            }
            .accessibilityIdentifier("tab-lists")
            Tab(AppTab.search.title, systemImage: AppTab.search.symbolName, value: AppTab.search) {
                stack(.search) { SearchRootView() }
            }
            .accessibilityIdentifier("tab-search")
            Tab(AppTab.explore.title, systemImage: AppTab.explore.symbolName, value: AppTab.explore) {
                stack(.explore) { ExploreRootView() }
            }
            .accessibilityIdentifier("tab-explore")
            Tab(AppTab.profile.title, systemImage: AppTab.profile.symbolName, value: AppTab.profile) {
                stack(.profile) { ProfileRootView() }
            }
            .accessibilityIdentifier("tab-profile")
        }
        .sheet(item: $router.sheet) { sheet in
            SheetContent(route: sheet)
        }
    }

    private func stack<Root: View>(_ tab: AppTab, @ViewBuilder root: () -> Root) -> some View {
        NavigationStack(path: router.binding(for: tab)) {
            root()
                .navigationDestination(for: AppRoute.self) { route in
                    RouteDestinationView(route: route)
                }
        }
    }
}

/// Resolves stable-ID routes to screens.
struct RouteDestinationView: View {
    let route: AppRoute

    var body: some View {
        switch route {
        case .globe(let userID):
            ExpandedGlobeView(userID: userID)
        case .travelFilter(let userID, let filter):
            ExpandedGlobeView(userID: userID, initialFilter: filter)
        case .newThisYear(let userID, let year):
            NewThisYearView(userID: userID, year: year)
        case .settings:
            SettingsView()
        case .editProfile:
            EditProfileView()
        case .safetyList(let kind):
            SafetyMembersView(kind: kind)
        case .reportHistory:
            ReportHistoryView()
        case .help(let topic):
            HelpView(topic: topic)
        case .deleteAccount:
            DeleteAccountView()
        case .experience(let id):
            ExperienceDetailView(experienceID: id)
        case .member(let id):
            ProfileView(userID: id)
        case .memberList(let id, let kind):
            PersonalListsView(ownerID: id, initialKind: kind)
        case .gallery(let experienceID, let visitID):
            VisitGalleryView(experienceID: experienceID, visitID: visitID)
        case .activity(let id):
            ActivityDetailView(activityID: id)
        case .notifications:
            NotificationsView()
        case .followGraph(let id, let segment):
            FollowListView(userID: id, initialSegment: segment)
        case .sharedWants(let id):
            SharedWantsView(otherID: id)
        }
    }
}

struct SheetContent: View {
    let route: SheetRoute
    @Environment(LibraryStore.self) private var library

    var body: some View {
        switch route {
        case .destinationPicker(let purpose):
            DestinationPickerSheet(purpose: purpose)
        case .log(let request):
            RatingFlowView(request: request) { completion in
                switch completion {
                case .rating(let result): library.applyRated(request.experience.id, category: result.category)
                case .visit: library.noteChanged()
                }
                Task { await library.refresh() }
            }
        }
    }
}
