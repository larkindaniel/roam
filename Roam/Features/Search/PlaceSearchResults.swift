import CoreLocation
import SwiftUI

// Roam has exactly three searches, and every search field in the app is one of them:
//   1. Worldwide places (`PlaceSearchScope.world`): your places, countries, states, cities, then everything Apple knows,
//      places near you first, as Apple Maps does. No filters.
//   2. A city or an area (`.city`, `.area`): only cities near it and places in or around it, nothing else.
//   3. Accounts (`AccountSearchResults`): people by name or @handle, or just your friends when picking them.
// They all type into `RoamSearchField` and list their results the same way.

/// Where a place search looks.
enum PlaceSearchScope: Equatable {
    /// Anywhere, places near you first.
    case world
    /// In and around one city: its places and the towns nearby.
    case city(Destination)
    /// Inside a country or a state ("Where in Norway?"); `around` steers places to the middle of it.
    case area(name: String, countryCode: String, region: Destination?, around: Destination)

    /// How far "around a city" reaches.
    static func reach(of city: Destination) -> CLLocationDistance { max(city.radiusMeters * 3, 40_000) }

    fileprivate var steer: Destination? {
        switch self {
        case .world: return nil
        case .city(let city): return city
        case .area(_, _, _, let around): return around
        }
    }

    /// Whether something at this spot, in this country and state, belongs in this search.
    fileprivate func contains(_ coordinate: CLLocationCoordinate2D, country: String?, region value: String?) -> Bool {
        switch self {
        case .world:
            return true
        case .city(let city):
            let centre = CLLocation(latitude: city.latitude, longitude: city.longitude)
            return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude).distance(from: centre) <= Self.reach(of: city)
        case .area(_, let code, let region, _):
            guard country?.uppercased() == code.uppercased() else { return false }
            guard let region else { return true }
            guard let value, !value.isEmpty else { return false }
            return [region.region, region.name].contains { $0?.caseInsensitiveCompare(value) == .orderedSame }
        }
    }

    fileprivate var emptyMessage: String {
        switch self {
        case .world: return "No places match"
        case .city(let city): return "Nothing in or around \(city.name) matches"
        case .area(let name, _, _, _): return "Nothing in \(name) matches"
        }
    }
}

/// Which kinds of result a screen can use. Everything, unless a screen can only take one kind (a city picker takes
/// only cities).
struct PlaceSearchKinds: OptionSet, Hashable {
    let rawValue: Int
    static let places = PlaceSearchKinds(rawValue: 1)
    static let cities = PlaceSearchKinds(rawValue: 2)
    /// Countries and states (worldwide only).
    static let areas = PlaceSearchKinds(rawValue: 4)
    static let all: PlaceSearchKinds = [.places, .cities, .areas]
}

/// A result someone tapped.
enum PlaceSearchPick: Hashable, Identifiable {
    /// Already on Roam: one of your places, or a place someone added.
    case experience(ExperienceSummary)
    /// From Apple Maps; `PlaceSearch.resolve` turns it into a Roam place.
    case place(SearchHit)
    case city(Destination)
    case region(Destination)
    case country(String)

    var id: String {
        switch self {
        case .experience(let place): return "experience:\(place.id)"
        case .place(let hit): return hit.experience.map { "experience:\($0.id)" } ?? "place:\(hit.id)"
        case .city(let city): return "city:\(city.id)"
        case .region(let area): return "region:\(area.id)"
        case .country(let code): return "country:\(code)"
        }
    }
}

/// The running place search. The page owns it, not the results view, so a card rebuilding its content as it rises
/// (My Places) can't cancel a search halfway and leave it blank.
@MainActor
@Observable
final class PlaceSearch {
    private(set) var model: ExperienceSearchModel?
    private(set) var scope: PlaceSearchScope = .world
    private var foundCities: [Destination] = []
    private var foundRegions: [Destination] = []
    private var foundCountries: [String] = []
    /// Places people added to Roam themselves, which Apple doesn't have.
    private var foundOnRoam: [ExperienceSummary] = []

    /// From the first letter until every part of the search (places, cities, Roam's own) has come back, so "nothing
    /// matches" never flashes up while results are still on their way.
    private(set) var isSearching = false
    private var generation = 0

    var phase: ExperienceSearchModel.Phase { model?.phase ?? .idle }
    var finished: Bool { !isSearching && (phase == .noResults || phase == .results) }

