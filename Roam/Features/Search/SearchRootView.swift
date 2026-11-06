import SwiftUI

/// S03: Experiences / Members search. Query, segment and results persist while switching tabs.
struct SearchRootView: View {
    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @State private var segment: SearchSegment = .experiences
    @State private var experienceModel: ExperienceSearchModel?
    @State private var memberModel: MemberSearchModel?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Search for", selection: $segment) {
                ForEach(SearchSegment.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.s)
            .accessibilityIdentifier("search-segment")
            if let experienceModel, let memberModel {
                if segment == .experiences {
                    ExperienceSearchView(model: experienceModel)
                } else {
                    MemberSearchView(model: memberModel)
                }
            }
        }
        .background(Theme.groupedCanvas)
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if experienceModel == nil { experienceModel = ExperienceSearchModel(services: services) }
            if memberModel == nil { memberModel = MemberSearchModel(services: services) }
            if let request = router.searchSegmentRequest { segment = request; router.searchSegmentRequest = nil }
        }
        .onChange(of: router.searchSegmentRequest) { _, request in
            if let request { segment = request; router.searchSegmentRequest = nil }
        }
        .screenIdentifier("search-root")
    }
}

/// Search field with clear button and 44-pt targets.
struct SearchField: View {
    let prompt: String
    @Binding var text: String
    var identifier: String
    var dismissKeyboardToken = 0
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondaryText).accessibilityHidden(true)
            TextField(prompt, text: $text)
                .focused($isFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier(identifier)
                .onChange(of: dismissKeyboardToken) { _, _ in isFocused = false }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.secondaryText)
                        .frame(width: Theme.minimumHitTarget, height: Theme.minimumHitTarget)
                }
                .accessibilityLabel("Clear search")
                .accessibilityIdentifier("\(identifier)-clear")
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .frame(minHeight: Theme.minimumHitTarget)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.raisedCard))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.hairline.opacity(0.6)))
    }
}

/// "Near Lisbon, Portugal" context chip that opens the destination picker.
struct DestinationChip: View {
    let destination: Destination?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                // Wraps so "Near Portland, Oregon, United States" stays whole beside Explore's location button.
                Text(destination.map { "Near \($0.displayName)" } ?? "Anywhere — choose a destination")
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.caption)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, 6)
            .frame(minHeight: Theme.minimumHitTarget)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accentFill))
        }
        .accessibilityLabel(destination.map { "Search near \($0.displayName). Change destination" } ?? "Choose a destination")
        .accessibilityIdentifier("destination-chip")
    }
}

struct ExperienceSearchView: View {
    @Bindable var model: ExperienceSearchModel
    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Environment(DestinationStore.self) private var destinations
    @Environment(LibraryStore.self) private var library
    @Environment(SessionStore.self) private var session
    @State private var openError: String?
    @State private var pendingSaves: Set<String> = []
    @State private var pendingLogs: Set<String> = []
    @State private var dismissKeyboardToken = 0

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            SearchField(prompt: "Restaurants, trails, museums, stays…", text: $model.query, identifier: "experience-search-field", dismissKeyboardToken: dismissKeyboardToken)
            DestinationChip(destination: destinations.search) { router.sheet = .destinationPicker(.search) }
            if let message = openError ?? library.lastError {
                InlineRetryView(message: message, retryTitle: "Dismiss") { openError = nil; library.clearError() }
            }
            content
        }
        .padding(.horizontal, Theme.Spacing.l)
        .onChange(of: library.revision) { _, _ in Task { await model.refreshMatches() } }
        .task(id: "\(model.query)|\(destinations.search?.id ?? "-")") {
            try? await Task.sleep(for: Limits.searchDebounce)
            guard !Task.isCancelled else { return }
            await model.search(model.query, near: destinations.search)
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle:
            ScrollView {
                EmptyStateView(systemImage: "magnifyingglass", title: "Find a place",
                               message: "Search by name or type — a café, a trail, a museum, a town for a day trip. Results come from Apple Maps.")
            }
        case .loading:
            ScrollView { SkeletonList(rows: 6) }
        case .failed(let message):
            ScrollView {
                InlineRetryView(message: message) { Task { await model.search(model.query, near: destinations.search) } }
            }
        case .noResults:
            ScrollView {
                EmptyStateView(systemImage: "mappin.slash", title: "No places found",
                               message: "Nothing matches “\(model.lastQuery)”\(destinations.search.map { " near \($0.name)" } ?? ""). Check the spelling or change the destination.",
                               primaryTitle: "Change destination", primaryAction: { router.sheet = .destinationPicker(.search) })
                    .accessibilityIdentifier("search-no-results")
            }
        case .results:
            List { Group {
                if let message = model.refreshError {
                    InlineRetryView(message: message) { Task { await model.search(model.query, near: destinations.search) } }
                        .accessibilityIdentifier("experience-search-refresh-error")
                    if !model.hits.isEmpty {
                        Text("Showing the last successful results for “\(model.lastQuery)”. The new query or destination has not loaded yet.")
                            .font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                }
                if model.isRefreshing {
                    HStack { ProgressView(); Text("Updating…").font(.footnote).foregroundStyle(Theme.secondaryText) }
                }
                ForEach(model.hits) { hit in
                    row(hit)
                        .listRowBackground(Theme.raisedCard)
                }
            }
            .listRowBackground(Roam.paperRaised)
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.immediately)
            .accessibilityIdentifier("search-results")
        }
    }

    private func row(_ hit: SearchHit) -> some View {
        let experience = hit.experience
        let rated = experience.map { library.ratedCategory($0.id) != nil || $0.viewer.isRated } ?? false
        let saveState: SaveActionState = {
            guard let experience else { return .notSaved }
            if rated { return .alreadyBeen }
            return library.saveState(for: experience.id)
        }()
        return ExperienceRow(
            name: hit.candidate.name, category: hit.category,
            area: [hit.candidate.locality, hit.candidate.countryName].compactMap { $0 }.uniqued().joined(separator: ", "),
            score: experience?.viewer.myScore, scoreSource: .you,
            secondaryScore: experience?.followingScore,
            secondarySource: experience.map { .following(count: $0.followingCount) },
            statusLine: hit.candidate.isLocality ? "Town or city · Day trip destination" : hit.candidate.address,
            saveState: saveState, logTitle: rated ? "Add visit" : "Log",
            onOpen: { Task { await open(hit) } },
            onSave: { Task { await toggleSave(hit) } },
            onLog: { Task { await log(hit) } })
    }

    private func open(_ hit: SearchHit) async {
        do {
            let summary = try await model.resolve(hit)
            router.push(.experience(summary.id))
        } catch {
            openError = session.handle(error)
        }
    }

    private func log(_ hit: SearchHit) async {
        guard !pendingLogs.contains(hit.id) else { return }
        dismissKeyboardToken += 1
        pendingLogs.insert(hit.id)
        defer { pendingLogs.remove(hit.id) }
        do {
            let summary = try await model.resolve(hit)
            router.sheet = .log(try await services.makeLogRequest(experienceID: summary.id))
        } catch { openError = session.handle(error) }
    }

    private func toggleSave(_ hit: SearchHit) async {
        guard !pendingSaves.contains(hit.id) else { return }
        pendingSaves.insert(hit.id)
        defer { pendingSaves.remove(hit.id) }
        do {
            let summary = try await model.resolve(hit)
            await library.setBookmark(summary.id, saved: !library.isBookmarked(summary.id))
        } catch {
            openError = session.handle(error)
        }
    }
}

