import MapKit
import Observation
import SwiftUI

extension PlaceMapItem {
    /// Each place appears once, in its most advanced state.
    static func items(been: [ExperienceSummary], planned: [ExperienceSummary], wishlist: [ExperienceSummary]) -> [PlaceMapItem] {
        var items: [UUID: PlaceMapItem] = [:]
        for place in wishlist { items[place.id] = PlaceMapItem(experience: place, state: .wishlist) }
        for place in planned { items[place.id] = PlaceMapItem(experience: place, state: .planned) }
        for place in been { items[place.id] = PlaceMapItem(experience: place, state: .visited) }
        return items.values.sorted { $0.experience.name < $1.experience.name }
    }
}

/// Your places in one country.
struct MyPlacesCountry: Identifiable, Hashable {
    let code: String
    let name: String
    let items: [PlaceMapItem]

    var id: String { code }
    var title: String { CountryTitle.text(name: name, code: code) }
    var coverURL: URL? { items.compactMap(\.experience.photoURL).first }

    func count(_ state: PlaceState) -> Int { items.filter { $0.state == state }.count }

    /// Countries you've been to most first, then planned, then wishlist.
    static func countries(_ items: [PlaceMapItem]) -> [MyPlacesCountry] {
        Dictionary(grouping: items.filter { $0.experience.countryCode != nil }) { $0.experience.countryCode?.uppercased() ?? "" }
            .map { code, items in
                MyPlacesCountry(code: code, name: items.compactMap(\.experience.countryName).first ?? code, items: items)
            }
            .sorted {
                let left = ($0.count(.visited), $0.count(.planned), $0.count(.wishlist)), right = ($1.count(.visited), $1.count(.planned), $1.count(.wishlist))
                return left != right ? left > right : $0.name < $1.name
            }
    }
}

@MainActor
@Observable
final class MyPlacesModel {
    private(set) var pins: [PlaceMapItem] = []
    private(set) var countries: [MyPlacesCountry] = []
    private(set) var trips: [TripSummary] = []
    private(set) var tripDetails: [UUID: TripDetail] = [:]
    private(set) var homeCities: [Destination] = []
    /// Cities on your wishlist, saved as a whole.
    private(set) var savedCities: [Destination] = []
    /// Whole countries (ISO codes) and states on your wishlist.
    private(set) var savedCountries: [String] = []
    private(set) var savedRegions: [SavedRegion] = []
    private(set) var passport: [PassportCountry] = []
    private(set) var lists: [PlaceList] = []
    private(set) var timeline: [TimelineEntry] = []
    private(set) var scores: [UUID: Score] = [:]
    private(set) var hasLoaded = false
    private(set) var error: String?
    private let services: AppServices
    private let ownerID: UUID
    var ownerIDValue: UUID { ownerID }

    init(services: AppServices, ownerID: UUID) {
        self.services = services
        self.ownerID = ownerID
    }

    /// Saved places you haven't planned or been to, away from your home cities.
    var travelWishlist: [PlaceMapItem] {
        pins.filter { $0.state == .wishlist && !CityMatch.isHome($0.experience, homes: homeCities) }
    }

    func load() async {
        do {
            async let been = services.lists.been(ownerID: ownerID)
            async let wishlist = services.lists.want(ownerID: ownerID)
            async let summaries = services.plans.myTrips()
            let (beenEntries, wishlistEntries, trips) = try await (been, wishlist, summaries)
            var details: [UUID: TripDetail] = [:]
            for trip in trips { details[trip.id] = try? await services.plans.trip(id: trip.id) }
            let planned = details.values.flatMap { $0.places.filter(\.isPlanned).map(\.experience) }
            homeCities = HomeCities.distinct((try? await services.plans.homeCities()) ?? homeCities)
            savedCities = (try? await services.plans.savedCities()) ?? savedCities
            savedCountries = (try? await services.plans.savedCountries()) ?? savedCountries
            savedRegions = (try? await services.plans.savedRegionList()) ?? savedRegions
            passport = (try? await services.plans.passport(ownerID: ownerID)) ?? passport
            lists = (try? await services.plans.myLists()) ?? lists
            self.trips = trips
            tripDetails = details
            pins = PlaceMapItem.items(been: beenEntries.map(\.experience), planned: planned, wishlist: wishlistEntries.map(\.experience))
            countries = MyPlacesCountry.countries(pins)
            scores = Dictionary(beenEntries.compactMap { entry in entry.ownerScore.map { (entry.id, $0) } }, uniquingKeysWith: { first, _ in first })
            timeline = MyTimeline.past(been: beenEntries, trips: trips, details: details, homes: homeCities, today: MyTimeline.today())
            hasLoaded = true
            error = nil
            // Saved places with no photo yet ask Google in the background, then refresh once.
            let missing = wishlistEntries.filter { $0.experience.photoURL == nil }.map(\.id)
            if !missing.isEmpty, await services.plans.refreshGoogleDetails(experienceIDs: Array(missing.prefix(20))),
               let refreshed = try? await services.lists.want(ownerID: ownerID) {
                pins = PlaceMapItem.items(been: beenEntries.map(\.experience), planned: planned, wishlist: refreshed.map(\.experience))
                countries = MyPlacesCountry.countries(pins)
            }
        } catch {
            self.error = error.roamMessage
        }
    }

