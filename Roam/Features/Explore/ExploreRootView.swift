import MapKit
import SwiftUI

struct ExploreItem: Identifiable, Hashable {
    let id: String
    var candidate: PlaceCandidate?
    var experience: ExperienceSummary?

    var name: String { experience?.name ?? candidate?.name ?? "" }
    var category: ExperienceCategory? { experience?.category ?? candidate?.suggestedCategory }
    var latitude: Double { experience?.latitude ?? candidate?.latitude ?? 0 }
    var longitude: Double { experience?.longitude ?? candidate?.longitude ?? 0 }
    var area: String {
        if let experience { return experience.areaLine }
        return [candidate?.locality, candidate?.countryName].compactMap { $0 }.uniqued().joined(separator: ", ")
    }

    var pin: MapPin { MapPin(id: id, name: name, category: category, latitude: latitude, longitude: longitude) }
}

@MainActor
@Observable
final class ExploreModel {
    var category: ExperienceCategory?
    /// Text typed in the search bar; while set, the map searches for it instead of browsing.
    private(set) var query = ""
    var showsMap = true
    var selectedID: String?
    private(set) var items: [ExploreItem] = []
    private(set) var phase: LoadPhase<Void> = .idle
    private(set) var loadedRegion: MKCoordinateRegion?
    var visibleRegion: MKCoordinateRegion?
    var focusRegion: MKCoordinateRegion?
    var focusToken = 0
    var locationMessage: String?
    private var generation = 0
    private var foregroundLoading = false
    private var projectionRefreshQueued = false
    private let places: any PlaceSearchProviding
    private let experiences: any ExperienceService
    private var requestedRegion: MKCoordinateRegion?
    private var followMap: Task<Void, Never>?

    /// Places with Roam data stay pinned; Apple Maps' other places show on the map itself and open when tapped.
    var pinnedItems: [ExploreItem] { items.filter { $0.experience != nil } }

