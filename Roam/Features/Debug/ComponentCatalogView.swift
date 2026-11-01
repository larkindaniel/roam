#if ROAM_FIXTURES
import SwiftUI

/// Debug-only catalogue of design-system components and states (launch with
/// `-roam-component-catalog`). Used for Dynamic Type/VoiceOver evidence; not reachable in the app UI.
struct ComponentCatalogView: View {
    @State private var showsMap = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let sample = ExperienceSummary(
        id: UUID(), placeID: UUID(), name: "Harbor Lantern Café", category: .foodDrink, locality: "Lisbon", region: "Lisboa",
        countryCode: "PT", countryName: "Portugal", latitude: 38.7, longitude: -9.1, providerPlaceID: nil,
        followingScore: Score(tenths: 75), followingCount: 2,
        viewer: ViewerExperienceState(isBookmarked: false, myRatingCategory: nil, myScore: nil, myRank: nil, hasVisits: false))

    @ViewBuilder private var badgeSamples: some View {
        ScoreBadge(score: Score(tenths: 84), source: .you)
        ScoreBadge(score: Score(tenths: 50), source: .following(count: 3))
        ScoreBadge(score: Score(tenths: 17), source: .owner(name: "Maya"))
        ScoreBadge(score: nil, source: .you)
        ScoreBadge(score: nil, source: .following(count: 0))
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Motion") {
                    // Skeleton pulses and map camera moves are skipped when this is on.
                    Text(reduceMotion ? "Reduce Motion: on" : "Reduce Motion: off")
                        .accessibilityIdentifier("catalog-reduce-motion")
                }
                Section("Score badges") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), alignment: .top)], spacing: Theme.Spacing.m) { badgeSamples }
                }
                Section("Sentiment") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], alignment: .leading) {
                        ForEach(Sentiment.allCases) { SentimentTag(sentiment: $0) }
                    }
                }
                Section("Experience rows") {
                    ExperienceRow(name: "Harbor Lantern Café", category: .foodDrink, area: "Lisbon, Portugal", rank: 1,
                                  score: Score(tenths: 100), scoreSource: .you, statusLine: "Visited Jun 14, 2026",
                                  saveState: .alreadyBeen, logTitle: "Add visit", onOpen: {}, onSave: {}, onLog: {})
                    ExperienceRow(name: "Cedar Ridge Trail", category: .outdoors, area: "Banff, Canada", score: nil,
                                  scoreSource: .you, secondaryScore: Score(tenths: 84), secondarySource: .following(count: 1),
                                  saveState: .notSaved, logTitle: "Log", onOpen: {}, onSave: {}, onLog: {})
                    ExperienceRow(name: "Glass Lagoon Baths", category: .activities, area: "Reykjavík, Iceland", score: nil,
                                  scoreSource: .you, statusLine: "Saving…", saveState: .pending(target: true), logTitle: "Log",
                                  onOpen: {}, onSave: {}, onLog: {})
                    ExperienceRow(name: "Lumen Street Hawker Hall", category: nil, area: "Singapore", score: nil, scoreSource: .you,
                                  statusLine: "Unranked memory", saveState: .saved, logTitle: "Log", onOpen: {}, onSave: {}, onLog: {})
                }
                Section("Members") {
                    MemberRowView(member: MemberSummary(id: UUID(), handle: "mayaroams", displayName: "Maya Chen", avatarPath: nil),
                                  followState: .friends)
                    MemberRowView(member: MemberSummary(id: UUID(), handle: "theowanders", displayName: "Theo Park", avatarPath: nil),
                                  followState: .accept)
                    MemberRowView(member: MemberSummary(id: UUID(), handle: "priyaplans", displayName: "Priya Nair", avatarPath: nil),
                                  followState: .pending)
                }
                Section("States") {
                    SkeletonList(rows: 2)
                    InlineRetryView(message: "Couldn't load your list. Your filters are kept.") {}
                    EmptyStateView(systemImage: "bookmark", title: "No saved experiences", message: "Save places you want to go.",
                                   primaryTitle: "Explore", primaryAction: {})
                    PaginationFooter(isLoading: false, errorMessage: "Couldn't load more.", hasMore: true) {}
                }
                Section("Map card and toggle") {
                    SelectedPlaceCard(summary: sample, onOpen: {}, onSave: {}, onLog: {}, saveState: .notSaved, onClose: {})
                    MapListToggle(showsMap: $showsMap)
                    RemoteImageView(path: nil).frame(height: 80)
                }
            }
            .navigationTitle("Components")
        }
        .screenIdentifier("component-catalog")
    }
}
#endif
