import Observation
import SwiftUI

/// Discover's two lists. A place sits in one list, and a place no friend rated is never shown as a friend's find.
struct ForYouSections: Equatable {
    /// The score a place needs to count as highly rated.
    static let highlyRated = Score(tenths: 70)

    var friends: [DiscoverPlace] = []
    var highlyRated: [DiscoverPlace] = []
    /// Everything else people have been to, for when you're browsing one city.
    var more: [DiscoverPlace] = []

    init(places: [DiscoverPlace] = []) {
        let unvisited = places.filter { $0.experience.viewer.myScore == nil && !$0.experience.viewer.hasVisits }
        friends = unvisited.filter { !$0.friendNames.isEmpty }.sorted(by: Self.order)
        let others = unvisited.filter { $0.friendNames.isEmpty }
        highlyRated = others.filter { ($0.communityScore ?? Score(tenths: 0)) >= Self.highlyRated }.sorted(by: Self.order)
        more = others.filter { ($0.communityScore ?? Score(tenths: 0)) < Self.highlyRated }.sorted(by: Self.order)
    }

    private static func order(_ lhs: DiscoverPlace, _ rhs: DiscoverPlace) -> Bool {
        let left = lhs.communityScore?.tenths ?? -1
        let right = rhs.communityScore?.tenths ?? -1
        return left == right ? lhs.experience.name < rhs.experience.name : left > right
    }
}

@MainActor
@Observable
final class ForYouModel {
    private(set) var phase: LoadPhase<ForYouSections> = .idle
    private(set) var picks: [DirectShare] = []
    private(set) var cities: [DiscoverCity] = []
    private let plans: any PlanService
    private var generation = 0

    init(plans: any PlanService) {
        self.plans = plans
    }

    /// Picks aren't tied to a destination, so they show even before one is chosen.
    func loadPicks() async {
        if let shares = try? await plans.sharedWithMe() { picks = shares }
    }

    /// With no destination the lists cover everywhere.
    func load(_ destination: Destination?) async {
        generation += 1
        let token = generation
        phase = .loading
        do {
            let bounds = destination.map {
                GeoBounds(region: .init(center: $0.coordinate, latitudinalMeters: $0.radiusMeters * 2, longitudinalMeters: $0.radiusMeters * 2))
            }
            let found = try await plans.discoverPlaces(in: bounds)
            guard token == generation, !Task.isCancelled else { return }
            if destination == nil { cities = DiscoverCity.cities(from: found) }
            phase = .loaded(ForYouSections(places: found))
        } catch {
            guard token == generation, !(error is CancellationError) else { return }
            phase = .failed(error.roamMessage)
        }
    }
}

/// Search results split into areas to browse and specific places to open.
struct DiscoverResults: Equatable {
    var destinations: [Destination] = []
    /// Places already on Roam come first, with what friends said about them.
    var onRoam: [ExperienceSummary] = []
    var places: [SearchHit] = []

    var isEmpty: Bool { destinations.isEmpty && places.isEmpty && onRoam.isEmpty }

    /// Towns come back from both searches, so place results keep only points of interest.
    init(destinations: [Destination] = [], candidates: [PlaceCandidate] = [], matches: [String: ExperienceSummary] = [:], onRoam: [ExperienceSummary] = []) {
        self.destinations = destinations
        self.onRoam = onRoam
        let known = Set(onRoam.map(\.id))
        let knownNames = Set(onRoam.map { $0.name.lowercased() })
        places = candidates.filter { !$0.isLocality && !knownNames.contains($0.name.lowercased()) }
            .map { SearchHit(candidate: $0, experience: matches[$0.id]) }
            .filter { $0.experience.map { !known.contains($0.id) } ?? true }
    }
}

/// Discover: search for somewhere, then see what your friends and the community found there.
/// Sources stay separate and in a fixed order.
struct ForYouRootView: View {
    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @Environment(DestinationStore.self) private var destinations
    @Environment(LibraryStore.self) private var library
    @State private var model: ForYouModel?
    @State private var query = ""
    @State private var results: LoadPhase<DiscoverResults> = .idle
    @State private var openError: String?
    @State private var selected: Destination?
    @State private var barsHidden = false
    @FocusState private var searchFocused: Bool

