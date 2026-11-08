import Observation
import SwiftUI

/// Roam's suggestions for one screen: cities (Discover, a country or state page) or a city's places. The server ranks
/// them from what you're allowed to see; this keeps them loaded and handles Not interested.
@MainActor
@Observable
final class ForYouModel {
    /// A city's places, best first.
    private(set) var phase: LoadPhase<[DiscoverPlace]> = .idle
    /// Cities, best first.
    private(set) var cityPhase: LoadPhase<[DiscoverCity]> = .idle
    private(set) var picks: [DirectShare] = []
    private let plans: any PlanService
    private var generation = 0
    private var cityGeneration = 0

    init(plans: any PlanService) {
        self.plans = plans
    }

    var places: [DiscoverPlace] { phase.value ?? [] }
    var cities: [DiscoverCity] { cityPhase.value ?? [] }

    /// Picks aren't tied to a destination, so they show even before one is chosen.
    func loadPicks() async {
        if let shares = try? await plans.sharedWithMe() { picks = shares }
    }

    /// Cities to suggest: everywhere (Discover), or one country's (its page; a state page keeps its own).
    func loadCities(countryCode: String?) async {
        cityGeneration += 1
        let token = cityGeneration
        if cityPhase.value == nil { cityPhase = .loading }
        do {
            let found = try await plans.suggestedCities(countryCode: countryCode)
            guard token == cityGeneration, !Task.isCancelled else { return }
            cityPhase = .loaded(found)
        } catch {
            guard token == cityGeneration, !(error is CancellationError) else { return }
            cityPhase = .failed(error.roamMessage)
        }
    }

    /// A city's places. They pick up Google photos and ratings in the background, then the list refreshes once.
    func load(_ destination: Destination) async {
        generation += 1
        let token = generation
        phase = .loading
        let bounds = GeoBounds(region: .init(center: destination.coordinate, latitudinalMeters: destination.radiusMeters * 2,
                                             longitudinalMeters: destination.radiusMeters * 2))
        do {
            let found = try await plans.suggestedPlaces(in: bounds)
            guard token == generation, !Task.isCancelled else { return }
            phase = .loaded(found)
            let missing = found.filter { $0.experience.googleRating == nil || $0.experience.photoURL == nil }.map(\.id)
            if await plans.refreshGoogleDetails(experienceIDs: Array(missing.prefix(30))),
               token == generation, let refreshed = try? await plans.suggestedPlaces(in: bounds), token == generation {
                phase = .loaded(refreshed)
            }
        } catch {
            guard token == generation, !(error is CancellationError) else { return }
            phase = .failed(error.roamMessage)
        }
    }

    /// Not interested: the place goes at once, and comes back if the server didn't take it.
    func hide(_ place: DiscoverPlace) async {
        guard let current = phase.value else { return }
        phase = .loaded(current.filter { $0.id != place.id })
        do { try await plans.hideSuggestion(experienceID: place.id, cityID: nil, hidden: true) }
        catch { phase = .loaded(SuggestionOrder.places(current)) }
    }

    func hide(_ city: DiscoverCity) async {
        guard let current = cityPhase.value, let cityID = city.cityID else { return }
        cityPhase = .loaded(current.filter { $0.id != city.id })
        do { try await plans.hideSuggestion(experienceID: nil, cityID: cityID, hidden: true) }
        catch { cityPhase = .loaded(SuggestionOrder.cities(current)) }
    }
}

/// Long-press on a suggestion: Not interested.
struct NotInterestedMenu: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content.contextMenu {
            Button("Not interested", systemImage: "eye.slash", action: action)
                .accessibilityIdentifier("suggestion-not-interested")
        }
    }
}

extension View {
    func notInterested(_ action: @escaping () -> Void) -> some View { modifier(NotInterestedMenu(action: action)) }
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
        // Towns saved on Roam as Day Trips are cities, not places: they show under Cities instead.
        let onRoam = onRoam.filter { $0.category != .dayTrips }
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
    @State private var placeSearch = PlaceSearch()
    @State private var scroll = ScrollPosition(edge: .top)
    @State private var results: LoadPhase<DiscoverResults> = .idle
    @State private var openError: String?
    @State private var barsHidden = false
    @State private var navigationBarHidden = true
    @FocusState private var searchFocused: Bool

    private var hasQuery: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    /// While you're searching, the search bar takes the whole row.
    private var searchActive: Bool { searchFocused || hasQuery }

