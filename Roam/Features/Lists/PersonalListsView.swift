import MapKit
import SwiftUI

@MainActor
@Observable
final class PersonalListsModel {
    let ownerID: UUID
    var kind: ListKind
    var beenScope: BeenScope = .all
    var beenFilter = ListFilter()
    var wantFilter = ListFilter()
    var query = ""
    var showsMap = false
    var sortOverride: [String: ListSort] = [:]
    var reference: DistanceReference?
    private(set) var been: LoadPhase<[ListEntry]> = .idle
    private(set) var want: LoadPhase<[ListEntry]> = .idle
    private(set) var refreshError: String?
    private let services: AppServices

    init(ownerID: UUID, kind: ListKind, services: AppServices) {
        self.ownerID = ownerID
        self.kind = kind
        self.services = services
    }

    private var scopeKey: String {
        switch (kind, beenScope) {
        case (.want, _): return "want"
        case (.been, .all): return "been-all"
        case (.been, .category(let c)): return "been-\(c.rawValue)"
        }
    }

    var sort: ListSort {
        get { sortOverride[scopeKey] ?? ListEngine.defaultSort(kind: kind, scope: beenScope) }
        set { sortOverride[scopeKey] = newValue }
    }

    var filter: ListFilter {
        get { kind == .been ? beenFilter : wantFilter }
        set { if kind == .been { beenFilter = newValue } else { wantFilter = newValue } }
    }

    var phase: LoadPhase<[ListEntry]> { kind == .been ? been : want }

    var allEntries: [ListEntry] { phase.value ?? [] }

    var visibleEntries: [ListEntry] {
        ListEngine.apply(allEntries, kind: kind, scope: beenScope, filter: filter, query: query, sort: sort, reference: reference)
    }

    /// Refresh keeps existing rows (and filters/scroll) on failure.
    func load() async {
        async let beenResult = result { try await self.services.lists.been(ownerID: self.ownerID) }
        async let wantResult = result { try await self.services.lists.want(ownerID: self.ownerID) }
        let (b, w) = await (beenResult, wantResult)
        apply(b, to: \.been)
        apply(w, to: \.want)
    }

    private func result(_ work: @escaping () async throws -> [ListEntry]) async -> Result<[ListEntry], Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }

    private func apply(_ result: Result<[ListEntry], Error>, to keyPath: ReferenceWritableKeyPath<PersonalListsModel, LoadPhase<[ListEntry]>>) {
        switch result {
        case .success(let entries):
            self[keyPath: keyPath] = .loaded(entries)
            refreshError = nil
        case .failure(let error):
            if self[keyPath: keyPath].value == nil { self[keyPath: keyPath] = .failed(error.roamMessage) } else { refreshError = error.roamMessage }
        }
    }

    func clearFilters() {
        filter = ListFilter()
        query = ""
    }
}

/// S12: Been / Want to Go for the signed-in member or another member (read-only, viewer Save/Log).
struct PersonalListsView: View {
    let ownerID: UUID
    var initialKind: ListKind = .been
    var isRoot = false

    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router
    @Environment(DestinationStore.self) private var destinations
    @State private var model: PersonalListsModel?
    @State private var ownerName: String?
    @State private var showsFilters = false
    @State private var selectedPin: String?

    private var isOwn: Bool { ownerID == session.userID }

    var body: some View {
        Group {
            if let model {
                ListsContent(model: model, isOwn: isOwn, ownerName: ownerName, showsFilters: $showsFilters, selectedPin: $selectedPin)
            } else {
                SkeletonList(rows: 5).padding()
            }
        }
        .background(Theme.groupedCanvas)
        .navigationTitle(isOwn ? "Your Lists" : "\(ownerName ?? "Member")'s lists")
        .navigationBarTitleDisplayMode(isRoot ? .large : .inline)
        .task {
            if model == nil { model = PersonalListsModel(ownerID: ownerID, kind: initialKind, services: services) }
            if !isOwn, ownerName == nil { ownerName = try? await services.profiles.publicProfile(userID: ownerID).member.displayName }
            await model?.load()
        }
        .onChange(of: library.revision) { _, _ in Task { await model?.load() } }
        .sheet(isPresented: $showsFilters) {
            if let model {
                FilterSheet(kind: model.kind, cities: ListEngine.cityFacets(model.allEntries), countries: ListEngine.countryFacets(model.allEntries),
                            applied: model.filter) { model.filter = $0 }
            }
        }
    }
}

private struct ListsContent: View {
    @Bindable var model: PersonalListsModel
    let isOwn: Bool
    let ownerName: String?
    @Binding var showsFilters: Bool
    @Binding var selectedPin: String?

    @Environment(AppServices.self) private var services
    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router
    @Environment(DestinationStore.self) private var destinations
    @State private var distanceNote: String?

