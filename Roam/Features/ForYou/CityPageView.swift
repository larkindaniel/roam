import MapKit
import SwiftUI

/// One city, the same from Discover and from My Places, and the app's way of exploring it: a full-screen map of the
/// city under a card that swipes up, like a place's page. Minimised, the card is a search bar in the tab bar's spot
/// ("Search Jardín", limited to the city and around it). Halfway or fully up it keeps the search at the top over the
/// city's photo, blurb, the spots you (or the friend whose passport you're in) have been to, and places we think you'd
/// enjoy; while you search, the results take their place. Fully up, the tab bar comes back.
struct CityPageView: View {
    let destination: Destination
    /// Whose spots to show; nil for your own.
    var ownerID: UUID?

    init(destination: Destination, ownerID: UUID? = nil) {
        self.destination = destination
        self.ownerID = ownerID
        // Opened from another map, the map starts on that same view and the card at that height, so nothing flashes.
        let kept = Self.handoffRegion[destination.id]
        _camera = State(initialValue: kept.map { .region($0) } ?? .automatic)
        _detent = State(initialValue: Self.handoffDetent[destination.id] ?? .half)
    }

    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(LibraryStore.self) private var library
    @State private var model: ForYouModel?
    @State private var search: ExperienceSearchModel?
    @State private var query = ""
    @FocusState private var searching: Bool
    @State private var opening: String?
    @State private var openError: String?
    @State private var detent = GlobeSheetDetent.half
    @State private var spots: [ListEntry] = []
    @State private var mySpotCount = 0
    @State private var loadedSpots = false
    @State private var homes: [Destination] = []
    @State private var saved: [Destination] = []
    /// Marked as been without logging a place there.
    @State private var markedVisited = false
    @State private var askingDates = false
    @State private var trips: [TripSummary] = []
    @State private var planningNewTrip = false
    @State private var selection: MapSelection<UUID>?
    @State private var camera: MapCameraPosition = .automatic
    /// The place open over this map, as in Apple Maps: one map, the card swaps.
    @State private var openPlace: UUID?
    /// What the city's map is showing now, for opening a place on the same view.
    @State private var cityViewRegion: MKCoordinateRegion?
    @State private var spotsCollapsed = false
    /// Places you've saved in this city (yours, or the friend's whose passport you're in).
    @State private var wishlist: [ListEntry] = []
    @State private var suggestionsCollapsed = false
    @State private var explainingSaved = false

    /// The view and card height a city opened from another city's map keeps.
    @MainActor static var handoffRegion: [String: MKCoordinateRegion] = [:]
    @MainActor static var handoffDetent: [String: GlobeSheetDetent] = [:]

    private var isOwn: Bool { ownerID == nil || ownerID == session.userID }
    private var hasQuery: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    /// Home cities can be stored under more than one region spelling, so they match by country and name.
    private var matchingHomes: [Destination] {
        homes.filter { $0.countryCode?.uppercased() == destination.countryCode?.uppercased() && GeographyKey.normalize($0.name) == GeographyKey.normalize(destination.name) }
    }
    private var isHome: Bool { !matchingHomes.isEmpty }
    private var matchingSaved: [Destination] {
        saved.filter { $0.countryCode?.uppercased() == destination.countryCode?.uppercased() && GeographyKey.normalize($0.name) == GeographyKey.normalize(destination.name) }
    }
    /// Places you've saved here and not been to: while there are any, the city is on your wishlist too.
    private var savedPlaceCount: Int { wishlist.filter { item in !spots.contains { $0.id == item.id } }.count }
    private var isSaved: Bool { !matchingSaved.isEmpty || (isOwn && savedPlaceCount > 0) }

    /// Places others loved that aren't already among your spots.
    private var recommended: [DiscoverPlace] {
        guard case .loaded(let sections) = model?.phase else { return [] }
        let shown = Set(spots.map(\.id))
        return (sections.friends + sections.highlyRated + sections.more).uniqued { $0.id }.filter { !shown.contains($0.id) }
    }

