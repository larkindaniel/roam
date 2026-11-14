import SwiftUI

/// Search 3 of 3: accounts, by name or @handle. Finding people searches everyone, with an Add button on each; picking
/// friends (Send, trip invitations, "went with") searches only your friends and ticks the ones you choose.
struct AccountSearchResults: View {
    let query: String
    /// When set, only your friends are listed and tapping one ticks it.
    var picking: Binding<Set<UUID>>? = nil
    var multiple = false
    var excluding: Set<UUID> = []

    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @State private var everyone: MemberSearchModel?
    @State private var friends: LoadPhase<[MemberRow]> = .idle
    @State private var friendsCursor: String?
    @State private var paging = false
    @State private var pageError: String?

    private var hasQuery: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        Group {
            if let picking { friendRows(picking) } else { everyoneRows }
        }
        .task(id: query) {
            if picking == nil, !hasQuery { everyone?.query = ""; return }
            if hasQuery { try? await Task.sleep(for: Limits.searchDebounce) }
            guard !Task.isCancelled else { return }
            if picking != nil {
                await loadFriends(query)
            } else {
                if everyone == nil { everyone = MemberSearchModel(services: services) }
                await everyone?.search(query)
            }
        }
    }

    // MARK: Everyone

    @ViewBuilder private var everyoneRows: some View {
        if !hasQuery {
            EmptyStateView(systemImage: "person.2", title: "Find people", message: "Search by name or @handle, then add them as a friend.")
        } else if let model = everyone {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                if let message = model.followError {
                    InlineRetryView(message: message, retryTitle: "Dismiss") { model.clearFollowError() }
                }
                switch model.phase {
                case .idle, .loading:
                    SkeletonList(rows: 4)
                case .failed(let message):
                    InlineRetryView(message: message) { Task { await model.search(query) } }
                case .loaded where model.rows.isEmpty:
                    Text("No one matches \u{201C}\(model.lastQuery)\u{201D}.").font(.subheadline).foregroundStyle(Roam.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("member-no-results")
                case .loaded:
                    VStack(spacing: 0) {
                        ForEach(model.rows) { row in
                            MemberRowView(member: row.member, subtitle: row.friendState == .received ? "Wants to be friends" : nil,
                                          followState: FollowButtonState(row.friendState, pending: model.pendingFollows.contains(row.id)),
                                          onOpen: MemberProfiles.available ? { router.push(.member(row.id)) } : nil,
                                          onToggleFollow: { Task { await model.toggleFollow(row) } })
                            if row.id != model.rows.last?.id { RowSeparator() }
                        }
                    }
                    .roamCard(padding: Theme.Spacing.m)
                    .accessibilityIdentifier("member-results")
                    PaginationFooter(isLoading: model.loadingMore, errorMessage: model.pageError,
                                     hasMore: model.nextCursor != nil && !model.isRefreshing) {
                        Task { await model.loadMore() }
                    }
                }
            }
        } else {
            SkeletonList(rows: 4)
        }
    }

    // MARK: Your friends

    @ViewBuilder private func friendRows(_ selection: Binding<Set<UUID>>) -> some View {
        switch friends {
        case .idle, .loading:
            SkeletonList(rows: 3)
        case .failed(let message):
            InlineRetryView(message: message) { Task { await loadFriends(query) } }
        case .loaded(let rows):
            let visible = rows.filter { !excluding.contains($0.id) }
            VStack(spacing: 0) {
                ForEach(visible) { row in
                    let picked = selection.wrappedValue.contains(row.id)
                    Button {
                        if picked { selection.wrappedValue.remove(row.id) }
                        else if multiple { selection.wrappedValue.insert(row.id) }
                        else { selection.wrappedValue = [row.id] }
                    } label: {
                        HStack(spacing: Theme.Spacing.m) {
                            AvatarView(member: row.member, size: 48)
                            VStack(alignment: .leading, spacing: -2) {
                                Text(row.member.displayName).font(.headline).lineLimit(1)
                                Text("@\(row.member.handle)").font(.footnote).foregroundStyle(Roam.inkMuted).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            if picked { Image(systemName: "checkmark") }
                        }
                        .padding(.vertical, Theme.Spacing.s)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(picked ? .isSelected : [])
                    .accessibilityIdentifier("pick-friend-\(row.member.handle)")
                    if row.id != visible.last?.id { RowSeparator() }
                }
                if visible.isEmpty && friendsCursor == nil {
                    Text(hasQuery ? "No friends match \u{201C}\(query)\u{201D}." : "No friends to choose")
                        .font(.footnote).foregroundStyle(Roam.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Theme.Spacing.s)
                }
            }
            .roamCard(padding: Theme.Spacing.m)
            PaginationFooter(isLoading: paging, errorMessage: pageError, hasMore: friendsCursor != nil) {
                Task { await loadFriends(query, cursor: friendsCursor) }
            }
        }
    }

    private func loadFriends(_ search: String, cursor: String? = nil) async {
        guard let userID = session.userID else { return }
        if cursor == nil {
            friends = .loading
            friendsCursor = nil
            pageError = nil
        } else {
            guard !paging else { return }
            paging = true
        }
        defer { if cursor != nil { paging = false } }
        do {
            let page = try await services.social.following(of: userID, query: search, cursor: cursor)
            guard search == query, !Task.isCancelled else { return }
            var rows = cursor == nil ? [] : friends.value ?? []
            var seen = Set(rows.map(\.id))
            rows += page.items.filter { $0.friendState == .friends && seen.insert($0.id).inserted }
            friends = .loaded(rows)
            friendsCursor = page.nextCursor
            pageError = nil
        } catch {
            guard search == query, !Task.isCancelled else { return }
            let message = session.handle(error)
            if cursor == nil { friends = .failed(message) } else { pageError = message }
        }
    }
}

/// Find people: the accounts search on a page of its own, from the Friends tab.
struct FindPeopleView: View {
    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            AccountSearchResults(query: query)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.s)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) {
            RoamSearchField(prompt: "Name or @handle", text: $query, focus: $focused, identifier: "member-search-field")
                .frame(height: 44)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.s)
                .background(Roam.paper)
        }
        .background(Roam.paper)
        .navigationTitle("Find people")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true }
        .screenIdentifier("find-people")
    }
}
