import SwiftUI

/// Custom lists: collections of places, separate from trips and the wishlist.
struct PlaceListsView: View {
    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @State private var lists: LoadPhase<[PlaceList]> = .idle
    @State private var received: [DirectShare] = []
    @State private var creating = false
    @State private var newTitle = ""
    @State private var error: String?

    var body: some View {
        List { Group {
            switch lists {
            case .idle, .loading: Section { SkeletonList(rows: 3) }
            case .failed(let message): Section { InlineRetryView(message: message) { Task { await load() } } }
            case .loaded(let value):
                Section {
                    if value.isEmpty {
                        Text("No lists yet. Make one to collect places worth sharing.")
                            .font(.subheadline).foregroundStyle(Roam.inkMuted)
                            .accessibilityIdentifier("lists-empty")
                    }
                    ForEach(value) { list in
                        SocialNavigationRow(title: list.title, symbol: "list.bullet") { router.push(.list(list.id)) }
                        .accessibilityIdentifier("list-\(list.title)")
                    }
                }
                .listRowBackground(Roam.paperRaised)
            }
            if !received.isEmpty {
                Section("Shared with you") {
                    ForEach(received) { ReceivedShareRow(share: $0) }
                }
                .listRowBackground(Roam.paperRaised)
            }
            if let error { Section { Text(error).foregroundStyle(Roam.signal) }.listRowBackground(Roam.paperRaised) }
        }
        .listRowBackground(Roam.paperRaised)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Roam.paper)
        .navigationTitle("Lists")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New list") { newTitle = ""; creating = true }.accessibilityIdentifier("list-new")
            }
        }
        .alert("New list", isPresented: $creating) {
            TextField("Title", text: $newTitle).accessibilityIdentifier("list-title")
            Button("Create") { Task { await create() } }
            Button("Cancel", role: .cancel) {}
        }
        .task { await load() }
        .refreshable { await load() }
        .screenIdentifier("place-lists")
    }

    private func load() async {
        if lists.value == nil { lists = .loading }
        do {
            async let own = services.plans.myLists()
            async let shares = services.plans.sharedWithMe()
            lists = .loaded(try await own)
            let receivedShares = try await shares
            var seen = Set<UUID>()
            received = receivedShares.filter { $0.list.map { seen.insert($0.id).inserted } ?? false }
        }
        catch { if lists.value == nil { lists = .failed(error.roamMessage) } }
    }

    private func create() async {
        do {
            _ = try await services.plans.saveList(id: nil, title: newTitle, description: "")
            await load()
        } catch { self.error = error.roamMessage }
    }
}

struct PlaceListDetailView: View {
    let listID: UUID

    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var detail: LoadPhase<PlaceListDetail> = .idle
    @State private var showsShare = false
    @State private var showingAccess = false
    @State private var renaming = false
    @State private var newTitle = ""
    @State private var confirmingDelete = false
    @State private var actionError: String?