struct MemberSearchView: View {
    @Bindable var model: MemberSearchModel
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            SearchField(prompt: "Name or @handle", text: $model.query, identifier: "member-search-field")
            if let message = model.followError {
                InlineRetryView(message: message, retryTitle: "Dismiss") { model.clearFollowError() }
            }
            switch model.phase {
            case .idle:
                ScrollView {
                    EmptyStateView(systemImage: "person.2", title: "Find people", message: "Search by name or @handle, then add them as a friend.")
                }
            case .loading:
                ScrollView { SkeletonList(rows: 5) }
            case .failed(let message):
                ScrollView { InlineRetryView(message: message) { Task { await model.search(model.query) } } }
            case .loaded where model.rows.isEmpty:
                ScrollView {
                    EmptyStateView(systemImage: "person.crop.circle.badge.questionmark", title: "Nobody found",
                                   message: "No one matches “\(model.lastQuery)”.")
                        .accessibilityIdentifier("member-no-results")
                }
            case .loaded:
                List { Group {
                    if let message = model.refreshError {
                        InlineRetryView(message: message) { Task { await model.search(model.query) } }
                            .accessibilityIdentifier("member-search-refresh-error")
                        if model.query.trimmingCharacters(in: .whitespacesAndNewlines) != model.lastQuery {
                            Text("Showing the previous results for “\(model.lastQuery)” until the new search succeeds.")
                                .font(.footnote).foregroundStyle(Theme.secondaryText)
                        }
                    }
                    if model.isRefreshing {
                        HStack { ProgressView(); Text("Updating…").font(.footnote).foregroundStyle(Theme.secondaryText) }
                    }
                    ForEach(model.rows) { row in
                        MemberRowView(member: row.member, subtitle: row.friendState == .received ? "Wants to be friends" : nil,
                                      followState: FollowButtonState(row.friendState, pending: model.pendingFollows.contains(row.id)),
                                      onOpen: { router.push(.member(row.id)) },
                                      onToggleFollow: { Task { await model.toggleFollow(row) } })
                    }
                    PaginationFooter(isLoading: model.loadingMore, errorMessage: model.pageError,
                                     hasMore: model.nextCursor != nil && !model.isRefreshing) {
                        Task { await model.loadMore() }
                    }
                }
                .listRowBackground(Roam.paperRaised)
                }
                .listStyle(.plain)
                .accessibilityIdentifier("member-results")
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .task(id: model.query) {
            try? await Task.sleep(for: Limits.searchDebounce)
            guard !Task.isCancelled else { return }
            await model.search(model.query)
        }
    }
}