    private var hasQuery: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    /// While you're searching, the search bar takes the whole row.
    private var searchActive: Bool { searchFocused || hasQuery }

    private var topBar: some View {
        HStack(spacing: Theme.Spacing.s) {
            if !searchActive {
                if selected != nil {
                    roundButton("chevron.left", label: "All cities", identifier: "discover-all-cities") { selected = nil }
                } else {
                    roundButton("plus", label: "Log a place", identifier: "log-place") { router.sheet = .logPlace }
                }
            }
            if selected == nil {
                searchField
            } else {
                Spacer(minLength: 0)
            }
            if searchActive {
                Button("Cancel") {
                    query = ""
                    searchFocused = false
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Roam.ink)
                .accessibilityIdentifier("discover-search-cancel")
            } else {
                HStack(spacing: Theme.Spacing.xs) {
                    ProfileAvatarButton()
                    Button {
                        // On a city's page the map opens on that city.
                        if let selected { destinations.select(selected, for: .explore) }
                        router.openExplore()
                    } label: {
                        Image(systemName: "map").font(.headline).foregroundStyle(Roam.ink).frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Explore the map")
                    .accessibilityIdentifier("open-explore")
                }
                .padding(.horizontal, 6)
                .frame(height: 48)
                .floatingBubble(Capsule())
            }
        }
        .animation(.spring(duration: 0.3), value: searchActive)
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "magnifyingglass").foregroundStyle(Roam.inkMuted).accessibilityHidden(true)
            TextField("Search", text: $query, prompt: Text(searchActive ? "A city, neighbourhood or place" : "Search"))
                .focused($searchFocused)
                .submitLabel(.search)
                .accessibilityIdentifier("discover-search")
            if hasQuery {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Roam.inkMuted) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .floatingBubble(Capsule())
    }

    private func roundButton(_ symbol: String, label: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.headline).foregroundStyle(Roam.ink).frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .floatingBubble(Circle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    var body: some View {
        Group {
            if hasQuery {
                List { searchResults }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
            } else {
                ScrollView { landing.padding(.horizontal, Theme.Spacing.l).padding(.bottom, Theme.Spacing.xxl) }
                    // Reading down hides the top buttons and search; any move back up brings them back.
                    .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { old, new in
                        let hide = new > 40 && new > old
                        if new <= 40 || new < old - 4 { if barsHidden { withAnimation(.easeOut(duration: 0.2)) { barsHidden = false } } }
                        else if hide && !barsHidden { withAnimation(.easeOut(duration: 0.2)) { barsHidden = true } }
                    }
            }
        }
        .background(Roam.paper)
        // One row of floating controls instead of a navigation bar: log or back, search, then profile and map.
        // Scrolling down tucks the row away; scrolling up brings it back.
        .safeAreaInset(edge: .top, spacing: 0) {
            topBar
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.s)
                .offset(y: barsHidden && !hasQuery && !searchFocused ? -140 : 0)
                .opacity(barsHidden && !hasQuery && !searchFocused ? 0 : 1)
        }
        .navigationTitle("Discover")
        .toolbar(.hidden, for: .navigationBar)
        .task(id: query) {
            guard hasQuery else { results = .idle; return }
            try? await Task.sleep(for: Limits.searchDebounce)
            guard !Task.isCancelled else { return }
            await search(query)
        }
        .task(id: selected?.id) {
            if model == nil { model = ForYouModel(plans: services.plans) }
            await model?.loadPicks()
            await model?.load(selected)
        }
        .screenIdentifier("foryou-root")
    }

