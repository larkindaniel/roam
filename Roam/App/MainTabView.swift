import SwiftUI

/// Three tabs, each with its own navigation stack. Each tab's main screen has a Log button at its top left. Tab views stay
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
        TabView(selection: selection) {
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
    }

    private func stack<Root: View>(_ tab: AppTab, @ViewBuilder root: () -> Root) -> some View {
        NavigationStack(path: router.binding(for: tab)) {
            root()
                .scrollContentBackground(.hidden)
                .background(Roam.paper)
                .navigationDestination(for: AppRoute.self) { route in
                    RouteDestinationView(route: route)
                        .scrollContentBackground(.hidden)
                        .background(Roam.paper)
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
        case .trip(let id):
            TripDetailView(tripID: id)
        case .countryUpdates(let ownerID, let countryCode, let title, let byline):
            CountryUpdatesView(ownerID: ownerID, countryCode: countryCode, title: title, byline: byline)
        case .myCountry(let code, let title):
            MyCountryView(code: code, title: title)
        case .lists:
            PlaceListsView()
        case .list(let id):
            PlaceListDetailView(listID: id)
        case .taste:
            TasteEditorView()
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

    private func saved(_ request: LogRequest, _ completion: RatingFlowCompletion) {
        switch completion {
        case .rating(let result): library.applyRated(request.experience.id, category: result.category)
        case .visit: library.noteChanged()
        }
        Task { await library.refresh() }
    }

    var body: some View {
        switch route {
        case .destinationPicker(let purpose):
            DestinationPickerSheet(purpose: purpose)
        case .addToTrip(let id, let name):
            AddToTripSheet(experienceID: id, placeName: name)
        case .addToList(let id, let name):
            AddToListSheet(experienceID: id, placeName: name)
        case .share(let target, let title):
            ShareSheet(target: target, title: title)
        case .researchBrief(let destination):
            ResearchBriefSheet(destination: destination)
        case .log(let request):
            RatingFlowView(request: request) { completion in saved(request, completion) }
        case .logPlace:
            LogPlaceSheet { request, completion in saved(request, completion) }
        }
    }
}