    var body: some View {
        cityLayout
        // Fully up, the card makes room for the tab bar; lower down it has the bottom of the screen to itself.
        .roamTabBar(hidden: detent != .full)
        // Fully up, the tab bar is there; the back button only shows over the map.
        .navigationBarBackButtonHidden(detent == .full)
        .navigationTitle(destination.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) } }
        // Searching wants room for the results.
        .onChange(of: searching) { _, focused in
            guard focused, detent != .full else { return }
            // The card glides up; it rebuilds the field, so the cursor goes back once it has settled.
            withAnimation(.smooth(duration: 0.35)) { detent = .full }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(360))
                searching = true
            }
        }
        // Tapping a pin, or any place Apple shows on the map, opens that place's page.
        .onChange(of: selection) { _, picked in
            guard let picked else { return }
            selection = nil
            if let id = picked.value, let place = mapPins.map(\.place).first(where: { $0.id == id }) {
                fly(to: place, moveMap: false)
            } else if let feature = picked.feature {
                Task { await open(feature, moveMap: false) }
            }
        }
        .task(id: destination.id) {
            if Self.handoffRegion.removeValue(forKey: destination.id) == nil { camera = .region(cityRegion) }
            Self.handoffDetent.removeValue(forKey: destination.id)
            await reload()
        }
        // Saving or logging the open place recolours its pin.
        // Saving, logging or a home change refreshes your spots and home without reloading the suggestions.
        .onChange(of: library.revision) { _, _ in Task { await refreshMine() } }
        .task(id: query) {
            guard hasQuery else { search?.query = ""; return }
            try? await Task.sleep(for: Limits.searchDebounce)
            guard !Task.isCancelled else { return }
            if search == nil { search = ExperienceSearchModel(services: services) }
            await search?.search(query, near: destination)
        }
        .alert("You've saved \(savedPlaceCount) \(savedPlaceCount == 1 ? "place" : "places") here", isPresented: $explainingSaved) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(destination.name) stays on your wishlist while they're saved. Remove them from their pages to take it off.")
        }
        .sheet(isPresented: $askingDates) {
            CityVisitDatesSheet(city: destination) { markedVisited = true; library.noteChanged() }
        }
        .sheet(isPresented: $planningNewTrip) {
            TripEditorSheet(draft: TripDraft(), initialCities: [destination]) { trip in router.push(.trip(trip.id)) }
                .presentationBackground(Roam.paper)
        }
        .screenIdentifier("city-page")
    }

    private var cityLayout: some View {
        GlobeSheetLayout(detent: $detent, peekHeight: 72, bottomOverlap: detent == .full ? RoamTabBar.reservedHeight + 16 : 0,
                         headerLabel: destination.name, headerIdentifier: "city-sheet-header", onRefresh: { await reload() },
                         floatsWhenPeeking: true, floatingBottomMargin: RoamTabBar.margin, floatingSideMargin: RoamTabBar.sideMargin,
                         collapsesHeaderOnScroll: true, floatingHeight: RoamTabBar.height, headerTapToggles: detent != .peek ) {
            cityMap
        } header: {
            // Minimised, the bubble is the search bar. Opened up, a see-through search bar sits over the city's name; scroll
            // and both give way to the city's name, small and white; scroll back up and they come back down.
            if detent == .peek {
                searchField
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    searchField
                        .padding(.horizontal, Theme.Spacing.m)
                        // A darker grey field inside the card, the same as My Places' search.
                        .background(Capsule().fill(Roam.ink.opacity(0.12)))
                    cityHeader(showsPhoto: false)
                }
            }
        } content: {
            if hasQuery {
                searchResults
            } else {
                cityInfo
            }
        }
    }

    // MARK: Map

    /// The city, with your spots in green and the places we'd suggest in red; tapping one opens it.
    /// The city in the middle of the map you can see above the card, not the middle of the screen.
    private var cityRegion: MKCoordinateRegion {
        ExperienceDetailView.visibleCentered(destination.coordinate, span: max(destination.radiusMeters * 2.2, 6_000))
    }

    /// Opens the place's page straight over this one, with no slide: its map starts on the view you were looking at
    /// (a pin tapped on the map is already on screen) or with the place in the middle of the visible map (from a card
    /// or search result), and its card is already halfway up.
    private func fly(to place: ExperienceSummary, moveMap: Bool = true) {
        searching = false
        ExperienceDetailView.handoff[place.id] = place.coordinate
        ExperienceDetailView.handoffRegion[place.id] = moveMap || cityViewRegion == nil
            ? ExperienceDetailView.visibleCentered(place.coordinate, span: ExperienceDetailView.placeSpan)
            : cityViewRegion
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { router.push(.experience(place.id)) }
    }

    /// Every pin on the city's map, each in its place's own colour: green where you've been, yellow if saved, red
    /// otherwise. Opening one keeps its colour.
    private var mapPins: [(place: ExperienceSummary, tint: Color, symbol: String)] {
        // Only your own places go on the map: where you've been, then what you've saved here. Suggestions stay in the list.
        // The place's own icon, green where you've been and yellow for what you've saved.
        spots.map { ($0.experience, PlaceState.visited.markerColor, "checkmark") }
            + wishlist.filter { item in !spots.contains { $0.id == item.id } }.map { ($0.experience, PlaceState.wishlist.markerColor, "bookmark.fill") }
    }

    private var cityMap: some View {
        Map(position: $camera, selection: $selection) {
            // With a place open, only it keeps the full pin; the rest shrink to dots so it stands out.
            ForEach(mapPins, id: \.place.id) { pin in
                if openPlace == nil || openPlace == pin.place.id {
                    Marker(pin.place.name, systemImage: pin.place.iconName, coordinate: pin.place.coordinate)
                        .tint(pin.tint)
                        .tag(MapSelection(pin.place.id))
                } else {
                    Annotation(pin.place.name, coordinate: pin.place.coordinate) {
                        Circle().fill(pin.tint).frame(width: 12, height: 12)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    }
                    .annotationTitles(.hidden)
                    .tag(MapSelection(pin.place.id))
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .all))
        .mapFeatureSelectionDisabled { $0.kind != .pointOfInterest && $0.kind != .territory }
        .onMapCameraChange(frequency: .onEnd) { cityViewRegion = $0.region }
        .accessibilityLabel("Map of \(destination.name)")
        .accessibilityIdentifier("city-map")
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "magnifyingglass").foregroundStyle(Roam.inkMuted).accessibilityHidden(true)
            TextField("Search \(destination.name)", text: $query)
                .focused($searching)
                .submitLabel(.search)
                // Type as you like: no capitalising or correcting.
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("city-search")
            if hasQuery || searching {
                Button {
                    query = ""
                    searching = false
                } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Roam.inkMuted) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel search")
            }
        }
        .font(.body)
        .frame(height: 40)
        .frame(maxWidth: .infinity)
    }

    /// Only what's in the city or just around it.
    private var nearbyHits: [SearchHit] {
        let center = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        let limit = max(destination.radiusMeters * 3, 25_000)
        return (search?.hits ?? []).filter {
            CLLocation(latitude: $0.candidate.latitude, longitude: $0.candidate.longitude).distance(from: center) <= limit
        }
    }

    @ViewBuilder private var searchResults: some View {
        if let openError { Text(openError).font(.footnote).foregroundStyle(Roam.signal) }
        switch search?.phase ?? .loading {
        case .idle, .loading:
            SkeletonList(rows: 3)
        case .failed(let message):
            InlineRetryView(message: message) { Task { await search?.search(query, near: destination) } }
        case .noResults, .results:
            if nearbyHits.isEmpty {
                Text("Nothing in \(destination.name) matches \u{201C}\(query)\u{201D}.").font(.subheadline).foregroundStyle(Roam.inkMuted)
            } else {
                VStack(spacing: 0) {
                    ForEach(nearbyHits) { hit in
                        Button { Task { await open(hit) } } label: {
                            HStack(spacing: Theme.Spacing.m) {
                                Image(systemName: hit.experience?.iconName ?? hit.candidate.iconName).foregroundStyle(Roam.inkMuted).frame(width: 24).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(hit.candidate.name).font(.headline).foregroundStyle(Roam.ink).lineLimit(1)
                                    Text(shortAddress(hit.candidate)).font(.footnote).foregroundStyle(Roam.inkMuted).lineLimit(1)
                                }
                                Spacer(minLength: Theme.Spacing.s)
                                if opening == hit.id { ProgressView() }
                            }
                            .frame(minHeight: Theme.minimumHitTarget)
                            .padding(.vertical, Theme.Spacing.s)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(opening != nil)
                        .accessibilityIdentifier("city-result-\(hit.candidate.name)")
                        if hit.id != nearbyHits.last?.id { Divider().padding(.leading, 24 + Theme.Spacing.m) }
                    }
                }
                .roamCard(padding: Theme.Spacing.m)
            }
        }
    }

    /// The street and the city, stopping there: no province, postal code or country.
    private func shortAddress(_ place: PlaceCandidate) -> String {
        guard let address = place.address, !address.isEmpty else { return place.locality ?? "" }
        let parts = address.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var kept = Array(parts.prefix(2))
        if let city = place.locality, let index = parts.firstIndex(where: { $0.localizedCaseInsensitiveContains(city) }) {
            kept = Array(parts[...index])
            // "Supía 178020" → "Supía": the city itself, not the postal code beside it.
            kept[kept.count - 1] = city
        }
        return kept.joined(separator: ", ")
    }

    private func open(_ feature: MapFeature, moveMap: Bool = true) async {
        // Another city on the map opens that city's page.
        if feature.kind == .territory {
            if let city = try? await services.places.destination(for: feature.coordinate),
               GeographyKey.normalize(city.name) != GeographyKey.normalize(destination.name) {
                // Like going place to place: the map stays put and the card keeps its height; only what's in it changes.
                Self.handoffRegion[city.id] = cityViewRegion
                Self.handoffDetent[city.id] = detent
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) { router.push(.city(city)) }
            }
            return
        }
        guard let item = try? await MKMapItemRequest(feature: feature).mapItem,
              let candidate = MapKitPlaceSearchProvider.candidate(from: item),
              let place = try? await services.experiences.resolve(candidate) else { return }
        fly(to: place, moveMap: moveMap)
    }

    private func open(_ hit: SearchHit) async {
        opening = hit.id
        defer { opening = nil }
        do {
            guard let search else { return }
            let place = try await search.resolve(hit)
            openError = nil
            fly(to: place)
        } catch { openError = error.roamMessage }
    }

    // MARK: City

    @ViewBuilder private var cityInfo: some View {
        CityPhoto(destination: destination)
        CityGuideCard(name: destination.name, region: destination.region, country: destination.countryName,
                      coordinate: destination.coordinate, showsPhoto: false)
        if !spots.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                collapsibleTitle(isOwn ? "Your spots" : "Their spots", collapsed: $spotsCollapsed)
                if !spotsCollapsed { LazyVStack(spacing: Theme.Spacing.l) {
                    ForEach(spots) { entry in
                        DiscoverPlaceCard(experience: entry.experience, score: entry.ownerScore) { fly(to: entry.experience) }
                    }
                } }
            }
        }
        switch model?.phase ?? .loading {
        case .idle, .loading:
            SkeletonList(rows: 3)
        case .failed(let message):
            InlineRetryView(message: message) { Task { await model?.load(destination) } }
        case .loaded:
            if !recommended.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    collapsibleTitle("Places we think you'd enjoy", collapsed: $suggestionsCollapsed)
                    // Lazy, so only the cards on screen build their maps.
                    if !suggestionsCollapsed { LazyVStack(spacing: Theme.Spacing.l) {
                        ForEach(recommended) { place in
                            DiscoverPlaceCard(experience: place.experience, path: place.coverPath, evidence: place.friendEvidence,
                                              score: (place.friendEvidence != nil ? place.experience.followingScore : nil) ?? place.communityScore) {
                                fly(to: place.experience)
                            }
                        }
                    } }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("discover-places")
            }
        }
    }

    private func cityHeader(showsPhoto: Bool) -> some View {
        CityHeader(destination: destination, hasBeen: mySpotCount > 0 || markedVisited, spotCount: mySpotCount, isHome: isOwn && isHome, showsPlanWithAI: loadedSpots && (mySpotCount == 0 || isHome),
                   onToggleHome: isOwn && loadedSpots ? { Task { await setHome(!isHome) } } : nil,
                   // No trips to your own home; Plan offers AI planning there instead.
                   trips: isOwn && !isHome ? trips.filter { $0.phase(today: MyTimeline.today()) != .past } : nil,
                   onAddToTrip: { trip in Task { await add(to: trip) } },
                   onNewTrip: { planningNewTrip = true },
                   // Marking it been asks when you were there; unmarking just removes it.
                   onMarkVisited: { present in
                       if present { askingDates = true }
                       else { Task { try? await services.plans.setCityVisited(destination, present: false); markedVisited = false; library.noteChanged() } }
                   },
                   isSaved: isSaved,
                   // Saved because of places saved here: it comes off with them, so tapping explains instead.
                   onToggleSaved: {
                       if isSaved && matchingSaved.isEmpty { explainingSaved = true } else { Task { await setSaved(!isSaved) } }
                   },
                   showsPhoto: showsPhoto)
    }

    /// A whole city on your wishlist; it shows on My Places' Saved tab.
    private func setSaved(_ present: Bool) async {
        if present {
            saved = (try? await services.plans.setCitySaved(destination, present: true)) ?? saved
        } else {
            for stored in matchingSaved { saved = (try? await services.plans.setCitySaved(stored, present: false)) ?? saved }
        }
        library.noteChanged()
    }

    private func refreshMine() async {
        let own = await loadSpots(of: session.userID)
        mySpotCount = own.count
        if isOwn { spots = own; homes = (try? await services.plans.homeCities()) ?? homes }
        // Saving or logging a place here updates its pin.
        if isOwn, let me = session.userID, let saved = try? await services.lists.want(ownerID: me) {
            wishlist = saved.filter { CityMatch.same($0.experience, destination) }
        }
    }

    private func reload() async {
        async let mine = loadSpots(of: session.userID)
        async let theirs = isOwn ? [] : loadSpots(of: ownerID)
        let own = await mine
        mySpotCount = own.count
        spots = isOwn ? own : await theirs
        loadedSpots = true
        if isOwn {
            homes = (try? await services.plans.homeCities()) ?? []
            trips = (try? await services.plans.myTrips()) ?? []
            saved = (try? await services.plans.savedCities()) ?? []
            if let me = session.userID, let passport = try? await services.plans.passport(ownerID: me) {
                markedVisited = passport.flatMap(\.cities).contains { $0.isMarked && GeographyKey.normalize($0.city.name) == GeographyKey.normalize(destination.name)
                    && $0.city.countryCode?.uppercased() == destination.countryCode?.uppercased() }
            }
        }
        if isOwn, let me = session.userID, let saved = try? await services.lists.want(ownerID: me) {
            wishlist = saved.filter { CityMatch.same($0.experience, destination) }
        }
        if model == nil { model = ForYouModel(plans: services.plans) }
        await model?.load(destination)
    }

    /// Only cities are planned: the city joins the trip, and places you've saved here show up on it.
    private func add(to trip: TripSummary) async {
        try? await services.plans.setTripCity(tripID: trip.id, city: destination, present: true)
        library.noteChanged()
        router.push(.trip(trip.id))
    }

    private func setHome(_ present: Bool) async {
        if present {
            homes = (try? await services.plans.setHomeCity(destination, present: true)) ?? homes
            // A home counts as somewhere you've been (the server marks it too).
            markedVisited = true
        } else {
            for stored in matchingHomes { homes = (try? await services.plans.setHomeCity(stored, present: false)) ?? homes }
        }
        // My Places reloads its home cities.
        library.noteChanged()
    }

    private func loadSpots(of owner: UUID?) async -> [ListEntry] {
        guard let owner, let been = try? await services.lists.been(ownerID: owner) else { return [] }
        return been.filter { CityMatch.same($0.experience, destination) }
            .sorted { ($0.ownerScore?.tenths ?? -1) > ($1.ownerScore?.tenths ?? -1) }
    }

    /// A section heading with a chevron that folds the list away and back.
    private func collapsibleTitle(_ title: String, collapsed: Binding<Bool>) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { collapsed.wrappedValue.toggle() }
        } label: {
            HStack {
                Text(title).font(.roamTitle()).foregroundStyle(Roam.ink)
                Spacer(minLength: Theme.Spacing.s)
                Image(systemName: "chevron.down").font(.headline).foregroundStyle(Roam.inkMuted)
                    .rotationEffect(.degrees(collapsed.wrappedValue ? -90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityHint(collapsed.wrappedValue ? "Shows the list" : "Hides the list")
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.roamTitle()).foregroundStyle(Roam.ink).accessibilityAddTraits(.isHeader)
    }
}

/// Finds the city at a point (or where you are) and shows its page; failing that, your home city or the last city you
/// looked at.
struct CityAtView: View {
    var coordinate: CLLocationCoordinate2D?

    @Environment(AppServices.self) private var services
    @Environment(DestinationStore.self) private var destinations
    @State private var city: Destination?
    @State private var lookedUp = false

    var body: some View {
        Group {
            if let city {
                CityPageView(destination: city)
            } else if lookedUp {
                EmptyStateView(systemImage: "map", title: "No city found", message: "Search for a city on Discover to explore it.")
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            guard city == nil else { return }
            var point = coordinate
            if point == nil, case .located(let here, _) = await services.location.currentLocation(timeout: .seconds(5)) { point = here }
            if let point, let found = try? await services.places.destination(for: point) { city = found }
            if city == nil { city = (try? await services.plans.homeCities())?.first ?? destinations.lastSelected }
            lookedUp = true
        }
    }
}

/// A place's card: its photo, or a map of where it is when there's none, then who's been and the score.
struct DiscoverPlaceCard: View {
    let experience: ExperienceSummary
    var path: String?
    var evidence: String?
    var score: Score?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PhotoCard(path: path, url: experience.photoURL, credit: experience.photoCredit,
                      label: "Photo of \(experience.name)", placeholderSymbol: experience.iconName,
                      height: 190, location: experience.coordinate) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(experience.name).font(.headline).foregroundStyle(Roam.ink).lineLimit(2).multilineTextAlignment(.leading)
                        Text([experience.category?.title, experience.locality].compactMap { $0 }.joined(separator: " · "))
                            .font(.footnote).foregroundStyle(Roam.inkMuted).lineLimit(1)
                        if let evidence { Text(evidence).font(.subheadline).foregroundStyle(Roam.ink).lineLimit(1) }
                        GoogleRatingLine(experience: experience)
                    }
                    Spacer(minLength: Theme.Spacing.s)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("foryou-place-\(experience.name)")
    }
}