    var cities: [Destination] {
        let scoped = foundCities.filter { scope.contains($0.coordinate, country: $0.countryCode, region: $0.region) }
        // A city's own search doesn't offer the city itself.
        if case .city(let city) = scope { return scoped.filter { GeographyKey.normalize($0.name) != GeographyKey.normalize(city.name) } }
        return scoped
    }
    var regions: [Destination] { scope == .world ? foundRegions : [] }
    var countries: [String] { scope == .world ? foundCountries : [] }
    var onRoam: [ExperienceSummary] {
        foundOnRoam.filter { scope.contains($0.coordinate, country: $0.countryCode, region: $0.region) }
    }
    var places: [SearchHit] {
        (model?.hits ?? []).filter { scope.contains($0.candidate.coordinate, country: $0.candidate.countryCode, region: $0.candidate.region) }
    }

    func run(_ query: String, services: AppServices, scope: PlaceSearchScope = .world) async {
        self.scope = scope
        generation += 1
        let current = generation
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            model?.query = ""; foundCities = []; foundCountries = []; foundRegions = []; foundOnRoam = []
            isSearching = false
            return
        }
        isSearching = true
        // A newer search takes over; only the latest one says it's done.
        defer { if current == generation { isSearching = false } }
        try? await Task.sleep(for: Limits.searchDebounce)
        guard !Task.isCancelled else { return }
        services.location.requestAccessIfNeeded()
        if model == nil { model = ExperienceSearchModel(services: services) }
        // Inside an area, its name goes with the city search so its towns come first.
        let cityQuery: String
        switch scope {
        case .world: cityQuery = query
        case .city(let city): cityQuery = [query, city.region ?? city.countryName].compactMap { $0 }.joined(separator: ", ")
        case .area(let name, _, _, _): cityQuery = "\(query), \(name)"
        }
        async let found = services.places.searchDestinations(query: cityQuery)
        async let areas = services.places.searchRegions(query: query)
        async let known = services.plans.searchRoamPlaces(query: query)
        await model?.search(query, near: scope.steer)
        let cityHits = (try? await found) ?? []
        let regionHits = scope == .world ? ((try? await areas) ?? []) : []
        let roamHits = ((try? await known) ?? []).filter { $0.category != .dayTrips }
        guard !Task.isCancelled else { return }
        foundCities = Array(cityHits.prefix(5))
        foundRegions = regionHits
        foundCountries = scope == .world ? Self.countries(matching: query) : []
        foundOnRoam = roamHits
    }

    func retry(_ query: String) async { await model?.search(query, near: scope.steer) }

    /// The Roam place behind a tapped place, adding it to Roam first if it's new.
    func resolve(_ hit: SearchHit) async throws -> ExperienceSummary {
        guard let model else { throw RoamError.unavailable }
        return try await model.resolve(hit)
    }

    private static let groupings: Set<String> = ["EU", "EZ", "UN", "QO", "XA", "XB"]

    private static func countries(matching query: String) -> [String] {
        let needle = " " + query.trimmingCharacters(in: .whitespaces)
        guard needle.count > 2 else { return [] }
        let found: [(code: String, name: String)] = Locale.Region.isoRegions.compactMap { region in
            let code = region.identifier
            // Every two-letter country or territory, small ones too (Hong Kong, Singapore aren't on the world outline map),
            // but not groupings like the EU or UN.
            guard code.count == 2, code.allSatisfy(\.isLetter), !Self.groupings.contains(code),
                  case let name = CountryName.display(code: code),
                  (" " + name).range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil else { return nil }
            return (code, name)
        }
        // "nor" puts Norway ahead of North Korea: the closest to what's typed first.
        return found.sorted { $0.name.count < $1.name.count }.prefix(2).map(\.code)
    }
}

/// A place search's results, the same everywhere: your own places first, then countries, states, cities, then places,
/// each a row with its icon, name and where it is. Tapping one opens it, unless the screen picks it instead.
struct PlaceSearchResults: View {
    let query: String
    let placeSearch: PlaceSearch
    /// Your places to match by name first (been, going, saved); only My Places has them to hand.
    var mine: [PlaceMapItem] = []
    var kinds: PlaceSearchKinds = .all
    /// Picks already made, left out of the results.
    var excluding: Set<String> = []
    /// Shows a tick on results already chosen, for screens that choose several (onboarding).
    var isPicked: ((PlaceSearchPick) -> Bool)? = nil
    /// What a tap does; without it, the result opens.
    var onPick: ((PlaceSearchPick) -> Void)? = nil

    @Environment(AppRouter.self) private var router
    @State private var opening: String?
    @State private var error: String?

    private struct Row: Identifiable {
        let pick: PlaceSearchPick
        var flag: String? = nil
        let symbol: String
        var tint: Color = Roam.inkMuted
        let title: String
        let subtitle: String
        var id: String { pick.id }
    }

