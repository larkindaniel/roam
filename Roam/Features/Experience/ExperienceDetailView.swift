import MapKit
import SwiftUI

@MainActor
@Observable
final class ExperienceDetailModel {
    let experienceID: UUID
    private(set) var phase: LoadPhase<ExperienceDetail> = .idle
    private(set) var refreshError: String?
    private let services: AppServices
    private var generation = 0

    init(experienceID: UUID, services: AppServices) {
        self.experienceID = experienceID
        self.services = services
    }

    var detail: ExperienceDetail? { phase.value }

    /// Refresh keeps the current content on failure.
    func load() async {
        generation += 1
        let token = generation
        if detail == nil { phase = .loading }
        do {
            let detail = try await services.experiences.detail(experienceID: experienceID)
            try Task.checkCancellation()
            guard token == generation else { return }
            phase = .loaded(detail)
            refreshError = nil
            // Google's photo and rating arrive in the background on the first visit, then the page refreshes once.
            if detail.summary.googleRating == nil || detail.summary.photoURL == nil,
               await services.plans.refreshGoogleDetails(experienceIDs: [experienceID]), token == generation,
               let refreshed = try? await services.experiences.detail(experienceID: experienceID), token == generation {
                phase = .loaded(refreshed)
            }
        } catch is CancellationError {
            guard token == generation else { return }
            if detail == nil { phase = .idle }
        } catch {
            guard token == generation else { return }
            if detail == nil { phase = .failed(error.roamMessage) } else { refreshError = error.roamMessage }
        }
    }
}

/// S06 experience detail.
/// A place's page that can move to another place on the same map: tapping a nearby place swaps the card in place
/// rather than opening a new screen.
struct PlaceBrowserView: View {
    let startID: UUID

    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(LibraryStore.self) private var library
    @State private var current: UUID?
    @State private var currentPlace: ExperienceSummary?
    @State private var camera: MapCameraPosition = .automatic
    @State private var placed = false
    @State private var selection: MapSelection<UUID>?
    @State private var mine: [(place: ExperienceSummary, tint: Color)] = []
    @State private var viewRegion: MKCoordinateRegion?
    @Environment(AppRouter.self) private var router

    var body: some View {
        let id = current ?? startID
        ZStack {
            map
            // Only the card changes between places; the map underneath stays where it is.
            ExperienceDetailView(experienceID: id, overMap: true, startDetent: .half,
                                 onLoaded: { place in placeOnMap(place) },
                                 preview: currentPlace?.id == id ? currentPlace : mine.first { $0.place.id == id }?.place)
                .id(id)
        }
        .background(Color.black.ignoresSafeArea())
        .roamTabBar(hidden: true)
        .navigationTitle(currentPlace?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) } }
        .task { await loadMine() }
        .onChange(of: library.revision) { _, _ in Task { await loadMine() } }
        .onChange(of: selection) { _, picked in
            guard let picked else { return }
            selection = nil
            if let id = picked.value, id != current ?? startID { show(id) }
            else if let feature = picked.feature { Task { await open(feature) } }
        }
    }

    /// Like pinned places in Apple Maps: your been (green) and saved (yellow) places are always dots on the map, and
    /// the place you're looking at is the one big pin.
    private var map: some View {
        let id = current ?? startID
        return Map(position: $camera, selection: $selection) {
            ForEach(mine.filter { $0.place.id != id }, id: \.place.id) { pin in
                Annotation(pin.place.name, coordinate: pin.place.coordinate) {
                    Circle().fill(pin.tint).frame(width: 12, height: 12)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        // A finger-sized target around the small dot.
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                        .onTapGesture { show(pin.place.id) }
                        .accessibilityAddTraits(.isButton)
                }
                .annotationTitles(.hidden)
            }
            if let place = currentPlace, place.id == id {
                Marker(place.name, systemImage: place.iconName, coordinate: place.coordinate)
                    .tint(mine.first { $0.place.id == id }?.tint ?? place.pinTint)
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .all))
        .mapFeatureSelectionDisabled { $0.kind != .pointOfInterest && $0.kind != .territory }
        .onMapCameraChange(frequency: .onEnd) { viewRegion = $0.region }
        .ignoresSafeArea()
        .accessibilityLabel("Map")
        .accessibilityIdentifier("detail-map")
    }

    private func show(_ id: UUID) {
        if let known = mine.first(where: { $0.place.id == id })?.place { currentPlace = known }
        current = id
    }

    private func placeOnMap(_ place: ExperienceSummary) {
        currentPlace = place
        guard !placed else { return }
        placed = true
        // Opened from another map, it keeps that view; otherwise the place sits in the middle of the visible map.
        camera = .region(ExperienceDetailView.handoffRegion.removeValue(forKey: place.id)
                         ?? ExperienceDetailView.visibleCentered(place.coordinate, span: ExperienceDetailView.placeSpan))
    }

    private func open(_ feature: MapFeature) async {
        // A city on the map opens as a city, on the same view, without a slide.
        if feature.kind == .territory {
            guard let city = try? await services.places.destination(for: feature.coordinate) else { return }
            CityPageView.handoffRegion[city.id] = viewRegion
            CityPageView.handoffDetent[city.id] = .half
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { router.push(.city(city)) }
            return
        }
        guard let item = try? await MKMapItemRequest(feature: feature).mapItem,
              let candidate = MapKitPlaceSearchProvider.candidate(from: item),
              let place = try? await services.experiences.resolve(candidate) else { return }
        currentPlace = place
        current = place.id
    }

    private func loadMine() async {
        guard let me = session.userID else { return }
        async let been = services.lists.been(ownerID: me)
        async let saved = services.lists.want(ownerID: me)
        let beenList = (try? await been) ?? []
        let savedList = (try? await saved) ?? []
        let beenIDs = Set(beenList.map(\.id))
        mine = beenList.map { ($0.experience, PlaceState.visited.markerColor) }
            + savedList.filter { !beenIDs.contains($0.id) }.map { ($0.experience, PlaceState.wishlist.markerColor) }
    }
}

