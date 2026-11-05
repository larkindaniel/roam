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


extension View {
    /// A floating control over a map: Liquid Glass on iOS 26, frosted material before it; `tint` colours the glass.
    @ViewBuilder func floatingBubble<S: Shape>(_ shape: S, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            background { ZStack { shape.fill(.regularMaterial); if let tint { shape.fill(tint) } } }
                .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
        }
    }
}
