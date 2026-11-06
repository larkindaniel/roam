import SwiftUI

/// S02: own and followed members' posts, newest publication first.
struct FeedRootView: View {
    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(ActivityChangeStore.self) private var changes
    @State private var model: FeedModel?

    var body: some View {
        Group {
            if let model { content(model) } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .background(Theme.groupedCanvas)
        .navigationTitle("Feed")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Roam").font(.system(.title2, design: .serif).weight(.bold)).foregroundStyle(Theme.accent)
                    .fixedSize()
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel("Roam feed")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.push(.notifications) } label: {
                    Image(systemName: (model?.unreadCount ?? 0) > 0 ? "bell.badge.fill" : "bell")
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel((model?.unreadCount ?? 0) > 0 ? "Notifications, \(model?.unreadCount ?? 0) unread" : "Notifications")
                .accessibilityIdentifier("open-notifications")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil { model = FeedModel(service: services.feed, notifications: services.notifications) }
            if model?.hasLoaded != true || changes.consumeFeedStale() { await model?.refresh() }
            await model?.refreshUnreadCount()
        }
        .onChange(of: changes.revision) { _, _ in model?.apply(changes) }
        .onChange(of: model?.authError) { _, error in if let error { _ = session.handle(error) } }
        .screenIdentifier("feed-root")
    }

    @ViewBuilder private func content(_ model: FeedModel) -> some View {
        if !model.hasLoaded {
            if let error = model.error, !model.isLoading {
                ScrollView {
                    EmptyStateView(systemImage: "wifi.exclamationmark", title: "Couldn't load your feed", message: error,
                                   primaryTitle: "Try again", primaryAction: { Task { await model.refresh() } })
                        .padding(.top, Theme.Spacing.xxl)
                }
            } else {
                // State identifiers sit on inner containers; the screen identifier owns the scroll view.
                ScrollView {
                    VStack { SkeletonList(rows: 5).padding() }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("feed-loading")
                }
            }
        } else if model.items.isEmpty {
            ScrollView {
                if let error = model.error { InlineRetryView(message: error) { Task { await model.refresh() } }.padding() }
                VStack {
                    EmptyStateView(systemImage: "person.2.wave.2", title: "Your feed is quiet",
                                   message: "Follow travellers to see their rankings here, newest first. Your own ratings appear here too.",
                                   primaryTitle: "Find people", primaryAction: { router.showFindPeople() },
                                   secondaryTitle: "Search experiences", secondaryAction: { router.selectedTab = .search })
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("feed-empty")
                .padding(.top, Theme.Spacing.xxl)
            }
            .refreshable { await model.refresh() }
        } else {
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.m) {
                    if let error = model.error {
                        InlineRetryView(message: "Couldn't refresh. Showing the posts you already had. \(error)") { Task { await model.refresh() } }
                            .accessibilityIdentifier("feed-refresh-error")
                    }
                    if let error = model.actionError {
                        InlineRetryView(message: error, retryTitle: "Dismiss") { Task { await model.refresh() } }
                    }
                    ForEach(model.items) { item in
                        FeedCard(item: item, likePending: model.likePending.contains(item.id),
                                 onLike: { liked in Task { await model.setLike(item.id, liked: liked) } })
                    }
                    PaginationFooter(isLoading: model.loadingMore, errorMessage: model.pageError, hasMore: model.nextCursor != nil) {
                        Task { await model.loadMore() }
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.m)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("feed-list")
            }
            .refreshable {
                await model.refresh()
                await model.refreshUnreadCount()
            }
        }
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
                .accessibilityLabel("Saved to Want to Go. Remove")
                .accessibilityIdentifier("feed-save-\(item.id.uuidString)")
        case .notSaved:
            Button { Task { await library.setBookmark(id, saved: true) } } label: { PillLabel(title: "Save", systemImage: "bookmark") }
                .buttonStyle(PillButtonStyle())
                .accessibilityLabel("Save \(item.experience.name) to Want to Go")
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
                .foregroundStyle(liked ? Theme.disliked : Theme.accent)
                .frame(minWidth: Theme.minimumHitTarget, minHeight: Theme.minimumHitTarget)
        }
        .disabled(pending)
        .roamHaptic(.impact(weight: .light), trigger: liked)
        .accessibilityLabel(liked ? "Liked, \(count) \(count == 1 ? "like" : "likes"). Unlike" : "Like, \(count) \(count == 1 ? "like" : "likes")")
        .accessibilityIdentifier("like-button")
    }
}
