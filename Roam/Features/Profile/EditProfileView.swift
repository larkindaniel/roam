import Observation
import PhotosUI
import SwiftUI
import UIKit

/// Profile edit (S18/S26). Changes live in an account-scoped draft that survives a restart until
/// Save succeeds or the member cancels; a failed save keeps every field.
@MainActor
@Observable
final class EditProfileModel {
    struct Draft: Codable, Equatable {
        var displayName: String
        var handle: String
        var bio: String
        var homeCity: Destination?
        /// The current avatar, a newly staged upload, or nil for no photo.
        var avatarPath: String?

        init(_ profile: OwnProfile) {
            displayName = profile.displayName
            handle = profile.handle
            bio = profile.bio
            homeCity = profile.homeCity
            avatarPath = profile.avatarPath
        }
    }

    enum HandleState: Equatable {
        case unchanged
        case checking
        case available
        case unavailable(String)
    }

    static let draftName = "profile-edit-draft"

    let original: Draft
    var draft: Draft { didSet { persist() } }
    private(set) var restoredDraft = false
    private(set) var handleState: HandleState = .unchanged
    private(set) var avatarBusy = false
    private(set) var saving = false
    var error: String?
    var avatarError: String?

    private let services: AppServices
    let userID: UUID

    init(services: AppServices, profile: OwnProfile) {
        self.services = services
        userID = profile.id
        original = Draft(profile)
        if let saved = services.storage.read(Draft.self, name: Self.draftName, userID: profile.id), saved != Draft(profile) {
            draft = saved
            restoredDraft = true
        } else {
            draft = Draft(profile)
        }
        if draft.handle != original.handle { handleState = .checking }
    }

    var hasChanges: Bool { draft != original }
    var nameIssue: String? { Validation.displayName(draft.displayName)?.localizedDescription }
    var handleIssue: String? {
        if let issue = Validation.handle(draft.handle) { return issue.localizedDescription }
        if case .unavailable(let message) = handleState { return message }
        return nil
    }
    var bioIssue: String? { Validation.bio(draft.bio)?.localizedDescription }

    var canSave: Bool {
        hasChanges && nameIssue == nil && handleIssue == nil && bioIssue == nil && !avatarBusy && !saving && handleState != .checking
    }

    /// Debounced availability check for a changed handle; it never reserves the handle.
    func checkHandle() async {
        let candidate = draft.handle
        guard candidate != original.handle else {
            handleState = .unchanged
            return
        }
        if let issue = Validation.handle(candidate) {
            handleState = .unavailable(issue.localizedDescription)
            return
        }
        handleState = .checking
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled, candidate == draft.handle else { return }
        do {
            switch try await services.profiles.checkHandle(candidate) {
            case .available: handleState = .available
            case .taken: handleState = .unavailable("@\(candidate) is taken. Try another.")
            case .invalid(let issue): handleState = .unavailable(issue.localizedDescription)
            }
        } catch {
            // Availability is advisory; the save itself enforces uniqueness.
            handleState = .available
        }
    }

    /// Strips metadata and uploads through the inspected avatar path; the profile changes only on Save.
    func pickAvatar(_ data: Data) async {
        avatarBusy = true
        avatarError = nil
        defer { avatarBusy = false }
        do {
            let processed = try ImageProcessor.prepare(data, maxPixel: 1_024)
            let staged = try await services.media.stage(jpegData: processed.data, width: processed.width, height: processed.height, purpose: .avatar)
            if let image = UIImage(data: processed.data) { services.images.store(image, for: staged.path) }
            draft.avatarPath = staged.path
        } catch {
            avatarError = "Couldn't use that photo. \(error.roamMessage)"
        }
    }

    func removeAvatar() {
        draft.avatarPath = nil
        avatarError = nil
    }

    func save() async -> OwnProfile? {
        guard canSave else { return nil }
        saving = true
        error = nil
        defer { saving = false }
        do {
            let saved = try await services.profiles.updateProfile(ProfileUpdate(
                displayName: draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines), handle: draft.handle,
                bio: draft.bio.trimmingCharacters(in: .whitespacesAndNewlines), homeCity: draft.homeCity, avatarPath: draft.avatarPath))
            services.storage.remove(name: Self.draftName, userID: userID)
            return saved
        } catch RoamError.conflict(let message) {
            handleState = .unavailable(message)
            error = message
        } catch RoamError.forbidden {
            error = "Your new photo is no longer available. Choose it again."
        } catch {
            self.error = "Your changes aren't saved yet. \(error.roamMessage)"
        }
        return nil
    }

    /// Cancel: nothing is sent and the local draft is dropped.
    func discard() {
        services.storage.remove(name: Self.draftName, userID: userID)
    }

    private func persist() {
        if hasChanges {
            try? services.storage.write(draft, name: Self.draftName, userID: userID)
        } else {
            services.storage.remove(name: Self.draftName, userID: userID)
        }
    }
}