    func setHome(_ city: Destination, present: Bool) async {
        if present {
            _ = try? await services.plans.setHomeCity(city, present: true)
        } else {
            // The same city can be stored under more than one region spelling; drop them all.
            for stored in ((try? await services.plans.homeCities()) ?? []) where stored.countryCode == city.countryCode && GeographyKey.normalize(stored.name) == GeographyKey.normalize(city.name) {
                _ = try? await services.plans.setHomeCity(stored, present: false)
            }
        }
        await load()
    }

    func createList(title: String) async -> PlaceList? {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty,
              let list = try? await services.plans.saveList(id: nil, title: title, description: "") else { return nil }
        lists.insert(list, at: 0)
        return list
    }

    func markVisited(_ city: Destination) async {
        try? await services.plans.setCityVisited(city, present: true)
        await load()
    }
}

/// A whole country as a destination, framed on its largest landmass so far-flung islands don't widen it.
enum CountryDestination {
    static func make(code: String) -> Destination? {
        guard let main = CountryGeometry.shared.polygons(for: [code]).max(by: { $0.boundingMapRect.width * $0.boundingMapRect.height < $1.boundingMapRect.width * $1.boundingMapRect.height }) else { return nil }
        let region = MKCoordinateRegion(main.boundingMapRect)
        let widest = max(region.span.latitudeDelta, region.span.longitudeDelta * cos(region.center.latitude * .pi / 180))
        let name = CountryName.display(code: code)
        return Destination(name: name, region: nil, countryCode: code, countryName: nil,
                           latitude: region.center.latitude, longitude: region.center.longitude,
                           radiusMeters: min(max(widest * 111_000 / 2, 50_000), 1_500_000))
    }
}

enum HomeCities {
    /// One per city name, preferring the copy that has coordinates.
    static func distinct(_ cities: [Destination]) -> [Destination] {
        cities.sorted { ($0.latitude == 0 && $0.longitude == 0 ? 1 : 0) < ($1.latitude == 0 && $1.longitude == 0 ? 1 : 0) }
            .uniqued { "\($0.countryCode ?? "")|\(GeographyKey.normalize($0.name))" }
            .sorted { first, second in cities.firstIndex(of: first) ?? 0 < cities.firstIndex(of: second) ?? 0 }
    }
}

private enum MyPlacesSheet: String, Identifiable {
    case homeCity
    case markCity
    case newTrip

    var id: String { rawValue }
}

/// My Places tab: the globe, with your countries on a card that comes up over it.
struct MyPlacesRootView: View {
    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(LibraryStore.self) private var library
    @State private var model: MyPlacesModel?
    @State private var showsCoachmark = false
    @State private var detent = GlobeSheetDetent.half
    @State private var recenterToken = 0
    @State private var sheet: MyPlacesSheet?
    @State private var tab = MyPlacesTab.been
    @State private var query = ""
    @State private var placeSearch = PlaceSearch()
    @FocusState private var searching: Bool
    @State private var focusRegion: MKCoordinateRegion?