/// A city's card for a list of cities: its Wikipedia photo with the name underneath.
struct CityPhotoCard: View {
    let destination: Destination
    var isHome = false

    @State private var guide: CityGuide?

    var body: some View {
        PhotoCard(url: guide?.photoURL, label: "Photo of \(destination.name)",
                  placeholderSymbol: "building.2", height: 160, location: destination.coordinate) {
            // The credit sits snug under the name.
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Theme.Spacing.s) {
                    if isHome { Image(systemName: "house.fill").foregroundStyle(Roam.home).accessibilityLabel("Home") }
                    Text(destination.name).font(.roamTitle()).foregroundStyle(Roam.ink)
                    Spacer(minLength: 0)
                }
                if guide?.photoURL != nil { Text("Photo: Wikipedia").font(.caption2).foregroundStyle(Roam.inkMuted) }
            }
        }
        .task(id: destination.id) {
            guide = await CityGuide.load(name: destination.name, region: destination.region, country: destination.countryName,
                                         coordinate: destination.coordinate)
        }
    }
}

/// The city heads its page: name and where it is, Plan with AI when you haven't been, then its Wikipedia photo.
struct CityHeader: View {
    let destination: Destination
    /// You've been: you have spots here (or just marked it).
    var hasBeen = false
    /// How many places you've logged here; while there are any, the city stays been.
    var spotCount = 0
    @State private var confirmingUnbeen = false
    @State private var markedNow = false
    private var beenHere: Bool { markedNow || hasBeen }
    var isHome = false
    var showsPlanWithAI = true
    /// Set (or unset) the city as home; nil when it isn't yours to change. Anywhere within 100 km of a home city counts
    /// as home and stays off your travel timeline.
    var onToggleHome: (() -> Void)?
    /// Your trips that haven't happened yet, to add this city to; nil when it isn't yours to plan.
    var trips: [TripSummary]?
    var onAddToTrip: (TripSummary) -> Void = { _ in }
    var onNewTrip: () -> Void = {}
    var onMarkVisited: (Bool) -> Void = { _ in }
    var isSaved = false
    var onToggleSaved: () -> Void = {}
    var showsPhoto = true

