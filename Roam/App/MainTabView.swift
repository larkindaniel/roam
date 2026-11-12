import MapKit
import SwiftUI

/// Three tabs, each with its own navigation stack, under one floating glass tab bar. Tab views stay alive, so
/// query, filter and scroll state persist for the session. The bar is Roam's own so it can sit with even margins
/// and screens can step it aside (a place's card, Explore, My Places until its card is fully up).
struct MainTabView: View {
    @Environment(AppRouter.self) private var router
    @State private var tabBar = TabBarState()

    var body: some View {
        @Bindable var router = router
        ZStack(alignment: .bottom) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let selected = router.selectedTab == tab
                stack(tab)
                    .environment(\.roamTab, tab)
                    .opacity(selected ? 1 : 0)
                    .allowsHitTesting(selected)
                    .accessibilityHidden(!selected)
            }
            if !tabBar.isHidden(on: router.selectedTab) {
                // Measured from the very bottom of the screen, not the home indicator, so the gaps match.
                VStack(spacing: Theme.Spacing.s) {
                    Spacer(minLength: 0)
                    if router.selectedTab == .friends, router.path(for: .friends).isEmpty {
                        logPlaceButton
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.horizontal, RoamTabBar.sideMargin)
                    }
                    RoamTabBar(selection: $router.selectedTab)
                }
                .ignoresSafeArea(edges: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: tabBar.isHidden(on: router.selectedTab))
        .environment(tabBar)
        .sheet(item: $router.sheet) { sheet in
            SheetContent(route: sheet)
                .presentationBackground(Roam.paper)
        }
    }

    private var logPlaceButton: some View {
        Button { router.sheet = .logPlace } label: {
            Image(systemName: "plus")
                .font(.headline)
                .foregroundStyle(Roam.ink)
                .frame(width: Theme.minimumHitTarget, height: Theme.minimumHitTarget)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .floatingBubble(Circle())
        .accessibilityLabel("Log a place")
        .accessibilityIdentifier("log-place")
    }

    @ViewBuilder private func stack(_ tab: AppTab) -> some View {
        switch tab {
        case .forYou: stack(.forYou) { ForYouRootView() }
        case .friends: stack(.friends) { FeedRootView() }
        case .myPlaces: stack(.myPlaces) { MyPlacesRootView() }
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
        // Content scrolls clear of the floating bar.
        .safeAreaPadding(.bottom, tabBar.isHidden(on: tab) ? 0 : RoamTabBar.reservedHeight)
    }
}

/// Which screens on each tab have asked for the tab bar to step aside.
@MainActor
@Observable
final class TabBarState {
    private var hiders: [AppTab: Set<UUID>] = [:]
    /// Screens that always have the tab bar, whatever the screens under them asked for.
    private var showers: [AppTab: Set<UUID>] = [:]

    func isHidden(on tab: AppTab) -> Bool { !(hiders[tab]?.isEmpty ?? true) && (showers[tab]?.isEmpty ?? true) }

    func set(_ hidden: Bool, by id: UUID, on tab: AppTab) {
        if hidden { hiders[tab, default: []].insert(id) } else { hiders[tab]?.remove(id) }
    }

    func setShown(_ shown: Bool, by id: UUID, on tab: AppTab) {
        if shown { showers[tab, default: []].insert(id) } else { showers[tab]?.remove(id) }
    }
}

extension EnvironmentValues {
    /// The tab a view belongs to.
    @Entry var roamTab: AppTab = .forYou
}

private struct TabBarHider: ViewModifier {
    let hidden: Bool
    @Environment(TabBarState.self) private var state
    @Environment(\.roamTab) private var tab
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { state.set(hidden, by: id, on: tab) }
            .onChange(of: hidden) { _, value in state.set(value, by: id, on: tab) }
            .onDisappear { state.set(false, by: id, on: tab) }
    }
}

private struct TabBarShower: ViewModifier {
    @Environment(TabBarState.self) private var state
    @Environment(\.roamTab) private var tab
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { state.setShown(true, by: id, on: tab) }
            .onDisappear { state.setShown(false, by: id, on: tab) }
    }
}