    @ViewBuilder private var searchResults: some View {
        if let openError {
            Section { Text(openError).foregroundStyle(Roam.signal) }.listRowBackground(Roam.paperRaised)
        }
        switch results {
        case .idle, .loading:
            Section {
                HStack { ProgressView(); Text("Searching…").foregroundStyle(Roam.inkMuted) }
            }
            .listRowBackground(Roam.paperRaised)
        case .failed(let message):
            Section { InlineRetryView(message: message) { Task { await search(query) } } }
                .listRowBackground(Roam.paperRaised)
        case .loaded(let found) where found.isEmpty:
            Section {
                Text("Nothing matches \u{201C}\(query)\u{201D}.").foregroundStyle(Roam.inkMuted)
                    .accessibilityIdentifier("discover-no-results")
            }
            .listRowBackground(Roam.paperRaised)
        case .loaded(let found):
            if !found.places.isEmpty || !found.onRoam.isEmpty {
                Section("Places") {
                    ForEach(found.onRoam) { place in
                        Button { router.push(.experience(place.id)) } label: { placeResultLabel(name: place.name, category: place.category, area: place.areaLine, experience: place) }
                            .accessibilityIdentifier("discover-place-\(place.name)")
                    }
                    ForEach(found.places) { hit in placeResult(hit) }
                }
                .listRowBackground(Roam.paperRaised)
            }
            if !found.destinations.isEmpty {
                Section("Cities and towns") {
                    ForEach(found.destinations) { destination in
                        Button { choose(destination) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(destination.name).font(.headline).foregroundStyle(Roam.ink)
                                if !destination.subtitle.isEmpty {
                                    Text(destination.subtitle).font(.footnote).foregroundStyle(Roam.inkMuted)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: Theme.minimumHitTarget, alignment: .leading)
                        }
                        .accessibilityIdentifier("discover-result-\(destination.name)")
                    }
                }
                .listRowBackground(Roam.paperRaised)
            }
        }
    }

    private func placeResult(_ hit: SearchHit) -> some View {
        Button { Task { await open(hit) } } label: {
            placeResultLabel(name: hit.candidate.name, category: hit.category,
                             area: [hit.candidate.locality, hit.candidate.countryName].compactMap { $0 }.uniqued().joined(separator: ", "), experience: hit.experience)
        }
        .accessibilityIdentifier("discover-place-\(hit.candidate.name)")
    }

