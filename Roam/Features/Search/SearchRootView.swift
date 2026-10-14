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

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier(identifier)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(width: 36, height: 36)
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
                Text(destination.map { "Near \($0.displayName)" } ?? "Anywhere — choose a destination")
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.caption)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, Theme.Spacing.m)
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
    @Environment(DestinationStore.self) private var destinations
    @Environment(LibraryStore.self) private var library
    @Environment(SessionStore.self) private var session
    @State private var openError: String?

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            SearchField(prompt: "Restaurants, trails, museums, stays…", text: $model.query, identifier: "experience-search-field")
            DestinationChip(destination: destinations.search) { router.sheet = .destinationPicker(.search) }
            if let message = openError ?? library.lastError {
                InlineRetryView(message: message, retryTitle: "Dismiss") { openError = nil; library.clearError() }
            }
            content
        }
        .padding(.horizontal, Theme.Spacing.l)
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
                EmptyStateView(systemImage: "magnifyingglass", title: "Find an experience",
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
            List {
                if model.isRefreshing {
                    HStack { ProgressView(); Text("Updating…").font(.footnote).foregroundStyle(.secondary) }
                }
                ForEach(model.hits) { hit in
                    row(hit)
                        .listRowBackground(Theme.raisedCard)
                }
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
            saveState: saveState,
            onOpen: { Task { await open(hit) } },
            onSave: { Task { await toggleSave(hit) } })
    }

    private func open(_ hit: SearchHit) async {
        do {
            let summary = try await model.resolve(hit)
            router.push(.experience(summary.id))
        } catch {
            openError = session.handle(error)
        }
    }

    private func toggleSave(_ hit: SearchHit) async {
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
            switch model.phase {
            case .idle:
                ScrollView {
                    EmptyStateView(systemImage: "person.2", title: "Find people", message: "Search for travellers by name or @handle and follow them to see their ratings in your feed.")
                }
            case .loading:
                ScrollView { SkeletonList(rows: 5) }
            case .failed(let message):
                ScrollView { InlineRetryView(message: message) { Task { await model.search(model.query) } } }
            case .loaded where model.rows.isEmpty:
                ScrollView {
                    EmptyStateView(systemImage: "person.crop.circle.badge.questionmark", title: "No members found",
                                   message: "No one matches “\(model.query)”.")
                        .accessibilityIdentifier("member-no-results")
                }
            case .loaded:
                List {
                    ForEach(model.rows) { row in
                        MemberRowView(member: row.member, subtitle: row.followsViewer ? "Follows you" : nil,
                                      followState: model.pendingFollows.contains(row.id) ? .pending
                                          : (row.isFollowing ? .following : (row.followsViewer ? .followBack : .follow)),
                                      onOpen: { router.push(.member(row.id)) },
                                      onToggleFollow: { Task { await model.toggleFollow(row) } })
                    }
                    PaginationFooter(isLoading: model.loadingMore, errorMessage: model.pageError, hasMore: model.nextCursor != nil) {
                        Task { await model.loadMore() }
                    }
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