    private var rows: [Row] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        var rows: [Row] = []
        if kinds.contains(.places) {
            rows += mine.filter { $0.experience.name.lowercased().contains(needle) }.uniqued { $0.id }.prefix(8).map {
                Row(pick: .experience($0.experience), symbol: $0.experience.iconName, tint: $0.state.markerColor,
                    title: $0.experience.name, subtitle: $0.experience.areaLine)
            }
        }
        if kinds.contains(.areas) {
            rows += placeSearch.countries.map {
                Row(pick: .country($0), flag: TripTitle.flag($0), symbol: "flag", title: CountryName.display(code: $0), subtitle: "Country")
            }
            rows += placeSearch.regions.map {
                Row(pick: .region($0), symbol: "map", title: $0.name, subtitle: CountryName.display($0.countryName, code: $0.countryCode) ?? "")
            }
        }
        if kinds.contains(.cities) {
            rows += placeSearch.cities.map { Row(pick: .city($0), symbol: "signpost.right.and.left", title: $0.name, subtitle: $0.subtitle) }
        }
        if kinds.contains(.places) {
            rows += placeSearch.onRoam.map { Row(pick: .experience($0), symbol: $0.iconName, title: $0.name, subtitle: $0.areaLine) }
            rows += placeSearch.places.map { hit in
                Row(pick: .place(hit), symbol: hit.experience?.iconName ?? hit.candidate.iconName, title: hit.candidate.name,
                    subtitle: [hit.candidate.locality, CountryName.display(hit.candidate.countryName, code: hit.candidate.countryCode)]
                        .compactMap { $0 }.uniqued().joined(separator: ", "))
            }
        }
        // The same place found twice (yours and Apple's) shows once.
        return rows.uniqued { $0.id }.filter { !excluding.contains($0.id) }
    }

    var body: some View {
        let rows = rows
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if let error { Text(error).font(.footnote).foregroundStyle(Roam.signal) }
            if rows.isEmpty {
                switch placeSearch.phase {
                case _ where placeSearch.isSearching, .idle, .loading:
                    // Still looking: rows are on their way, rather than a blank page.
                    SkeletonList(rows: 3)
                case .failed(let message):
                    InlineRetryView(message: message) { Task { await placeSearch.retry(query) } }
                case .noResults, .results:
                    Text("\(placeSearch.scope.emptyMessage) \u{201C}\(query)\u{201D}.").font(.subheadline).foregroundStyle(Roam.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("search-no-results")
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        rowView(row)
                        if row.id != rows.last?.id { RowSeparator() }
                    }
                }
                .roamCard(padding: Theme.Spacing.m)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("search-results")
            }
        }
    }

    private func rowView(_ row: Row) -> some View {
        Button { Task { await pick(row.pick) } } label: {
            HStack(spacing: Theme.Spacing.m) {
                Group {
                    if let flag = row.flag { Text(flag).font(.title3) } else { Image(systemName: row.symbol).foregroundStyle(row.tint) }
                }
                .frame(width: 24).accessibilityHidden(true)
                // Name and where it is sit tight together, so the rows read apart.
                VStack(alignment: .leading, spacing: -2) {
                    Text(row.title).font(.headline).foregroundStyle(Roam.ink).lineLimit(1)
                    if !row.subtitle.isEmpty { Text(row.subtitle).font(.footnote).foregroundStyle(Roam.inkMuted).lineLimit(1) }
                }
                Spacer(minLength: 0)
                if opening == row.id {
                    ProgressView()
                } else if let isPicked {
                    let picked = isPicked(row.pick)
                    Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(picked ? PlaceState.visited.markerColor : Roam.inkFaint)
                }
            }
            .frame(minHeight: Theme.minimumHitTarget)
            .padding(.vertical, Theme.Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(opening != nil)
        .accessibilityIdentifier("search-result-\(row.title)")
    }

    private func pick(_ pick: PlaceSearchPick) async {
        if let onPick { onPick(pick); return }
        error = nil
        switch pick {
        case .experience(let place): router.push(.experience(place.id))
        case .city(let city): router.push(.city(city))
        case .region(let area): router.push(.region(area))
        case .country(let code): router.push(.country(code))
        case .place(let hit):
            opening = pick.id
            defer { opening = nil }
            do { router.push(.experience(try await placeSearch.resolve(hit).id)) }
            catch { self.error = error.roamMessage }
        }
    }
}

/// The one search field: a magnifying glass, the text (never capitalised or corrected), and an × that clears it and
/// puts the keyboard away. `style` only changes what's behind it.
struct RoamSearchField: View {
    enum Style {
        /// A grey capsule, inside cards and sheets.
        case filled
        /// A floating glass capsule, over pages (Discover).
        case glass
        /// Nothing behind it: it sits in something that already has its own shape (a lowered card's bubble).
        case bare
    }

    let prompt: String
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    var style: Style = .filled
    /// White text, for dark glass over the globe.
    var onDark = false
    var identifier = "search-field"
    @Environment(\.onDarkBubble) private var onDarkBubble
    /// Extra to do when the × is tapped (closing a sheet's search, say).
    var onClear: (() -> Void)? = nil
    /// The × always shows (a sheet that is only this search, where it closes the sheet).
    var alwaysCancel = false

    private var hasText: Bool { !text.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        let onDark = onDark || onDarkBubble
        return HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "magnifyingglass").foregroundStyle(onDark ? Color.white.opacity(0.85) : Roam.inkMuted).accessibilityHidden(true)
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(onDark ? Color.white.opacity(0.75) : Roam.inkMuted))
                .foregroundStyle(onDark ? Color.white : Roam.ink)
                .tint(onDark ? Color.white : Roam.ink)
                .focused(focus)
                .submitLabel(.search)
                // Type as you like: no capitalising or correcting.
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier(identifier)
            if alwaysCancel || hasText || focus.wrappedValue {
                Button {
                    text = ""
                    focus.wrappedValue = false
                    onClear?()
                } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Roam.inkMuted) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel search")
                    .accessibilityIdentifier("\(identifier)-cancel")
            }
        }
        .font(.body)
        .padding(.horizontal, style == .bare ? 0 : Theme.Spacing.m)
        .frame(height: style == .glass ? 48 : 40)
        .frame(maxWidth: .infinity)
        .background { if style == .filled { Capsule().fill(Roam.ink.opacity(0.12)) } }
        .modifier(GlassIfNeeded(enabled: style == .glass))
    }

    private struct GlassIfNeeded: ViewModifier {
        let enabled: Bool
        func body(content: Content) -> some View {
            if enabled { content.floatingBubble(Capsule()) } else { content }
        }
    }
}