struct EditProfileView: View {
    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(DestinationStore.self) private var destinations
    @Environment(\.dismiss) private var dismiss
    @State private var model: EditProfileModel?
    @State private var photoItem: PhotosPickerItem?
    @State private var showsHomePicker = false

    var body: some View {
        Group {
            if let model {
                form(model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Edit profile")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    model?.discard()
                    dismiss()
                }
                .accessibilityIdentifier("edit-profile-cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await save() }
                } label: {
                    if model?.saving == true { ProgressView() } else { Text("Save").bold() }
                }
                .disabled(model?.canSave != true)
                .accessibilityIdentifier("edit-profile-save")
            }
        }
        .sheet(isPresented: $showsHomePicker) { DestinationPickerSheet(purpose: .homeCity) }
        .onChange(of: destinations.pickedHomeCity) { _, picked in
            if let picked { model?.draft.homeCity = picked; destinations.pickedHomeCity = nil }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { await model?.pickAvatar(data) }
                photoItem = nil
            }
        }
        .task {
            if model == nil, let profile = session.profile { model = EditProfileModel(services: services, profile: profile) }
        }
        .screenIdentifier("edit-profile")
    }

    private func save() async {
        guard let model, let saved = await model.save() else { return }
        session.profileUpdated(saved)
        dismiss()
    }

    @ViewBuilder private func form(_ model: EditProfileModel) -> some View {
        @Bindable var model = model
        Form { Group {
            if model.restoredDraft {
                Section {
                    Text("Your unsaved changes were restored.")
                    Button {
                        model.discard()
                        dismiss()
                    } label: { Text("Discard changes").foregroundStyle(Theme.disliked) }
                    .accessibilityIdentifier("edit-profile-discard")
                }
                .accessibilityIdentifier("edit-profile-restored")
            }
            if let error = model.error {
                Section {
                    Text(error).foregroundStyle(Theme.disliked).accessibilityIdentifier("edit-profile-error")
                }
            }
            Section {
                HStack(spacing: Theme.Spacing.l) {
                    ZStack {
                        AvatarView(member: MemberSummary(id: model.userID, handle: model.draft.handle, displayName: model.draft.displayName,
                                                         avatarPath: model.draft.avatarPath), size: 72)
                        if model.avatarBusy { ProgressView() }
                    }
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Text(model.draft.avatarPath == nil ? "Add photo" : "Change photo")
                        }
                        .disabled(model.avatarBusy)
                        .accessibilityIdentifier("edit-profile-photo")
                        if model.draft.avatarPath != nil {
                            Button { model.removeAvatar() } label: { Text("Remove photo").foregroundStyle(Theme.disliked) }
                                .disabled(model.avatarBusy)
                                .accessibilityIdentifier("edit-profile-remove-photo")
                        }
                    }
                }
                if let avatarError = model.avatarError {
                    Text(avatarError).font(.footnote).foregroundStyle(Theme.disliked)
                }
            } footer: {
                Text("Photos are resized and their location data removed before upload.")
            }
            Section {
                TextField("Name", text: $model.draft.displayName)
                    .textContentType(.name)
                    .accessibilityIdentifier("edit-profile-name")
                issue(model.nameIssue)
            } header: { Text("Name") }
            Section {
                HStack(spacing: 2) {
                    Text("@").foregroundStyle(Theme.secondaryText)
                    TextField("handle", text: Binding(get: { model.draft.handle },
                                                      set: { model.draft.handle = $0.lowercased().filter { !$0.isWhitespace } }))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("edit-profile-handle")
                }
                handleStatus(model)
            } header: { Text("Handle") }
            Section {
                TextField("A line about how you travel", text: $model.draft.bio, axis: .vertical)
                    .lineLimit(2...5)
                    .accessibilityIdentifier("edit-profile-bio")
                issue(model.bioIssue)
            } header: {
                Text("Bio")
            } footer: {
                Text("\(model.draft.bio.count)/\(Limits.bioMax)")
            }
            Section {
                Button { showsHomePicker = true } label: {
                    LabeledContent("Home city", value: model.draft.homeCity?.displayName ?? "Not set")
                }
                .accessibilityIdentifier("edit-profile-home")
                if model.draft.homeCity != nil {
                    Button { model.draft.homeCity = nil } label: { Text("Remove home city").foregroundStyle(Theme.disliked) }
                        .accessibilityIdentifier("edit-profile-remove-home")
                }
            } footer: {
                Text("Your home city shows on your profile. It never counts as a place you've visited.")
            }
        }
        .listRowBackground(Roam.paperRaised)
        }
        .task(id: model.draft.handle) { await model.checkHandle() }
    }

    @ViewBuilder private func issue(_ message: String?) -> some View {
        if let message {
            Text(message).font(.footnote).foregroundStyle(Theme.disliked)
        }
    }

    @ViewBuilder private func handleStatus(_ model: EditProfileModel) -> some View {
        switch model.handleState {
        case .unchanged:
            if let issue = model.handleIssue { self.issue(issue) }
        case .checking:
            Label("Checking…", systemImage: "hourglass").font(.footnote).foregroundStyle(Theme.secondaryText)
        case .available:
            Label("@\(model.draft.handle) is available", systemImage: "checkmark.circle").font(.footnote).foregroundStyle(Theme.liked)
        case .unavailable(let message):
            self.issue(message)
        }
    }
}