    var body: some View {
        List { Group {
            switch detail {
            case .idle, .loading: Section { SkeletonList(rows: 3) }
            case .failed(let message): Section { InlineRetryView(message: message) { Task { await load() } } }
            case .loaded(let value):
                Section {
                    Text("By \(value.summary.owner.displayName)").font(.footnote).foregroundStyle(Roam.inkMuted)
                    if !value.summary.description.isEmpty { Text(value.summary.description) }
                    if let actionError { Text(actionError).foregroundStyle(Roam.signal) }
                }
                .listRowBackground(Roam.paperRaised)
                Section {
                    if value.items.isEmpty {
                        Text("No places yet. Open a place and choose Add to list.")
                            .font(.subheadline).foregroundStyle(Roam.inkMuted)
                    }
                    ForEach(value.items) { item in
                        SocialNavigationRow(title: item.experience.name, symbol: "mappin", subtitle: item.note, place: item.experience) {
                            router.push(.experience(item.id))
                        }
                        .swipeActions {
                            if value.summary.isOwn {
                                Button("Remove", role: .destructive) { Task { await remove(item) } }
                            } else {
                                Button("Save") { Task { await library.setBookmark(item.id, saved: true) } }
                            }
                        }
                    }
                }
                .listRowBackground(Roam.paperRaised)
            }
        }
        .listRowBackground(Roam.paperRaised)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Roam.paper)
        .navigationTitle(detail.value?.summary.title ?? "List")
        .toolbar {
            if detail.value?.summary.isOwn == true {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Share with a friend") { showsShare = true }
                        Button("Manage access") { showingAccess = true }
                        Button("Rename") { newTitle = detail.value?.summary.title ?? ""; renaming = true }
                        Button("Delete list", role: .destructive) { confirmingDelete = true }
                    } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("List options")
                }
            }
        }
        .sheet(isPresented: $showsShare) {
            ShareSheet(target: .list(listID), title: detail.value?.summary.title ?? "this list").presentationBackground(Roam.paper)
        }
        .sheet(isPresented: $showingAccess) { ListAccessSheet(listID: listID) }
        .alert("Rename list", isPresented: $renaming) {
            TextField("Name", text: $newTitle)
            Button("Save") {
                Task {
                    guard let list = detail.value?.summary else { return }
                    do {
                        _ = try await services.plans.saveList(id: listID, title: newTitle, description: list.description)
                        await load()
                    } catch { actionError = error.roamMessage }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this list?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete list", role: .destructive) {
                Task {
                    do { try await services.plans.deleteList(id: listID); dismiss() }
                    catch { actionError = error.roamMessage }
                }
            }
        } message: {
            Text("The places themselves stay in Roam.")
        }
        .task { await load() }
        .refreshable { await load() }
        .screenIdentifier("place-list-detail")
    }

    private func load() async {
        if detail.value == nil { detail = .loading }
        do { detail = .loaded(try await services.plans.list(id: listID)) }
        catch { if detail.value == nil { detail = .failed(error.roamMessage) } else { actionError = error.roamMessage } }
    }

    private func remove(_ item: PlaceListItem) async {
        do {
            try await services.plans.setListItem(listID: listID, experienceID: item.id, note: item.note, present: false)
            await load()
        } catch { actionError = error.roamMessage }
    }
}

