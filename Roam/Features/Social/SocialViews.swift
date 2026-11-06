import MapKit
import SwiftUI

/// S25: in-app notifications (follow, like, comment). No push prompt or push toggle exists in v1.
struct NotificationsView: View {
    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @State private var model: NotificationsModel?

    var body: some View {
        Group {
            if let model { content(model) } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .background(Theme.groupedCanvas)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Mark all read") { Task { await model?.markAllRead() } }
                    .disabled(model?.unread.isEmpty ?? true)
                    .accessibilityIdentifier("notifications-mark-all")
            }
        }
        .task {
            if model == nil { model = NotificationsModel(service: services.notifications) }
            await model?.load()
        }
        .onChange(of: model?.authError) { _, error in if let error { _ = session.handle(error) } }
        .screenIdentifier("notifications")
    }

    @ViewBuilder private func content(_ model: NotificationsModel) -> some View {
        if !model.hasLoaded {
            if let error = model.error, !model.isLoading {
                ScrollView {
                    EmptyStateView(systemImage: "bell.slash", title: "Couldn't load notifications", message: error,
                                   primaryTitle: "Try again", primaryAction: { Task { await model.load() } })
                        .padding(.top, Theme.Spacing.xxl)
                }
            } else {
                ScrollView { SkeletonList(rows: 5).padding() }
            }
        } else if model.items.isEmpty {
            ScrollView {
                VStack {
                    EmptyStateView(systemImage: "bell", title: "No notifications yet",
                                   message: "Friend requests, likes and comments on your posts appear here.")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("notifications-empty")
                .padding(.top, Theme.Spacing.xxl)
            }
            .refreshable { await model.load() }
        } else {
            List { Group {
                if let error = model.actionError {
                    Text(error).foregroundStyle(Theme.disliked).accessibilityIdentifier("notifications-action-error")
                }
                if let error = model.error {
                    InlineRetryView(message: "Couldn't refresh. \(error)") { Task { await model.load() } }
                }
                if !model.unread.isEmpty {
                    Section("Unread") { ForEach(model.unread) { row($0, model: model) } }
                }
                if !model.earlier.isEmpty {
                    Section("Earlier") { ForEach(model.earlier) { row($0, model: model) } }
                }
                PaginationFooter(isLoading: model.loadingMore, errorMessage: model.pageError, hasMore: model.nextCursor != nil) {
                    Task { await model.loadMore() }
                }
                .listRowBackground(Color.clear)
            }
            .listRowBackground(Roam.paperRaised)
            }
            .refreshable { await model.load() }
            .accessibilityIdentifier("notifications-list")
        }
    }

    private func row(_ notification: AppNotification, model: NotificationsModel) -> some View {
        Button {
            Task { if let route = await model.open(notification) { router.push(route) } }
        } label: {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                AvatarView(member: notification.actor, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.message(notification)).font(.subheadline).foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(notification.createdAt.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(Theme.secondaryText)
                    if !notification.targetAvailable {
                        Text("No longer available").font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                }
                Spacer(minLength: 0)
                if notification.isUnread {
                    Circle().fill(Theme.accent).frame(width: 10, height: 10).accessibilityHidden(true)
                }
            }
            .frame(minHeight: Theme.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel((notification.isUnread ? "Unread. " : "") + Self.message(notification))
        .accessibilityIdentifier("notification-\(notification.type.rawValue)-\(notification.actor.handle)")
    }

    static func message(_ notification: AppNotification) -> String {
        let name = notification.actor.displayName
        switch notification.type {
        case .follow: return "\(name) started following you."
        case .friendRequest: return "\(name) wants to be friends."
        case .friendAccept: return "\(name) accepted your friend request."
        case .like: return "\(name) liked your post about \(notification.experienceName ?? "a place")."
        case .comment:
            if let preview = notification.commentPreview { return "\(name) commented on \(notification.experienceName ?? "your post"): “\(preview)”" }
            return "\(name) commented on your post."
        }
    }
}

/// S21: followers and following with search, paging and follow controls.
struct FollowListView: View {
    let userID: UUID
    let initialSegment: FollowSegment

    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @State private var model: FollowListModel?
    @State private var segment: FollowSegment
    @State private var query = ""

    init(userID: UUID, initialSegment: FollowSegment) {
        self.userID = userID
        self.initialSegment = initialSegment
        _segment = State(initialValue: initialSegment)
    }

    private var isOwn: Bool { session.userID == userID }

    var body: some View {
        VStack(spacing: 0) {
            if isOwn {
                Picker("List", selection: $segment) {
                    ForEach(FollowSegment.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.s)
                .accessibilityIdentifier("follow-segment")
            }
            if let model { list(model) } else { Spacer() }
        }
        .background(Theme.groupedCanvas)
        .navigationTitle(segment.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search by name or handle")
        // Type as you like: no capitalising or correcting.
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .task(id: "\(segment.rawValue)|\(query)") {
            if model == nil { model = FollowListModel(userID: userID, segment: segment, service: services.social) }
            model?.segment = segment
            if model?.hasLoaded == true { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            await model?.load(query: query)
        }
        .onChange(of: model?.authError) { _, error in if let error { _ = session.handle(error) } }
        .screenIdentifier("follow-list")
    }

    @ViewBuilder private func list(_ model: FollowListModel) -> some View {
        if !model.hasLoaded && model.isLoading {
            ScrollView { SkeletonList(rows: 6).padding() }
        } else if !model.hasLoaded, let error = model.error {
            ScrollView {
                EmptyStateView(systemImage: "person.2.slash", title: "Couldn't load this list", message: error,
                               primaryTitle: "Try again", primaryAction: { Task { await model.load(query: query) } })
            }
        } else if model.rows.isEmpty {
            ScrollView {
                VStack { emptyState(model) }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("follow-list-empty")
                    .padding(.top, Theme.Spacing.xl)
            }
        } else {
            List { Group {
                if let error = model.error { InlineRetryView(message: error) { Task { await model.load(query: query) } } }
                if let error = model.actionError { Text(error).foregroundStyle(Theme.disliked) }
                ForEach(model.rows) { row in
                    MemberRowView(member: row.member, subtitle: row.friendState == .received && !row.isSelf ? "Wants to be friends" : nil,
                                  followState: followState(row, model: model),
                                  onToggleFollow: { Task { await model.apply(row.friendState.primaryAction, to: row) } })
                    .swipeActions {
                        if row.friendState == .received {
                            Button("Decline", role: .destructive) { Task { await model.apply(.decline, to: row) } }
                        }
                    }
                }
                PaginationFooter(isLoading: model.loadingMore, errorMessage: model.pageError, hasMore: model.nextCursor != nil) {
                    Task { await model.loadMore() }
                }
                .listRowBackground(Color.clear)
            }
            .listRowBackground(Roam.paperRaised)
            }
            .accessibilityIdentifier("follow-list-rows")
        }
    }

    private func followState(_ row: MemberRow, model: FollowListModel) -> FollowButtonState? {
        if row.isSelf { return nil }
        return FollowButtonState(row.friendState, pending: model.pendingFollow.contains(row.id))
    }

    @ViewBuilder private func emptyState(_ model: FollowListModel) -> some View {
        if !model.loadedQuery.isEmpty {
            EmptyStateView(systemImage: "magnifyingglass", title: "No matches",
                           message: "No one here matches “\(model.loadedQuery)”. Check the spelling or clear the search.")
        } else if segment == .requests {
            EmptyStateView(systemImage: "person.2", title: "No requests", message: "When someone asks to be your friend, they appear here.")
        } else if isOwn {
            EmptyStateView(systemImage: "person.badge.plus", title: "No friends yet",
                           message: "Add friends to see their places here.",
                           primaryTitle: "Find people", primaryAction: { router.showFindPeople() })
        } else {
            EmptyStateView(systemImage: "person.2", title: "No friends yet", message: "They haven't added any friends yet.")
        }
    }
}
