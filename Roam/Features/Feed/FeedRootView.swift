import SwiftUI

/// One card per activity, ordered by publication time.
struct FeedRootView: View {
    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(ActivityChangeStore.self) private var changes
    @State private var model: FeedModel?
    @State private var scroll = ScrollPosition(edge: .top)

    @State private var barsHidden = false
    @State private var scrolledDown = false
    @State private var navigationBarHidden = true

    private static let barHeight: CGFloat = 44

    /// "+ Log a place" on the left, then Add friends and your profile, each in its own glass circle, as on Discover.
    private var topBar: some View {
        HStack(spacing: Theme.Spacing.s) {
            logPlaceButton
            Spacer(minLength: 0)
            // Just Add friends for now; notifications come back later.
            Button {
                router.showFindPeople()
            } label: { barGlyph("person.badge.plus") }
            .buttonStyle(.plain)
            .accessibilityLabel("Friends and requests")
            .tapID("open-friends")
            .floatingBubble(Circle())
            // Just the picture, no glass ring around it.
            ProfileAvatarButton()
            // The beta's bug button, always right-most.
            BugReportButton()
        }
        .frame(height: Self.barHeight)
    }

    /// A green bubble like "+ Add visit", in the Log button's green.
    private var logPlaceButton: some View {
        Button { router.sheet = .logPlace } label: {
            Label("Log a place", systemImage: "plus")
                .font(.headline)
                .foregroundStyle(PlaceState.visited.markerColor)
                .padding(.horizontal, Theme.Spacing.l)
                .frame(height: Self.barHeight)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .floatingBubble(Capsule(), tint: PlaceState.visited.markerColor.opacity(0.15))
        .tapID("log-place")
    }

    private func barGlyph(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(Roam.ink)
            .frame(width: Self.barHeight, height: Self.barHeight)
    }

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
        // Reading down swaps the buttons for the fade; any move back up brings them back.
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { old, new in
            if (new > 1) != scrolledDown { withAnimation(.easeOut(duration: 0.15)) { scrolledDown = new > 1 } }
            if new <= 40 || new < old - 4 { if barsHidden { withAnimation(.easeOut(duration: 0.2)) { barsHidden = false } } }
            else if new > old && !barsHidden { withAnimation(.easeOut(duration: 0.2)) { barsHidden = true } }
        }
        .contentMargins(.bottom, RoamTabBar.reservedHeight + Theme.Spacing.l, for: .scrollContent)
        // Room for the top row; the feed scrolls on underneath it.
        .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: Self.barHeight + Theme.Spacing.s) }
        .overlay(alignment: .top) {
            if barsHidden {
                ScrolledTitleFade(title: "Friends").transition(.opacity)
            } else {
                // Never a solid band: once the page moves, the glass buttons float on the fade, as on Discover.
                ZStack(alignment: .top) {
                    if scrolledDown { ScrolledTitleFade(depth: Self.barHeight + Theme.Spacing.xl).transition(.opacity) }
                    topBar
                        .padding(.horizontal, Theme.Spacing.l)
                        .padding(.bottom, Theme.Spacing.s)
                }
                .transition(.opacity)
            }
        }
        .background(Roam.paper)
        .navigationTitle("Friends")
        .toolbar(navigationBarHidden ? .hidden : .visible, for: .navigationBar)
        // As on Discover: coming back from a pushed page can leave the system bar showing over the row.
        .onAppear {
            navigationBarHidden = false
            Task { @MainActor in navigationBarHidden = true }
        }
        .task(id: session.userID) {
            guard session.userID != nil else { model = nil; return }
            let feed = services.feed
            let plans = services.plans
            model = FeedModel(service: feed, notifications: services.notifications,
                              fetchPlacePhotos: { await plans.refreshGoogleDetails(experienceIDs: $0) }) { cursor in
                try await feed.friendsActivity(cursor: cursor)
            }
            await refresh()
        }
        .refreshable { await refresh() }
        .onChange(of: router.scrollToTopRequests[.friends]) { _, _ in
            withAnimation { scroll.scrollTo(edge: .top); barsHidden = false }
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
            LazyVStack(spacing: Theme.Spacing.xl) {
                if let error = model.actionError ?? model.error {
                    InlineRetryView(message: error) { Task { await refresh() } }
                }
                ForEach(model.cards) { item in
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

    private func actions(onPhoto: Bool) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            // The note's first line, left, level with like and comment; the rest is on the log's page.
            Text(Self.firstLine(of: item.note))
                .font(.subheadline)
                .foregroundStyle(onPhoto ? Color.white : Roam.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("feed-note")
            LikeButton(liked: item.likedByViewer, count: item.likeCount, pending: likePending, tint: onPhoto ? .white : Roam.ink) {
                onLike(!item.likedByViewer)
            }
            Button { router.push(.activity(item.id)) } label: {
                // The count tucked close to its icon.
                HStack(spacing: 4) { Image(systemName: "bubble.right"); Text("\(item.commentCount)") }
                    .monospacedDigit()
                    .foregroundStyle(onPhoto ? Color.white : Roam.ink)
                    .frame(minWidth: Theme.minimumHitTarget, minHeight: Theme.minimumHitTarget)
            }
            .accessibilityLabel(item.commentCount == 1 ? "1 comment" : "\(item.commentCount) comments")
            .tapID("feed-comments-\(item.id.uuidString)")
        }
        .buttonStyle(.plain)
    }

    /// The note's first line, with "…" when there's more than fits or more lines after it.
    static func firstLine(of note: String) -> String {
        let lines = note.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let first = lines.first else { return "" }
        return lines.count > 1 ? first + "…" : first
    }

    var body: some View {
        // With a photo, like and comment sit in its bottom right (white); without, under the card.
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ActivityCardView(item: item, actions: AnyView(actions(onPhoto: true)),
                             onDoubleTap: { if !item.likedByViewer { onLike(true) } },
                             onTap: { router.push(.activity(item.id)) })
            if !ActivityCardView.hasPhoto(item) { actions(onPhoto: false) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // No card around it: the photos set the logs apart.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("feed-card-\(item.id.uuidString)")
    }
}

struct LikeButton: View {
    let liked: Bool
    let count: Int
    var pending = false
    /// White over a photo.
    var tint: Color = Roam.ink
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) { Image(systemName: liked ? "heart.fill" : "heart"); Text("\(count)") }
                .monospacedDigit()
                .foregroundStyle(tint)
                .frame(minWidth: Theme.minimumHitTarget, minHeight: Theme.minimumHitTarget)
        }
        .disabled(pending)
        .roamHaptic(.impact(weight: .light), trigger: liked)
        .accessibilityLabel(liked ? "Liked, \(count) \(count == 1 ? "like" : "likes"). Unlike" : "Like, \(count) \(count == 1 ? "like" : "likes")")
        .tapID("like-button")
    }
}

