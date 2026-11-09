import SwiftUI

/// One card per activity, ordered by publication time.
struct FeedRootView: View {
    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(ActivityChangeStore.self) private var changes
    @State private var model: FeedModel?
    @State private var scroll = ScrollPosition(edge: .top)

    var body: some View {
        ScrollView {
            Group {
                if let model { content(model) }
                else { SkeletonCards() }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.m)
        }
        .scrollPosition($scroll)
        .contentMargins(.bottom, RoamTabBar.reservedHeight + Theme.Spacing.l, for: .scrollContent)
        .background(Roam.paper)
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
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
                    Image(systemName: (model?.unreadCount ?? 0) > 0 ? "bell.badge.fill" : "bell")
                }
                .accessibilityLabel("Notifications, \(model?.unreadCount ?? 0) unread")
                .accessibilityIdentifier("open-notifications")
            }
            SettingsToolbarItem()
        }
        .task(id: session.userID) {
            guard session.userID != nil else { model = nil; return }
            let feed = services.feed
            model = FeedModel(service: feed, notifications: services.notifications) { cursor in
                try await feed.friendsActivity(cursor: cursor)
            }
            await refresh()
        }
        .refreshable { await refresh() }
        .onChange(of: router.scrollToTopRequests[.friends]) { _, _ in
            withAnimation { scroll.scrollTo(edge: .top) }
        }
        .onChange(of: router.selectedTab) { _, tab in
            if tab == .friends { Task { await refresh() } }
        }
        .onChange(of: router.path(for: .friends).isEmpty) { _, atRoot in
            if atRoot, router.selectedTab == .friends { Task { await refresh() } }
        }
        .onChange(of: changes.revision) { _, _ in
            model?.apply(changes)
            if changes.consumeFeedStale() { Task { await refresh() } }
        }
        .onChange(of: model?.authError) { _, error in if let error { _ = session.handle(error) } }
        .screenIdentifier("feed-root")
    }

    @ViewBuilder private func content(_ model: FeedModel) -> some View {
        if !model.hasLoaded, let error = model.error {
            InlineRetryView(message: error) { Task { await refresh() } }
        } else if !model.hasLoaded {
            SkeletonCards().accessibilityIdentifier("feed-loading")
        } else if model.items.isEmpty {
            EmptyStateView(systemImage: "person.2", title: "No activity yet",
                           message: "See where your friends have been.",
                           primaryTitle: "Find people", primaryAction: { router.showFindPeople() })
                .accessibilityIdentifier("feed-empty")
        } else {
            LazyVStack(spacing: Theme.Spacing.l) {
                if let error = model.actionError ?? model.error {
                    InlineRetryView(message: error) { Task { await refresh() } }
                }
                ForEach(model.items) { item in
                    FeedCard(item: item, likePending: model.likePending.contains(item.id)) { liked in
                        Task {
                            await model.setLike(item.id, liked: liked)
                            if let updated = model.items.first(where: { $0.id == item.id }) { changes.publish(updated) }
                        }
                    }
                }
                PaginationFooter(isLoading: model.loadingMore, errorMessage: model.pageError, hasMore: model.nextCursor != nil) {
                    Task { await model.loadMore() }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("feed-list")
        }
    }

    private func refresh() async {
        guard let model else { return }
        async let count: Void = model.refreshUnreadCount()
        await model.refresh()
        await count
    }
}

struct FeedCard: View {
    let item: ActivityItem
    var likePending = false
    let onLike: (Bool) -> Void
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ActivityCardView(item: item)
            HStack(spacing: Theme.Spacing.m) {
                LikeButton(liked: item.likedByViewer, count: item.likeCount, pending: likePending) { onLike(!item.likedByViewer) }
                Button { router.push(.activity(item.id)) } label: {
                    Label("\(item.commentCount)", systemImage: "bubble.left")
                        .monospacedDigit()
                        .frame(minWidth: Theme.minimumHitTarget, minHeight: Theme.minimumHitTarget)
                }
                .accessibilityLabel(item.commentCount == 1 ? "1 comment" : "\(item.commentCount) comments")
                .accessibilityIdentifier("feed-comments-\(item.id.uuidString)")
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .roamCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("feed-card-\(item.id.uuidString)")
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