    private var topBar: some View {
        HStack(spacing: Theme.Spacing.s) {
            // No + here: places are logged from their own card.
            searchField
            if !searchActive {
                // Your profile on the far right, the same on every tab.
                // The same glass circle the system toolbar gives the cog on Friends and My Places.
                ProfileAvatarButton()
                    .frame(width: 44, height: 44)
                    .floatingBubble(Circle())
            }
        }
        .animation(.spring(duration: 0.3), value: searchActive)
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "magnifyingglass").foregroundStyle(Roam.inkMuted).accessibilityHidden(true)
            TextField("Search", text: $query, prompt: Text(searchActive ? "A city, neighbourhood or place" : "Search"))
                // Type as you like: no capitalising or correcting.
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .submitLabel(.search)
                .accessibilityIdentifier("discover-search")
            // The field's own × ends the search: clears it and puts the keyboard away.
            if searchActive {
                Button {
                    query = ""
                    searchFocused = false
                } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Roam.inkMuted) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel search")
                    .accessibilityIdentifier("discover-search-cancel")
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .floatingBubble(Capsule())
    }

    private func roundButton(_ symbol: String, label: String, identifier: String, tint: Color = Roam.ink, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // Same glyph size as the system toolbar's + on Friends and My Places.
            Image(systemName: symbol).font(.system(size: 20, weight: .regular)).foregroundStyle(tint).frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .floatingBubble(Circle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    var body: some View {
        // A ZStack, not a Group: a Group would re-run onAppear when the results list replaces the page on the first
        // typed letter, and the bar toggling there took the keyboard away.
        ZStack {
            if hasQuery {
                // The same search results as My Places.
                ScrollView {
                    PlaceSearchResults(query: query, placeSearch: placeSearch)
                        .padding(.horizontal, Theme.Spacing.l)
                        .padding(.vertical, Theme.Spacing.s)
                }
            } else {
                ScrollView { landing.padding(.horizontal, Theme.Spacing.l).padding(.bottom, Theme.Spacing.xxl) }
                    .solidTopEdge()
                    .scrollPosition($scroll)
                    // Reading down hides the top buttons and search; any move back up brings them back.
                    .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { old, new in
                        let hide = new > 40 && new > old
                        if new <= 40 || new < old - 4 { if barsHidden { withAnimation(.easeOut(duration: 0.2)) { barsHidden = false } } }
                        else if hide && !barsHidden { withAnimation(.easeOut(duration: 0.2)) { barsHidden = true } }
                    }
            }
        }
        .background(Roam.paper)
        .task(id: query) { await placeSearch.run(query, services: services) }
        // Tapping Discover in the tab bar scrolls back to the top, with the search row showing.
        // Opening a result puts the keyboard away, so it doesn't spring back over the results on the way back.
        .onChange(of: router.path(for: .forYou).count) { _, depth in if depth > 0 { searchFocused = false } }
        .onChange(of: router.scrollToTopRequests[.forYou]) { _, _ in
            withAnimation { scroll.scrollTo(edge: .top); barsHidden = false }
        }
        // Leaving the tab puts it back on its home page, with no search.
        .onChange(of: router.selectedTab) { _, tab in
            guard tab != .forYou else { return }
            query = ""; searchFocused = false
        }
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
        .toolbar(navigationBarHidden ? .hidden : .visible, for: .navigationBar)
        // Coming back from a pushed page can leave the system bar showing, empty, over the floating row and
        // swallowing its taps; hiding it again on every return keeps the row tappable.
        .onAppear {
            navigationBarHidden = false
            Task { @MainActor in navigationBarHidden = true }
        }
        .task {
            if model == nil { model = ForYouModel(plans: services.plans) }
            await model?.loadPicks()
            await model?.loadCities(countryCode: nil)
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
            if Score.isShown, let score = experience?.followingScore {
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
            if let model, !model.picks.isEmpty { picksSection(model.picks) }
            switch model?.cityPhase ?? .loading {
            case .idle, .loading:
                SkeletonCards()
            case .failed(let message):
                InlineRetryView(message: message) { Task { await model?.loadCities(countryCode: nil) } }
            case .loaded(let cities):
                citiesSection(cities)
            }
        }
        .padding(.top, Theme.Spacing.s)
    }

    @ViewBuilder private func citiesSection(_ cities: [DiscoverCity]) -> some View {
        if cities.isEmpty {
            // Nothing to go on yet (no friends, nothing rated nearby): say so plainly and offer the way in.
            EmptyStateView(systemImage: "person.2", title: "Nothing to suggest yet",
                           message: "Add friends to see the places they love.",
                           primaryTitle: "Find people", primaryAction: { router.showFindPeople() })
                .accessibilityIdentifier("discover-empty")
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                sectionTitle("Places we think you'd enjoy")
                ForEach(cities) { city in cityCard(city) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("discover-cities")
        }
    }

    private func cityCard(_ city: DiscoverCity) -> some View {
        Button { choose(city.destination) } label: {
            CityCoverCard(city: city, subtitle: cityLine(city))
        }
        .buttonStyle(.plain)
        .notInterested { Task { await model?.hide(city) } }
        .accessibilityIdentifier("discover-city-\(city.destination.name)")
    }

    /// "Portugal · Theo sent you a place here": the country, then why it's suggested.
    private func cityLine(_ city: DiscoverCity) -> String {
        [CountryName.display(city.destination.countryName, code: city.destination.countryCode), city.reason]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
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

    private func choose(_ destination: Destination) {
        destinations.select(destination, for: .search)
        router.push(.city(destination))
        query = ""
        searchFocused = false
    }

    private func search(_ text: String) async {
        services.location.requestAccessIfNeeded()
        results = .loading
        do {
            async let foundDestinations = services.places.searchDestinations(query: text)
            async let foundPlaces = services.places.searchPlaces(query: text, around: nil)
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

/// A city's card, like an upcoming trip's: led by its Google photo, else a photo from a place there.
private struct CityCoverCard: View {
    let city: DiscoverCity
    var subtitle = ""

    @Environment(AppServices.self) private var services
    @State private var photo: AreaPhotos.Photo?
    @State private var looked = false

    var body: some View {
        let destination = city.destination
        Group {
            if let photo {
                HeroPhotoCard(url: photo.url, title: destination.name, subtitle: subtitle, symbol: "signpost.right.and.left",
                              location: destination.coordinate)
            } else {
                HeroPhotoCard(path: looked ? city.coverPath : nil, url: looked ? city.coverURL : nil, title: destination.name,
                              subtitle: subtitle, symbol: "signpost.right.and.left", location: destination.coordinate)
            }
        }
        .task(id: destination.id) {
            photo = await AreaPhotos.city(services, name: destination.name, region: destination.region, country: destination.countryName,
                                          coordinate: destination.coordinate)
            looked = true
        }
    }
}
