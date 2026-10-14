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
            async let poiResult = places.pointsOfInterest(in: region, category: category)
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
    @State private var model: ExploreModel?
    @State private var actionError: String?
    @State private var pendingSaves: Set<String> = []
    @State private var pendingLogs: Set<String> = []

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
        .navigationTitle("Explore")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil {
                model = ExploreModel(services: services)
            }
            if model?.loadedRegion == nil, let destination = destinations.explore {
                await model?.focus(on: destination)
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

    @ViewBuilder private func content(_ model: ExploreModel) -> some View {
        @Bindable var model = model
        VStack(spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                DestinationChip(destination: destinations.explore) { router.sheet = .destinationPicker(.explore) }
                    .accessibilityIdentifier("explore-destination-button")
                Button { Task { await useCurrentLocation(model) } } label: {
                    Image(systemName: services.location.isAuthorized ? "location.fill" : "location")
                        .frame(width: Theme.minimumHitTarget, height: Theme.minimumHitTarget)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accentFill))
                }
                .accessibilityLabel(services.location.isAuthorized ? "Recenter on my location" : "Use current location")
                .accessibilityIdentifier("explore-current-location")
            }
            .padding(.horizontal, Theme.Spacing.l)
            categoryChips(model)
            if case .failed(let message) = model.phase {
                InlineRetryView(message: message) { Task { await model.retry() } }
                    .padding(.horizontal, Theme.Spacing.l)
                    .accessibilityIdentifier("explore-load-error")
                if !model.items.isEmpty {
                    Text("Showing places from the last successful area search.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let message = model.locationMessage ?? actionError {
                InlineRetryView(message: message, retryTitle: "Dismiss") { model.locationMessage = nil; actionError = nil }
                    .padding(.horizontal, Theme.Spacing.l)
                    .accessibilityIdentifier("explore-location-message")
            }
            if destinations.explore == nil && model.loadedRegion == nil {
                ScrollView {
                    EmptyStateView(systemImage: "map", title: "Explore anywhere",
                                   message: "Pick a destination to browse places on the map. Location access is optional.",
                                   primaryTitle: "Choose a destination", primaryAction: { router.sheet = .destinationPicker(.explore) })
                }
            } else {
                ZStack(alignment: .bottom) {
                    if model.showsMap { mapLayer(model) } else { listLayer(model) }
                    HStack {
                        if model.showsMap && model.canSearchThisArea {
                            Button { Task { await model.searchThisArea() } } label: {
                                PillLabel(title: "Search this area", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(PillButtonStyle(isSelected: true))
                            .accessibilityIdentifier("search-this-area")
                        }
                        Spacer()
                        MapListToggle(showsMap: $model.showsMap)
                    }
                    .padding(Theme.Spacing.l)
                }
            }
        }
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
            GlobeMapView(pins: model.items.map(\.pin), shadedCountryCodes: [], style: .standard, interactive: true,
                         selectedPinID: model.selectedID, focusRegion: model.focusRegion, focusToken: model.focusToken,
                         onSelectPin: { model.selectedID = $0.id }, onRegionChange: { model.visibleRegion = $0 })
                .mapAccessibility("Map with \(model.items.count) places. Switch to the list to browse them.", identifier: "explore-map")
                .overlay(alignment: .top) {
                    if model.phase.isLoading { ProgressView().padding(8).background(Capsule().fill(.regularMaterial)).padding(.top, 8) }
                }
            if let selected = model.items.first(where: { $0.id == model.selectedID }) {
                itemCard(selected, model: model)
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.bottom, 72)
            }
        }
    }

    @ViewBuilder private func listLayer(_ model: ExploreModel) -> some View {
        switch model.phase {
        case .loading where model.items.isEmpty:
            ScrollView { SkeletonList(rows: 6).padding(.horizontal) }
        case .failed where model.items.isEmpty:
            ScrollView { ContentUnavailableView("Places unavailable", systemImage: "wifi.exclamationmark", description: Text("Retry the last area or choose another destination.")) }
        default:
            if model.items.isEmpty {
                ScrollView {
                    EmptyStateView(systemImage: "mappin.slash", title: "Nothing here yet",
                                   message: "No \(model.category?.title.lowercased() ?? "places") found in this area. Try another category or move the map.")
                }
            } else {
                List(model.items) { item in
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        row(item, model: model)
                        Button {
                            model.selectedID = item.id
                            model.focusRegion = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: item.latitude, longitude: item.longitude), latitudinalMeters: 1_500, longitudinalMeters: 1_500)
                            model.focusToken += 1
                            model.showsMap = true
                        } label: { Label("Show on map", systemImage: "mappin.and.ellipse") }
                        .frame(minHeight: Theme.minimumHitTarget)
                        .accessibilityIdentifier("explore-show-on-map-\(item.name)")
                    }
                        .listRowBackground(item.id == model.selectedID ? Theme.accentFill : Theme.raisedCard)
                        .accessibilityElement(children: .contain)
                        .accessibilityAddTraits(item.id == model.selectedID ? .isSelected : [])
                        .accessibilityIdentifier("explore-list-row-\(item.name)")
                }
                .listStyle(.plain)
                .accessibilityIdentifier("explore-list")
            }
        }
    }

    private func row(_ item: ExploreItem, model: ExploreModel) -> some View {
        let experience = item.experience
        let rated = experience.map { library.ratedCategory($0.id) != nil || $0.viewer.isRated } ?? false
        let save: SaveActionState = experience.map { rated ? .alreadyBeen : library.saveState(for: $0.id) } ?? .notSaved
        return ExperienceRow(name: item.name, category: item.category, area: item.area,
                             score: experience?.viewer.myScore, scoreSource: .you,
                             secondaryScore: experience?.followingScore, secondarySource: experience.map { .following(count: $0.followingCount) },
                             statusLine: item.candidate?.address,
                             saveState: save, logTitle: rated ? "Add visit" : "Log",
                             onOpen: { Task { await open(item, model) } },
                             onSave: { Task { await toggleSave(item, model) } },
                             onLog: { Task { await log(item, model) } })
    }

    private func itemCard(_ item: ExploreItem, model: ExploreModel) -> some View {
        HStack(alignment: .top) {
            row(item, model: model)
            Button { model.selectedID = nil } label: {
                Image(systemName: "xmark").font(.footnote.weight(.bold)).frame(width: Theme.minimumHitTarget, height: Theme.minimumHitTarget)
            }
            .accessibilityLabel("Close selected place")
        }
        .roamCard(padding: Theme.Spacing.m)
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
