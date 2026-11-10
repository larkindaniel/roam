import SwiftUI

/// Search and paging shared by Send, trip invitations and the With picker.
struct FriendPickerRows: View {
    @Binding var selection: Set<UUID>
    var multiple = false
    var excluding: Set<UUID> = []

    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @State private var query = ""
    @State private var phase: LoadPhase<[MemberRow]> = .idle
    @State private var nextCursor: String?
    @State private var paging = false
    @State private var pageError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "magnifyingglass").accessibilityHidden(true)
                TextField("Search friends", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .frame(minHeight: Theme.minimumHitTarget)
            .background(Roam.fill, in: Capsule())
            switch phase {
            case .idle, .loading:
                SkeletonList(rows: 3)
            case .failed(let message):
                InlineRetryView(message: message) { Task { await load(query) } }
            case .loaded(let rows):
                let visible = rows.filter { !excluding.contains($0.id) }
                VStack(spacing: 0) {
                    ForEach(visible) { row in
                        Button {
                            if selection.contains(row.id) { selection.remove(row.id) }
                            else if multiple { selection.insert(row.id) }
                            else { selection = [row.id] }
                        } label: {
                            HStack(spacing: Theme.Spacing.m) {
                                AvatarView(member: row.member, size: 48)
                                VStack(alignment: .leading, spacing: -2) {
                                    Text(row.member.displayName).font(.headline).lineLimit(1)
                                    Text("@\(row.member.handle)").font(.footnote).foregroundStyle(Roam.inkMuted).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                if selection.contains(row.id) { Image(systemName: "checkmark") }
                            }
                            .padding(.vertical, Theme.Spacing.s)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selection.contains(row.id) ? .isSelected : [])
                        .accessibilityIdentifier("pick-friend-\(row.member.handle)")
                        if row.id != visible.last?.id { RowSeparator() }
                    }
                    if visible.isEmpty && nextCursor == nil {
                        Text(query.isEmpty ? "No friends to choose" : "No matching friends")
                            .font(.footnote).foregroundStyle(Roam.inkMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, Theme.Spacing.s)
                    }
                }
                .roamCard(padding: Theme.Spacing.m)
                PaginationFooter(isLoading: paging, errorMessage: pageError, hasMore: nextCursor != nil) {
                    Task { await load(query, cursor: nextCursor) }
                }
            }
        }
        .task(id: query) {
            let search = query
            if !search.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
            guard !Task.isCancelled else { return }
            await load(search)
        }
    }

    private func load(_ search: String, cursor: String? = nil) async {
        guard let userID = session.userID else { return }
        if cursor == nil {
            phase = .loading
            nextCursor = nil
            pageError = nil
        } else {
            guard !paging else { return }
            paging = true
        }
        defer { if cursor != nil { paging = false } }
        do {
            let page = try await services.social.following(of: userID, query: search, cursor: cursor)
            guard search == query, !Task.isCancelled else { return }
            var rows = cursor == nil ? [] : phase.value ?? []
            var seen = Set(rows.map(\.id))
            rows += page.items.filter { $0.friendState == .friends && seen.insert($0.id).inserted }
            phase = .loaded(rows)
            nextCursor = page.nextCursor
            pageError = nil
        } catch {
            guard search == query, !Task.isCancelled else { return }
            let message = session.handle(error)
            if cursor == nil { phase = .failed(message) } else { pageError = message }
        }
    }
}

struct FriendSelectionSheet: View {
    let title: String
    let action: String
    var multiple = false
    var excluding: Set<UUID> = []
    @State var selection: Set<UUID> = []
    let onSelect: (Set<UUID>) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    FriendPickerRows(selection: $selection, multiple: multiple, excluding: excluding)
                        .disabled(saving)
                    if multiple && !selection.isEmpty {
                        Button("Clear selection") { selection.removeAll() }
                            .disabled(saving)
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(Roam.signal) }
                }
                .padding(Theme.Spacing.l)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Roam.paper)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                        .disabled(saving)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await save() }
                } label: {
                    Group {
                        if saving { ProgressView() } else { Text(action).fontWeight(.semibold) }
                    }
                    .frame(maxWidth: .infinity, minHeight: Theme.minimumHitTarget)
                }
                .buttonStyle(.plain)
                .floatingBubble(Capsule())
                .disabled(saving || (!multiple && selection.isEmpty))
                .padding(Theme.Spacing.l)
            }
        }
        .interactiveDismissDisabled(saving)
        .roamSheetStyle()
    }

    private func save() async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        do { try await onSelect(selection); dismiss() }
        catch { self.error = error.roamMessage }
    }
}
