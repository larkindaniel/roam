import SwiftUI

struct FriendAreaRows: View {
    let area: FriendVisitArea
    let activity: [FriendAreaActivity]
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Friends who’ve been").font(.roamTitle(.title3)).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(activity) { item in
                    SocialNavigationRow(title: item.member.displayName, symbol: "person", subtitle: subtitle(item), member: item.member) {
                        router.push(.friendAreaVisits(area, item.member))
                    }
                    .accessibilityIdentifier("area-friend-\(item.member.handle)")
                    if item.id != activity.last?.id { RowSeparator() }
                }
            }
            .roamCard(padding: Theme.Spacing.m)
        }
        .screenIdentifier("area-friends")
    }

    private func subtitle(_ item: FriendAreaActivity) -> String {
        if area.cityName != nil {
            return item.placeCount == 1 ? "1 place" : "\(item.placeCount) places"
        }
        let names = item.cities.map(\.name).uniqued()
        let first = Array(names.prefix(2)).formatted(.list(type: .and))
        let remaining = names.count - 2
        return remaining > 0 ? "\(first) · +\(remaining) more" : first
    }
}

struct FriendAreaVisitsView: View {
    let area: FriendVisitArea
    let friend: MemberSummary
    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @State private var activity: LoadPhase<[FriendAreaActivity]> = .idle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Button { router.push(.member(friend.id)) } label: {
                    HStack(spacing: Theme.Spacing.m) {
                        AvatarView(member: friend, size: 48)
                        Text(friend.displayName).font(.headline)
                    }
                    .frame(minHeight: Theme.minimumHitTarget)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens profile")
                switch activity {
                case .idle, .loading:
                    SkeletonList(rows: 3)
                case .failed(let message):
                    InlineRetryView(message: message) { Task { await load() } }
                case .loaded(let rows):
                    if let item = rows.first {
                        if area.cityName == nil { cities(item.cities) }
                        else { places(item.places) }
                    } else {
                        Text("No shared visits here.").font(.subheadline).foregroundStyle(Roam.inkMuted)
                    }
                }
            }
            .padding(Theme.Spacing.l)
        }
        .contentMargins(.bottom, RoamTabBar.reservedHeight, for: .scrollContent)
        .background(Roam.paper)
        .navigationTitle(area.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .screenIdentifier("friend-area-visits")
    }

    private func cities(_ cities: [Destination]) -> some View {
        VStack(spacing: 0) {
            ForEach(cities) { city in
                CityRow(city: city, state: .visited, subtitle: city.region ?? "") {
                    let scope = FriendVisitArea(name: city.name, countryCode: area.countryCode,
                                                regions: area.regions.isEmpty ? [city.region].compactMap { $0 } : area.regions,
                                                cityName: city.name)
                    router.push(.friendAreaVisits(scope, friend))
                }
                if city.id != cities.last?.id { RowSeparator() }
            }
        }
        .roamCard(padding: Theme.Spacing.m)
    }

    private func places(_ places: [ExperienceSummary]) -> some View {
        VStack(spacing: 0) {
            ForEach(places) { place in
                SocialNavigationRow(title: place.name, symbol: "mappin", place: place) {
                    router.push(.friendPlaceVisits(placeID: place.id, placeName: place.name, friend: friend))
                }
                .accessibilityIdentifier("friend-visited-place-\(place.name)")
                if place.id != places.last?.id { RowSeparator() }
            }
        }
        .roamCard(padding: Theme.Spacing.m)
    }

    private func load() async {
        do { activity = .loaded(try await services.plans.friendAreaActivity(in: area, friendID: friend.id)) }
        catch { if !Task.isCancelled { activity = .failed(session.handle(error)) } }
    }
}

struct FriendPlaceVisitsView: View {
    let placeID: UUID
    let placeName: String
    let friend: MemberSummary
    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @State private var model: PublicMemoriesModel?
    @State private var report: ReportTarget?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SocialNavigationRow(title: placeName, symbol: "mappin") { router.push(.experience(placeID)) }
                    .roamCard(padding: Theme.Spacing.m)
                if let model {
                    if let error = model.error {
                        InlineRetryView(message: error) { Task { await model.load() } }
                    } else if !model.hasLoaded {
                        SkeletonList(rows: 2)
                    } else if model.memories.isEmpty {
                        Text("No shared visits here.").font(.subheadline).foregroundStyle(Roam.inkMuted)
                    }
                    ForEach(model.memories) { memory in
                        PublicMemoryCard(memory: memory, onOpenAuthor: { router.push(.member(friend.id)) },
                                         onOpenPhotos: { photoID in
                            router.push(.visitPhoto(experienceID: placeID, visitID: memory.id, photoID: photoID))
                        }, onReport: { report = .visit(memory.id) }, compactNote: false)
                        .roamCard()
                    }
                    PaginationFooter(isLoading: model.loadingMore, errorMessage: model.pageError, hasMore: model.nextCursor != nil) {
                        Task { await model.loadMore() }
                    }
                } else {
                    SkeletonList(rows: 2)
                }
            }
            .padding(Theme.Spacing.l)
        }
        .contentMargins(.bottom, RoamTabBar.reservedHeight, for: .scrollContent)
        .background(Roam.paper)
        .navigationTitle("\(friend.displayName)’s visits")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil { model = PublicMemoriesModel(experienceID: placeID, service: services.memories, friendID: friend.id) }
            await model?.load()
        }
        .refreshable { await model?.load() }
        .onChange(of: model?.authError) { _, error in if let error { _ = session.handle(error) } }
        .sheet(item: $report) { ReportSheet(target: $0) }
        .screenIdentifier("friend-place-visits")
    }
}
