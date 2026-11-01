import Observation
import SwiftUI

/// Places in a destination split by source. A place sits in one section, and a place with no
/// friend ratings is never presented as a friend's find.
struct ForYouSections: Equatable {
    var friends: [ExperienceSummary] = []
    var community: [ExperienceSummary] = []

    init(experiences: [ExperienceSummary] = []) {
        let unvisited = experiences.filter { $0.viewer.myScore == nil }
        friends = unvisited.filter { $0.followingCount > 0 }.sorted { lhs, rhs in
            let left = lhs.followingScore?.tenths ?? 0
            let right = rhs.followingScore?.tenths ?? 0
            return left == right ? lhs.name < rhs.name : left > right
        }
        community = unvisited.filter { $0.followingCount == 0 }.sorted { $0.name < $1.name }
    }
}

@MainActor
@Observable
final class ForYouModel {
    private(set) var phase: LoadPhase<ForYouSections> = .idle
    private(set) var picks: [DirectShare] = []
    private(set) var needsTaste = false
    private let experiences: any ExperienceService
    private let plans: any PlanService
    private var generation = 0

    init(experiences: any ExperienceService, plans: any PlanService) {
        self.experiences = experiences
        self.plans = plans
    }

    /// Picks aren't tied to a destination, so they show even before one is chosen.
    func loadPicks() async {
        if let shares = try? await plans.sharedWithMe() { picks = shares }
        if let taste = try? await plans.taste() { needsTaste = taste == .empty }
    }

