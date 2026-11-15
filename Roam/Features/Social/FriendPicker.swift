import SwiftUI

/// Picking friends for Send, trip invitations and the With picker: the accounts search, limited to your friends.
struct FriendPickerRows: View {
    @Binding var selection: Set<UUID>
    var multiple = false
    var excluding: Set<UUID> = []

    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            RoamSearchField(prompt: "Search friends", text: $query, focus: $focused, identifier: "friend-search")
            AccountSearchResults(query: query, picking: $selection, multiple: multiple, excluding: excluding)
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
                    // The whole pill takes the tap, not just the word.
                    .contentShape(Capsule())
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