/// Your photo, name and handle, edited right on the Settings page. Save appears once something's changed.
struct InlineProfileSection: View {
    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @State private var model: EditProfileModel?
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        Section {
            if let model { fields(model) } else { ProgressView() }
        } header: {
            Text("Profile")
        }
        .task {
            if model == nil, let profile = session.profile { model = EditProfileModel(services: services, profile: profile) }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { await model?.pickAvatar(data) }
                photoItem = nil
            }
        }
    }

    @ViewBuilder private func fields(_ model: EditProfileModel) -> some View {
        @Bindable var model = model
        HStack(spacing: Theme.Spacing.m) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                ZStack {
                    AvatarView(member: MemberSummary(id: model.userID, handle: model.draft.handle, displayName: model.draft.displayName,
                                                     avatarPath: model.draft.avatarPath), size: 56)
                    if model.avatarBusy { ProgressView() }
                }
            }
            .buttonStyle(.plain)
            .disabled(model.avatarBusy)
            .accessibilityLabel(model.draft.avatarPath == nil ? "Add photo" : "Change photo")
            .accessibilityIdentifier("edit-profile-photo")
            VStack(alignment: .leading, spacing: 6) {
                TextField("Name", text: $model.draft.displayName)
                    .font(.headline)
                    .textContentType(.name)
                    .accessibilityIdentifier("edit-profile-name")
                HStack(spacing: 2) {
                    Text("@").foregroundStyle(Theme.secondaryText)
                    TextField("handle", text: Binding(get: { model.draft.handle },
                                                      set: { model.draft.handle = $0.lowercased().filter { !$0.isWhitespace } }))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(Theme.secondaryText)
                        .accessibilityIdentifier("edit-profile-handle")
                }
                .font(.subheadline)
            }
        }
        .task(id: model.draft.handle) { await model.checkHandle() }
        if let message = model.nameIssue ?? model.handleIssue ?? model.error ?? model.avatarError {
            Text(message).font(.footnote).foregroundStyle(Theme.disliked)
        } else if case .unavailable(let message) = model.handleState {
            Text(message).font(.footnote).foregroundStyle(Theme.disliked)
        }
        if model.draft != model.original {
            HStack {
                Button("Cancel") {
                    model.discard()
                    if let profile = session.profile { self.model = EditProfileModel(services: services, profile: profile) }
                }
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Button {
                    Task {
                        guard let saved = await model.save() else { return }
                        session.profileUpdated(saved)
                        // Start fresh from what was saved, so Save goes away.
                        self.model = EditProfileModel(services: services, profile: saved)
                    }
                } label: {
                    if model.saving { ProgressView() } else { Text("Save").bold() }
                }
                .disabled(!model.canSave)
                .accessibilityIdentifier("edit-profile-save")
            }
            .buttonStyle(.borderless)
        }
    }
}
