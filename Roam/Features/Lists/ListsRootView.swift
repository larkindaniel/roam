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
        let name = Locale.current.localizedString(forRegionCode: code) ?? code
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
    /// The country the globe is zoomed in on; the card shows that country instead of everything.
    @State private var focusedCountry: String?
    @State private var focusRegion: MKCoordinateRegion?
    @State private var flyingToCountry = false

    private func countryTitle(_ code: String) -> String {
        model?.countries.first { $0.code == code }?.title ?? CountryTitle.text(name: Locale.current.localizedString(forRegionCode: code), code: code)
    }

    /// Countries with something of yours in them: places, or a trip that's still ahead.
    private func isYours(_ code: String) -> Bool {
        guard let model else { return false }
        return model.countries.contains { $0.code == code }
            || model.trips.contains { trip in trip.phase(today: MyTimeline.today()) != .past && trip.cities.contains { $0.countryCode?.uppercased() == code } }
    }

    private func zoom(to code: String) {
        // A country you have nothing in does nothing when tapped.
        guard isYours(code) else { return }
        // Framed on your places there when you have some, so a big country doesn't open on empty land.
        let mine = model?.countries.first { $0.code == code }?.items.map(\.experience) ?? []
        if let minLat = mine.map(\.latitude).min(), let maxLat = mine.map(\.latitude).max(),
           let minLon = mine.map(\.longitude).min(), let maxLon = mine.map(\.longitude).max() {
            focusRegion = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
                                             span: MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.4, 1.5), longitudeDelta: max((maxLon - minLon) * 1.4, 1.5)))
        } else if let destination = CountryDestination.make(code: code) {
            focusRegion = MKCoordinateRegion(center: destination.coordinate, latitudinalMeters: destination.radiusMeters * 2, longitudinalMeters: destination.radiusMeters * 2)
        } else {
            return
        }
        recenterToken += 1
        flyingToCountry = true
        focusedCountry = code
        if detent == .full { detent = .half }
    }

    private func showWorld() {
        focusRegion = nil
        recenterToken += 1
        focusedCountry = nil
    }

    var body: some View {
        GlobeSheetLayout(detent: $detent, peekHeight: 72, bottomOverlap: detent == .full ? RoamTabBar.reservedHeight + 16 : 0,
                         headerLabel: focusedCountry.map(countryTitle) ?? "My Places",
                         headerIdentifier: "myplaces-sheet-header", onRefresh: { await model?.load() }, floatsWhenPeeking: true,
                         collapsesHeaderOnScroll: true) {
            globe
        } header: {
            if detent == .peek {
                // Minimised, like a place's bubble: the name and one action.
                HStack {
                    Text(focusedCountry.map(countryTitle) ?? "My Places").font(.roamTitle()).foregroundStyle(Roam.ink).lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    Button { router.sheet = .logPlace } label: { PillLabel(title: "Add a place", systemImage: "plus") }
                        .buttonStyle(PillButtonStyle(isSelected: true, tint: PlaceState.visited.markerColor))
                        .accessibilityIdentifier("myplaces-add-place")
                }
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text(focusedCountry.map(countryTitle) ?? "My Places").font(.roamTitle()).foregroundStyle(Roam.ink)
                        .accessibilityAddTraits(.isHeader)
                    if focusedCountry == nil { MyPlacesTabPicker(tab: $tab) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } content: {
            if let model, model.hasLoaded {
                if let focusedCountry {
                    CountryFocusSection(model: model, code: focusedCountry, title: countryTitle(focusedCountry))
                } else {
                    switch tab {
                    case .been: BeenTab(model: model, onMarkCity: { sheet = .markCity }, onAddHome: { sheet = .homeCity })
                    case .going: GoingTab(model: model) { sheet = .newTrip }
                    case .saved: SavedTab(model: model)
                    }
                }
            } else if let error = model?.error {
                InlineRetryView(message: error) { Task { await model?.load() } }
            } else {
                SkeletonList(rows: 4)
            }
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
        .navigationTitle("My Places")
        .navigationBarTitleDisplayMode(.inline)
        // The tab bar comes back only once the card is fully up; over the globe the card has the bottom to itself.
        .roamTabBar(hidden: detent != .full)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            // Fully up: log a place, with the tab bar below. Lower down, back to Discover takes its place.
            ToolbarItem(placement: .topBarLeading) {
                if detent == .full {
                    Button { router.sheet = .logPlace } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Log a place")
                        .accessibilityIdentifier("log-place")
                } else {
                    Button { router.selectedTab = .forYou } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Back to Discover")
                        .accessibilityIdentifier("myplaces-back")
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button { showWorld() } label: { Image(systemName: "scope") }
                    .accessibilityLabel("Recenter globe")
                    .accessibilityIdentifier("recenter-globe")
            }
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
            ToolbarItem(placement: .topBarTrailing) {
                // The globe stays satellite; the street map opens on its own, on the country you're looking at.
                Button {
                    if let focusedCountry { router.push(.myCountry(code: focusedCountry, title: countryTitle(focusedCountry))) } else { router.push(.explore) }
                } label: { Image(systemName: "map") }
                    .accessibilityLabel(focusedCountry.map { "Map of \(countryTitle($0))" } ?? "Explore the map")
                    .accessibilityIdentifier("myplaces-open-map")
            }
            ToolbarItem(placement: .topBarTrailing) { ProfileAvatarButton() }
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
            // The globe shows the chosen tab: green where you've been, blue where you're going, yellow what you've saved.
            let pins = focusedCountry == nil ? model.pins.filter { $0.state == tab.state } : model.pins
            GlobeMapView(pins: pins.map { MapPin(id: $0.id.uuidString, name: $0.experience.name, category: nil, latitude: $0.experience.latitude, longitude: $0.experience.longitude) },
                         shadedCountryCodes: Set(PlaceMapItem.countryTints(pins).keys),
                         focusRegion: focusRegion,
                         focusToken: recenterToken,
                         onSelectPin: { pin in if let id = UUID(uuidString: pin.id) { router.push(.experience(id)) } },
                         globeCenter: PlaceMapItem.startingRegion(pins.isEmpty ? model.pins : pins).center,
                         countryTints: PlaceMapItem.countryTints(pins),
                         pinTints: Dictionary(uniqueKeysWithValues: pins.map { ($0.id.uuidString, UIColor($0.state.markerColor)) }),
                         onSelectCountry: { code in zoom(to: code) },
                         onCameraChange: { center, scale in
                             // Landing after flying to a tapped country keeps that country, even if the middle of the
                             // view (framed on your places there) falls just over a border.
                             if flyingToCountry { flyingToCountry = false; return }
                             // Close enough to see one country, the card follows whichever is under the middle of the view.
                             let code = scale < 22_000 ? CountryGeometry.shared.code(at: center, among: Set(CountryGeometry.shared.allCodes)).flatMap { isYours($0) ? $0 : nil } : nil
                             if code != focusedCountry { focusedCountry = code }
                         })
                .mapAccessibility("Globe of the places you've been, planned and saved", identifier: "myplaces-map")
        } else {
            Color.black
        }
    }
}