    private var hasQuery: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    private var searchField: some View {
        // Lowered over the dark globe it's plain glass like the buttons there, with a more solid field and white text.
        let overGlobe = detent == .peek
        return HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "magnifyingglass").foregroundStyle(overGlobe ? Color.white.opacity(0.85) : Roam.inkMuted).accessibilityHidden(true)
            TextField("", text: $query, prompt: Text("Search places").foregroundStyle(overGlobe ? Color.white.opacity(0.75) : Roam.inkMuted))
                .foregroundStyle(overGlobe ? Color.white : Roam.ink)
                // A white, regular-sized cursor over the dark glass.
                .tint(overGlobe ? Color.white : Roam.ink)
                .font(.body)
                .focused($searching)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("myplaces-search")
            if hasQuery || searching {
                Button { query = ""; searching = false } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Roam.inkMuted) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel search")
            }
        }
        .padding(.horizontal, overGlobe ? 0 : Theme.Spacing.m)
        .frame(height: 40)
        // In the card, a darker field; lowered, just the glass bubble itself (one tone), with white text.
        .background { if !overGlobe { Capsule().fill(Roam.ink.opacity(0.12)) } }
        .onChange(of: searching) { _, focused in
            guard focused, detent != .full else { return }
            // The card glides up; it rebuilds the field, so the cursor goes back once it has settled.
            withAnimation(.smooth(duration: 0.35)) { detent = .full }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(360))
                searching = true
            }
        }
    }

    /// The same search results as Discover, with your own places matched first.
    private var searchResults: some View {
        PlaceSearchResults(query: query, placeSearch: placeSearch, mine: model?.pins ?? [])
    }

    private func showWorld() {
        focusRegion = nil
        recenterToken += 1
    }

    private var sheetLayout: some View {
        GlobeSheetLayout(detent: $detent, peekHeight: 72, bottomOverlap: detent == .full ? RoamTabBar.reservedHeight + 16 : 0,
                         headerLabel: "My Places",
                         headerIdentifier: "myplaces-sheet-header", onRefresh: { await model?.load() }, floatsWhenPeeking: true,
                         floatingBottomMargin: RoamTabBar.margin, floatingSideMargin: RoamTabBar.sideMargin,
                         collapsesHeaderOnScroll: true, floatingHeight: RoamTabBar.height, peekOpacity: 0,
                         // Tapping the header (outside the search field) flips between halfway and fully up.
                         headerTapToggles: detent != .peek) {
            globe
        } header: {
            // A search bar for every place, there at every height; opened up, your places sit under it.
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                searchField
                if detent != .peek, !hasQuery {
                    Text("My Places").font(.roamTitle()).foregroundStyle(Roam.ink)
                        .accessibilityAddTraits(.isHeader)
                    MyPlacesTabPicker(tab: $tab)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } content: {
            if hasQuery {
                searchResults
            } else if let model, model.hasLoaded {
                switch tab {
                case .been: BeenTab(model: model, onAddHome: { sheet = .homeCity })
                case .going: GoingTab(model: model)
                case .saved: SavedTab(model: model)
                }
            } else if let error = model?.error {
                InlineRetryView(message: error) { Task { await model?.load() } }
            } else {
                SkeletonList(rows: 4)
            }
        }
    }

    var body: some View {
        sheetLayout
        .task(id: query) { await placeSearch.run(query, services: services) }
        // Leaving the tab puts it back on its home page: no search, the card halfway as it opens.
        .onChange(of: router.selectedTab) { _, tab in
            guard tab != .myPlaces else { return }
            query = ""; searching = false; detent = .half
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .homeCity:
                DestinationPickerSheet(purpose: .homeCity, title: "Home city") { city in Task { await model?.setHome(city, present: true) } }
            case .markCity:
                DestinationPickerSheet(purpose: .homeCity, title: "City you've been to") { city in Task { await model?.markVisited(city) } }
            case .newTrip:
                TripEditorSheet(draft: TripDraft()) { _ in Task { await model?.load() } }.presentationBackground(Roam.paper)
            }
        }
        .animation(.spring(duration: 0.35), value: detent)
        .navigationTitle("My Places")
        .navigationBarTitleDisplayMode(.inline)
        // Fully up, the standard tab bar is at the bottom; lower down the search bubble takes its place.
        .roamTabBar(hidden: detent != .full)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            // Back to Discover over the globe; fully up the tab bar is there instead.
            if detent != .full {
                ToolbarItem(placement: .topBarLeading) {
                    Button { router.selectedTab = .forYou } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Back to Discover")
                        .accessibilityIdentifier("myplaces-back")
                }
            }
            // Recentring only matters while the globe is in view.
            if detent != .full {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showWorld() } label: { Image(systemName: "scope") }
                        .accessibilityLabel("Recenter globe")
                        .accessibilityIdentifier("recenter-globe")
                }
            }
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
            SettingsToolbarItem()
        }
        .task {
            if model == nil, let me = session.userID { model = MyPlacesModel(services: services, ownerID: me) }
            await model?.load()
        }
        .onChange(of: library.revision) { _, _ in Task { await model?.load() } }
        // Switching tabs turns the globe to that tab's places.
        .onChange(of: tab) { _, _ in showWorld() }
        .onChange(of: router.path(for: .myPlaces).isEmpty) { _, isRoot in if isRoot { Task { await model?.load() } } }
        .overlay {
            if session.profile?.hasSeenBeenIntro == false {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    BeenIntroCard {
                        Task {
                            await session.markBeenIntroSeen()
                            showsCoachmark = true
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if showsCoachmark { LogCoachmark { showsCoachmark = false } }
        }
        .screenIdentifier("myplaces-root")
    }

    /// The Earth, with your countries filled in and your places as dots. Spin and zoom it freely.
    @ViewBuilder private var globe: some View {
        if let model, model.hasLoaded {
            // Minimised, the globe shows everything; with the card up it shows the chosen tab: green where you've been,
            // blue where you're going, yellow what you've saved.
            let pins = detent != .peek ? model.pins.filter { $0.state == tab.state } : model.pins
            GlobeMapView(pins: pins.map { MapPin(id: $0.id.uuidString, name: $0.experience.name, category: nil, latitude: $0.experience.latitude, longitude: $0.experience.longitude) },
                         shadedCountryCodes: Set(PlaceMapItem.countryTints(pins).keys),
                         focusRegion: focusRegion,
                         focusToken: recenterToken,
                         onSelectPin: { pin in if let id = UUID(uuidString: pin.id) { router.push(.experience(id)) } },
                         globeCenter: PlaceMapItem.startingRegion(pins.isEmpty ? model.pins : pins).center,
                         countryTints: PlaceMapItem.countryTints(pins),
                         // Countries aren't tappable here: the globe just shows them.
                         pinTints: Dictionary(uniqueKeysWithValues: pins.map { ($0.id.uuidString, UIColor($0.state.markerColor)) }))
                .mapAccessibility("Globe of the places you've been, planned and saved", identifier: "myplaces-map")
        } else {
            Color.black
        }
    }
}
