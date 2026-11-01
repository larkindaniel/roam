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
            List {
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
                EmptyStateView(systemImage: "person.2.slash", title: "Couldn't load members", message: error,
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
            List {
                if let error = model.error { InlineRetryView(message: error) { Task { await model.load(query: query) } } }
                if let error = model.actionError { Text(error).foregroundStyle(Theme.disliked) }
                ForEach(model.rows) { row in
                    MemberRowView(member: row.member, subtitle: row.friendState == .received && !row.isSelf ? "Wants to be friends" : nil,
                                  followState: followState(row, model: model),
                                  onOpen: { router.push(.member(row.id)) },
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
                           message: "Add friends to see their trips and places here.",
                           primaryTitle: "Find people", primaryAction: { router.showFindPeople() })
        } else {
            EmptyStateView(systemImage: "person.2", title: "No friends yet", message: "This member hasn't added any friends yet.")
        }
    }
}

/// S22: read-only intersection of your Wishlist with one other member's.
struct SharedWantsView: View {
    let otherID: UUID

    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(LibraryStore.self) private var library
    @State private var model: SharedWantsModel?
    @State private var other: PublicProfile?
    @State private var showsMap = false
    @State private var selectedPin: String?

    var body: some View {
        Group {
            if let model { content(model) } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .background(Theme.groupedCanvas)
        .navigationTitle("Shared Wishlist")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil { model = SharedWantsModel(otherID: otherID, service: services.lists) }
            async let profile = try? services.profiles.publicProfile(userID: otherID)
            await model?.load()
            other = await profile
        }
        .onChange(of: library.revision) { _, _ in Task { await model?.load() } }
        .onChange(of: model?.authError) { _, error in if let error { _ = session.handle(error) } }
        .screenIdentifier("shared-wants")
    }

    private var otherName: String { other?.member.displayName ?? "this member" }

    @ViewBuilder private func content(_ model: SharedWantsModel) -> some View {
        VStack(spacing: 0) {
            header(model)
            if !model.hasLoaded && model.isLoading {
                ScrollView { SkeletonList(rows: 4).padding() }
            } else if !model.hasLoaded, let error = model.error {
                ScrollView {
                    EmptyStateView(systemImage: "bookmark.slash", title: "Couldn't compare lists", message: error,
                                   primaryTitle: "Try again", primaryAction: { Task { await model.load() } })
                }
            } else if model.entries.isEmpty {
                ScrollView {
                    VStack {
                        EmptyStateView(systemImage: "bookmark", title: "Nothing shared yet",
                                       message: "You and \(otherName) haven't saved the same place. Neither Wishlist list is changed by comparing.",
                                       primaryTitle: "See \(otherName)'s Wishlist", primaryAction: { router.push(.memberList(otherID, .want)) })
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("shared-wants-empty")
                }
            } else if showsMap {
                sharedMap(model)
            } else {
                List {
                    if let error = model.error {
                        InlineRetryView(message: "Couldn't refresh. Showing the last shared list. \(error)") { Task { await model.load() } }
                    }
                    ForEach(model.entries) { entry in
                        let experience = entry.experience
                        // Same row as Wishlist: removing your own bookmark here refreshes the intersection.
                        ExperienceRow(name: experience.name, category: experience.category, area: experience.areaLine,
                                      score: experience.viewer.myScore, scoreSource: .you,
                                      statusLine: entry.savedAt.map { "You saved \($0.formatted(date: .abbreviated, time: .omitted))" },
                                      saveState: library.saveState(for: experience.id),
                                      logTitle: library.ratedCategory(experience.id) == nil ? "Log" : "Add visit",
                                      onOpen: { router.push(.experience(experience.id)) },
                                      onSave: { Task { await library.setBookmark(experience.id, saved: !library.isBookmarked(experience.id)) } },
                                      onLog: { Task {
                                          do { router.sheet = .log(try await services.makeLogRequest(experienceID: experience.id)) }
                                          catch { _ = session.handle(error) }
                                      } })
                    }
                }
                .accessibilityIdentifier("shared-wants-list")
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !(model.entries.isEmpty) {
                MapListToggle(showsMap: $showsMap).padding(Theme.Spacing.l)
            }
        }
    }

    private func header(_ model: SharedWantsModel) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            HStack(spacing: -12) {
                if let me = session.profile?.summary { AvatarView(member: me, size: 40) }
                if let other { AvatarView(member: other.member, size: 40) }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("You and \(otherName)").font(.headline)
                Text(model.hasLoaded ? "\(model.entries.count) \(model.entries.count == 1 ? "place" : "places") you both want to visit" : "Comparing your lists…")
                    .font(.subheadline).foregroundStyle(Theme.secondaryText)
                    .accessibilityIdentifier("shared-wants-count")
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.l)
        .accessibilityElement(children: .combine)
    }

    /// Same map as Wishlist: the UIKit-backed map fits every pin (SwiftUI `Map` could not zoom out
    /// far enough to show places on opposite sides of the world), and a pin opens its place card.
    private func sharedMap(_ model: SharedWantsModel) -> some View {
        let pins = model.entries.map { MapPin(id: $0.id.uuidString, name: $0.experience.name, category: $0.experience.category,
                                              latitude: $0.experience.latitude, longitude: $0.experience.longitude) }
        return ZStack(alignment: .bottom) {
            GlobeMapView(pins: pins, shadedCountryCodes: [], style: .standard, interactive: true, selectedPinID: selectedPin,
                         focusRegion: GlobeMapView.region(fitting: pins), focusToken: pins.map(\.id).hashValue,
                         onSelectPin: { selectedPin = $0.id })
                .mapAccessibility("Map of \(pins.count) shared \(pins.count == 1 ? "place" : "places"). The list view shows the same places.", identifier: "shared-wants-map")
            if let selected = model.entries.first(where: { $0.id.uuidString == selectedPin }) {
                SelectedPlaceCard(summary: selected.experience, onOpen: { router.push(.experience(selected.id)) },
                                  onSave: { Task { await library.setBookmark(selected.id, saved: !library.isBookmarked(selected.id)) } },
                                  onLog: { Task {
                                      do { router.sheet = .log(try await services.makeLogRequest(experienceID: selected.id)) }
                                      catch { _ = session.handle(error) }
                                  } }, saveState: library.saveState(for: selected.id), onClose: { selectedPin = nil })
                    .padding()
                    .padding(.bottom, 56)
            }
        }
    }
}
