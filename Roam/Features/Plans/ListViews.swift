import SwiftUI

/// Custom lists: collections of places, separate from trips and the wishlist. Your lists, then lists friends sent you, each
/// as a card of standard rows, with New list as a full-width bubble.
struct PlaceListsView: View {
    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @State private var lists: LoadPhase<[PlaceList]> = .idle
    @State private var received: [DirectShare] = []
    @State private var creating = false
    @State private var newTitle = ""
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Text("Lists").font(.roamDisplay(.title)).accessibilityAddTraits(.isHeader)
                switch lists {
                case .idle, .loading: SkeletonList(rows: 3)
                case .failed(let message): InlineRetryView(message: message) { Task { await load() } }
                case .loaded(let value):
                    if !value.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(value) { list in
                                ListRow(list: list) { router.push(.list(list.id)) }
                                    .accessibilityIdentifier("list-\(list.title)")
                                if list.id != value.last?.id { RowSeparator() }
                            }
                        }
                        .roamCard(padding: Theme.Spacing.m)
                    }
                    newListBubble
                }
                if !received.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("Sent to you").font(.roamTitle(.title3)).accessibilityAddTraits(.isHeader)
                        VStack(spacing: 0) {
                            ForEach(received) { share in
                                ReceivedShareRow(share: share)
                                if share.id != received.last?.id { RowSeparator() }
                            }
                        }
                        .roamCard(padding: Theme.Spacing.m)
                    }
                }
                if let error { Text(error).font(.footnote).foregroundStyle(Roam.signal) }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.s)
        }
        .contentMargins(.bottom, RoamTabBar.reservedHeight + Theme.Spacing.l, for: .scrollContent)
        .background(Roam.paper)
        .navigationBarTitleDisplayMode(.inline)
        .alert("New list", isPresented: $creating) {
            TextField("Name", text: $newTitle).accessibilityIdentifier("list-title")
            Button("Create") { Task { await create() } }
            Button("Cancel", role: .cancel) {}
        }
        .task { await load() }
        .refreshable { await load() }
        .screenIdentifier("place-lists")
    }

    /// The standard full-width bubble, in the list colour.
    private var newListBubble: some View {
        Button { newTitle = ""; creating = true } label: {
            Label("New list", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .imageScale(.small)
                .foregroundStyle(Roam.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Capsule().fill(Roam.fill))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .tapID("list-new")
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
            let list = try await services.plans.saveList(id: nil, title: newTitle, description: "")
            await load()
            // Straight into the new list, ready to add places.
            router.push(.list(list.id))
        } catch { self.error = error.roamMessage }
    }
}

/// A list as a standard row: a list mark, its name, and how many places (and whose, when it's a friend's).
private struct ListRow: View {
    let list: PlaceList
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "list.bullet")
                    .font(.headline)
                    .foregroundStyle(Roam.ink)
                    .frame(width: 48, height: 48)
                    .background(Roam.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: -2) {
                    Text(list.title).font(.headline).lineLimit(1).truncationMode(.tail)
                    Text(subtitle).font(.footnote).foregroundStyle(Roam.inkMuted).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Roam.inkMuted)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Roam.ink)
            .padding(.vertical, Theme.Spacing.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        let count = list.itemCount == 1 ? "1 place" : "\(list.itemCount) places"
        return list.isOwn ? count : "\(list.owner.displayName) · \(count)"
    }
}