    private func placeResultLabel(name: String, category: ExperienceCategory?, area: String, experience: ExperienceSummary?) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline).foregroundStyle(Roam.ink)
                Text([category?.title, area].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.footnote).foregroundStyle(Roam.inkMuted)
                if let count = experience?.followingCount, count > 0 {
                    Text("\(count) \(count == 1 ? "friend" : "friends") rated this").font(.subheadline).foregroundStyle(Roam.ink)
                }
            }
            Spacer(minLength: Theme.Spacing.s)
            if let score = experience?.followingScore {
                Text(score.formatted).font(.system(.body, design: .rounded).bold()).monospacedDigit().foregroundStyle(Roam.ink)
            }
        }
        .frame(minHeight: Theme.minimumHitTarget)
    }

    private func open(_ hit: SearchHit) async {
        do {
            let summary: ExperienceSummary
            if let known = hit.experience { summary = known } else { summary = try await services.experiences.resolve(hit.candidate) }
            openError = nil
            router.push(.experience(summary.id))
        } catch { openError = error.roamMessage }
    }

    private var landing: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            if let selected { cityHeader(selected) }
            if let model, !model.picks.isEmpty { picksSection(model.picks) }
            switch model?.phase ?? .loading {
            case .idle, .loading:
                SkeletonList(rows: 3)
            case .failed(let message):
                InlineRetryView(message: message) { Task { await model?.load(selected) } }
            case .loaded where selected == nil:
                citiesSection(model?.cities ?? [])
            case .loaded(let sections):
                if let selected { cityDetail(selected, sections) }
            }
        }
        .padding(.top, Theme.Spacing.s)
    }

    /// What's known about one city: its Wikipedia summary, then friends' finds and highly rated places.
    @ViewBuilder private func cityDetail(_ destination: Destination, _ sections: ForYouSections) -> some View {
        CityGuideCard(name: destination.name, region: destination.region, country: destination.countryName, coordinate: destination.coordinate, showsPhoto: false)
        // One list: friends' places first, then the best rated, then the rest. Each card says who's been.
        let places = (sections.friends + sections.highlyRated + sections.more).uniqued { $0.id }
        if !places.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                sectionTitle("Places we think you'd enjoy")
                ForEach(places) { place in placeCard(place, evidence: place.friendEvidence, photoHeight: 200) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("discover-places")
        }
    }

    @ViewBuilder private func citiesSection(_ cities: [DiscoverCity]) -> some View {
        if cities.isEmpty {
            Text("Search for a city or a place to get started.")
                .font(.subheadline).foregroundStyle(Roam.inkMuted)
                .accessibilityIdentifier("discover-empty")
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                ForEach(cities) { city in cityCard(city) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("discover-cities")
        }
    }

    private func cityCard(_ city: DiscoverCity) -> some View {
        Button { choose(city.destination) } label: {
            CityCoverCard(city: city) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(city.destination.name).font(.roamTitle()).foregroundStyle(Roam.ink)
                    Text(cityLine(city)).font(.footnote).foregroundStyle(Roam.inkMuted).lineLimit(2).multilineTextAlignment(.leading)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("discover-city-\(city.destination.name)")
    }

    private func cityLine(_ city: DiscoverCity) -> String {
        var parts = [city.destination.countryName, "\(city.placeCount) \(city.placeCount == 1 ? "place" : "places")"].compactMap { $0 }
        let names = city.friendNames.compactMap { $0.split(separator: " ").first.map(String.init) }
        if let first = names.first {
            parts.append(names.count == 1 ? "\(first) has been" : (names.count == 2 ? "\(first) and \(names[1]) have been" : "\(first) and \(names.count - 1) others have been"))
        }
        return parts.joined(separator: " · ")
    }

    /// The chosen city heads the page: its Wikipedia photo, then its name and where it is.
    private func cityHeader(_ destination: Destination) -> some View {
        CityHeader(destination: destination)
    }

    private func picksSection(_ picks: [DirectShare]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            sectionTitle("Picked for you")
            ForEach(picks) { pick in
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text(pick.title).font(.roamTitle()).foregroundStyle(Roam.ink)
                    Text(pickLine(pick)).font(.footnote).foregroundStyle(Roam.inkMuted)
                    if !pick.message.isEmpty { Text("\u{201C}\(pick.message)\u{201D}") }
                    HStack(spacing: Theme.Spacing.s) {
                        Button(pick.experience != nil ? "Open place" : (pick.list != nil ? "Open list" : "Open trip")) { open(pick) }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)
                            .accessibilityIdentifier("foryou-pick-open-\(pick.title)")
                        if let place = pick.experience, !place.viewer.isBookmarked {
                            Button("Save") { Task { await library.setBookmark(place.id, saved: true) } }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                                .accessibilityIdentifier("foryou-pick-save-\(pick.title)")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .roamCard()
            }
        }
    }




    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.roamTitle()).foregroundStyle(Roam.ink).accessibilityAddTraits(.isHeader)
    }

    private func placeCard(_ place: DiscoverPlace, evidence: String?, photoHeight: CGFloat) -> some View {
        Button { router.push(.experience(place.id)) } label: {
            PhotoCard(path: place.coverPath, url: place.experience.photoURL, credit: place.experience.photoCredit,
                      label: "Photo of \(place.experience.name)", placeholderSymbol: place.experience.category?.symbolName ?? "mappin", height: photoHeight, lookAround: place.experience.coordinate) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.experience.name).font(.headline).foregroundStyle(Roam.ink).lineLimit(2).multilineTextAlignment(.leading)
                        Text([place.experience.category?.title, place.experience.locality].compactMap { $0 }.joined(separator: " · "))
                            .font(.footnote).foregroundStyle(Roam.inkMuted).lineLimit(1)
                        if let evidence { Text(evidence).font(.subheadline).foregroundStyle(Roam.ink).lineLimit(1) }
                    }
                    Spacer(minLength: Theme.Spacing.s)
                    if let score = (evidence != nil ? place.experience.followingScore : nil) ?? place.communityScore {
                        Text(score.formatted).font(.system(.title3, design: .rounded).bold()).monospacedDigit().foregroundStyle(Roam.ink)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("foryou-place-\(place.experience.name)")
    }

    private func choose(_ destination: Destination) {
        selected = destination
        destinations.select(destination, for: .search)
        query = ""
        searchFocused = false
    }

    private func search(_ text: String) async {
        services.location.requestAccessIfNeeded()
        results = .loading
        do {
            async let foundDestinations = services.places.searchDestinations(query: text)
            async let foundPlaces = services.places.searchPlaces(query: text, around: selected)
            async let foundOnRoam = services.plans.searchRoamPlaces(query: text)
            let (destinationList, candidates) = try await (foundDestinations, foundPlaces)
            let onRoam = (try? await foundOnRoam) ?? []
            let matches = (try? await services.experiences.matches(for: candidates)) ?? [:]
            guard !Task.isCancelled, text == query else { return }
            let found = DiscoverResults(destinations: destinationList, candidates: candidates, matches: matches, onRoam: onRoam)
            results = .loaded(found)
        } catch is CancellationError {
        } catch {
            guard text == query else { return }
            results = .failed(error.roamMessage)
        }
    }

    private func pickLine(_ pick: DirectShare) -> String {
        if let list = pick.list { return "A list from \(pick.sender.displayName) · \(list.itemCount) \(list.itemCount == 1 ? "place" : "places")" }
        if pick.trip != nil { return "A trip from \(pick.sender.displayName)" }
        return "From \(pick.sender.displayName)"
    }

    private func open(_ pick: DirectShare) {
        if let place = pick.experience { router.push(.experience(place.id)) }
        else if let list = pick.list { router.push(.list(list.id)) }
        else if let trip = pick.trip { router.push(.trip(trip.id)) }
    }
}

