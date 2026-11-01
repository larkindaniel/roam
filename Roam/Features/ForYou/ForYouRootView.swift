import Observation
import SwiftUI

/// Discover's two lists. A place sits in one list, and a place no friend rated is never shown as a friend's find.
struct ForYouSections: Equatable {
    /// The score a place needs to count as highly rated.
    static let highlyRated = Score(tenths: 70)

    var friends: [DiscoverPlace] = []
    var highlyRated: [DiscoverPlace] = []

    init(places: [DiscoverPlace] = []) {
        let unvisited = places.filter { $0.experience.viewer.myScore == nil }
        friends = unvisited.filter { !$0.friendNames.isEmpty }.sorted(by: Self.order)
        highlyRated = unvisited.filter { $0.friendNames.isEmpty && $0.communityScore >= Self.highlyRated }.sorted(by: Self.order)
    }

    private static func order(_ lhs: DiscoverPlace, _ rhs: DiscoverPlace) -> Bool {
        lhs.communityScore == rhs.communityScore ? lhs.experience.name < rhs.experience.name : lhs.communityScore > rhs.communityScore
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
    var places: [SearchHit] = []

    var isEmpty: Bool { destinations.isEmpty && places.isEmpty }

    /// Towns come back from both searches, so place results keep only points of interest.
    init(destinations: [Destination] = [], candidates: [PlaceCandidate] = [], matches: [String: ExperienceSummary] = [:]) {
        self.destinations = destinations
        places = candidates.filter { !$0.isLocality }.map { SearchHit(candidate: $0, experience: matches[$0.id]) }
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
    @State private var isSearching = false
    @State private var results: LoadPhase<DiscoverResults> = .idle
    @State private var openError: String?
    @State private var selected: Destination?

    private var hasQuery: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        Group {
            if hasQuery {
                List { searchResults }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
            } else {
                ScrollView { landing.padding(.horizontal, Theme.Spacing.l).padding(.bottom, Theme.Spacing.xxl) }
            }
        }
        .background(Roam.paper)
        .searchable(text: $query, isPresented: $isSearching, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search cities or places")
        .navigationTitle("Discover")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { ProfileAvatarButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.openExplore() } label: { Image(systemName: "map") }
                    .accessibilityLabel("Explore the map")
                    .accessibilityIdentifier("open-explore")
            }
            LogPlaceToolbarFallback()
        }
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
            if !found.places.isEmpty {
                Section("Places") {
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
            HStack(spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.candidate.name).font(.headline).foregroundStyle(Roam.ink)
                    Text([hit.category?.title, hit.candidate.locality, hit.candidate.countryName].compactMap { $0 }.uniqued().joined(separator: " · "))
                        .font(.footnote).foregroundStyle(Roam.inkMuted)
                    if let count = hit.experience?.followingCount, count > 0 {
                        Text("\(count) \(count == 1 ? "friend" : "friends") rated this").font(.subheadline).foregroundStyle(Roam.ink)
                    }
                }
                Spacer(minLength: Theme.Spacing.s)
                if let score = hit.experience?.followingScore {
                    Text(score.formatted).font(.system(.body, design: .rounded).bold()).monospacedDigit().foregroundStyle(Roam.ink)
                }
            }
            .frame(minHeight: Theme.minimumHitTarget)
        }
        .accessibilityIdentifier("discover-place-\(hit.candidate.name)")
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
            if let selected { selectedChip(selected) }
            if let model, !model.picks.isEmpty { picksSection(model.picks) }
            switch model?.phase ?? .loading {
            case .idle, .loading:
                SkeletonList(rows: 3)
            case .failed(let message):
                InlineRetryView(message: message) { Task { await model?.load(selected) } }
            case .loaded where selected == nil:
                citiesSection(model?.cities ?? [])
            case .loaded(let sections):
                if !sections.friends.isEmpty { friendsSection(sections.friends) }
                if !sections.highlyRated.isEmpty { highlyRatedSection(sections.highlyRated) }
                if sections.friends.isEmpty && sections.highlyRated.isEmpty {
                    Text(selected.map { "Nobody has rated a place in \($0.name) yet." } ?? "")
                        .font(.subheadline).foregroundStyle(Roam.inkMuted)
                        .accessibilityIdentifier("discover-empty")
                }
                if let selected, sections.friends.count + sections.highlyRated.count < 3 { researchLink(selected) }
            }
        }
        .padding(.top, Theme.Spacing.s)
    }

    @ViewBuilder private func citiesSection(_ cities: [DiscoverCity]) -> some View {
        if cities.isEmpty {
            Text("Search for a city or a place to get started.")
                .font(.subheadline).foregroundStyle(Roam.inkMuted)
                .accessibilityIdentifier("discover-empty")
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                sectionTitle("Cities to explore")
                ForEach(cities) { city in cityCard(city) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("discover-cities")
        }
    }

    private func cityCard(_ city: DiscoverCity) -> some View {
        Button { choose(city.destination) } label: {
            PhotoCard(path: city.coverPath, url: city.coverURL, credit: city.coverCredit,
                      label: "Photo from \(city.destination.name)", height: 180) {
                Text(city.destination.name).font(.roamTitle()).foregroundStyle(Roam.ink)
                Text(cityLine(city)).font(.footnote).foregroundStyle(Roam.inkMuted).lineLimit(2).multilineTextAlignment(.leading)
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

    private func selectedChip(_ destination: Destination) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(destination.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
            Button { selected = nil } label: {
                Image(systemName: "xmark").font(.caption.weight(.bold)).frame(width: 28, height: 28)
            }
            .accessibilityLabel("Clear \(destination.name)")
            .accessibilityIdentifier("discover-clear")
        }
        .foregroundStyle(Roam.ink)
        .padding(.leading, Theme.Spacing.m)
        .padding(.trailing, Theme.Spacing.xs)
        .frame(minHeight: Theme.minimumHitTarget)
        .background(Capsule().fill(Roam.fill))
        .accessibilityIdentifier("discover-selected")
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

    private func friendsSection(_ places: [DiscoverPlace]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            sectionTitle("From your friends")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Theme.Spacing.m) {
                    ForEach(places) { place in
                        placeCard(place, evidence: place.friendEvidence, photoHeight: 150).frame(width: 250)
                    }
                }
            }
            .scrollClipDisabled()
            .accessibilityIdentifier("discover-friends")
        }
    }

    private func highlyRatedSection(_ places: [DiscoverPlace]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            sectionTitle(selected.map { "Highly rated in \($0.name)" } ?? "Highly rated")
            ForEach(places) { place in
                placeCard(place, evidence: nil, photoHeight: 200)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("discover-highly-rated")
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.roamTitle()).foregroundStyle(Roam.ink).accessibilityAddTraits(.isHeader)
    }

    private func placeCard(_ place: DiscoverPlace, evidence: String?, photoHeight: CGFloat) -> some View {
        Button { router.push(.experience(place.id)) } label: {
            PhotoCard(path: place.coverPath, url: place.experience.photoURL, credit: place.experience.photoCredit,
                      label: "Photo of \(place.experience.name)", placeholderSymbol: place.experience.category?.symbolName ?? "mappin", height: photoHeight) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.experience.name).font(.headline).foregroundStyle(Roam.ink).lineLimit(2).multilineTextAlignment(.leading)
                        Text([place.experience.category?.title, place.experience.locality].compactMap { $0 }.joined(separator: " · "))
                            .font(.footnote).foregroundStyle(Roam.inkMuted).lineLimit(1)
                        if let evidence { Text(evidence).font(.subheadline).foregroundStyle(Roam.ink).lineLimit(1) }
                    }
                    Spacer(minLength: Theme.Spacing.s)
                    Text((evidence != nil ? place.experience.followingScore : nil)?.formatted ?? place.communityScore.formatted)
                        .font(.system(.title3, design: .rounded).bold()).monospacedDigit().foregroundStyle(Roam.ink)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("foryou-place-\(place.experience.name)")
    }

    private func researchLink(_ destination: Destination) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Not much here yet. Want suggestions from an AI assistant?").font(.subheadline).foregroundStyle(Roam.inkMuted)
            Button("Copy a brief for ChatGPT or Claude") { router.sheet = .researchBrief(destination) }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .accessibilityIdentifier("foryou-research-open")
        }
    }

    private func choose(_ destination: Destination) {
        selected = destination
        destinations.select(destination, for: .search)
        query = ""
        isSearching = false
    }

    private func search(_ text: String) async {
        results = .loading
        do {
            async let foundDestinations = services.places.searchDestinations(query: text)
            async let foundPlaces = services.places.searchPlaces(query: text, around: selected)
            let (destinationList, candidates) = try await (foundDestinations, foundPlaces)
            let matches = (try? await services.experiences.matches(for: candidates)) ?? [:]
            guard !Task.isCancelled, text == query else { return }
            let found = DiscoverResults(destinations: destinationList, candidates: candidates, matches: matches)
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