struct ExperienceDetailView: View {
    @State private var plannedTrips: [String] = []
    @State private var choosingMapsApp = false
    @State private var sheetDetent = GlobeSheetDetent.half
    @State private var showsLookAround = false
    @State private var lookAround: MKLookAroundScene?
    let experienceID: UUID
    /// Opens another place on this same map; nil pushes it as its own page.
    var onOpenPlace: ((UUID) -> Void)? = nil
    /// Shown over another screen's map (a city's): only the card, the map behind it is that screen's.
    var overMap = false
    /// Over a city's map: the card's height to start at (the city card's), and a call once the place has loaded, so
    /// the city's card can hand over without a gap.
    var startDetent: GlobeSheetDetent? = nil
    var onLoaded: ((ExperienceSummary) -> Void)? = nil
    /// Over a city's map: what's known already, shown on the card at once while the rest loads.
    var preview: ExperienceSummary? = nil
    @State private var mapCamera: MapCameraPosition = .automatic
    @State private var cameraPlaced = false

    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL
    @State private var friendMemories: [PublicMemory] = []
    @State private var model: ExperienceDetailModel?
    @State private var memoriesModel: PublicMemoriesModel?
    @State private var editingVisit: Visit?
    @State private var showsPrivateNote = false
    @State private var reportTarget: ReportTarget?
    @State private var reportReason: ReportReason?
    @State private var pendingDeletion: DetailDeletion?
    @State private var failedDeletion: DetailDeletion?
    @State private var actionError: String?
    @State private var deleting = false
    @State private var nearbyFeature: MapFeature?
    @State private var choosingBeen = false
    @State private var confirmingUnbeen = false
    /// The card rises from the bottom once the page is up, as in Apple Maps.
    @State private var cardRisen = false

    /// How much of the map a place shows; a city page flies to this before opening one, so the maps line up.
    static let placeSpan: CLLocationDistance = 1_500
    /// Where a city's map left off for a place it's opening.
    @MainActor static var handoff: [UUID: CLLocationCoordinate2D] = [:]
    /// The exact view a place should open on (the map you were just looking at), so nothing moves.
    @MainActor static var handoffRegion: [UUID: MKCoordinateRegion] = [:]
    @State private var mapRegion: MKCoordinateRegion?

