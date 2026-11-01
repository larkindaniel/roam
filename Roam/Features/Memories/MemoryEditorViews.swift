import SwiftUI

struct VisitMemoryEditor: View {
    let visit: Visit
    var destinationTimeZone: String? = nil
    var onSaved: (Visit) -> Void = { _ in }
    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var model: VisitMemoryEditorModel?
    @State private var photos: PhotoDraftModel?
    @State private var showsPhotos = false
    @State private var showsPendingClose = false
    @State private var photoError: String?
    @State private var audience: Audience?
    @State private var audienceError: String?

    var body: some View {
        NavigationStack {
            Group {
                if let model { form(model) }
                else { ProgressView("Loading your memory…") }
            }
            .navigationTitle("Edit visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if model?.pending != nil { showsPendingClose = true }
                        else {
                            Task { await photos?.discard(); model?.discard(); dismiss() }
                        }
                    }.disabled(model?.isSaving == true).accessibilityIdentifier("memory-editor-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model?.pending == nil ? "Done" : "Retry save") { Task { await save() } }
                        .disabled(model == nil || model?.isSaving == true || (model?.pending == nil && photos?.canCommit == false))
                        .accessibilityIdentifier("memory-editor-done")
                }
            }
            .confirmationDialog("Saving wasn't confirmed", isPresented: $showsPendingClose, titleVisibility: .visible) {
                Button("Keep pending save") { dismiss() }
                Button("Continue checking", role: .cancel) {}
            } message: { Text("Keep the exact pending changes so the original save can be checked safely later.") }
            .interactiveDismissDisabled(model?.isDirty == true || model?.isSaving == true)
            .task {
                guard model == nil, let owner = account.userID else { return }
                model = VisitMemoryEditorModel(visit: visit, ownerID: owner, memories: services.memories,
                                               storage: services.storage, currentAccount: { account.userID },
                                               destinationTimeZone: destinationTimeZone)
                photos = PhotoDraftModel(ownerID: owner, draftID: "visit-edit-\(visit.id.uuidString.lowercased())-photos",
                                         existingMedia: visit.media, storage: services.storage, media: services.media,
                                         currentAccount: { account.userID })
            }
        }.screenIdentifier("memory-editor")
    }

    private func form(_ model: VisitMemoryEditorModel) -> some View {
        @Bindable var model = model
        return Form {
            Section {
                TextEditor(text: $model.note).frame(minHeight: 180).disabled(!model.canEdit)
                    .accessibilityIdentifier("memory-note-text")
                Text("\(Validation.characterCount(model.note)) / 5,000 characters")
                    .foregroundStyle(Validation.characterCount(model.note) > 5_000 ? Theme.disliked : .secondary)
            } header: { Text("Public note") }
            footer: { Text("Only the people you choose below can see this note. Editing it does not publish a new activity.") }
            Section("Who can see this") {
                Picker("Who can see this", selection: Binding(get: { audience ?? visit.audience }, set: { value in
                    audience = value
                    Task {
                        do { try await services.plans.setVisitAudience(visitID: visit.id, audience: value); audienceError = nil }
                        catch { audience = visit.audience; audienceError = error.roamMessage }
                    }
                })) {
                    ForEach(Audience.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("memory-audience")
                if let audienceError { Text(audienceError).foregroundStyle(Roam.signal) }
            }
            Section("Visit date") {
                Toggle("Date unknown", isOn: Binding(get: { model.date.date == nil }, set: { unknown in
                    model.date = VisitDate(date: unknown ? nil : model.today, timeZoneIdentifier: model.zone.identifier)
                })).disabled(!model.canEdit).accessibilityIdentifier("memory-date-unknown")
                if model.date.date != nil {
                    DatePicker("Visit date", selection: Binding(get: { (model.date.date ?? model.today).date(in: model.zone) }, set: {
                        model.date = VisitDate(date: LocalDate(date: $0, timeZone: model.zone), timeZoneIdentifier: model.zone.identifier)
                    }), in: ...model.today.date(in: model.zone), displayedComponents: .date)
                    .environment(\.timeZone, model.zone).disabled(!model.canEdit)
                }
            }
            if let photos {
                Section {
                    Button { showsPhotos = true } label: { Label("\(photos.assets.count) visit photos", systemImage: "photo.on.rectangle") }
                        .disabled(!model.canEdit).frame(minHeight: 44).accessibilityIdentifier("memory-edit-photos")
                    if !photos.canCommit { Text("Retry or remove unfinished photos before saving.").foregroundStyle(Theme.disliked) }
                }
            }
            if model.isSaving { Section { ProgressView("Saving…").accessibilityIdentifier("memory-saving") } }
            if let error = photoError ?? model.persistenceError ?? model.error {
                Section { Text(error).foregroundStyle(Theme.disliked).accessibilityIdentifier("memory-editor-error") }
            }
        }
        .onChange(of: model.authError) { _, error in if let error { _ = account.handle(error) } }
        .sheet(isPresented: $showsPhotos) {
            if let photos {
                PhotoDraftEditor(model: photos, failureMessage: { photoError ?? model.persistenceError ?? model.error }) {
                    do { model.setMediaIDs(try photos.attachmentIDs()); return model.persistenceError == nil }
                    catch { photoError = error.roamMessage; return false }
                }
            }
        }
    }

    private func save() async {
        guard let model else { return }
        if model.pending == nil, let photos {
            do { model.setMediaIDs(try photos.attachmentIDs()); photoError = nil }
            catch { photoError = error.roamMessage; return }
        }
        await model.save()
        if model.rejectedExpiredMedia {
            // Local bytes stay; each expired photo needs a fresh upload before the next save.
            photos?.expireStagedUploads()
        }
        if let saved = model.saved {
            photos?.committed()
            onSaved(saved)
            dismiss()
        }
    }
}

struct PrivateNoteEditor: View {
    let experienceID: UUID
    var onSaved: () -> Void = {}
    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var model: PrivateNoteEditorModel?
    @State private var showsDelete = false
    @State private var showsPendingClose = false

    var body: some View {
        NavigationStack {
            Group {
                if let model { form(model) }
                else { ProgressView("Loading private note…") }
            }
            .navigationTitle("Private note").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if model?.pendingID != nil { showsPendingClose = true }
                        else { model?.discard(); dismiss() }
                    }.disabled(model?.isSaving == true).accessibilityIdentifier("private-note-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model?.pendingID == nil ? "Done" : "Retry save") { Task { await save() } }
                        .disabled(model?.loaded != true || model?.isSaving == true ||
                                  (model?.pendingID == nil && !Self.canSubmit(model?.text ?? "")))
                        .accessibilityIdentifier("private-note-done")
                }
            }
            .confirmationDialog("Delete this private note?", isPresented: $showsDelete, titleVisibility: .visible) {
                Button("Delete private note", role: .destructive) { Task { await save(delete: true) } }
                    .accessibilityIdentifier("confirm-delete-private-note")
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Saving wasn't confirmed", isPresented: $showsPendingClose, titleVisibility: .visible) {
                Button("Keep pending save") { dismiss() }
                Button("Continue checking", role: .cancel) {}
            } message: { Text("The original private-note change can be checked safely when you reopen it.") }
            .interactiveDismissDisabled(model?.loaded == true || model?.isSaving == true)
            .task {
                if model == nil, let owner = account.userID {
                    model = PrivateNoteEditorModel(experienceID: experienceID, ownerID: owner, memories: services.memories,
                                                   storage: services.storage, currentAccount: { account.userID })
                }
                await model?.load()
            }
        }.screenIdentifier("private-note-editor")
    }

    private func form(_ model: PrivateNoteEditorModel) -> some View {
        @Bindable var model = model
        return Form {
            Section {
                Label("Only you can see this note", systemImage: "lock.fill").accessibilityIdentifier("private-note-warning")
                if model.loaded {
                    TextEditor(text: $model.text).frame(minHeight: 240).disabled(!model.canEdit)
                        .accessibilityIdentifier("private-note-text")
                    Text("\(Validation.characterCount(model.text)) / 10,000 characters")
                        .foregroundStyle(Validation.characterCount(model.text) > 10_000 ? Theme.disliked : .secondary)
                    if model.hasSavedNote && model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("To remove your note, use Delete private note.").font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                } else if model.isLoading { ProgressView("Loading…") }
            }
            if let error = model.persistenceError ?? model.error {
                Section {
                    Text(error).foregroundStyle(Theme.disliked).accessibilityIdentifier("private-note-error")
                    if !model.loaded { Button("Retry") { Task { await model.load() } }.accessibilityIdentifier("private-note-retry-load") }
                }
            }
            if model.isSaving { Section { ProgressView("Saving…").accessibilityIdentifier("private-note-saving") } }
            if model.loaded && model.hasSavedNote && model.pendingID == nil {
                Section {
                    Button(role: .destructive) { showsDelete = true } label: { Text("Delete private note").foregroundStyle(Theme.disliked) }
                        .disabled(model.isSaving).accessibilityIdentifier("private-note-delete")
                }
            }
        }.onChange(of: model.authError) { _, error in if let error { _ = account.handle(error) } }
    }

    private func save(delete: Bool = false) async {
        await model?.save(delete: delete)
        if model?.didSave == true { onSaved(); dismiss() }
    }

    /// A private note has 1–10,000 characters; an empty note is removed with Delete instead.
    static func canSubmit(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && Validation.characterCount(text) <= 10_000
    }
}