    @Environment(AppRouter.self) private var router

    private var title: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Spacing.s) {
                Text(destination.name).font(.roamDisplay(.title)).lineLimit(1).minimumScaleFactor(0.6).accessibilityAddTraits(.isHeader)
            }
            // The country first, as a slim grey chip that opens its page (as a place's city does); then the region.
            HStack(spacing: Theme.Spacing.s) {
                if let code = destination.countryCode?.uppercased(), code.count == 2 {
                    Button { router.push(.country(code)) } label: {
                        HStack(spacing: 3) {
                            Text(CountryName.display(destination.countryName, code: code) ?? code).lineLimit(1)
                            Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Roam.ink)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(Roam.ink.opacity(0.08)))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("city-open-country")
                    if let region = destination.region, !region.isEmpty, region != destination.name {
                        Text(region).font(.subheadline).foregroundStyle(Roam.inkMuted).lineLimit(1)
                    }
                } else if !destination.subtitle.isEmpty {
                    Text(destination.subtitle).font(.subheadline).foregroundStyle(Roam.inkMuted)
                }
            }
        }
    }

    /// Set as home, on the title row; a home city shows as a solid black house.
    @ViewBuilder private var homePill: some View {
        if let onToggleHome {
            Button(action: onToggleHome) {
                if isHome { Image(systemName: "house.fill") } else { Label("Set as home", systemImage: "house") }
            }
            .buttonStyle(PillButtonStyle(isSelected: isHome, tint: Roam.home))
            .accessibilityLabel(isHome ? "Home" : "Set as home")
            .accessibilityHint(isHome ? "Removes it as a home city" : "Makes it a home city")
            .accessibilityIdentifier("city-toggle-home")
        }
    }

    /// Round actions with a caption under each, laid out like a place's: been here (green), wishlist (yellow), add to a
    /// trip (blue), send (indigo) and plan with AI (pink). A home city keeps just send and AI.
    private var actionRow: some View {
        // Spread evenly across the card's width.
        HStack(spacing: 0) {
            if trips != nil {
                circle(beenHere ? "checkmark" : "plus", tint: PlaceState.visited.markerColor, filled: beenHere,
                       caption: beenHere ? "Been" : "Log", identifier: "city-log") {
                    // Tapping again asks before taking it back off where you've been.
                    if beenHere { confirmingUnbeen = true } else { onMarkVisited(true) }
                }
                .alert(spotCount > 0 ? "You've logged \(spotCount) \(spotCount == 1 ? "spot" : "spots") here" : "Remove from places you've been?",
                       isPresented: $confirmingUnbeen) {
                    if spotCount > 0 {
                        Button("OK", role: .cancel) {}
                    } else {
                        Button("Remove", role: .destructive) { markedNow = false; onMarkVisited(false) }
                        Button("Cancel", role: .cancel) {}
                    }
                } message: {
                    if spotCount > 0 {
                        Text("\(destination.name) counts as somewhere you've been while those are logged. Remove them from their pages to take it off.")
                    }
                }
                // Somewhere you've been isn't on your wishlist: once you've been, Wishlist greys out.
                circle(isSaved ? "bookmark.fill" : "bookmark", tint: beenHere ? Roam.inkFaint : PlaceState.wishlist.markerColor,
                       filled: isSaved && !beenHere, caption: isSaved ? "Saved" : "Wishlist", identifier: "city-wishlist") {
                    if !beenHere { onToggleSaved() }
                }
                Menu {
                    ForEach(trips ?? []) { trip in Button(trip.name) { onAddToTrip(trip) } }
                    Button("New trip", systemImage: "plus") { onNewTrip() }
                } label: {
                    circleLabel("airplane", tint: PlaceState.planned.markerColor, filled: false, caption: "Trip")
                }
                .accessibilityLabel("Add to a trip")
                .accessibilityIdentifier("city-trip")
            }
            // Sending isn't ready yet, so Send shows greyed out.
            circleLabel("paperplane", tint: Roam.inkFaint, filled: false, caption: "Send")
                .opacity(0.7)
                .accessibilityLabel("Send (coming soon)")
                .accessibilityIdentifier("city-send")
            circle("sparkles", tint: .pink, filled: false, caption: "Plan", identifier: "foryou-research-open") {
                router.sheet = .researchBrief(destination)
            }
        }
    }

    private func circle(_ symbol: String, tint: Color, filled: Bool, caption: String, identifier: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) { circleLabel(symbol, tint: tint, filled: filled, caption: caption) }
            .buttonStyle(.plain)
            .accessibilityLabel(caption)
            .accessibilityIdentifier(identifier)
    }

    private func circleLabel(_ symbol: String, tint: Color, filled: Bool, caption: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(filled ? .white : tint)
                .frame(width: 38, height: 38)
                .background(Circle().fill(filled ? tint : tint.opacity(0.15)))
            Text(caption).font(.caption2).foregroundStyle(Roam.ink).lineLimit(1).fixedSize()
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            // The name with Set as home beside it, then the actions underneath, as on a place.
            HStack(alignment: .center, spacing: Theme.Spacing.s) {
                title.layoutPriority(-1)
                Spacer(minLength: Theme.Spacing.xs)
                // A home city needs no row of actions: just its house, then Plan, beside the name.
                homePill
                if isHome {
                    Button { router.sheet = .researchBrief(destination) } label: { Label("Plan", systemImage: "sparkles") }
                        .buttonStyle(PillButtonStyle(tint: .pink))
                        .accessibilityLabel("Plan with AI")
                        .accessibilityIdentifier("foryou-research-open")
                }
            }
            if !isHome { actionRow }
            // Credited once, under the blurb that follows.
            if showsPhoto { CityPhoto(destination: destination) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("discover-city-header")
    }
}

