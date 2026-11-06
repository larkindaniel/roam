import SwiftUI

/// The Friends tab: one card per person and country, newest update first.
struct FeedRootView: View {
    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(ActivityChangeStore.self) private var changes
    @State private var cards: LoadPhase<[FriendFeedGroup]> = .idle
    @State private var unreadCount = 0
    @State private var scroll = ScrollPosition(edge: .top)

    var body: some View {
        ScrollView { content.padding(.horizontal, Theme.Spacing.l).padding(.vertical, Theme.Spacing.m) }
            .scrollPosition($scroll)
            // Tapping Friends in the tab bar scrolls back to the top.
            .onChange(of: router.scrollToTopRequests[.friends]) { _, _ in withAnimation { scroll.scrollTo(edge: .top) } }
            .background(Roam.paper)
            .navigationTitle("Friends")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let me = session.userID { router.push(.followGraph(me, .friends)) }
                    } label: { Image(systemName: "person.badge.plus") }
                    .accessibilityLabel("Friends and requests")
                    .accessibilityIdentifier("open-friends")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { router.push(.notifications) } label: {
                        Image(systemName: unreadCount > 0 ? "bell.badge.fill" : "bell").symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel(unreadCount > 0 ? "Notifications, \(unreadCount) unread" : "Notifications")
                    .accessibilityIdentifier("open-notifications")
                }
                SettingsToolbarItem()
            }
            .navigationBarTitleDisplayMode(.large)
            .task { await load() }
            .refreshable { await load() }
            .onChange(of: changes.revision) { _, _ in Task { await load() } }
            .screenIdentifier("feed-root")
    }

    @ViewBuilder private var content: some View {
        switch cards {
        case .idle, .loading:
            SkeletonList(rows: 4).accessibilityIdentifier("feed-loading")
        case .failed(let message):
            EmptyStateView(systemImage: "wifi.exclamationmark", title: "Couldn't load your friends' places", message: message,
                           primaryTitle: "Try again", primaryAction: { Task { await load() } })
        case .loaded(let value) where value.isEmpty:
            EmptyStateView(systemImage: "person.2", title: "Nothing from friends yet",
                           message: "Add friends to follow their places here.",
                           primaryTitle: "Find people", primaryAction: { router.showFindPeople() })
                .accessibilityIdentifier("feed-empty")
        case .loaded(let value):
            LazyVStack(spacing: Theme.Spacing.l) {
                ForEach(value) { group in
                    FriendGroupCard(group: group) { router.push(.friendGroup(group)) }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("feed-list")
        }
    }

    private func load() async {
        if cards.value == nil { cards = .loading }
        do {
            // A trip, a city or a country per card, newest first by when they were there (not when they posted).
            cards = .loaded(FriendFeedGrouping.groups(try await services.plans.friendsFeed()))
        } catch {
            if cards.value == nil { cards = .failed(session.handle(error)) }
        }
        if let count = try? await services.notifications.unreadCount() { unreadCount = count }
    }
}

/// A friend's trip, city or country: their name and when, what it is, then their three best-ranked places as rows with
/// their stars at the right.
struct FriendGroupCard: View {
    let group: FriendFeedGroup
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(spacing: Theme.Spacing.s) {
                    AvatarView(member: group.author, size: 36)
                    VStack(alignment: .leading, spacing: -2) {
                        Text(group.author.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(Roam.ink)
                        if let dates = MyTimeline.range(group.firstVisit, group.lastVisit) {
                            Text(dates).font(.caption).foregroundStyle(Roam.inkMuted)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Roam.inkMuted)
                }
                FriendGroupTitle(kind: group.kind)
                let rows = group.preview
                VStack(spacing: 0) {
                    ForEach(rows) { entry in
                        FriendPlaceRow(entry: entry)
                        if entry.id != rows.last?.id { RowSeparator() }
                    }
                }
                let more = group.places.count - rows.count
                if more > 0 {
                    Text("+ \(more) more").font(.footnote.weight(.semibold)).foregroundStyle(Roam.inkMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .roamCard(padding: Theme.Spacing.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("friend-group-\(group.author.handle)-\(group.id)")
    }

}

/// A place a friend went: its photo, its name, and their stars at the right.
struct FriendPlaceRow: View {
    let entry: TripFeedEntry

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            PlaceThumbnail(id: "feed-\(entry.id)", path: entry.media.sorted { $0.position < $1.position }.first?.path,
                           url: entry.experience.photoURL, coordinate: entry.experience.coordinate, symbol: entry.experience.iconName, size: 48)
            Text(entry.experience.name).font(.headline).foregroundStyle(Roam.ink).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
            if let score = entry.score { FriendStars(score: score) }
        }
        .padding(.vertical, Theme.Spacing.s)
        .contentShape(Rectangle())
    }
}

/// What a friend's card is about: a trip's name, a country with its flag, or a city with its country and flag small
/// under it.
struct FriendGroupTitle: View {
    let kind: FriendFeedGroup.Kind

    var body: some View {
        switch kind {
        case .trip(let name):
            Text(name).font(.roamTitle()).foregroundStyle(Roam.ink).lineLimit(2)
        case .country(let code, let name):
            Text(country(code, name)).font(.roamTitle()).foregroundStyle(Roam.ink).lineLimit(1)
        case .city(let name, let code, let countryName):
            VStack(alignment: .leading, spacing: -2) {
                Text(name).font(.roamTitle()).foregroundStyle(Roam.ink).lineLimit(1)
                Text(country(code, countryName)).font(.footnote).foregroundStyle(Roam.inkMuted).lineLimit(1)
            }
        }
    }

    private func country(_ code: String?, _ name: String?) -> String {
        [TripTitle.flag(code), name ?? code ?? "Somewhere"].compactMap { $0 }.joined(separator: " ")
    }
}

/// A friend's stars for a place, out of 5.
struct FriendStars: View {
    let score: Score
    var color: Color = Roam.ink

    var body: some View {
        Label(score.formatted, systemImage: "star.fill")
            .labelStyle(.titleAndIcon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
            .accessibilityLabel("Rated \(score.formatted) out of 5")
    }
}

/// All of a friend's places on a trip, in a city or in a country, laid out like a trip's page: each city a white card
/// with its photo big on top and the places they went there as rows under it, their stars at the right.
struct FriendGroupView: View {
    let group: FriendFeedGroup

    @Environment(AppRouter.self) private var router
    /// The tight margin round a city's photo in its card, as on a trip's page.
    private let margin: CGFloat = 6

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Text([group.author.displayName, MyTimeline.range(group.firstVisit, group.lastVisit)].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(Roam.inkMuted)
                ForEach(group.cities, id: \.name) { city in cityCard(city) }
            }
            .padding(Theme.Spacing.l)
        }
        .background(Roam.paper)
        .navigationTitle(title)
        .screenIdentifier("friend-group")
    }

    private var title: String {
        switch group.kind {
        case .trip(let name): return name
        case .city(let name, _, _): return name
        case .country(let code, let name): return [TripTitle.flag(code), name ?? code].compactMap { $0 }.joined(separator: " ")
        }
    }

    private func cityCard(_ city: (name: String, countryCode: String?, countryName: String?, places: [TripFeedEntry])) -> some View {
        let first = city.places.first?.experience
        let destination = Destination(name: city.name, region: first?.region, countryCode: city.countryCode, countryName: city.countryName,
                                      latitude: first?.latitude ?? 0, longitude: first?.longitude ?? 0, radiusMeters: 15_000)
        return VStack(spacing: 0) {
            Button { router.push(.city(destination, ownerID: nil)) } label: {
                CityHeroCard(city: destination, subtitle: [TripTitle.flag(city.countryCode), city.countryName].compactMap { $0 }.joined(separator: " "),
                             cornerRadius: Theme.cornerRadius - margin)
            }
            .buttonStyle(.plain)
            .padding(margin)
            .accessibilityIdentifier("friend-group-city-\(city.name)")
            VStack(spacing: 0) {
                ForEach(city.places) { entry in
                    Button { router.push(.experience(entry.experience.id)) } label: { FriendPlaceRow(entry: entry) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("friend-group-place-\(entry.experience.name)")
                    if entry.id != city.places.last?.id { RowSeparator() }
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.s)
        }
        .roamCard(padding: 0)
    }
}

/// A feed post: author, action, place, score when posted, visit date, note/photos, likes,
/// comments and the viewer's own Save/Log actions for the place.
struct FeedCard: View {
    let item: ActivityItem
    var likePending = false
    let onLike: (Bool) -> Void

    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(LibraryStore.self) private var library
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            ActivityCardView(item: item, compact: true,
                             onOpen: { router.push(.activity(item.id)) })
            Divider()
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.s))
                                                      : AnyLayout(HStackLayout(spacing: Theme.Spacing.m))
            layout {
                LikeButton(liked: item.likedByViewer, count: item.likeCount, pending: likePending) { onLike(!item.likedByViewer) }
                Button { router.push(.activity(item.id)) } label: {
                    Label("\(item.commentCount)", systemImage: "bubble.left").monospacedDigit()
                        .frame(minWidth: Theme.minimumHitTarget, minHeight: Theme.minimumHitTarget)
                }
                .accessibilityLabel(item.commentCount == 1 ? "1 comment" : "\(item.commentCount) comments")
                .accessibilityIdentifier("feed-comments-\(item.id.uuidString)")
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                saveButton
                Button { openLog() } label: {
                    PillLabel(title: library.ratedCategory(item.experience.id) == nil ? "Log" : "Add visit", systemImage: "plus.circle")
                }
                .buttonStyle(PillButtonStyle(isSelected: true))
                .accessibilityIdentifier("feed-log-\(item.id.uuidString)")
            }
            .buttonStyle(.borderless)
        }
        .roamCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("feed-card-\(item.id.uuidString)")
    }

    @ViewBuilder private var saveButton: some View {
        let id = item.experience.id
        switch library.saveState(for: id) {
        case .alreadyBeen:
            EmptyView()
        case .pending(let target):
            Button {} label: { HStack { ProgressView().controlSize(.small); Text(target ? "Saving" : "Removing") } }
                .buttonStyle(PillButtonStyle(isSelected: target)).disabled(true)
        case .saved:
            Button { Task { await library.setBookmark(id, saved: false) } } label: { PillLabel(title: "Saved", systemImage: "bookmark.fill") }
                .buttonStyle(PillButtonStyle(isSelected: true))
                .accessibilityLabel("Saved to Wishlist. Remove")
                .accessibilityIdentifier("feed-save-\(item.id.uuidString)")
        case .notSaved:
            Button { Task { await library.setBookmark(id, saved: true) } } label: { PillLabel(title: "Save", systemImage: "bookmark") }
                .buttonStyle(PillButtonStyle())
                .accessibilityLabel("Save \(item.experience.name) to Wishlist")
                .accessibilityIdentifier("feed-save-\(item.id.uuidString)")
        }
    }

    private func openLog() {
        Task {
            do { router.sheet = .log(try await services.makeLogRequest(experienceID: item.experience.id)) }
            catch { _ = session.handle(error) }
        }
    }
}

struct LikeButton: View {
    let liked: Bool
    let count: Int
    var pending = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("\(count)", systemImage: liked ? "heart.fill" : "heart")
                .monospacedDigit()
                .foregroundStyle(Roam.ink)
                .frame(minWidth: Theme.minimumHitTarget, minHeight: Theme.minimumHitTarget)
        }
        .disabled(pending)
        .roamHaptic(.impact(weight: .light), trigger: liked)
        .accessibilityLabel(liked ? "Liked, \(count) \(count == 1 ? "like" : "likes"). Unlike" : "Like, \(count) \(count == 1 ? "like" : "likes")")
        .accessibilityIdentifier("like-button")
    }
}
