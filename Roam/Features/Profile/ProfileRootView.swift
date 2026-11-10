import SwiftUI

/// S18 own profile root.
struct ProfileRootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router

    var body: some View {
        Group {
            if let userID = session.userID {
                ProfileView(userID: userID)
            } else {
                ProgressView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.push(.settings) } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("open-settings")
            }
        }
    }
}

/// Member identity, places and visible activities.
struct ProfileView: View {
    let userID: UUID

    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(ActivityChangeStore.self) private var changes
    @Environment(LibraryStore.self) private var library
    @State private var profile: LoadPhase<PublicProfile> = .idle
    @State private var sharedLists: [PlaceList] = []
    @State private var activity: FeedModel?
    @State private var followPending = false
    @State private var safetyPending = false
    @State private var actionError: String?
    @State private var confirmingBlock = false
    @State private var reportTarget: ReportTarget?
    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                switch profile {
                case .idle, .loading:
                    SkeletonList(rows: 3).padding()
                case .failed(let message):
                    EmptyStateView(systemImage: "person.crop.circle.badge.exclamationmark", title: "Profile unavailable", message: message,
                                   primaryTitle: "Try again", primaryAction: { Task { await load() } })
                case .loaded(let value):
                    header(value)
                    if value.relationship.isSelf {
                        Button { router.push(.editProfile) } label: { PillLabel(title: "Edit profile", systemImage: "pencil") }
                            .buttonStyle(PillButtonStyle())
                            .accessibilityIdentifier("profile-edit")
                    } else {
                        relationshipActions(value)
                    }
                    if let actionError {
                        InlineRetryView(message: actionError, retryTitle: "Dismiss") { self.actionError = nil }.padding(.horizontal)
                    }
                    shortcuts(value)
                    activitySection(value)
                }
            }
            .padding(.bottom, Theme.Spacing.xl)
        }
        .contentMargins(.bottom, RoamTabBar.reservedHeight, for: .scrollContent)
        .background(Roam.paper)
        .navigationTitle(profile.value?.member.displayName ?? "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let value = profile.value {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: ShareText.profile(displayName: value.member.displayName, handle: value.member.handle,
                                                      countryCount: value.countryCount, cityCount: value.cityCount)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share profile")
                    .accessibilityIdentifier("share-profile")
                }
                if !value.relationship.isSelf {
                    ToolbarItem(placement: .topBarTrailing) { overflow(value) }
                }
            }
        }
        .confirmationDialog("Block @\(profile.value?.member.handle ?? "")?", isPresented: $confirmingBlock, titleVisibility: .visible) {
            Button("Block", role: .destructive) { Task { await block() } }
                .accessibilityIdentifier("confirm-block")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll stop being friends and won't see each other's profiles, posts, lists, photos or comments. Unblocking later doesn't restore follows.")
        }
        .sheet(item: $reportTarget) { target in ReportSheet(target: target, title: "Report this person") }
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: session.profile) { _, updated in
            // An own-profile edit or a new visit elsewhere refreshes the header and travel counts.
            if updated?.id == userID { Task { await load() } }
        }
        .onChange(of: library.revision) { _, _ in
            if userID == session.userID { Task { await load() } }
        }
        .screenIdentifier("profile-root")
    }

    private func load() async {
        if profile.value == nil { profile = .loading }
        if activity == nil {
            let feed = services.feed, id = userID
            activity = FeedModel(service: feed, notifications: services.notifications,
                                 source: { try await feed.profileActivity(userID: id, cursor: $0) })
        }
        do {
            let loaded = try await services.profiles.publicProfile(userID: userID)
            profile = .loaded(loaded)
        } catch {
            if profile.value == nil { profile = .failed(error.roamMessage) }
            _ = session.handle(error)
        }
        async let posts: Void = activity?.refresh() ?? ()
        let shares = (try? await services.plans.sharedWithMe()) ?? []
        var seen = Set<UUID>()
        sharedLists = shares.compactMap(\.list).filter { $0.owner.id == userID && seen.insert($0.id).inserted }
        await posts
    }

    private func header(_ value: PublicProfile) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                AvatarView(member: value.member, size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(value.member.displayName).font(.roamTitle(.title))
                    Text("@\(value.member.handle)").font(.subheadline).foregroundStyle(Roam.inkMuted)
                }
                Spacer(minLength: 0)
            }
            if !value.bio.isEmpty { Text(value.bio).font(.body) }
            if let home = value.homeCityName {
                Label(home, systemImage: "house.fill").font(.footnote).foregroundStyle(Roam.inkMuted)
            }
        }
        .roamCard()
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.m)
    }

    private func shortcuts(_ value: PublicProfile) -> some View {
        VStack(spacing: 0) {
            SocialNavigationRow(title: "Friends", symbol: "person.2") {
                router.push(.followGraph(userID, .friends))
            }
            .accessibilityIdentifier("profile-friends")
            if value.relationship.isSelf || value.relationship.friendState == .friends {
                RowSeparator()
                SocialNavigationRow(title: "Passport", symbol: "book.closed") {
                    router.push(.passport(ownerID: userID, name: value.member.displayName))
                }
            }
            if value.relationship.isSelf {
                RowSeparator()
                SocialNavigationRow(title: "Lists", symbol: "list.bullet") { router.push(.lists) }
            } else {
                ForEach(sharedLists) { list in
                    RowSeparator()
                    SocialNavigationRow(title: list.title, symbol: "list.bullet") { router.push(.list(list.id)) }
                }
            }
        }
        .roamCard(padding: Theme.Spacing.m)
        .padding(.horizontal, Theme.Spacing.l)
    }

    private func relationshipActions(_ value: PublicProfile) -> some View {
        let relationship = value.relationship
        let state = FollowButtonState(relationship.friendState, pending: followPending)
        return VStack(spacing: Theme.Spacing.s) {
            FollowButton(state: state, name: value.member.displayName) { Task { await toggleFollow(value) } }
            if relationship.isMuted {
                Label("Muted", systemImage: "speaker.slash").font(.footnote).foregroundStyle(Roam.inkMuted)
                    .accessibilityIdentifier("profile-muted")
            }
        }
        .padding(.horizontal)
    }

    private func overflow(_ value: PublicProfile) -> some View {
        Menu {
            Button { Task { await setMute(!value.relationship.isMuted) } } label: {
                Label(value.relationship.isMuted ? "Unmute" : "Mute", systemImage: value.relationship.isMuted ? "speaker.wave.2" : "speaker.slash")
            }
            .accessibilityIdentifier("profile-mute")
            Button(role: .destructive) { confirmingBlock = true } label: { Label("Block", systemImage: "hand.raised") }
                .accessibilityIdentifier("profile-block")
            Button { reportTarget = .member(userID) } label: { Label("Report", systemImage: "flag") }
                .accessibilityIdentifier("profile-report")
        } label: {
            Image(systemName: "ellipsis.circle").accessibilityLabel("More")
        }
        .disabled(safetyPending)
        .accessibilityIdentifier("profile-overflow")
    }

    private func toggleFollow(_ value: PublicProfile) async {
        guard !followPending, case .loaded(var current) = profile else { return }
        let action = current.relationship.friendState.primaryAction
        let before = current
        followPending = true
        defer { followPending = false }
        current.relationship.friendState = current.relationship.friendState.applying(action)
        profile = .loaded(current)
        do {
            let persisted = try await services.social.friendAction(userID: userID, action: action)
            current.relationship.friendState = persisted
            if persisted == .friends && before.relationship.friendState != .friends {
                current.followingCount += 1
                current.followerCount += 1
            } else if persisted != .friends && before.relationship.friendState == .friends {
                current.followingCount = max(0, current.followingCount - 1)
                current.followerCount = max(0, current.followerCount - 1)
            }
            profile = .loaded(current)
            changes.markFeedStale()
            actionError = nil
        } catch {
            profile = .loaded(before)
            actionError = session.handle(error)
        }
    }

    private func setMute(_ muted: Bool) async {
        safetyPending = true
        defer { safetyPending = false }
        do {
            try await services.social.setMute(userID: userID, muted: muted)
            changes.markFeedStale()
            if case .loaded(var current) = profile { current.relationship.isMuted = muted; profile = .loaded(current) }
            actionError = nil
        } catch {
            actionError = session.handle(error)
        }
    }

    private func block() async {
        safetyPending = true
        defer { safetyPending = false }
        do {
            try await services.social.setBlock(userID: userID, blocked: true)
            changes.markFeedStale()
            // The blocked profile is no longer visible; return to where it was opened.
            var path = router.path(for: router.selectedTab)
            if path.last == .member(userID) { path.removeLast(); router.binding(for: router.selectedTab).wrappedValue = path }
        } catch {
            actionError = session.handle(error)
        }
    }

    @ViewBuilder private func activitySection(_ value: PublicProfile) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Activity").font(.roamTitle(.title3)).accessibilityAddTraits(.isHeader)
            if let activity {
                if !activity.hasLoaded && activity.isLoading {
                    SkeletonList(rows: 2)
                } else if let error = activity.error, activity.items.isEmpty {
                    InlineRetryView(message: error) { Task { await activity.refresh() } }
                } else if activity.items.isEmpty {
                    Text(value.relationship.isSelf ? "Places you log appear here."
                                                   : "\(value.member.displayName) hasn't shared anything you can see yet.")
                        .font(.subheadline).foregroundStyle(Theme.secondaryText)
                        .accessibilityIdentifier("profile-activity-empty")
                } else {
                    ForEach(activity.items) { item in
                        FeedCard(item: item, likePending: activity.likePending.contains(item.id),
                                 onLike: { liked in
                            Task {
                                await activity.setLike(item.id, liked: liked)
                                if let updated = activity.items.first(where: { $0.id == item.id }) { changes.publish(updated) }
                            }
                        })
                    }
                    if activity.nextCursor != nil || activity.pageError != nil {
                        PaginationFooter(isLoading: activity.loadingMore, errorMessage: activity.pageError, hasMore: false) {
                            Task { await activity.loadMore() }
                        }
                        if activity.pageError == nil {
                            Button(activity.loadingMore ? "Loading…" : "Show more posts") { Task { await activity.loadMore() } }
                                .disabled(activity.loadingMore)
                                .frame(minHeight: Theme.minimumHitTarget)
                                .accessibilityIdentifier("profile-activity-more")
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile-activity")
        .onChange(of: changes.revision) { _, _ in activity?.apply(changes) }
    }
}