struct AddToListSheet: View {
    let experienceID: UUID
    let placeName: String

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var lists: LoadPhase<[PlaceList]> = .idle
    @State private var note = ""
    @State private var newTitle = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List { Group {
                Section("Note (optional)") {
                    TextField("Why this place?", text: $note, axis: .vertical).textInputAutocapitalization(.never)
                }
                .listRowBackground(Roam.paperRaised)
                Section("Add to") {
                    switch lists {
                    case .idle, .loading: ProgressView()
                    case .failed(let message): Text(message).foregroundStyle(Roam.signal)
                    case .loaded(let value):
                        ForEach(value) { list in
                            Button(list.title) { Task { await add(to: list.id) } }
                                .accessibilityIdentifier("add-to-list-\(list.title)")
                        }
                    }
                    HStack {
                        TextField("New list title", text: $newTitle).accessibilityIdentifier("add-to-list-title")
                        Button("Create") { Task { await createAndAdd() } }
                            .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .listRowBackground(Roam.paperRaised)
                if let error { Section { Text(error).foregroundStyle(Roam.signal) }.listRowBackground(Roam.paperRaised) }
            }
            .listRowBackground(Roam.paperRaised)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Add \(placeName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task {
                do { lists = .loaded(try await services.plans.myLists()) }
                catch { lists = .failed(error.roamMessage) }
            }
        }
        .roamSheetStyle()
        .presentationDetents([.medium, .large])
    }

    private func add(to listID: UUID) async {
        do {
            try await services.plans.setListItem(listID: listID, experienceID: experienceID, note: note, present: true)
            dismiss()
        } catch { self.error = error.roamMessage }
    }

    private func createAndAdd() async {
        do {
            let list = try await services.plans.saveList(id: nil, title: newTitle, description: "")
            await add(to: list.id)
        } catch { self.error = error.roamMessage }
    }
}

private struct ListAccessSheet: View {
    let listID: UUID
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var people: LoadPhase<[MemberSummary]> = .idle
    @State private var pending: UUID?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                switch people {
                case .idle, .loading: SkeletonList(rows: 2)
                case .failed(let message):
                    InlineRetryView(message: message) { Task { await load() } }
                case .loaded(let members):
                    if members.isEmpty {
                        Text("This list is private").foregroundStyle(Roam.inkMuted)
                    }
                    ForEach(members) { member in
                        HStack(spacing: Theme.Spacing.m) {
                            AvatarView(member: member, size: 48)
                            Text(member.displayName).font(.headline)
                            Spacer(minLength: 0)
                            Menu {
                                Button("Remove access", role: .destructive) {
                                    Task { await revoke(member.id) }
                                }
                            } label: {
                                Image(systemName: "ellipsis").frame(minWidth: Theme.minimumHitTarget, minHeight: Theme.minimumHitTarget)
                            }
                            .disabled(pending != nil)
                            .accessibilityLabel("Access for \(member.displayName)")
                        }
                    }
                }
                if let error { Text(error).font(.footnote).foregroundStyle(Roam.signal) }
            }
            .scrollContentBackground(.hidden)
            .background(Roam.paper)
            .navigationTitle("List access")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
            }
            .task { await load() }
        }
        .roamSheetStyle()
    }

    private func load() async {
        do { people = .loaded(try await services.plans.listRecipients(listID: listID)) }
        catch { people = .failed(error.roamMessage) }
    }

    private func revoke(_ recipient: UUID) async {
        guard pending == nil else { return }
        pending = recipient
        error = nil
        defer { pending = nil }
        do {
            try await services.plans.revokeListShare(listID: listID, recipientID: recipient)
            await load()
        } catch { self.error = error.roamMessage }
    }
}

/// Sends a recommendation to an existing friend.
struct ShareSheet: View {
    let target: ShareTarget
    let title: String

    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<UUID> = []
    @State private var message = ""
    @State private var error: String?
    @State private var sending = false
    @State private var submitted: (recipient: UUID, note: String, operation: UUID)?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text(title).font(.roamTitle()).accessibilityAddTraits(.isHeader)
                    FriendPickerRows(selection: $selection)
                    TextField("Add a note (optional)", text: $message, axis: .vertical)
                        .lineLimit(2...5)
                        .roamCard()
                        .accessibilityIdentifier("share-message")
                    if let error { Text(error).font(.footnote).foregroundStyle(Roam.signal) }
                }
                .disabled(sending)
                .padding(Theme.Spacing.l)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Roam.paper)
            .navigationTitle("Send")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .disabled(sending)
                        .accessibilityLabel("Close")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button { Task { await send() } } label: {
                    Group {
                        if sending { ProgressView() } else { Text("Send").fontWeight(.semibold) }
                    }
                    .frame(maxWidth: .infinity, minHeight: Theme.minimumHitTarget)
                }
                .buttonStyle(.plain)
                .floatingBubble(Capsule())
                .disabled(selection.isEmpty || sending || message.count > 500)
                .accessibilityIdentifier("share-send")
                .padding(Theme.Spacing.l)
            }
        }
        .interactiveDismissDisabled(sending)
        .roamSheetStyle()
    }

    private func send() async {
        guard !sending, let recipient = selection.first else { return }
        let note = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let operation = submitted.flatMap { $0.recipient == recipient && $0.note == note ? $0.operation : nil } ?? UUID()
        submitted = (recipient, note, operation)
        sending = true
        error = nil
        defer { sending = false }
        do {
            try await services.plans.share(target, with: recipient, message: note, operationID: operation)
            dismiss()
        } catch { self.error = session.handle(error) }
    }
}