/// A city's Wikipedia lead photo; credited once, under the blurb that follows it.
struct CityPhoto: View {
    let destination: Destination
    @State private var guide: CityGuide?

    var body: some View {
        // A ZStack always has a view to host `.task`; an empty Group would never run it.
        ZStack {
            if let photo = guide?.photoURL {
                PlacePhotoView(url: photo, credit: nil, label: "Photo of \(destination.name)", placeholderSymbol: "building.2", height: 220, showsCredit: false)
            }
        }
        .task(id: destination.id) {
            guide = await CityGuide.load(name: destination.name, region: destination.region, country: destination.countryName, coordinate: destination.coordinate)
        }
    }
}

/// When you were in a city you're marking as been. Both dates are optional.
struct CityVisitDatesSheet: View {
    let city: Destination
    var onSaved: () -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date?
    @State private var end: Date?
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TripDatesRow(start: $start, end: $end)
                } header: {
                    Text("When were you there?")
                } footer: {
                    Text("Optional. Dates put \(city.name) in order on your timeline and in friends' feeds.")
                }
                .listRowBackground(Roam.paperRaised)
                if let error { Section { Text(error).foregroundStyle(Roam.signal) } }
            }
            .scrollContentBackground(.hidden)
            .background(Roam.paper)
            .navigationTitle(city.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(saving).accessibilityIdentifier("city-dates-save")
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await services.plans.markCityVisited(city, start: start.map { LocalDate(date: $0, timeZone: .current) },
                                                     end: end.map { LocalDate(date: $0, timeZone: .current) })
            onSaved()
            dismiss()
        } catch { self.error = error.roamMessage }
    }
}
