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
    @State private var trips: [TripSummary] = []
    @State private var planningNewTrip = false
    @State private var selection: MapSelection<UUID>?
    @State private var camera: MapCameraPosition = .automatic
    /// The place open over this map, as in Apple Maps: one map, the card swaps.
    @State private var openPlace: UUID?
    /// What the city's map is showing now, for opening a place on the same view.
    @State private var cityViewRegion: MKCoordinateRegion?
    @State private var spotsCollapsed = false
    @State private var suggestionsCollapsed = false

    private var isOwn: Bool { ownerID == nil || ownerID == session.userID }
    private var hasQuery: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    /// Home cities can be stored under more than one region spelling, so they match by country and name.
    private var matchingHomes: [Destination] {
        homes.filter { $0.countryCode?.uppercased() == destination.countryCode?.uppercased() && GeographyKey.normalize($0.name) == GeographyKey.normalize(destination.name) }
    }
    private var isHome: Bool { !matchingHomes.isEmpty }

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
        .navigationTitle(destination.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) } }
        // Searching wants room for the results.
        .onChange(of: searching) { _, focused in if focused && detent != .full { detent = .full } }
        // Tapping a pin, or any place Apple shows on the map, opens that place's page.
        .onChange(of: selection) { _, picked in
            guard let picked else { return }
            selection = nil
            if let id = picked.value, let place = (spots.map(\.experience) + recommended.map(\.experience)).first(where: { $0.id == id }) {
                fly(to: place, moveMap: false)
            } else if let feature = picked.feature {
                Task { await open(feature, moveMap: false) }
            }
        }
        .task(id: destination.id) {
            camera = .region(cityRegion)
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
        .sheet(isPresented: $planningNewTrip) {
            TripEditorSheet(draft: TripDraft(name: destination.name), initialCities: [destination]) { trip in router.push(.trip(trip.id)) }
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
                        .background(Capsule().fill(.ultraThinMaterial))
                        .overlay(Capsule().fill(Roam.ink.opacity(0.05)).allowsHitTesting(false))
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
    private var mapPins: [(place: ExperienceSummary, tint: Color)] {
        spots.map { ($0.experience, PlaceState.visited.markerColor) } + recommended.map { ($0.experience, $0.experience.pinTint) }
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
        .mapFeatureSelectionDisabled { $0.kind != .pointOfInterest }
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
        CityHeader(destination: destination, isHome: isOwn && isHome, showsPlanWithAI: loadedSpots && (mySpotCount == 0 || isHome),
                   onToggleHome: isOwn && loadedSpots ? { Task { await setHome(!isHome) } } : nil,
                   // No trips to your own home; Plan offers AI planning there instead.
                   trips: isOwn && !isHome ? trips.filter { $0.phase(today: MyTimeline.today()) != .past } : nil,
                   onAddToTrip: { trip in Task { await add(to: trip) } },
                   onNewTrip: { planningNewTrip = true },
                   onMarkVisited: { Task { try? await services.plans.setCityVisited(destination, present: true); library.noteChanged() } },
                   showsPhoto: showsPhoto)
    }

    private func refreshMine() async {
        let own = await loadSpots(of: session.userID)
        mySpotCount = own.count
        if isOwn { spots = own; homes = (try? await services.plans.homeCities()) ?? homes }
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
                    if isHome { Image(systemName: "house.fill").foregroundStyle(PlaceState.visited.markerColor).accessibilityLabel("Home") }
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
    var isHome = false
    var showsPlanWithAI = true
    /// Set (or unset) the city as home; nil when it isn't yours to change. Anywhere within 100 km of a home city counts
    /// as home and stays off your travel timeline.
    var onToggleHome: (() -> Void)?
    /// Your trips that haven't happened yet, to add this city to; nil when it isn't yours to plan.
    var trips: [TripSummary]?
    var onAddToTrip: (TripSummary) -> Void = { _ in }
    var onNewTrip: () -> Void = {}
    var onMarkVisited: () -> Void = {}
    var showsPhoto = true

    @Environment(AppRouter.self) private var router

    private var title: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Spacing.s) {
                Text(destination.name).font(.roamDisplay(.title)).lineLimit(1).minimumScaleFactor(0.6).accessibilityAddTraits(.isHeader)
            }
            if !destination.subtitle.isEmpty {
                Text(destination.subtitle).font(.subheadline).foregroundStyle(Roam.inkMuted)
            }
        }
    }

    @ViewBuilder private var actions: some View {
        if showsPlanWithAI || onToggleHome != nil || trips != nil {
            // ViewThatFits drops to icon-only pills when the card is too narrow for the words.
            ViewThatFits(in: .horizontal) {
                actionPills(compact: false)
                actionPills(compact: true)
            }
        }
    }

    private func actionPills(compact: Bool) -> some View {
            HStack(spacing: Theme.Spacing.s) {
                if let onToggleHome {
                    // Once it's home, the pill shrinks to a solid green house.
                    Button(action: onToggleHome) {
                        if compact || isHome { Image(systemName: isHome ? "house.fill" : "house") }
                        else { Label("Set as home", systemImage: "house") }
                    }
                    .buttonStyle(PillButtonStyle(isSelected: isHome, tint: PlaceState.visited.markerColor))
                    .accessibilityLabel(isHome ? "Home" : "Set as home")
                    .accessibilityHint(isHome ? "Removes it as a home city" : "Makes it a home city")
                    .accessibilityIdentifier("city-toggle-home")
                }
                // A home city isn't somewhere to take a trip: the button is just Plan with AI.
                if trips == nil, showsPlanWithAI {
                    Button { router.sheet = .researchBrief(destination) } label: {
                        if compact { Image(systemName: "sparkles") } else { Label("Plan with AI", systemImage: "sparkles") }
                    }
                    .buttonStyle(PillButtonStyle(tint: PlaceState.planned.markerColor))
                    .accessibilityLabel("Plan with AI")
                    .accessibilityIdentifier("foryou-research-open")
                }
                // Otherwise one Plan menu: add the city to a trip (only cities are planned), start one, or plan it with AI.
                if trips != nil {
                    Menu {
                        if let trips {
                            ForEach(trips) { trip in Button("Add to \(trip.name)", systemImage: "airplane") { onAddToTrip(trip) } }
                            Button("New trip", systemImage: "plus") { onNewTrip() }
                            Button("I've been here", systemImage: "checkmark") { onMarkVisited() }
                        }
                        if showsPlanWithAI {
                            Button("Plan with AI", systemImage: "sparkles") { router.sheet = .researchBrief(destination) }
                        }
                    } label: {
                        Label("Plan", systemImage: "airplane")
                    }
                    .buttonStyle(PillButtonStyle(tint: PlaceState.planned.markerColor))
                    .accessibilityIdentifier("city-plan")
                }
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            // The actions always sit level with the name: home, then Plan, on the right. A long name shrinks to fit.
            HStack(alignment: .center, spacing: Theme.Spacing.s) {
                title.layoutPriority(-1)
                Spacer(minLength: Theme.Spacing.xs)
                actions
            }
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