    /// A region with the point in the middle of the map you can see above the card at half height (not the middle of
    /// the screen).
    static func visibleCentered(_ point: CLLocationCoordinate2D, span: CLLocationDistance) -> MKCoordinateRegion {
        let latitudeDelta = span / 111_000
        // The card covers roughly the lower 45%; the visible map's middle sits about 22% of a screen above centre.
        let center = CLLocationCoordinate2D(latitude: point.latitude - latitudeDelta * 0.22, longitude: point.longitude)
        return MKCoordinateRegion(center: center, latitudinalMeters: span, longitudinalMeters: span)
    }
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            switch model?.phase ?? .idle {
            case .idle, .loading:
                if overMap {
                    // The card is there at once with the name and area; the rest fills in when it loads.
                    GlobeSheetLayout(detent: $sheetDetent, peekHeight: 150, bottomOverlap: 0, headerLabel: preview?.name ?? "",
                                     headerIdentifier: "detail-sheet-header", floatsWhenPeeking: true, collapsesHeaderOnScroll: true,
                                     seeThrough: true) {
                        Color.clear.allowsHitTesting(false)
                    } header: {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(preview?.name ?? "").font(.roamTitle()).foregroundStyle(Roam.ink).lineLimit(1)
                            if sheetDetent != .peek, let preview {
                                Text([preview.category?.title, preview.areaLine.isEmpty ? nil : preview.areaLine].compactMap { $0 }.joined(separator: " · "))
                                    .font(.subheadline).foregroundStyle(Theme.secondaryText).lineLimit(1).padding(.top, -4)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } content: {
                        SkeletonList(rows: 4)
                    }
                    .onAppear {
                        if let startDetent { sheetDetent = startDetent }
                    }
                } else if let center = Self.handoff[experienceID] {
                    // Arriving from a city's map: show the same map while the place loads, so nothing jumps.
                    Map(initialPosition: .region(Self.handoffRegion[experienceID] ?? Self.visibleCentered(center, span: Self.placeSpan)))
                        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .all))
                        .ignoresSafeArea()
                        .accessibilityIdentifier("experience-loading")
                } else {
                    ScrollView { SkeletonList(rows: 6).padding() }
                        .accessibilityIdentifier("experience-loading")
                }
            case .failed(let message):
                ScrollView {
                    EmptyStateView(systemImage: "exclamationmark.triangle", title: "Couldn't load this place", message: message,
                                   primaryTitle: "Try again", primaryAction: { Task { await model?.load() } })
                }
            case .loaded(let detail):
                content(detail)
                    .onAppear {
                        guard !cardRisen else { return }
                        if overMap {
                            // Over a city's map the card is already there: only what's in it changes.
                            if preview == nil, let startDetent { sheetDetent = startDetent }
                            cardRisen = true
                            onLoaded?(detail.summary)
                        } else {
                            Self.handoff.removeValue(forKey: experienceID)
                            withAnimation(.snappy(duration: 0.32)) { cardRisen = true }
                        }
                    }
            }
        }
        .background(overMap ? Color.clear : Theme.groupedCanvas)
        // The place's card takes the tab bar's spot and runs to the bottom of the screen.
        .modifier(PlacePageChrome(enabled: !overMap, title: model?.detail?.summary.name ?? ""))
        .sheet(item: $reportTarget) { target in
            ReportSheet(target: target, title: reportTitle(target), suggestedReason: reportReason)
        }
        .sheet(item: $editingVisit) { visit in
            VisitMemoryEditor(visit: visit, destinationTimeZone: model?.detail?.timeZoneIdentifier) { _ in
                library.noteChanged()
                Task { await reload() }
            }
        }
        .sheet(isPresented: $showsPrivateNote) {
            PrivateNoteEditor(experienceID: experienceID) { Task { await model?.load() } }
        }
        .alert(pendingDeletion?.title ?? "Confirm removal", isPresented: Binding(
            get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }), presenting: pendingDeletion) { action in
                Button(action.buttonTitle, role: .destructive) { Task { await confirmDeletion(action) } }
                    .accessibilityIdentifier(action.confirmID)
                Button("Cancel", role: .cancel) {}
            } message: { action in Text(action.message) }
        .safeAreaInset(edge: .bottom) {
            if let actionError {
                InlineRetryView(message: actionError, retryTitle: failedDeletion == nil ? "Dismiss" : "Try again") {
                    if let failedDeletion { Task { await confirmDeletion(failedDeletion) } } else { self.actionError = nil }
                }.padding().background(.bar).accessibilityIdentifier("detail-action-error")
            }
        }
        .task {
            if let owner = session.userID {
                let name = "detail-pending-delete-\(experienceID.uuidString)"
                if let retained = services.storage.read(DetailDeletion.self, name: name, userID: owner) {
                    failedDeletion = retained
                    actionError = "A removal response was interrupted. Retry the same request to confirm its result."
                }
            }
            if model == nil { model = ExperienceDetailModel(experienceID: experienceID, services: services) }
            if memoriesModel == nil { memoriesModel = PublicMemoriesModel(experienceID: experienceID, service: services.memories) }
            await reload()
        }
        .onChange(of: library.revision) { _, _ in Task { await reload() } }
        .onChange(of: memoriesModel?.authError) { _, error in if let error { _ = session.handle(error) } }
        .screenIdentifier("experience-detail")
    }

    /// The place on a full-screen map you can move around, with everything about it on a card that swipes up over it.
    private func content(_ detail: ExperienceDetail) -> some View {
        let summary = detail.summary
        return GlobeSheetLayout(detent: $sheetDetent, peekHeight: 150, bottomOverlap: 0, headerLabel: summary.name,
                                headerIdentifier: "detail-sheet-header", onRefresh: { await reload() }, floatsWhenPeeking: true,
                                mapAccessory: lookAround.map { scene in AnyView(lookAroundButton(scene)) }, collapsesHeaderOnScroll: true,
                                cardHidden: !cardRisen, seeThrough: overMap) {
            if overMap { Color.clear.allowsHitTesting(false) } else { placeMap(detail) }
        } header: {
            // Just the name and directions, so the bubble over the map stays short.
            HStack(alignment: .center, spacing: Theme.Spacing.s) {
                // Opened up, the category and area sit right under the name.
                VStack(alignment: .leading, spacing: 0) {
                    Text(summary.name)
                        .font(.roamTitle())
                        .foregroundStyle(Roam.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityAddTraits(.isHeader)
                    if sheetDetent != .peek {
                        Text([(detail.myRating?.category ?? summary.category)?.title, summary.areaLine.isEmpty ? nil : summary.areaLine]
                                .compactMap { $0 }.joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(Theme.secondaryText).lineLimit(1)
                            // Tucked right up under the name.
                            .padding(.top, -4)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(PlaceState.planned.markerColor))
                    .contentShape(Circle().inset(by: -4))
                    .onTapGesture { choosingMapsApp = true }
                // Sit in the bubble's rounded end: the same gap on the right as above and below.
                .padding(.trailing, sheetDetent == .peek ? -(Theme.Spacing.l - Theme.Spacing.s) : 0)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { choosingMapsApp = true }
                .accessibilityLabel("Directions to \(summary.name)")
                .accessibilityIdentifier("detail-directions")
                .confirmationDialog("Directions", isPresented: $choosingMapsApp, titleVisibility: .hidden) {
                    Button("Apple Maps") { openInMaps(detail) }
                    Button("Google Maps") { openInGoogleMaps(detail) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Log, Save and Send sit in the card's fixed header, under the name, as in Apple Maps (buttons in the
            // scrolling part weren't reliably receiving taps).
            if sheetDetent != .peek {
                actionRow(detail).padding(.top, Theme.Spacing.s)
            }
        } content: {
                if !galleryItems(summary).isEmpty {
                    PlaceGallery(items: galleryItems(summary), placeName: summary.name)
                }
                if let refreshError = model?.refreshError {
                    InlineRetryView(message: refreshError) { Task { await model?.load() } }
                }
                if detail.isLocality {
                    Label("Town or city — logged as a Day Trip destination", systemImage: "signpost.right").font(.footnote).foregroundStyle(Theme.secondaryText)
                }
                FriendMemoriesSection(memories: friendMemories, onOpenAuthor: { router.push(.member($0)) },
                                      onOpenPhotos: { router.push(.gallery(experienceID: experienceID, visitID: $0)) },
                                      onReport: { target in reportReason = nil; reportTarget = target })
                scores(detail)
                memories(detail)
                privateNote(detail)
                if detail.isLocality {
                    CityGuideCard(name: summary.locality ?? summary.name, region: summary.region, country: summary.countryName, coordinate: summary.coordinate)
                }
                if detail.providerStatus == .unavailable {
                    Label("This listing is no longer available in Apple Maps. Your memories stay here.", systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(Theme.fine)
                }
                if let memoriesModel, !memoriesModel.hasLoaded || memoriesModel.memories.contains(where: { !$0.isOwn && !friendMemories.map(\.id).contains($0.id) }) {
                    PublicMemoriesSection(model: memoriesModel, onOpenAuthor: { router.push(.member($0)) },
                                          onOpenPhotos: { router.push(.gallery(experienceID: experienceID, visitID: $0)) },
                                          onReport: { target in reportReason = nil; reportTarget = target },
                                          excludedIDs: Set(friendMemories.map(\.id)))
                }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .task(id: summary.id) {
            let appleItem = await AppleMapsLookup.mapItem(for: summary)
            lookAround = await AppleMapsLookup.lookAroundScene(item: appleItem, coordinate: summary.coordinate)
        }
    }

    /// The place's photo first, then photos from friends' visits. Look Around is a button on the map.
    private func galleryItems(_ summary: ExperienceSummary) -> [PlaceGalleryItem] {
        var items: [PlaceGalleryItem] = []
        if let url = summary.photoURL { items.append(.photo(url, credit: summary.photoCredit)) }
        let visitPhotos = friendMemories.flatMap { $0.media.sorted { $0.position < $1.position } }.prefix(8)
        items += visitPhotos.map { .visitPhoto(path: $0.path) }
        return items
    }

    private func reload() async {
        async let detail: Void = model?.load() ?? ()
        async let memories: Void = memoriesModel?.load() ?? ()
        async let friends = try? services.plans.friendMemories(experienceID: experienceID)
        let loadedFriends = await friends
        _ = await (detail, memories)
        if let loadedFriends { friendMemories = loadedFriends }
    }

    private func reportTitle(_ target: ReportTarget) -> String {
        if reportReason == .incorrectPlaceOrCategory { return "Report category issue" }
        if case .visit = target { return "Report memory" }
        return "Report a problem"
    }

    /// Apple's street-level view of the spot, from a binoculars button on the map.
    private func lookAroundButton(_ scene: MKLookAroundScene) -> some View {
        Button { showsLookAround = true } label: {
            Image(systemName: "binoculars.fill")
                .font(.headline)
                .foregroundStyle(Roam.ink)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .floatingBubble(Circle())
        .lookAroundViewer(isPresented: $showsLookAround, initialScene: scene)
        .accessibilityLabel("Look Around")
        .accessibilityIdentifier("detail-look-around")
    }

    /// The place on a map that fills the screen behind the card; pan and zoom freely.
    private func placeMap(_ detail: ExperienceDetail) -> some View {
        let coordinate = detail.summary.coordinate
        let span: CLLocationDistance = detail.isLocality ? 20_000 : Self.placeSpan
        return Map(position: $mapCamera, selection: $nearbyFeature) {
            Marker(detail.summary.name, systemImage: PlaceIcon.symbol(appleType: detail.summary.providerCategory, category: detail.myRating?.category ?? detail.summary.category),
                   coordinate: coordinate)
                .tint(detail.myRating != nil ? PlaceState.visited.markerColor : detail.summary.pinTint)
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .all))
        // Tapping a nearby place Apple shows on the map opens that place's page.
        .mapFeatureSelectionDisabled { $0.kind != .pointOfInterest }
        .onChange(of: nearbyFeature) { _, feature in
            guard let feature else { return }
            nearbyFeature = nil
            Task {
                guard let item = try? await MKMapItemRequest(feature: feature).mapItem,
                      let candidate = MapKitPlaceSearchProvider.candidate(from: item),
                      let place = try? await services.experiences.resolve(candidate), place.id != experienceID else { return }
                // The tapped place is already on screen, so the map stays exactly where it is; only the card changes.
                Self.handoff[place.id] = place.coordinate
                if let mapRegion { Self.handoffRegion[place.id] = mapRegion }
                if let onOpenPlace { onOpenPlace(place.id) } else { router.push(.experience(place.id)) }
            }
        }
        .onMapCameraChange(frequency: .onEnd) { mapRegion = $0.region }
        .onAppear {
            guard !cameraPlaced else { return }
            cameraPlaced = true
            // Opened from another map, it keeps that view; otherwise the place sits in the middle of the visible map.
            mapCamera = .region(Self.handoffRegion.removeValue(forKey: experienceID) ?? Self.visibleCentered(coordinate, span: span))
        }
        .accessibilityLabel("Map showing \(detail.summary.name)")
        .accessibilityIdentifier("detail-map")
    }

    /// The place's state is shown by its button alone: once you've been, planned or saved it, that button fills in
    /// and the other two step aside. Send is always there.
    private func actionRow(_ detail: ExperienceDetail) -> some View {
        let id = detail.summary.id
        let rated = detail.myRating != nil
        let visited = rated || detail.summary.viewer.hasVisits
        let planned = !visited && !plannedTrips.isEmpty
        let saved = !visited && !planned && library.isBookmarked(id)
        // Only cities are planned; a place is saved, then shows up on any trip to its city.
        let anyState = visited || saved
        // A place is either somewhere you've been or somewhere you want to go: once you've been, Save greys out.
        // A saved place can still be logged, which moves it to been.
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.m) {
                do {
                    circleAction(visited ? "checkmark" : "plus", tint: PlaceState.visited.markerColor, filled: visited, caption: visited ? "Been" : "Log",
                                 label: visited ? "Been here" : "Log a visit", identifier: rated ? "detail-add-visit" : "detail-log") {
                        // Been here offers another visit, or taking the place off where you've been.
                        if visited { choosingBeen = true } else { Task { await openLog(.firstLog) } }
                    }
                    .confirmationDialog("Been here", isPresented: $choosingBeen, titleVisibility: .hidden) {
                        Button("Add another visit") { Task { await openLog(rated ? .addVisit : .firstLog) } }
                        Button("Remove from places I've been", role: .destructive) { confirmingUnbeen = true }
                    }
                    .alert("Remove from places you've been?", isPresented: $confirmingUnbeen) {
                        Button("Remove", role: .destructive) { Task { await removeBeen(detail) } }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This deletes your visits here, with their notes and photos, and your ranking.")
                    }
                    .disabled(deleting || failedDeletion != nil)
                }
                circleAction(saved ? "bookmark.fill" : "bookmark", tint: PlaceState.wishlist.markerColor, filled: saved,
                             caption: saved ? "Saved" : "Save", label: saved ? "Saved. Tap to remove" : "Save", identifier: "detail-save",
                             inactive: visited) {
                    Task { await library.setBookmark(id, saved: !library.isBookmarked(id)) }
                }
                // Sending isn't ready yet, so Send shows greyed out.
                circleAction("paperplane", tint: Roam.ink, filled: false, caption: "Send", label: "Send (coming soon)", identifier: "detail-recommend",
                             inactive: true) {
                    router.sheet = .share(.place(id), title: detail.summary.name)
                }
                Spacer(minLength: 0)
            }
            .animation(.spring(duration: 0.3), value: anyState)
            .task(id: "\(id)-\(library.revision)") { plannedTrips = await PlannedPlaces.trips(holding: id, services: services) }
            if let error = library.lastError {
                InlineRetryView(message: error, retryTitle: "Dismiss") { library.clearError() }
            }
        }
    }

    /// A round icon button: filled in its colour when on (or always, for the main action), tinted outline otherwise.
    /// `inactive` greys the button out and ignores taps.
    private func circleAction(_ symbol: String, tint: Color, filled: Bool, caption: String, label: String, identifier: String,
                              inactive: Bool = false, action: @escaping () -> Void) -> some View {
        let color = inactive ? Roam.inkFaint : tint
        // A tap handler rather than a Button: on a place's card over a city's map, Buttons never received their taps.
        return VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(filled && !inactive ? .white : color)
                // The same size as the directions button.
                .frame(width: 38, height: 38)
                .background(Circle().fill(filled && !inactive ? color : color.opacity(0.15)))
            Text(caption).font(.caption2).foregroundStyle(inactive ? Roam.inkFaint : Roam.ink).lineLimit(1).fixedSize()
        }
        .frame(minWidth: 52)
        .contentShape(Rectangle())
        .onTapGesture { if !inactive { action() } }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }


    /// For now only Google's rating is shown; Roam's own scores are set aside.
    @ViewBuilder private func scores(_ detail: ExperienceDetail) -> some View {
        if detail.summary.googleRating != nil {
            GoogleRatingLine(experience: detail.summary).font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .roamCard()
                .accessibilityIdentifier("detail-google-rating")
        }
    }

    @ViewBuilder private func memories(_ detail: ExperienceDetail) -> some View {
        if !detail.myVisits.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("Your memories").font(.roamTitle(.title3))
                ForEach(detail.myVisits) { visit in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(visit.visitDate.displayString).font(.subheadline.weight(.semibold))
                        if !visit.publicNote.isEmpty { Text(visit.publicNote).font(.body) }
                        if !visit.media.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(Array(visit.media.sorted { $0.position < $1.position }.enumerated()), id: \.element.id) { index, media in
                                        Button { router.push(.gallery(experienceID: experienceID, visitID: visit.id)) } label: {
                                            RemoteImageView(path: media.path, accessibilityLabel: "Photo \(index + 1) from your visit")
                                                .frame(width: 96, height: 96).clipShape(RoundedRectangle(cornerRadius: 10))
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("detail-visit-photo-\(visit.id.uuidString)-\(index)")
                                    }
                                }
                            }
                        }
                        HStack(spacing: Theme.Spacing.l) {
                            Button { editingVisit = visit } label: { Label("Edit", systemImage: "pencil") }
                                .frame(minHeight: Theme.minimumHitTarget)
                                .disabled(deleting || failedDeletion != nil)
                                .accessibilityLabel("Edit note, date and photos for this visit")
                                .accessibilityIdentifier("detail-edit-visit-\(visit.id.uuidString)")
                            Button(role: .destructive) {
                                pendingDeletion = DetailDeletion(experienceID: experienceID, visitID: visit.id,
                                                                 lastVisit: detail.myVisits.count == 1 && detail.myRating != nil)
                            } label: { Text("Delete visit").foregroundStyle(Theme.disliked) }
                            .frame(minHeight: Theme.minimumHitTarget)
                            .disabled(deleting || failedDeletion != nil)
                            .accessibilityIdentifier("detail-delete-visit-\(visit.id.uuidString)")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .contain)
                    Divider()
                }
            }
            .roamCard()
            .accessibilityIdentifier("detail-memories")
        }
    }

    /// Owner-only note, separate from public visit notes and never part of any public projection.
    private func privateNote(_ detail: ExperienceDetail) -> some View {
        Button { showsPrivateNote = true } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "lock.fill").foregroundStyle(Theme.accent).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(detail.hasPrivateNote ? "Private note" : "Add a private note").font(.subheadline.weight(.semibold))
                    Text("Only you can see this.").font(.caption).foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.secondaryText).accessibilityHidden(true)
            }
            .frame(minHeight: Theme.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .roamCard()
        .accessibilityIdentifier("detail-private-note")
    }

    private func overflowMenu(_ detail: ExperienceDetail) -> some View {
        Menu {
            if let website = detail.website {
                Button { openURL(website) } label: { Label("Website", systemImage: "safari") }
                    .accessibilityIdentifier("detail-website")
            }
            if let phone = detail.phone, let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                Button { openURL(url) } label: { Label("Call", systemImage: "phone") }
                    .accessibilityIdentifier("detail-call")
            }
            if detail.myRating != nil {
                Button { Task { await openLog(.rerank) } } label: { Label("Rank again", systemImage: "arrow.triangle.2.circlepath") }
                    .disabled(deleting || failedDeletion != nil)
                    .accessibilityIdentifier("detail-rerank")
                Button(role: .destructive) {
                    pendingDeletion = DetailDeletion(experienceID: experienceID, visitID: nil, lastVisit: false)
                } label: { Label("Remove ranking", systemImage: "minus.circle") }
                .disabled(deleting || failedDeletion != nil)
                .accessibilityIdentifier("detail-remove-ranking")
            }
            Button { openInMaps(detail) } label: { Label("Open in Maps", systemImage: "map") }
            if detail.categoryLocked {
                Button {
                    reportReason = .incorrectPlaceOrCategory
                    reportTarget = .experience(detail.summary.id)
                } label: { Label("Report category issue", systemImage: "tag.slash") }
            }
            Button {
                reportReason = nil
                reportTarget = .experience(detail.summary.id)
            } label: { Label("Report a problem", systemImage: "flag") }
        } label: {
            Image(systemName: "ellipsis.circle").accessibilityLabel("More")
        }
        .accessibilityIdentifier("detail-overflow")
    }

    private func openLog(_ mode: LogRequest.Mode) async {
        do { router.sheet = .log(try await services.makeLogRequest(experienceID: experienceID, mode: mode)) }
        catch { actionError = session.handle(error) }
    }

    /// Takes the place off where you've been: every visit goes, and the ranking with the last one.
    private func removeBeen(_ detail: ExperienceDetail) async {
        guard !deleting else { return }
        deleting = true
        defer { deleting = false }
        actionError = nil
        do {
            for visit in detail.myVisits {
                let result = try await services.ranking.deleteVisit(visitID: visit.id, operationID: UUID(), allowRatingRemoval: true)
                if result.removedRating { library.applyRatingRemoved(experienceID) }
            }
            if detail.myRating != nil, detail.myVisits.isEmpty {
                try await services.ranking.removeRating(experienceID: experienceID, operationID: UUID())
                library.applyRatingRemoved(experienceID)
            }
            await library.refresh()
            library.noteChanged()
            await model?.load()
        } catch { actionError = session.handle(error) }
    }

    private func confirmDeletion(_ action: DetailDeletion) async {
        guard !deleting, let owner = session.userID else { return }
        let name = "detail-pending-delete-\(experienceID.uuidString)"
        deleting = true
        defer { deleting = false }
        actionError = nil
        do {
            try services.storage.write(action, name: name, userID: owner)
            if let visitID = action.visitID {
                let result = try await services.ranking.deleteVisit(visitID: visitID, operationID: action.operationID, allowRatingRemoval: action.lastVisit)
                guard owner == session.userID else { return }
                if result.removedRating { library.applyRatingRemoved(experienceID) }
            } else {
                try await services.ranking.removeRating(experienceID: experienceID, operationID: action.operationID)
                guard owner == session.userID else { return }
                library.applyRatingRemoved(experienceID)
            }
            services.storage.remove(name: name, userID: owner)
            failedDeletion = nil
            await library.refresh()
            library.noteChanged()
            await model?.load()
        } catch {
            guard owner == session.userID else { return }
            if let error = error as? RoamError, error == .lastVisitConfirmationRequired, let visitID = action.visitID {
                services.storage.remove(name: name, userID: owner)
                failedDeletion = nil
                pendingDeletion = DetailDeletion(experienceID: experienceID, visitID: visitID, lastVisit: true)
                await model?.load()
                return
            }
            if let error = error as? RoamError, !error.isRetryable {
                services.storage.remove(name: name, userID: owner)
                failedDeletion = nil
            } else { failedDeletion = action }
            actionError = session.handle(error)
        }
    }

    /// Hands off to Apple Maps; cancelling there leaves Roam unchanged.
    private func openInGoogleMaps(_ detail: ExperienceDetail) {
        var parts = URLComponents(string: "https://www.google.com/maps/dir/")!
        parts.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: "\(detail.summary.latitude),\(detail.summary.longitude)"),
        ]
        if let url = parts.url { openURL(url) }
    }

    private func openInMaps(_ detail: ExperienceDetail) {
        Task { @MainActor in
            var item: MKMapItem?
            if detail.provider == .mapkit, let raw = detail.summary.providerPlaceID, let identifier = MKMapItem.Identifier(rawValue: raw) {
                item = try? await MKMapItemRequest(mapItemIdentifier: identifier).mapItem
            }
            let mapItem = item ?? {
                let fallback = MKMapItem(placemark: MKPlacemark(coordinate: detail.summary.coordinate))
                fallback.name = detail.summary.name
                return fallback
            }()
            mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
        }
    }
}