extension View {
    /// Hides Roam's floating tab bar while this screen is showing.
    func roamTabBar(hidden: Bool) -> some View { modifier(TabBarHider(hidden: hidden)) }

    /// Keeps Roam's floating tab bar showing on this screen, even over one that hid it.
    func roamTabBarShown() -> some View { modifier(TabBarShower()) }
}

/// The floating glass tab bar: the same gap from the sides of the screen as from its bottom.
struct RoamTabBar: View {
    @Binding var selection: AppTab
    @Environment(AppRouter.self) private var router
    static let margin: CGFloat = 18
    static let height: CGFloat = 54
    /// Wider at the sides than below: the screen's corners curve in, so this leaves the same gap at the corners.
    static var sideMargin: CGFloat { margin + 14 }
    /// Room content keeps clear of, above the home indicator's safe area.
    static var reservedHeight: CGFloat { height + margin - 16 }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let selected = tab == selection
                // Each tab always opens on its main page, like a back button to it.
                // Back to the tab's home page, scrolled to the top.
                Button { router.popToRoot(tab); router.requestTop(tab); selection = tab } label: {
                    VStack(spacing: 1) {
                        Image(systemName: tab.symbolName).font(.system(size: 17, weight: .semibold)).frame(height: 21)
                        Text(tab.title).font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(Roam.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background { if selected { Capsule().fill(Roam.ink.opacity(0.08)) } }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("tab-\(tab.rawValue)")
            }
        }
        .padding(4)
        .frame(height: Self.height)
        .floatingBubble(Capsule())
        // Wider at the sides than below: the screen's corners curve in, so this leaves the same gap at the corners.
        .padding(.horizontal, Self.sideMargin)
        .padding(.bottom, Self.margin)
    }
}

/// Resolves stable-ID routes to screens.
struct RouteDestinationView: View {
    let route: AppRoute

    var body: some View {
        switch route {
        case .search:
            SearchRootView()
        case .ownProfile:
            ProfileRootView()
        case .trip(let id):
            TripDetailView(tripID: id)
        case .placeGroup(let title, let subtitle, let ids):
            PlaceGroupView(title: title, subtitle: subtitle, ids: ids)
        case .homeCity(let city):
            HomeCityView(city: city)
        case .city(let destination, let ownerID):
            CityPageView(destination: destination, ownerID: ownerID)
        case .cityAt(let latitude, let longitude):
            CityAtView(coordinate: latitude.flatMap { lat in longitude.map { CLLocationCoordinate2D(latitude: lat, longitude: $0) } })
        case .wishlistCountry(let code, let title):
            WishlistCountryView(code: code, title: title)
        case .country(let code):
            CountryPageView(code: code)
        case .region(let area):
            CountryPageView(code: area.countryCode ?? "", region: area)
        case .friendAreaVisits(let area, let friend):
            FriendAreaVisitsView(area: area, friend: friend)
        case .friendPlaceVisits(let placeID, let placeName, let friend):
            FriendPlaceVisitsView(placeID: placeID, placeName: placeName, friend: friend)
        case .passport(let ownerID, let name):
            PassportView(ownerID: ownerID, name: name)
        case .passportCountry(let ownerID, let country):
            PassportCountryView(ownerID: ownerID, country: country)
        case .passportCity(let ownerID, let city):
            PassportCityView(ownerID: ownerID, city: city)
        case .lists:
            PlaceListsView()
        case .receivedShares:
            ReceivedSharesView()
        case .tripInvitations:
            TripInvitationsView()
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
            PlaceBrowserView(startID: id)
        case .member(let id):
            ProfileView(userID: id)
        case .memberList(let id, let kind):
            PersonalListsView(ownerID: id, initialKind: kind)
        case .gallery(let experienceID, let visitID):
            VisitGalleryView(experienceID: experienceID, visitID: visitID)
        case .visitPhoto(let experienceID, let visitID, let photoID):
            VisitGalleryView(experienceID: experienceID, visitID: visitID, initialPhotoID: photoID)
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
        case .visit, .edited: library.noteChanged()
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