    /// Loads the area the map settles on, so places appear as you move around.
    func regionChanged(_ region: MKCoordinateRegion) {
        visibleRegion = region
        followMap?.cancel()
        followMap = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, loadedRegion == nil || canSearchThisArea else { return }
            await load(region: region)
        }
    }

    /// An Apple Maps place tapped on the map: its Roam match if there is one, else a new result to open or log.
    func select(mapItem: MKMapItem) {
        guard let candidate = MapKitPlaceSearchProvider.candidate(from: mapItem) else { return }
        if let known = items.first(where: { $0.candidate?.id == candidate.id || ($0.name == candidate.name && abs($0.latitude - candidate.latitude) < 0.002 && abs($0.longitude - candidate.longitude) < 0.002) }) {
            selectedID = known.id
        } else {
            items.append(ExploreItem(id: candidate.id, candidate: candidate, experience: nil))
            selectedID = candidate.id
        }
    }

    init(services: AppServices) {
        places = services.places
        experiences = services.experiences
    }

    init(places: any PlaceSearchProviding, experiences: any ExperienceService) {
        self.places = places
        self.experiences = experiences
    }

    func retry() async {
        guard let region = requestedRegion else { return }
        await load(region: region)
    }

    /// True after the member pans/zooms away from the area the results came from.
    var canSearchThisArea: Bool {
        guard let loaded = loadedRegion, let visible = visibleRegion else { return false }
        let moved = abs(loaded.center.latitude - visible.center.latitude) > loaded.span.latitudeDelta * 0.25
            || abs(loaded.center.longitude - visible.center.longitude) > loaded.span.longitudeDelta * 0.25
        let zoomed = abs(loaded.span.latitudeDelta - visible.span.latitudeDelta) > loaded.span.latitudeDelta * 0.4
        return moved || zoomed
    }

    func focus(on destination: Destination) async {
        let region = MKCoordinateRegion(center: destination.coordinate, latitudinalMeters: destination.radiusMeters * 2,
                                        longitudinalMeters: destination.radiusMeters * 2)
        focusRegion = region
        focusToken += 1
        await load(region: region)
    }

    /// New viewport results replace the previous set; incompatible regions never merge silently.
    func load(region: MKCoordinateRegion) async {
        generation += 1
        let current = generation
        requestedRegion = region
        foregroundLoading = true
        defer {
            if current == generation {
                foregroundLoading = false
                if projectionRefreshQueued {
                    projectionRefreshQueued = false
                    Task { await self.refreshMatches() }
                }
            }
        }
        phase = .loading
        do {
            let text = query
            let around = Destination(name: "", region: nil, countryCode: nil, countryName: nil, latitude: region.center.latitude,
                                     longitude: region.center.longitude, radiusMeters: region.span.latitudeDelta * 111_000 / 2)
            async let poiResult = text.isEmpty
                ? places.pointsOfInterest(in: region, category: category)
                : places.searchPlaces(query: text, around: around)
            async let roamResult = experiences.experiences(in: GeoBounds(region: region), category: category)
            let pois = try await poiResult
            let roam = try await roamResult
            let matches = try await experiences.matches(for: pois)
            try Task.checkCancellation()
            guard current == generation else { return }
            var seenExperiences = Set<UUID>()
            var merged: [ExploreItem] = pois.map { poi in
                let match = matches[poi.id]
                if let match { seenExperiences.insert(match.id) }
                return ExploreItem(id: match.map { $0.id.uuidString } ?? poi.id, candidate: poi, experience: match)
            }
            merged += roam.filter { !seenExperiences.contains($0.id) }.map { ExploreItem(id: $0.id.uuidString, candidate: nil, experience: $0) }
            items = merged.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            loadedRegion = region
            if let selectedID, !items.contains(where: { $0.id == selectedID }) { self.selectedID = nil }
            phase = .loaded(())
        } catch is CancellationError {
            guard current == generation else { return }
            phase = loadedRegion == nil ? .idle : .loaded(())
        } catch {
            guard current == generation else { return }
            phase = .failed(error.roamMessage)
        }
    }

    /// Refresh acknowledged scores without restoring a previous destination during navigation.
    func refreshMatches() async {
        if foregroundLoading { projectionRefreshQueued = true; return }
        guard let region = requestedRegion ?? loadedRegion else { return }
        await load(region: region)
    }

    /// Searches the area on the map for the text, or goes back to browsing when it's empty.
    func search(_ text: String) async {
        query = text.trimmingCharacters(in: .whitespaces)
        guard let region = visibleRegion ?? loadedRegion else { return }
        await load(region: region)
    }

    func searchThisArea() async {
        guard let visibleRegion else { return }
        await load(region: visibleRegion)
    }

    func resolve(_ item: ExploreItem) async throws -> ExperienceSummary {
        if let experience = item.experience { return experience }
        guard let candidate = item.candidate else { throw RoamError.notFound }
        let summary = try await experiences.resolve(candidate)
        if let index = items.firstIndex(where: { $0.id == item.id }) { items[index].experience = summary }
        return summary
    }
}

/// S05: manual-destination or current-location map/list with category filters. Works without
/// location permission; denial/timeout/approximate location keep manual browsing available.
struct ExploreRootView: View {
    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @Environment(DestinationStore.self) private var destinations
    @Environment(LibraryStore.self) private var library
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var model: ExploreModel?
    @State private var actionError: String?
    @State private var pendingSaves: Set<String> = []
    @State private var pendingLogs: Set<String> = []
    /// Set when opened for a country: Explore starts on it, and your places there come up on a card.
    var countryCode: String?
    var countryTitle: String?
    @State private var mine: MyPlacesModel?
    @State private var expanded = false
    @State private var query = ""
    @FocusState private var searching: Bool

    private var myItems: [PlaceMapItem] {
        guard let countryCode else { return [] }
        return mine?.countries.first { $0.code == countryCode }?.items ?? []
    }

