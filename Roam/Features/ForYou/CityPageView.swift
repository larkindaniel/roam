import MapKit
import SwiftUI

/// One city's page, the same from Discover and from My Places: its photo and blurb, the spots you (or the friend whose
/// passport you're in) have been to there, then places we think you'd enjoy. Plan with AI shows only for a city you
/// haven't logged anywhere in yet.
struct CityPageView: View {
    let destination: Destination
    /// Whose spots to show; nil for your own.
    var ownerID: UUID?

    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(DestinationStore.self) private var destinations
    @Environment(LibraryStore.self) private var library
    @State private var model: ForYouModel?
    @State private var spots: [ListEntry] = []
    @State private var mySpotCount = 0
    @State private var loadedSpots = false
    @State private var homes: [Destination] = []

    private var isOwn: Bool { ownerID == nil || ownerID == session.userID }
    /// Home cities can be stored under more than one region spelling, so they match by country and name.
    private var matchingHomes: [Destination] {
        homes.filter { $0.countryCode == destination.countryCode && GeographyKey.normalize($0.name) == GeographyKey.normalize(destination.name) }
    }
    private var isHome: Bool { !matchingHomes.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                CityHeader(destination: destination, isHome: isOwn && isHome, showsPlanWithAI: loadedSpots && mySpotCount == 0,
                           onToggleHome: isOwn && loadedSpots ? { Task { await setHome(!isHome) } } : nil)
                CityGuideCard(name: destination.name, region: destination.region, country: destination.countryName,
                              coordinate: destination.coordinate, showsPhoto: false)
                if !spots.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                        sectionTitle(isOwn ? "Your spots" : "Their spots")
                        LazyVStack(spacing: Theme.Spacing.l) {
                            ForEach(spots) { entry in
                                DiscoverPlaceCard(experience: entry.experience, score: entry.ownerScore) { router.push(.experience(entry.id)) }
                            }
                        }
                    }
                }
                recommendations
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .background(Roam.paper)
        .navigationTitle(destination.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // The map opens on this city.
                Button {
                    destinations.select(destination, for: .explore)
                    router.openExplore()
                } label: { Image(systemName: "map") }
                    .accessibilityLabel("Map of \(destination.name)")
                    .accessibilityIdentifier("city-open-map")
            }
        }
        .task(id: destination.id) {
            async let mine = loadSpots(of: session.userID)
            async let theirs = isOwn ? [] : loadSpots(of: ownerID)
            let own = await mine
            mySpotCount = own.count
            spots = isOwn ? own : await theirs
            loadedSpots = true
            if isOwn { homes = (try? await services.plans.homeCities()) ?? [] }
            if model == nil { model = ForYouModel(plans: services.plans) }
            await model?.load(destination)
        }
        .screenIdentifier("city-page")
    }

    /// Places others loved that aren't already among the spots above.
    @ViewBuilder private var recommendations: some View {
        switch model?.phase ?? .loading {
        case .idle, .loading:
            SkeletonList(rows: 3)
        case .failed(let message):
            InlineRetryView(message: message) { Task { await model?.load(destination) } }
        case .loaded(let sections):
            let shown = Set(spots.map(\.id))
            let places = (sections.friends + sections.highlyRated + sections.more).uniqued { $0.id }.filter { !shown.contains($0.id) }
            if !places.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    sectionTitle("Places we think you'd enjoy")
                    // Lazy, so only the cards on screen build their maps.
                    LazyVStack(spacing: Theme.Spacing.l) {
                        ForEach(places) { place in
                            DiscoverPlaceCard(experience: place.experience, path: place.coverPath, evidence: place.friendEvidence,
                                              score: (place.friendEvidence != nil ? place.experience.followingScore : nil) ?? place.communityScore) {
                                router.push(.experience(place.id))
                            }
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("discover-places")
            }
        }
    }

    private func setHome(_ present: Bool) async {
        if present {
            homes = (try? await services.plans.setHomeCity(destination, present: true)) ?? homes
        } else {
            for stored in matchingHomes { homes = (try? await services.plans.setHomeCity(stored, present: false)) ?? homes }
        }
        // My Places reloads its home cities.
        library.noteChanged()
    }

    private func loadSpots(of owner: UUID?) async -> [ListEntry] {
        guard let owner, let been = try? await services.lists.been(ownerID: owner) else { return [] }
        return been.filter { CityMatch.same($0.experience, destination) }
            .sorted { ($0.ownerScore?.tenths ?? -1) > ($1.ownerScore?.tenths ?? -1) }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.roamTitle()).foregroundStyle(Roam.ink).accessibilityAddTraits(.isHeader)
    }
}

