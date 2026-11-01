import SwiftUI

/// Three tabs, each with its own navigation stack, plus the Log a place action. Tab views stay
/// alive, so query, filter and scroll state persist for the session.
struct MainTabView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        tabs(selection: $router.selectedTab)
            .sheet(item: $router.sheet) { sheet in
                SheetContent(route: sheet)
                    .presentationBackground(Roam.paper)
            }
    }

    private func tabs(selection: Binding<AppTab>) -> some View {
        let view = TabView(selection: selection) {
            Tab(AppTab.forYou.title, systemImage: AppTab.forYou.symbolName, value: AppTab.forYou) {
                stack(.forYou) { ForYouRootView() }
            }
            .accessibilityIdentifier("tab-foryou")
            Tab(AppTab.friends.title, systemImage: AppTab.friends.symbolName, value: AppTab.friends) {
                stack(.friends) { FeedRootView() }
            }
            .accessibilityIdentifier("tab-friends")
            Tab(AppTab.myPlaces.title, systemImage: AppTab.myPlaces.symbolName, value: AppTab.myPlaces) {
                stack(.myPlaces) { MyPlacesRootView() }
            }
            .accessibilityIdentifier("tab-myplaces")
        }
        return Group {
            if #available(iOS 26.0, *) {
                view.tabViewBottomAccessory { LogPlaceAccessory() }
            } else {
                view
            }
        }
    }

    private func stack<Root: View>(_ tab: AppTab, @ViewBuilder root: () -> Root) -> some View {
        NavigationStack(path: router.binding(for: tab)) {
            root()
                .scrollContentBackground(.hidden)
                .background(Roam.paper)
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
        case .search:
            SearchRootView()
        case .explore:
            ExploreRootView()
        case .ownProfile:
            ProfileRootView()
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