    var body: some View {
        // A ZStack always has a view to host `.task`; an empty Group would never run it.
        ZStack {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.groupedCanvas)
        .navigationTitle(countryTitle ?? "Explore")
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if model == nil {
                model = ExploreModel(services: services)
            }
            if model?.loadedRegion == nil, let countryCode, let destination = CountryDestination.make(code: countryCode) {
                destinations.select(destination, for: .explore)
            }
            if model?.loadedRegion == nil, let destination = destinations.explore {
                await model?.focus(on: destination)
            }
            if countryCode != nil, let me = session.userID {
                if mine == nil { mine = MyPlacesModel(services: services, ownerID: me) }
                await mine?.load()
            }
        }
        .onChange(of: library.revision) { _, _ in
            Task { await model?.refreshMatches() }
        }
        .onChange(of: destinations.explore) { _, destination in
            guard let destination else { return }
            Task { await model?.focus(on: destination) }
        }
        .screenIdentifier("explore-root")
    }

    /// The map fills the screen under the tab bar, with a row of floating bubbles at the top: back, search and
    /// your location. Searching, or the list button, drops a card down with your places here and what's on the map.
    @ViewBuilder private func content(_ model: ExploreModel) -> some View {
        if destinations.explore == nil && model.loadedRegion == nil {
            ScrollView {
                EmptyStateView(systemImage: "map", title: "Explore anywhere",
                               message: "Pick a destination to browse places on the map. Location access is optional.",
                               primaryTitle: "Choose a destination", primaryAction: { router.sheet = .destinationPicker(.explore) })
            }
        } else {
            mapLayer(model)
                .overlay(alignment: .top) {
                    VStack(spacing: Theme.Spacing.s) {
                        HStack(spacing: Theme.Spacing.s) {
                            Button { dismiss() } label: {
                                Image(systemName: "chevron.left").font(.headline).foregroundStyle(Roam.ink).frame(width: 48, height: 48)
                            }
                            .buttonStyle(.plain)
                            .floatingBubble(Circle())
                            .accessibilityLabel("Back")
                            .accessibilityIdentifier("explore-back")
                            searchBar(model)
                            Button { Task { await useCurrentLocation(model) } } label: {
                                Image(systemName: services.location.isAuthorized ? "location.fill" : "location")
                                    .font(.headline).foregroundStyle(Roam.ink).frame(width: 48, height: 48)
                            }
                            .buttonStyle(.plain)
                            .floatingBubble(Circle())
                            .accessibilityLabel(services.location.isAuthorized ? "Recenter on my location" : "Use current location")
                            .accessibilityIdentifier("explore-current-location")
                        }
                        if expanded { resultsCard(model).transition(.move(edge: .top).combined(with: .opacity)) }
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.top, Theme.Spacing.xs)
                }
        }
    }

    private func setExpanded(_ value: Bool) {
        if !value { searching = false }
        if UIAccessibility.isReduceMotionEnabled { expanded = value } else { withAnimation(.spring(duration: 0.35)) { expanded = value } }
    }

    private func resultsCard(_ model: ExploreModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) { sheetContent(model) }
                .padding(Theme.Spacing.l)
        }
        .containerRelativeFrame(.vertical) { height, _ in height * 0.6 }
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Roam.paper).shadow(color: .black.opacity(0.2), radius: 12, y: 4))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func searchBar(_ model: ExploreModel) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "magnifyingglass").foregroundStyle(Roam.inkMuted).accessibilityHidden(true)
            TextField(countryTitle.map { "Search \($0)" } ?? "Search this area", text: $query)
                .focused($searching)
                .submitLabel(.search)
                .onSubmit { Task { await model.search(query) } }
                .accessibilityIdentifier("explore-search")
            if !query.isEmpty {
                Button { query = ""; Task { await model.search("") } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Roam.inkMuted) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
            }
            if !expanded && !myItems.isEmpty {
                Button { setExpanded(true) } label: {
                    HStack(spacing: 3) {
                        Image(systemName: PlaceState.visited.markerSymbol)
                        Text("\(myItems.count)").monospacedDigit()
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(Capsule().fill(PlaceState.visited.markerColor))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Your \(myItems.count) places here")
            }
            Button { setExpanded(!expanded) } label: {
                Image(systemName: expanded ? "chevron.up" : "list.bullet").foregroundStyle(Roam.ink).frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "Hide the list" : "Show places as a list")
            .accessibilityIdentifier("explore-toggle-list")
        }
        .padding(.horizontal, Theme.Spacing.m)
        .frame(height: 48)
        .floatingBubble(Capsule())
        .onChange(of: searching) { _, focused in if focused && !expanded { setExpanded(true) } }
    }

    @ViewBuilder private func sheetContent(_ model: ExploreModel) -> some View {
        categoryChips(model).padding(.horizontal, -Theme.Spacing.l)
        if case .failed(let message) = model.phase {
            InlineRetryView(message: message) { Task { await model.retry() } }
                .accessibilityIdentifier("explore-load-error")
        }
        if let message = model.locationMessage ?? actionError {
            InlineRetryView(message: message, retryTitle: "Dismiss") { model.locationMessage = nil; actionError = nil }
                .accessibilityIdentifier("explore-location-message")
        }
        if !myItems.isEmpty && model.query.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Your places").font(.roamTitle()).accessibilityAddTraits(.isHeader)
                    Text("\(myItems.count)").font(.subheadline).foregroundStyle(Roam.inkMuted).monospacedDigit()
                }
                PlaceBreakdown(items: myItems, scores: mine?.scores ?? [:])
            }
        }
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Text(model.query.isEmpty ? "On the map" : "Results").font(.roamTitle()).accessibilityAddTraits(.isHeader)
                Spacer()
                if model.phase.isLoading { ProgressView() }
            }
            if model.items.isEmpty && !model.phase.isLoading {
                Text(model.query.isEmpty ? "Move the map to find places." : "Nothing called “\(model.query)” here. Try moving the map.")
                    .font(.subheadline).foregroundStyle(Roam.inkMuted)
            }
            LazyVStack(spacing: Theme.Spacing.s) {
                ForEach(model.items) { item in
                    placeCard(item, model: model)
                        .contextMenu {
                            Button { showOnMap(item, model); setExpanded(false) } label: { Label("Show on map", systemImage: "map") }
                        }
                        .accessibilityIdentifier("explore-list-row-\(item.name)")
                }
            }
        }
        DestinationChip(destination: destinations.explore) { router.sheet = .destinationPicker(.explore) }
            .accessibilityIdentifier("explore-destination-button")
    }

    private func categoryChips(_ model: ExploreModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", symbol: "square.grid.2x2", selected: model.category == nil) { select(nil, model) }
                ForEach(ExperienceCategory.allCases) { category in
                    chip(title: category.title, symbol: category.symbolName, selected: model.category == category) { select(category, model) }
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
        }
        .accessibilityIdentifier("explore-categories")
    }

    private func chip(title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { PillLabel(title: title, systemImage: symbol) }
            .buttonStyle(PillButtonStyle(isSelected: selected))
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("explore-chip-\(title)")
    }

    private func select(_ category: ExperienceCategory?, _ model: ExploreModel) {
        model.category = category
        Task { if let region = model.loadedRegion ?? model.visibleRegion { await model.load(region: region) } }
    }

    private func mapLayer(_ model: ExploreModel) -> some View {
        ZStack(alignment: .bottom) {
            GlobeMapView(pins: model.pinnedItems.map(\.pin), shadedCountryCodes: [], style: .standard, interactive: true,
                         selectedPinID: model.selectedID, focusRegion: model.focusRegion, focusToken: model.focusToken,
                         onSelectPin: { model.selectedID = $0.id }, onRegionChange: { model.regionChanged($0) },
                         onSelectMapFeature: { model.select(mapItem: $0) })
                .ignoresSafeArea()
                .mapAccessibility("Map with \(model.items.count) \(model.items.count == 1 ? "place" : "places"). Switch to the list to browse them.", identifier: "explore-map")
                .overlay(alignment: .top) {
                    if model.phase.isLoading { ProgressView().padding(8).background(Capsule().fill(.regularMaterial)).padding(.top, 64) }
                }
            if let selected = model.items.first(where: { $0.id == model.selectedID }) {
                itemCard(selected, model: model)
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.bottom, Theme.Spacing.s)
            }
        }
    }

    private func showOnMap(_ item: ExploreItem, _ model: ExploreModel) {
        model.selectedID = item.id
        model.focusRegion = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: item.latitude, longitude: item.longitude), latitudinalMeters: 1_500, longitudinalMeters: 1_500)
        model.focusToken += 1
        model.showsMap = true
    }

    /// Photo, name, where it is and who rated it; tap to open. Save and Log sit on the right.
    private func placeCard(_ item: ExploreItem, model: ExploreModel, onClose: (() -> Void)? = nil) -> some View {
        let experience = item.experience
        let rated = experience.map { library.ratedCategory($0.id) != nil || $0.viewer.isRated } ?? false
        let save: SaveActionState = experience.map { rated ? .alreadyBeen : library.saveState(for: $0.id) } ?? .notSaved
        return HStack(spacing: Theme.Spacing.m) {
            Button { Task { await open(item, model) } } label: {
                HStack(spacing: Theme.Spacing.m) {
                    PlaceThumbnail(id: item.id, url: experience?.photoURL,
                                   coordinate: CLLocationCoordinate2D(latitude: item.latitude, longitude: item.longitude),
                                   symbol: item.category?.symbolName ?? "mappin")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name).font(.headline).foregroundStyle(Roam.ink).lineLimit(2).multilineTextAlignment(.leading)
                        // The area is already in the destination bar above the list.
                        if let category = item.category {
                            Text(category.title).font(.footnote).foregroundStyle(Roam.inkMuted).lineLimit(1)
                        }
                        if let line = scoreLine(experience) {
                            Text(line).font(.footnote.weight(.semibold)).foregroundStyle(Roam.ink).monospacedDigit()
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the place")
            HStack(spacing: 0) { actions(item, model: model, save: save, rated: rated, onClose: onClose) }
        }
        .padding(Theme.Spacing.m)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).fill(Roam.paperRaised))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
            .strokeBorder(item.id == model.selectedID && onClose == nil ? Roam.ink : Roam.rule, lineWidth: item.id == model.selectedID && onClose == nil ? 1.5 : 1))
    }

    @ViewBuilder private func actions(_ item: ExploreItem, model: ExploreModel, save: SaveActionState, rated: Bool, onClose: (() -> Void)?) -> some View {
            switch save {
            case .alreadyBeen:
                EmptyView()
            case .pending:
                ProgressView().frame(width: 36, height: 36)
            case .saved, .notSaved:
                circleButton(save == .saved ? "bookmark.fill" : "bookmark", label: save == .saved ? "Remove \(item.name) from wishlist" : "Save \(item.name) to wishlist") {
                    Task { await toggleSave(item, model) }
                }
            }
            circleButton("plus", label: rated ? "Add a visit to \(item.name)" : "Log \(item.name)", prominent: true) {
                Task { await log(item, model) }
            }
            if let onClose {
                circleButton("xmark", label: "Close selected place", action: onClose)
            }
    }

    private func scoreLine(_ experience: ExperienceSummary?) -> String? {
        guard let experience else { return nil }
        if let mine = experience.viewer.myScore { return "You · \(mine.formatted)" }
        if let friends = experience.followingScore, experience.followingCount > 0 {
            return "\(friends.formatted) · \(experience.followingCount) \(experience.followingCount == 1 ? "friend" : "friends")"
        }
        return nil
    }

    private func circleButton(_ symbol: String, label: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.footnote.weight(.bold))
                .foregroundStyle(prominent ? Roam.paper : Roam.ink)
                .frame(width: 36, height: 36)
                .background(Circle().fill(prominent ? Roam.ink : Roam.fill))
                .frame(width: Theme.minimumHitTarget, height: Theme.minimumHitTarget)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func itemCard(_ item: ExploreItem, model: ExploreModel) -> some View {
        placeCard(item, model: model) { model.selectedID = nil }
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            .accessibilityIdentifier("selected-place-card")
    }

    private func open(_ item: ExploreItem, _ model: ExploreModel) async {
        do {
            let summary = try await model.resolve(item)
            router.push(.experience(summary.id))
        } catch {
            actionError = session.handle(error)
        }
    }

    private func log(_ item: ExploreItem, _ model: ExploreModel) async {
        guard !pendingLogs.contains(item.id) else { return }
        pendingLogs.insert(item.id)
        defer { pendingLogs.remove(item.id) }
        do {
            let summary = try await model.resolve(item)
            router.sheet = .log(try await services.makeLogRequest(experienceID: summary.id))
        } catch { actionError = session.handle(error) }
    }

    private func toggleSave(_ item: ExploreItem, _ model: ExploreModel) async {
        guard !pendingSaves.contains(item.id) else { return }
        pendingSaves.insert(item.id)
        defer { pendingSaves.remove(item.id) }
        do {
            let summary = try await model.resolve(item)
            await library.setBookmark(summary.id, saved: !library.isBookmarked(summary.id))
        } catch {
            actionError = session.handle(error)
        }
    }

    private func useCurrentLocation(_ model: ExploreModel) async {
        let outcome = await services.location.currentLocation()
        model.locationMessage = outcome.message
        if case .located(let coordinate, _) = outcome {
            if let destination = try? await services.places.destination(for: coordinate) {
                destinations.select(destination, for: .explore)
            } else {
                let region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 10_000, longitudinalMeters: 10_000)
                model.focusRegion = region
                model.focusToken += 1
                await model.load(region: region)
            }
        }
    }
}

extension View {
    /// A floating control over a map: Liquid Glass on iOS 26, frosted material before it.
    @ViewBuilder func floatingBubble<S: Shape>(_ shape: S) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: shape)
        } else {
            background(.regularMaterial, in: shape).shadow(color: .black.opacity(0.18), radius: 10, y: 3)
        }
    }
}