/// A city's card, led by its Wikipedia photo; a photo from a place there when Wikipedia has none.
private struct CityCoverCard<Content: View>: View {
    let city: DiscoverCity
    @ViewBuilder var content: () -> Content

    @State private var guide: CityGuide?
    @State private var looked = false

    var body: some View {
        let destination = city.destination
        Group {
            if let photo = guide?.photoURL {
                PhotoCard(url: photo, credit: "Wikipedia", label: "Photo of \(destination.name)", height: 180, content: content)
            } else if looked {
                PhotoCard(path: city.coverPath, url: city.coverURL, credit: city.coverCredit, label: "Photo from \(destination.name)", height: 180, content: content)
            } else {
                PhotoCard(label: "Photo of \(destination.name)", height: 180, content: content)
            }
        }
        .task(id: destination.id) {
            guide = await CityGuide.load(name: destination.name, region: destination.region, country: destination.countryName, coordinate: destination.coordinate)
            looked = true
        }
    }
}

private struct CityHeader: View {
    let destination: Destination

    @Environment(AppRouter.self) private var router
    @State private var guide: CityGuide?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .center, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(destination.name).font(.roamDisplay(.title)).accessibilityAddTraits(.isHeader)
                    if !destination.subtitle.isEmpty {
                        Text(destination.subtitle).font(.subheadline).foregroundStyle(Roam.inkMuted)
                    }
                }
                Spacer(minLength: 0)
                Button { router.sheet = .researchBrief(destination) } label: {
                    Label("Plan with AI", systemImage: "sparkles").font(.subheadline.weight(.semibold))
                }
                .buttonStyle(PillButtonStyle(tint: PlaceState.planned.markerColor))
                .accessibilityIdentifier("foryou-research-open")
            }
            // Credited once, under the blurb that follows.
            if let photo = guide?.photoURL {
                PlacePhotoView(url: photo, credit: nil, label: "Photo of \(destination.name)", placeholderSymbol: "building.2", height: 220, showsCredit: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("discover-city-header")
        .task(id: destination.id) {
            guide = await CityGuide.load(name: destination.name, region: destination.region, country: destination.countryName, coordinate: destination.coordinate)
        }
    }
}