/// A sheet that is only a search: its field at the top, whose × closes the sheet. No title bar or separate close button.
struct SearchSheetBar: View {
    let prompt: String
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    var identifier = "search-field"
    let onClose: () -> Void

    var body: some View {
        RoamSearchField(prompt: prompt, text: $text, focus: focus, identifier: identifier, onClear: onClose, alwaysCancel: true)
            .frame(height: 44)
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.s)
    }
}

extension PlaceSearchPick {
    var title: String {
        switch self {
        case .experience(let place): return place.name
        case .place(let hit): return hit.candidate.name
        case .city(let city), .region(let city): return city.name
        case .country(let code): return CountryName.display(code: code)
        }
    }

    /// What it is, under its name in a list of picks.
    var kind: String {
        switch self {
        case .experience(let place): return place.category?.title ?? "Place"
        case .place(let hit): return hit.category?.title ?? "Place"
        case .city: return "City"
        case .region: return "State"
        case .country: return "Country"
        }
    }

    var symbol: String {
        switch self {
        case .experience(let place): return place.iconName
        case .place(let hit): return hit.experience?.iconName ?? hit.candidate.iconName
        case .city: return "signpost.right.and.left"
        case .region: return "map"
        case .country: return "flag"
        }
    }

    var coordinate: CLLocationCoordinate2D? {
        switch self {
        case .experience(let place): return place.coordinate
        case .place(let hit): return hit.candidate.coordinate
        case .city(let city), .region(let city): return city.coordinate
        case .country: return nil
        }
    }

    var photoURL: URL? {
        switch self {
        case .experience(let place): return place.photoURL
        case .place(let hit): return hit.experience?.photoURL
        default: return nil
        }
    }

    /// Logs it as somewhere you've been, from a city's or a country's log: a city is marked been with the dates, a place
    /// gets a visit with no rating (its own category files it).
    @MainActor
    func logAsBeen(services: AppServices, start: LocalDate?, end: LocalDate?) async throws {
        let place: ExperienceSummary
        var fallback: ExperienceCategory?
        switch self {
        case .city(let city):
            try await services.plans.markCityVisited(city, start: start, end: end)
            return
        case .region, .country:
            return
        case .experience(let known):
            place = known
        case .place(let hit):
            if let known = hit.experience { place = known } else { place = try await services.experiences.resolve(hit.candidate) }
            fallback = hit.category
        }
        let visit = VisitPayload(date: start, timeZoneIdentifier: TimeZone.current.identifier, publicNote: "", mediaIDs: [], audience: .public)
        _ = try await services.ranking.addVisit(AddVisitRequest(operationID: UUID(), experienceID: place.id, visit: visit,
                                                                category: place.category ?? fallback ?? .activities))
    }
}
