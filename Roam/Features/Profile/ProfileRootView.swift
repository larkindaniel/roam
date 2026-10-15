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

/// S18: public profile header, follow controls, travel globe and the member's posts.
struct ProfileView: View {
    let userID: UUID

    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(ActivityChangeStore.self) private var changes
    @Environment(LibraryStore.self) private var library
    @State private var profile: LoadPhase<PublicProfile> = .idle
    @State private var travel: TravelProfile?
    @State private var travelError: String?
    @State private var activity: FeedModel?
    @State private var followPending = false
    @State private var safetyPending = false
    @State private var actionError: String?
    @State private var confirmingBlock = false
    @State private var reportTarget: ReportTarget?
    @State private var tab: ProfileTab = .activity

    enum ProfileTab: String, CaseIterable, Identifiable {
        case activity
        case travel

        var id: String { rawValue }
        var title: String { self == .activity ? "Activity" : "Travel Profile" }
    }

    private var year: Int { Calendar.current.component(.year, from: Date()) }

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
                    globeCard(value)
                    Picker("Profile section", selection: $tab) {
                        ForEach(ProfileTab.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .accessibilityIdentifier("profile-tabs")
                    switch tab {
                    case .activity:
                        activitySection(value)
                    case .travel:
                        TravelProfileSection(userID: userID, travel: travel, error: travelError, isSelf: value.relationship.isSelf,
                                             ownerName: value.member.displayName, retry: { Task { await loadTravel() } })
                    }
                }
            }
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.groupedCanvas)
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
            Text("You'll both stop following each other and won't see each other's profiles, posts, lists, photos or comments. Unblocking later doesn't restore follows.")
        }
        .sheet(item: $reportTarget) { target in ReportSheet(target: target, title: "Report member") }
        .task { if profile.value == nil { await load() } }
        .refreshable { await load() }
        .onChange(of: session.profile) { _, updated in
            // An own-profile edit or a new visit elsewhere refreshes the header and travel counts.
            if updated?.id == userID { Task { await load() } }
        }
        .onChange(of: library.revision) { _, _ in
            // Visits logged, edited or deleted elsewhere change travel counts.
            if userID == session.userID { Task { await loadTravel() } }
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
        await loadTravel()
        await posts
    }

    private func loadTravel() async {
        do {
            travel = try await services.travel.travelProfile(userID: userID, year: year)
            travelError = nil
        } catch {
            travelError = error.roamMessage
        }
    }

    private func header(_ value: PublicProfile) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            AvatarView(member: value.member, size: 88)
            Text(value.member.displayName).font(.roamTitle(.title))
                .multilineTextAlignment(.center)
            Text("@\(value.member.handle)").font(.subheadline).foregroundStyle(.secondary)
            if !value.bio.isEmpty {
                Text(value.bio).font(.body).multilineTextAlignment(.center).padding(.horizontal)
            }
            if let home = value.homeCityName {
                Label("Home: \(home)", systemImage: "house").font(.footnote).foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.xl) { stats(value) }
                VStack(spacing: Theme.Spacing.s) { stats(value) }
            }
            .padding(.top, Theme.Spacing.s)
        }
        .padding(.top, Theme.Spacing.l)
        .padding(.horizontal)
    }

    @ViewBuilder private func stats(_ value: PublicProfile) -> some View {
        Button { router.push(.followGraph(userID, .followers)) } label: { stat(value.followerCount, "Followers") }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile-followers")
        Button { router.push(.followGraph(userID, .following)) } label: { stat(value.followingCount, "Following") }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile-following")
        Button { router.push(.memberList(userID, .been)) } label: { stat(value.rankedCount, "Ranked") }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile-been-count")
        Button { router.push(.memberList(userID, .want)) } label: { stat(value.wantCount, "Want to Go") }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile-want-count")
    }

    private func stat(_ count: Int, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(count)").font(.headline).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(minWidth: Theme.minimumHitTarget, minHeight: Theme.minimumHitTarget)
        .accessibilityElement(children: .combine)
    }

    private func relationshipActions(_ value: PublicProfile) -> some View {
        let relationship = value.relationship
        let state: FollowButtonState = followPending ? .pending : relationship.isFollowing ? .following : relationship.followsViewer ? .followBack : .follow
        return VStack(spacing: Theme.Spacing.s) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.s) { followAndShared(value, state: state) }
                VStack(spacing: Theme.Spacing.s) { followAndShared(value, state: state) }
            }
            if relationship.isMuted {
                Label("Muted: their posts are hidden from your feed.", systemImage: "speaker.slash").font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("profile-muted")
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder private func followAndShared(_ value: PublicProfile, state: FollowButtonState) -> some View {
        FollowButton(state: state, name: value.member.displayName) { Task { await toggleFollow(value) } }
        Button { router.push(.sharedWants(userID)) } label: { PillLabel(title: "Shared Want to Go", systemImage: "bookmark.circle") }
            .buttonStyle(PillButtonStyle())
            .accessibilityIdentifier("profile-shared-wants")
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
        let target = !current.relationship.isFollowing
        let before = current
        followPending = true
        defer { followPending = false }
        current.relationship.isFollowing = target
        current.followerCount = max(0, current.followerCount + (target ? 1 : -1))
        profile = .loaded(current)
        do {
            let persisted = try await services.social.setFollow(userID: userID, following: target)
            if persisted != target { profile = .loaded(before) }
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

    private func globeCard(_ value: PublicProfile) -> some View {
        Button {
            router.push(.globe(userID))
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                GlobeMapView(pins: (travel?.pins ?? []).map(MapPin.init), shadedCountryCodes: Set(travel?.countries.map(\.countryCode) ?? []),
                             style: .globe, interactive: false)
                    .frame(height: 230)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(value.countryCount) \(value.countryCount == 1 ? "country" : "countries") · \(value.cityCount) \(value.cityCount == 1 ? "city" : "cities")")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(travelError ?? "All-time places visited")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.left.and.arrow.down.right").foregroundStyle(Theme.accent)
                }
                .padding(Theme.Spacing.m)
            }
            .background(Theme.raisedCard)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.hairline.opacity(0.5)))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .accessibilityLabel("Travel globe: \(value.countryCount) countries, \(value.cityCount) cities. Opens the full globe.")
        .accessibilityIdentifier("mini-globe")
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
                    Text(value.relationship.isSelf ? "Your rankings and revisits appear here after you log them."
                                                   : "\(value.member.displayName) hasn't posted any rankings yet.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityIdentifier("profile-activity-empty")
                } else {
                    ForEach(activity.items) { item in
                        FeedCard(item: item, likePending: activity.likePending.contains(item.id),
                                 onLike: { liked in Task { await activity.setLike(item.id, liked: liked) } })
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
