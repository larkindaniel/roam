import SwiftUI

/// Custom lists: collections of places, separate from trips and the wishlist.
struct PlaceListsView: View {
    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @State private var lists: LoadPhase<[PlaceList]> = .idle
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
                        Button { router.push(.list(list.id)) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(list.title).font(.headline).foregroundStyle(Roam.ink)
                                Text("\(list.itemCount) \(list.itemCount == 1 ? "place" : "places")").font(.footnote).foregroundStyle(Roam.inkMuted)
                            }
                            .frame(minHeight: Theme.minimumHitTarget)
                        }
                        .accessibilityIdentifier("list-\(list.title)")
                    }
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
        .navigationTitle("Custom lists")
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
        do { lists = .loaded(try await services.plans.myLists()) }
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
                        Button { router.push(.experience(item.id)) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.experience.name).font(.headline).foregroundStyle(Roam.ink)
                                if !item.note.isEmpty { Text(item.note).font(.subheadline).foregroundStyle(Roam.ink) }
                            }
                            .frame(minHeight: Theme.minimumHitTarget)
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
                        Button("Delete list", role: .destructive) { confirmingDelete = true }
                    } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("List options")
                }
            }
        }
        .sheet(isPresented: $showsShare) {
            ShareSheet(target: .list(listID), title: detail.value?.summary.title ?? "this list").presentationBackground(Roam.paper)
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
                    TextField("Why this place?", text: $note, axis: .vertical)
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

/// Sends a place, list or trip to one friend with a personal message.
struct ShareSheet: View {
    let target: ShareTarget
    let title: String

    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var friends: LoadPhase<[MemberRow]> = .idle
    @State private var recipient: UUID?
    @State private var message = ""
    @State private var error: String?
    @State private var sending = false
    /// Kept across retries so a repeated send can't create a second share.
    @State private var operationID = UUID()

    var body: some View {
        NavigationStack {
            List { Group {
                Section("Friend") {
                    switch friends {
                    case .idle, .loading: ProgressView()
                    case .failed(let text): Text(text).foregroundStyle(Roam.signal)
                    case .loaded(let rows):
                        if rows.isEmpty { Text("Add a friend first, then you can share with them.").foregroundStyle(Roam.inkMuted) }
                        ForEach(rows) { row in
                            Button {
                                recipient = row.id
                            } label: {
                                HStack {
                                    Text(row.member.displayName).foregroundStyle(Roam.ink)
                                    Spacer()
                                    if recipient == row.id { Image(systemName: "checkmark").foregroundStyle(Roam.ink) }
                                }
                                .frame(minHeight: Theme.minimumHitTarget)
                            }
                            .accessibilityAddTraits(recipient == row.id ? .isSelected : [])
                            .accessibilityIdentifier("share-friend-\(row.member.handle)")
                        }
                    }
                }
                .listRowBackground(Roam.paperRaised)
                Section("Message") {
                    TextField("Why you'd love it", text: $message, axis: .vertical).accessibilityIdentifier("share-message")
                }
                .listRowBackground(Roam.paperRaised)
                if let error { Section { Text(error).foregroundStyle(Roam.signal) }.listRowBackground(Roam.paperRaised) }
            }
            .listRowBackground(Roam.paperRaised)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Share \(title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Share") { Task { await send() } }
                        .disabled(recipient == nil || sending)
                        .accessibilityIdentifier("share-send")
                }
            }
            .task { await load() }
        }
        .roamSheetStyle()
        .presentationDetents([.medium, .large])
    }

    private func load() async {
        guard let me = session.userID else { return }
        do { friends = .loaded(try await services.social.following(of: me, query: "", cursor: nil).items) }
        catch { friends = .failed(error.roamMessage) }
    }

    private func send() async {
        guard let recipient else { return }
        sending = true
        defer { sending = false }
        do {
            try await services.plans.share(target, with: recipient, message: message, operationID: operationID)
            dismiss()
        } catch { self.error = error.roamMessage }
    }
}
