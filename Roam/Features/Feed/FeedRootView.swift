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
            .solidTopEdge()
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
            SkeletonCards().accessibilityIdentifier("feed-loading")
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
                ForEach(value) { group in FriendCityCard(group: group) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("feed-list")
        }
    }

    private func load() async {
        if cards.value == nil { cards = .loading }
        do {
            // A card per friend and city, newest first by when they were there (not when they posted).
            cards = .loaded(FriendFeedGrouping.groups(try await services.plans.friendsFeed()))
        } catch {
            if cards.value == nil { cards = .failed(session.handle(error)) }
        }
        if let count = try? await services.notifications.unreadCount() { unreadCount = count }
    }
}

/// A friend's places in one city, right on the Friends tab: their avatar, name and how long they were there, the
/// city's photo big (it opens the city) with its country and flag small under the name, then each place as a row
/// with a chevron that opens it.
struct FriendCityCard: View {
    let group: FriendFeedGroup

    @Environment(AppRouter.self) private var router
    /// The tight margin round the city's photo, as on a trip's page.
    private let margin: CGFloat = 6

    private var destination: Destination {
        let first = group.places.first?.experience
        return Destination(name: group.city, region: group.region, countryCode: group.countryCode, countryName: group.countryName,
                           latitude: first?.latitude ?? 0, longitude: first?.longitude ?? 0, radiusMeters: 15_000)
    }

    var body: some View {
        let places = group.places
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Spacing.s) {
                AvatarView(member: group.author, size: 36)
                VStack(alignment: .leading, spacing: -2) {
                    Text(group.author.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(Roam.ink)
                    if let dates = MyTimeline.range(group.firstVisit, group.lastVisit) {
                        Text(dates).font(.caption).foregroundStyle(Roam.inkMuted)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.top, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.m)
            Button { router.push(.city(destination, ownerID: nil)) } label: {
                CityHeroCard(city: destination, subtitle: [group.countryName ?? group.countryCode, TripTitle.flag(group.countryCode)]
                                 .compactMap { $0 }.joined(separator: " "),
                             cornerRadius: Theme.cornerRadius - margin)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, margin)
            .accessibilityIdentifier("friend-city-\(group.author.handle)-\(group.city)")
            VStack(spacing: 0) {
                ForEach(places) { entry in
                    Button { router.push(.experience(entry.experience.id)) } label: { row(entry) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("friend-place-\(entry.experience.name)")
                    if entry.id != places.last?.id { RowSeparator() }
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.xs)
        }
        .roamCard(padding: 0)
    }

    private func row(_ entry: TripFeedEntry) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            PlaceThumbnail(id: "feed-\(entry.id)", path: entry.media.sorted { $0.position < $1.position }.first?.path,
                           url: entry.experience.photoURL, coordinate: entry.experience.coordinate, symbol: entry.experience.iconName, size: 48)
            Text(entry.experience.name).font(.headline).foregroundStyle(Roam.ink).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Roam.inkMuted).accessibilityHidden(true)
        }
        .padding(.vertical, Theme.Spacing.s)
        .contentShape(Rectangle())
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
            ActivityCardView(item: item, compact: true, onOpenAuthor: { router.push(.member(item.author.id)) },
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