/// One list, laid out like the app's other pages: its name (with an edit pencil on your own), whose it is as a small chip
/// on a friend's, then its places as standard rows in one card (swipe to remove).
/// Add a place opens the worldwide place search; Send and Delete are round buttons at the top right.
struct PlaceListDetailView: View {
    let listID: UUID

    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var detail: LoadPhase<PlaceListDetail> = .idle
    @State private var showsShare = false
    @State private var addingPlaces = false
    @State private var renaming = false
    @State private var newTitle = ""
    @State private var confirmingDelete = false
    @State private var actionError: String?
    /// Scrolled past the big name, so the small one shows at the top.
    @State private var scrolledPastTitle = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                switch detail {
                case .idle, .loading: SkeletonList(rows: 3)
                case .failed(let message): InlineRetryView(message: message) { Task { await load() } }
                case .loaded(let value): content(value)
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.s)
        }
        .contentMargins(.bottom, RoamTabBar.reservedHeight + Theme.Spacing.l, for: .scrollContent)
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 44 } action: { _, past in
            withAnimation(.easeInOut(duration: 0.2)) { scrolledPastTitle = past }
        }
        .background(Roam.paper)
        .navigationTitle(detail.value?.summary.title ?? "List")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(detail.value?.summary.title ?? "").font(.headline)
                    .opacity(scrolledPastTitle ? 1 : 0).accessibilityHidden(!scrolledPastTitle)
            }
            if detail.value?.summary.isOwn == true {
                // Send (indigo) to the left of the bin. A list is private: only friends you send it to can open it.
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsShare = true } label: { Image(systemName: "paperplane").foregroundStyle(.indigo) }
                        .accessibilityLabel("Send list")
                        .tapID("list-send")
                }
                // Two separate round buttons rather than one shared capsule.
                if #available(iOS 26.0, *) { ToolbarSpacer(.fixed, placement: .topBarTrailing) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) { confirmingDelete = true } label: { Image(systemName: "trash").foregroundStyle(.red) }
                        // Attached to the bin, so the confirmation pops up from it.
                        .confirmationDialog("Delete this list?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                            Button("Delete", role: .destructive) {
                                Task {
                                    do { try await services.plans.deleteList(id: listID); dismiss() }
                                    catch { actionError = error.roamMessage }
                                }
                            }
                        } message: {
                            Text("The places themselves stay in Roam.")
                        }
                        .accessibilityLabel("Delete list")
                        .accessibilityIdentifier("list-delete")
                }
            }
        }
        .sheet(isPresented: $showsShare) {
            ShareSheet(target: .list(listID), title: detail.value?.summary.title ?? "this list").presentationBackground(Roam.paper)
        }
        .sheet(isPresented: $addingPlaces, onDismiss: { Task { await load() } }) {
            AddPlacesToListSheet(listID: listID, inList: Set(detail.value?.items.map(\.id) ?? []))
        }
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
        .task { await load() }
        .refreshable { await load() }
        .screenIdentifier("place-list-detail")
    }

    @ViewBuilder private func content(_ value: PlaceListDetail) -> some View {
        let own = value.summary.isOwn
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .center, spacing: Theme.Spacing.s) {
                Text(value.summary.title).font(.roamDisplay(.title)).lineLimit(2).minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
                if own {
                    Button { newTitle = value.summary.title; renaming = true } label: {
                        Image(systemName: "square.and.pencil").font(.title2).foregroundStyle(Roam.ink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Rename list")
                    .tapID("list-rename")
                }
            }
            // A friend's list says whose, as a small chip that opens their profile.
            if !own { ownerChip(value.summary.owner) }
            if !value.summary.description.isEmpty {
                Text(value.summary.description).font(.body).foregroundStyle(Roam.inkMuted)
            }
        }
        if let actionError { Text(actionError).font(.footnote).foregroundStyle(Roam.signal) }
        if !value.items.isEmpty {
            VStack(spacing: 0) {
                ForEach(value.items) { item in
                    SwipeToDelete(disabled: !own) { Task { await remove(item) } } content: {
                        SocialNavigationRow(title: item.experience.name, symbol: "mappin",
                                            subtitle: item.note.isEmpty ? item.experience.areaLine : item.note, place: item.experience) {
                            router.push(.experience(item.id))
                        }
                    }
                    if item.id != value.items.last?.id { RowSeparator() }
                }
            }
            .roamCard(padding: Theme.Spacing.m)
            .accessibilityIdentifier("list-places")
        } else if !own {
            Text("No places yet.").font(.subheadline).foregroundStyle(Roam.inkMuted)
        }
        if own { addPlaceBubble }
    }

    /// Their picture and name in a slim grey capsule, like the city chip.
    private func ownerChip(_ owner: MemberSummary) -> some View {
        Button { router.push(.member(owner.id)) } label: {
            HStack(spacing: 6) {
                AvatarView(member: owner, size: 20)
                Text(owner.displayName).font(.subheadline.weight(.medium)).lineLimit(1)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(Roam.inkMuted)
            }
            .foregroundStyle(Roam.ink)
            .padding(.leading, 3)
            .padding(.trailing, 10)
            .frame(height: 26)
            .background(Capsule().fill(Roam.fill))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(owner.displayName)'s list")
        .tapID("list-owner")
    }

    /// Green full-width bubble under the places: opens the place search.
    private var addPlaceBubble: some View {
        Button { addingPlaces = true } label: {
            Label("Add a place", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .imageScale(.small)
                .foregroundStyle(PlaceState.visited.markerColor)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Capsule().fill(PlaceState.visited.markerColor.opacity(0.15)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .tapID("list-add-place")
    }

    private func load() async {
        if detail.value == nil { detail = .loading }
        do { detail = .loaded(try await services.plans.list(id: listID)); actionError = nil }
        catch { if detail.value == nil { detail = .failed(error.roamMessage) } else { actionError = error.roamMessage } }
    }

    private func remove(_ item: PlaceListItem) async {
        do {
            try await services.plans.setListItem(listID: listID, experienceID: item.id, note: item.note, present: false)
            await load()
        } catch { actionError = error.roamMessage }
    }
}

/// Add places to a list: the worldwide place search (search 1, places only). Tapping a result adds it, with a tick; tapping
/// it again takes it back off. The × closes.
struct AddPlacesToListSheet: View {
    let listID: UUID
    @State var inList: Set<UUID>

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var placeSearch = PlaceSearch()
    @State private var query = ""
    @State private var error: String?
    @FocusState private var searchFocused: Bool

    private var hasQuery: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    if let error { Text(error).font(.footnote).foregroundStyle(Roam.signal) }
                    if hasQuery {
                        PlaceSearchResults(query: query, placeSearch: placeSearch, kinds: .places, isPicked: isPicked) { pick in
                            Task { await toggle(pick) }
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.s)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Roam.paper)
            .safeAreaInset(edge: .top, spacing: 0) {
                SearchSheetBar(prompt: "Add a place", text: $query, focus: $searchFocused, identifier: "list-add-search") { dismiss() }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { searchFocused = true }
        }
        .roamSheetStyle()
        .task(id: query) { await placeSearch.run(query, services: services) }
        .screenIdentifier("list-add-places")
    }

    private func isPicked(_ pick: PlaceSearchPick) -> Bool {
        switch pick {
        case .experience(let place): return inList.contains(place.id)
        case .place(let hit): return hit.experience.map { inList.contains($0.id) } ?? false
        default: return false
        }
    }

    private func toggle(_ pick: PlaceSearchPick) async {
        do {
            let place: ExperienceSummary
            switch pick {
            case .experience(let known): place = known
            case .place(let hit): place = try await placeSearch.resolve(hit)
            default: return
            }
            let adding = !inList.contains(place.id)
            try await services.plans.setListItem(listID: listID, experienceID: place.id, note: "", present: adding)
            if adding { inList.insert(place.id) } else { inList.remove(place.id) }
            error = nil
        } catch { self.error = error.roamMessage }
    }
}

/// Add a place to one of your lists, from the place's page: your lists as standard rows (tapping one adds it), a new list
/// by name, and an optional note.
struct AddToListSheet: View {
    let experienceID: UUID
    let placeName: String

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var lists: LoadPhase<[PlaceList]> = .idle
    @State private var note = ""
    @State private var newTitle = ""
    @State private var error: String?
    @FocusState private var focusedField: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    Text("Add to a list").font(.roamTitle()).accessibilityAddTraits(.isHeader)
                    switch lists {
                    case .idle, .loading: SkeletonList(rows: 2)
                    case .failed(let message): InlineRetryView(message: message) { Task { await loadLists() } }
                    case .loaded(let value):
                        if !value.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(value) { list in
                                    ListRow(list: list) { Task { await add(to: list.id) } }
                                        .accessibilityIdentifier("add-to-list-\(list.title)")
                                    if list.id != value.last?.id { RowSeparator() }
                                }
                            }
                            .roamCard(padding: Theme.Spacing.m)
                        }
                    }
                    HStack(spacing: Theme.Spacing.s) {
                        TextField("New list", text: $newTitle)
                            .focused($focusedField)
                            .textInputAutocapitalization(.never)
                            .accessibilityIdentifier("add-to-list-title")
                        Button("Create") { Task { await createAndAdd() } }
                            .font(.subheadline.weight(.semibold))
                            .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .roamCard()
                    TextField("Add a note (optional)", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($focusedField)
                        .textInputAutocapitalization(.never)
                        .roamCard()
                    if let error { Text(error).font(.footnote).foregroundStyle(Roam.signal) }
                }
                .padding(Theme.Spacing.l)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Roam.paper)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
            }
            .task { await loadLists() }
        }
        .roamSheetStyle()
        .presentationDetents([.medium, .large])
    }

    private func loadLists() async {
        do { lists = .loaded(try await services.plans.myLists().filter(\.isOwn)) }
        catch { lists = .failed(error.roamMessage) }
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
    /// Each friend's send has its own operation ID for this note, so a retry never sends twice; friends it already reached
    /// are skipped.
    @State private var operations: [UUID: (note: String, operation: UUID)] = [:]
    @State private var sent: Set<UUID> = []
    @FocusState private var noteFocused: Bool
    @State private var noteFrame: CGRect = .zero

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text(title).font(.roamTitle()).accessibilityAddTraits(.isHeader)
                    // Pick as many friends as you like.
                    FriendPickerRows(selection: $selection, multiple: true)
                    TextField("Add a note (optional)", text: $message, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($noteFocused)
                        .roamCard()
                        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { noteFrame = $0 }
                        .accessibilityIdentifier("share-message")
                    if let error { Text(error).font(.footnote).foregroundStyle(Roam.signal) }
                }
                .disabled(sending)
                .padding(Theme.Spacing.l)
            }
            .scrollDismissesKeyboard(.interactively)
            // Tapping anywhere off the note drops the cursor.
            .simultaneousGesture(SpatialTapGesture(coordinateSpace: .global).onEnded { tap in
                if !noteFrame.contains(tap.location) { noteFocused = false }
            })
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
                        if sending { ProgressView() } else { Text(selection.count > 1 ? "Send to \(selection.count) friends" : "Send").fontWeight(.semibold) }
                    }
                    .frame(maxWidth: .infinity, minHeight: Theme.minimumHitTarget)
                }
                .buttonStyle(.plain)
                .floatingBubble(Capsule())
                .disabled(selection.isEmpty || sending || message.count > 500)
                .tapID("share-send")
                .padding(Theme.Spacing.l)
            }
        }
        .interactiveDismissDisabled(sending)
        .roamSheetStyle()
    }

    private func send() async {
        guard !sending, !selection.isEmpty else { return }
        let note = message.trimmingCharacters(in: .whitespacesAndNewlines)
        sending = true
        error = nil
        defer { sending = false }
        for recipient in selection.sorted(by: { $0.uuidString < $1.uuidString }) where !sent.contains(recipient) {
            let operation = operations[recipient].flatMap { $0.note == note ? $0.operation : nil } ?? UUID()
            operations[recipient] = (note, operation)
            do {
                try await services.plans.share(target, with: recipient, message: note, operationID: operation)
                sent.insert(recipient)
            } catch {
                self.error = session.handle(error)
                return
            }
        }
        dismiss()
    }
}