extension ReportTarget: Identifiable {
    var id: String { "\(kind)-\(targetID.uuidString)" }
}

private struct DetailDeletion: Codable, Identifiable {
    let operationID: UUID
    let experienceID: UUID
    let visitID: UUID?
    let lastVisit: Bool
    var id: UUID { operationID }
    init(experienceID: UUID, visitID: UUID?, lastVisit: Bool) {
        operationID = UUID(); self.experienceID = experienceID; self.visitID = visitID; self.lastVisit = lastVisit
    }
    var title: String { visitID == nil ? "Remove ranking?" : (lastVisit ? "Delete your last visit?" : "Delete visit?") }
    var buttonTitle: String { visitID == nil ? "Remove ranking" : "Delete visit" }
    var confirmID: String { visitID == nil ? "confirm-remove-ranking" : (lastVisit ? "confirm-delete-last-visit" : "confirm-delete-visit") }
    var message: String {
        if visitID == nil { return "Your visits, notes and photos will stay; your ranking and rating activity will be removed." }
        if lastVisit { return "This deletes the visit, its public note and photos, and its activity. Because it is your last visit, your ranking and rating activity will also be removed." }
        return "This deletes this visit, its public note and photos, and its activity. Other visits stay. Removing the last visit of a ranking requires a separate confirmation."
    }
}

/// Places you plan to go. Stored on your trips, including ones from before places were organized by country;
/// new plans go on a single "Planned" trip that never appears in the app.
/// The upcoming or planning trips a place is on.
enum PlannedPlaces {
    @MainActor static func trips(holding id: UUID, services: AppServices) async -> [String] {
        let today = MyTimeline.today()
        var names: [String] = []
        for trip in (try? await services.plans.myTrips()) ?? [] where trip.phase(today: today) != .past {
            if let detail = try? await services.plans.trip(id: trip.id), detail.places.contains(where: { $0.id == id && $0.isPlanned }) {
                names.append(trip.name)
            }
        }
        return names
    }
}

/// A place page's navigation-bar setup. Over a city's map the city page owns the bar, so the card adds none (a second
/// title and toolbar from the card stopped every button in it from receiving taps).
private struct PlacePageChrome: ViewModifier {
    let enabled: Bool
    let title: String

    func body(content: Content) -> some View {
        if enabled {
            content
                // The place's card takes the tab bar's spot and runs to the bottom of the screen.
                .roamTabBar(hidden: true)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // The card over the map names the place; the bar stays clear so the map shows through.
                    ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
                }
        } else {
            content
        }
    }
}