    var body: some View {
        VStack(spacing: 0) {
            controls
            if let refreshError = model.refreshError {
                InlineRetryView(message: refreshError) { Task { await model.load() } }.padding(.horizontal)
            }
            ZStack(alignment: .bottomTrailing) {
                if model.showsMap { mapView } else { listView }
                if model.phase.value?.isEmpty == false {
                    MapListToggle(showsMap: $model.showsMap).padding(Theme.Spacing.l)
                }
            }
        }
        .screenIdentifier(isOwn ? "lists-root" : "member-lists")
    }

    private var controls: some View {
        VStack(spacing: Theme.Spacing.s) {
            Picker("List", selection: $model.kind) {
                ForEach(ListKind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("list-kind")
            HStack(spacing: Theme.Spacing.s) {
                if model.kind == .been {
                    Menu {
                        Button("All categories") { model.beenScope = .all }
                        ForEach(ExperienceCategory.allCases) { category in
                            Button { model.beenScope = .category(category) } label: { Label(category.title, systemImage: category.symbolName) }
                        }
                    } label: {
                        PillLabel(title: scopeTitle, systemImage: scopeSymbol)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(Theme.accentFill))
                    }
                    .frame(minHeight: Theme.minimumHitTarget)
                    .accessibilityIdentifier("category-scope")
                }
                Button { showsFilters = true } label: {
                    PillLabel(title: model.filter.activeCount > 0 ? "Filters (\(model.filter.activeCount))" : "Filters",
                              systemImage: "line.3.horizontal.decrease.circle")
                }
                .buttonStyle(PillButtonStyle(isSelected: model.filter.activeCount > 0))
                .accessibilityIdentifier("open-filters")
                Menu {
                    ForEach(ListEngine.availableSorts(kind: model.kind, scope: model.beenScope)) { option in
                        Button {
                            Task { await choose(option) }
                        } label: {
                            if option == model.sort { Label(option.title, systemImage: "checkmark") } else { Text(option.title) }
                        }
                    }
                } label: {
                    PillLabel(title: model.sort.title, systemImage: "arrow.up.arrow.down")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Capsule().fill(Theme.accentFill))
                }
                .frame(minHeight: Theme.minimumHitTarget)
                .accessibilityIdentifier("sort-menu")
                Spacer(minLength: 0)
            }
            SearchField(prompt: "Search names and places", text: $model.query, identifier: "list-search-field")
            if model.sort == .distance, let note = distanceNote ?? model.reference.map({ "Distance \($0.label)" }) {
                Text(note).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.s)
    }

    private var scopeTitle: String {
        if case .category(let category) = model.beenScope { return category.title }
        return "All categories"
    }

    private var scopeSymbol: String {
        if case .category(let category) = model.beenScope { return category.symbolName }
        return "square.grid.2x2"
    }

    /// Distance uses current location when already authorized, else the chosen destination, and says which.
    private func choose(_ sort: ListSort) async {
        if sort == .distance {
            if services.location.isAuthorized, case .located(let coordinate, let approximate) = await services.location.currentLocation() {
                model.reference = DistanceReference(latitude: coordinate.latitude, longitude: coordinate.longitude, source: .currentLocation)
                distanceNote = approximate ? "Distance from your approximate location" : nil
            } else if let destination = destinations.explore ?? destinations.search {
                model.reference = DistanceReference(latitude: destination.latitude, longitude: destination.longitude, source: .destination(destination.name))
                distanceNote = nil
            } else {
                model.reference = nil
                distanceNote = "Choose a destination in Explore or allow location to sort by distance. Unknown distances are listed last."
            }
        }
        model.sort = sort
    }

    @ViewBuilder private var listView: some View {
        switch model.phase {
        case .idle, .loading:
            ScrollView { SkeletonList(rows: 6).padding(.horizontal) }
        case .failed(let message):
            ScrollView { InlineRetryView(message: message) { Task { await model.load() } }.padding() }
        case .loaded(let entries):
            let visible = model.visibleEntries
            if entries.isEmpty || (model.kind == .been && entries.allSatisfy({ !$0.isRanked }) && model.filter.isEmpty && model.query.isEmpty) && visible.isEmpty {
                ScrollView { emptyState }
            } else if visible.isEmpty {
                ScrollView {
                    EmptyStateView(systemImage: "line.3.horizontal.decrease.circle", title: model.filter.unrankedMemories ? "No unranked memories" : "No matches",
                                   message: "Nothing in this list matches your search and filters.",
                                   primaryTitle: "Reset filters", primaryAction: { model.clearFilters() })
                        .accessibilityIdentifier("filtered-empty")
                }
            } else {
                List {
                    ForEach(visible) { entry in
                        row(entry)
                            .listRowBackground(selectedPin == entry.id.uuidString ? Theme.accentFill : Theme.raisedCard)
                    }
                }
                .listStyle(.plain)
                .refreshable { await model.load() }
                .accessibilityIdentifier("list-rows")
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        if isOwn {
            if model.kind == .been {
                EmptyStateView(systemImage: "checkmark.seal", title: "Nothing ranked yet",
                               message: "Log a place you've been and Roam ranks it within its category.",
                               primaryTitle: "Search experiences", primaryAction: { router.selectedTab = .search })
            } else {
                EmptyStateView(systemImage: "bookmark", title: "No saved experiences",
                               message: "Save places you want to go. They'll wait here until you've been.",
                               primaryTitle: "Explore places", primaryAction: { router.selectedTab = .explore })
            }
        } else {
            EmptyStateView(systemImage: model.kind == .been ? "checkmark.seal" : "bookmark",
                           title: model.kind == .been ? "No rankings yet" : "Nothing saved yet",
                           message: "\(ownerName ?? "This member") hasn't \(model.kind == .been ? "ranked any places" : "saved any places") yet.")
        }
    }

    private func row(_ entry: ListEntry) -> some View {
        let experience = entry.experience
        let viewerRated = library.ratedCategory(experience.id) != nil || experience.viewer.isRated
        let saveState: SaveActionState = viewerRated ? .alreadyBeen : library.saveState(for: experience.id)
        let scopeIsCategory: Bool = { if case .category = model.beenScope { return true } else { return false } }()
        return ExperienceRow(
            name: experience.name,
            category: entry.ownerCategory ?? experience.category,
            area: experience.areaLine,
            rank: model.kind == .been && scopeIsCategory && !model.filter.unrankedMemories ? entry.ownerRank : nil,
            score: model.kind == .been ? entry.ownerScore : (isOwn ? nil : experience.viewer.myScore),
            scoreSource: model.kind == .been ? (isOwn ? .you : .owner(name: ownerName ?? "Owner")) : .you,
            statusLine: status(entry),
            saveState: saveState,
            onOpen: { router.push(.experience(experience.id)) },
            onSave: { Task { await library.setBookmark(experience.id, saved: !library.isBookmarked(experience.id)) } })
    }

    private func status(_ entry: ListEntry) -> String {
        if model.kind == .want {
            let saved = entry.savedAt.map { "Saved \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "Saved"
            if model.sort == .distance, let reference = model.reference { return "\(saved) · \(distanceText(reference.distance(to: entry)))" }
            return saved
        }
        var parts: [String] = []
        if !entry.isRanked { parts.append("Unranked") }
        parts.append(entry.latestVisitDate.map { "Visited \($0.displayString)" } ?? "Visit date unknown")
        if model.sort == .distance, let reference = model.reference { parts.append(distanceText(reference.distance(to: entry))) }
        return parts.joined(separator: " · ")
    }

    private func distanceText(_ meters: CLLocationDistance) -> String {
        Measurement(value: meters / 1000, unit: UnitLength.kilometers).formatted(.measurement(width: .abbreviated, usage: .road))
    }

    private var mapView: some View {
        let visible = model.visibleEntries
        let pins = visible.map { MapPin(id: $0.id.uuidString, name: $0.experience.name, category: $0.ownerCategory ?? $0.experience.category,
                                        latitude: $0.experience.latitude, longitude: $0.experience.longitude) }
        return ZStack(alignment: .bottom) {
            GlobeMapView(pins: pins, shadedCountryCodes: [], style: .standard, interactive: true, selectedPinID: selectedPin,
                         focusRegion: Self.region(fitting: pins), focusToken: pins.map(\.id).hashValue,
                         onSelectPin: { selectedPin = $0.id })
                .mapAccessibility("Map with \(pins.count) places from this list. Switch to the list to browse them.", identifier: "list-map")
            if let selected = visible.first(where: { $0.id.uuidString == selectedPin }) {
                SelectedPlaceCard(summary: selected.experience, onOpen: { router.push(.experience(selected.id)) },
                                  onSave: { Task { await library.setBookmark(selected.id, saved: !library.isBookmarked(selected.id)) } },
                                  onLog: nil, saveState: library.saveState(for: selected.id), onClose: { selectedPin = nil })
                    .padding()
                    .padding(.bottom, 56)
            }
        }
    }

    static func region(fitting pins: [MapPin]) -> MKCoordinateRegion? {
        guard !pins.isEmpty else { return nil }
        let lats = pins.map(\.latitude), lons = pins.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(latitudeDelta: min(170, max(0.05, (lats.max()! - lats.min()!) * 1.4)),
                                    longitudeDelta: min(355, max(0.05, (lons.max()! - lons.min()!) * 1.4)))
        return MKCoordinateRegion(center: center, span: span)
    }
}