/// A place's card: its photo, or a map of where it is when there's none, then who's been and the score.
struct DiscoverPlaceCard: View {
    let experience: ExperienceSummary
    var path: String?
    var evidence: String?
    var score: Score?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PhotoCard(path: path, url: experience.photoURL, credit: experience.photoCredit,
                      label: "Photo of \(experience.name)", placeholderSymbol: experience.category?.symbolName ?? "mappin",
                      height: 190, location: experience.coordinate) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(experience.name).font(.headline).foregroundStyle(Roam.ink).lineLimit(2).multilineTextAlignment(.leading)
                        Text([experience.category?.title, experience.locality].compactMap { $0 }.joined(separator: " · "))
                            .font(.footnote).foregroundStyle(Roam.inkMuted).lineLimit(1)
                        if let evidence { Text(evidence).font(.subheadline).foregroundStyle(Roam.ink).lineLimit(1) }
                        GoogleRatingLine(experience: experience)
                    }
                    Spacer(minLength: Theme.Spacing.s)
                    if let score {
                        Text(score.formatted).font(.system(.title3, design: .rounded).bold()).monospacedDigit().foregroundStyle(Roam.ink)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("foryou-place-\(experience.name)")
    }
}

/// A city's card for a list of cities: its Wikipedia photo with the name underneath.
struct CityPhotoCard: View {
    let destination: Destination
    var isHome = false

    @State private var guide: CityGuide?

    var body: some View {
        PhotoCard(url: guide?.photoURL, label: "Photo of \(destination.name)",
                  placeholderSymbol: "building.2", height: 160, location: destination.coordinate) {
            // The credit sits snug under the name.
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Theme.Spacing.s) {
                    if isHome { Image(systemName: "house.fill").foregroundStyle(PlaceState.visited.markerColor).accessibilityLabel("Home") }
                    Text(destination.name).font(.roamTitle()).foregroundStyle(Roam.ink)
                    Spacer(minLength: 0)
                }
                if guide?.photoURL != nil { Text("Photo: Wikipedia").font(.caption2).foregroundStyle(Roam.inkMuted) }
            }
        }
        .task(id: destination.id) {
            guide = await CityGuide.load(name: destination.name, region: destination.region, country: destination.countryName,
                                         coordinate: destination.coordinate)
        }
    }
}

/// The city heads its page: name and where it is, Plan with AI when you haven't been, then its Wikipedia photo.
struct CityHeader: View {
    let destination: Destination
    var isHome = false
    var showsPlanWithAI = true
    /// Set (or unset) the city as home; nil when it isn't yours to change. Anywhere within 100 km of a home city counts
    /// as home and stays off your travel timeline.
    var onToggleHome: (() -> Void)?

    @Environment(AppRouter.self) private var router
    @State private var guide: CityGuide?

    private var title: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Spacing.s) {
                Text(destination.name).font(.roamDisplay(.title)).lineLimit(1).fixedSize().accessibilityAddTraits(.isHeader)
                if isHome {
                    Image(systemName: "house.fill").font(.title3).foregroundStyle(PlaceState.visited.markerColor).accessibilityLabel("Home")
                }
            }
            if !destination.subtitle.isEmpty {
                Text(destination.subtitle).font(.subheadline).foregroundStyle(Roam.inkMuted)
            }
        }
    }

    @ViewBuilder private var actions: some View {
        if showsPlanWithAI || onToggleHome != nil {
            HStack(spacing: Theme.Spacing.s) {
                if let onToggleHome {
                    Button(action: onToggleHome) {
                        Label(isHome ? "Home" : "Set as home", systemImage: isHome ? "house.fill" : "house")
                    }
                    .buttonStyle(PillButtonStyle(tint: PlaceState.visited.markerColor))
                    .accessibilityHint(isHome ? "Removes it as a home city" : "Makes it a home city")
                    .accessibilityIdentifier("city-toggle-home")
                }
                if showsPlanWithAI {
                    Button { router.sheet = .researchBrief(destination) } label: {
                        Label("Plan with AI", systemImage: "sparkles")
                    }
                    .buttonStyle(PillButtonStyle(tint: PlaceState.planned.markerColor))
                    .accessibilityIdentifier("foryou-research-open")
                }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            // The actions sit level with the name (home on the left, Plan with AI on the right); a long name pushes
            // them onto their own row.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: Theme.Spacing.s) {
                    title
                    Spacer(minLength: Theme.Spacing.s)
                    actions
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    title
                    actions
                }
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