    func load(_ destination: Destination) async {
        generation += 1
        let token = generation
        if phase.value == nil { phase = .loading }
        do {
            let bounds = GeoBounds(region: .init(center: destination.coordinate,
                                                 latitudinalMeters: destination.radiusMeters * 2,
                                                 longitudinalMeters: destination.radiusMeters * 2))
            let found = try await experiences.experiences(in: bounds, category: nil)
            guard token == generation, !Task.isCancelled else { return }
            phase = .loaded(ForYouSections(experiences: found))
        } catch {
            guard token == generation, !(error is CancellationError) else { return }
            phase = .failed(error.roamMessage)
        }
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
    @State private var results: LoadPhase<[Destination]> = .idle
    @State private var selected: Destination?

    private var hasQuery: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        List {
            if hasQuery {
                searchResults
            } else {
                if let selected {
                    selectedRow(selected)
                } else {
                    Section {
                        Text("Search for a city or town to see what your friends found there.")
                            .font(.subheadline).foregroundStyle(Roam.inkMuted)
                            .accessibilityIdentifier("discover-start")
                    }
                    .listRowBackground(Roam.paperRaised)
                }
                if let model, !model.picks.isEmpty { picksSection(model.picks) }
                if model?.needsTaste == true {
                    Section {
                        Button("Tell Roam what you like") { router.push(.taste) }
                            .accessibilityIdentifier("foryou-set-taste")
                    }
                    .listRowBackground(Roam.paperRaised)
                }
                if let destination = selected, let model {
                    switch model.phase {
                    case .idle, .loading:
                        Section { SkeletonList(rows: 3) }
                    case .failed(let message):
                        Section {
                            InlineRetryView(message: message) { Task { await model.load(destination) } }
                        }
                    case .loaded(let sections):
                        friendsSection(sections.friends, destination: destination)
                        communitySection(sections.community, destination: destination)
                    }
                    researchSection(destination)
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, isPresented: $isSearching, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search for a place")
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
            if model == nil { model = ForYouModel(experiences: services.experiences, plans: services.plans) }
            await model?.loadPicks()
            if let selected { await model?.load(selected) }
        }
        .screenIdentifier("foryou-root")
    }

    @ViewBuilder private var searchResults: some View {
        Section {
            switch results {
            case .idle, .loading:
                HStack { ProgressView(); Text("Searching…").foregroundStyle(Roam.inkMuted) }
            case .failed(let message):
                InlineRetryView(message: message) { Task { await search(query) } }
            case .loaded(let found) where found.isEmpty:
                Text("No places match \u{201C}\(query)\u{201D}.").foregroundStyle(Roam.inkMuted)
                    .accessibilityIdentifier("discover-no-results")
            case .loaded(let found):
                ForEach(found) { destination in
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
        }
        .listRowBackground(Roam.paperRaised)
    }

    private func selectedRow(_ destination: Destination) -> some View {
        Section {
            HStack {
                Text(destination.displayName).font(.headline).foregroundStyle(Roam.ink)
                Spacer(minLength: Theme.Spacing.s)
                Button { selected = nil } label: { Image(systemName: "xmark").font(.footnote.weight(.semibold)) }
                    .buttonStyle(.borderless)
                    .frame(minWidth: Theme.minimumHitTarget, minHeight: Theme.minimumHitTarget)
                    .accessibilityLabel("Clear \(destination.name)")
                    .accessibilityIdentifier("discover-clear")
            }
            .accessibilityIdentifier("discover-selected")
        }
        .listRowBackground(Roam.paperRaised)
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
            let found = try await services.places.searchDestinations(query: text)
            guard !Task.isCancelled, text == query else { return }
            results = .loaded(found)
        } catch is CancellationError {
        } catch {
            guard text == query else { return }
            results = .failed(error.roamMessage)
        }
    }

    private func picksSection(_ picks: [DirectShare]) -> some View {
        Section {
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
                .padding(.vertical, Theme.Spacing.xs)
            }
        } header: { SourceLabel(source: .picked).textCase(nil) }
        .listRowBackground(Roam.paperRaised)
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

    private func friendsSection(_ places: [ExperienceSummary], destination: Destination) -> some View {
        Section {
            if places.isEmpty {
                Text("None of your friends have been to \(destination.name) yet.")
                    .font(.subheadline).foregroundStyle(Roam.inkMuted)
                    .accessibilityIdentifier("foryou-friends-empty")
            }
            ForEach(places) { place in
                row(place, evidence: "\(place.followingCount) \(place.followingCount == 1 ? "friend" : "friends") rated this", score: place.followingScore)
            }
        } header: { SourceLabel(source: .friends).textCase(nil) }
        .listRowBackground(Roam.paperRaised)
        .listRowSeparatorTint(Roam.rule)
    }

    private func communitySection(_ places: [ExperienceSummary], destination: Destination) -> some View {
        Section {
            if places.isEmpty {
                Text("Nobody has shared a place in \(destination.name) yet.")
                    .font(.subheadline).foregroundStyle(Roam.inkMuted)
                    .accessibilityIdentifier("foryou-community-empty")
            }
            ForEach(places) { place in row(place, evidence: nil, score: nil) }
        } header: { SourceLabel(source: .community).textCase(nil) }
        .listRowBackground(Roam.paperRaised)
        .listRowSeparatorTint(Roam.rule)
    }

    private func researchSection(_ destination: Destination) -> some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SourceLabel(source: .research)
                Text("Not enough here yet? Take a brief to ChatGPT or Claude.")
                    .font(.subheadline).foregroundStyle(Roam.inkMuted)
                Button("Copy research brief") { router.sheet = .researchBrief(destination) }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .accessibilityIdentifier("foryou-research-open")
            }
            .padding(.vertical, Theme.Spacing.xs)
            .accessibilityIdentifier("foryou-research")
        }
        .listRowBackground(Roam.paperRaised)
    }

    private func row(_ place: ExperienceSummary, evidence: String?, score: Score?) -> some View {
        Button { router.push(.experience(place.id)) } label: {
            HStack(spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name).font(.headline).foregroundStyle(Roam.ink)
                    Text([place.category?.title, place.areaLine].compactMap { $0 }.joined(separator: " · "))
                        .font(.footnote).foregroundStyle(Roam.inkMuted)
                    if let evidence { Text(evidence).font(.subheadline).foregroundStyle(Roam.ink) }
                }
                Spacer(minLength: Theme.Spacing.s)
                if let score {
                    Text(score.formatted).font(.system(.body, design: .rounded).bold()).monospacedDigit().foregroundStyle(Roam.ink)
                }
            }
            .frame(minHeight: Theme.minimumHitTarget)
        }
        .accessibilityIdentifier("foryou-place-\(place.id.uuidString)")
    }
}
