import PhotosUI
import SwiftUI

struct ProfileSetupFlowView: View {
    let auth: AuthSession

    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @State private var model: ProfileSetupModel?

    var body: some View {
        Group {
            if let model {
                SetupSteps(model: model)
            } else {
                ProgressView()
            }
        }
        .task {
            if model == nil {
                model = ProfileSetupModel(services: services, auth: auth, profile: session.profile, prefillName: session.pendingAppleName)
            }
        }
    }
}

private struct SetupSteps: View {
    @Bindable var model: ProfileSetupModel
    @Environment(SessionStore.self) private var session
    @Environment(DestinationStore.self) private var destinations
    @State private var photoItem: PhotosPickerItem?
    @State private var showsHomePicker = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if model.step == .handle {
                    Button { model.step = .name } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                        .accessibilityLabel("Back")
                }
                ProgressView(value: model.progress)
                    .tint(Theme.accent)
                    .accessibilityLabel("Setup progress")
                    .accessibilityValue("Step \(model.step.rawValue + 1) of \(ProfileSetupModel.Step.allCases.count)")
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.s)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    content
                    if let error = model.error { ErrorText(error) }
                }
                .padding(Theme.Spacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.groupedCanvas)
        .sheet(isPresented: $showsHomePicker) {
            DestinationPickerSheet(purpose: .homeCity)
        }
        .onChange(of: destinations.pickedHomeCity) { _, picked in
            if let picked { model.homeCity = picked; destinations.pickedHomeCity = nil }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { await model.uploadAvatar(data) }
                photoItem = nil
            }
        }
        .screenIdentifier("profile-setup")
    }

    @ViewBuilder private var content: some View {
        switch model.step {
        case .name:
            question("What should we call you?", "This is how other travellers see you. You can change it later.")
            RoamTextField(title: "Display name", text: $model.displayName, contentType: .name, identifier: "display-name-field")
                .onChange(of: model.displayName) { _, _ in model.saveDraft() }
            Button("Continue") { model.continueFromName() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.nameIssue != nil)
                .accessibilityIdentifier("setup-continue")
        case .handle:
            question("Choose your handle", "Lowercase letters, numbers and underscores, 3–20 characters. You can change it later.")
            HStack(spacing: Theme.Spacing.s) {
                Text("@").font(.title3.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                RoamTextField(title: "Handle", text: $model.handle, identifier: "handle-field")
                    .onChange(of: model.handle) { _, value in
                        let normalized = Validation.normalizedHandleInput(value)
                        if normalized != value { model.handle = normalized }
                        model.saveDraft()
                    }
            }
            handleStatus
            Button {
                Task { await model.createProfile() }
            } label: {
                if model.busy { ProgressView().tint(Roam.onInk) } else { Text("Continue") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(Validation.handle(model.handle) != nil || model.busy || model.handleState == .checking)
            .accessibilityIdentifier("setup-continue")
            .task(id: model.handle) { await model.checkHandle() }
        case .photo:
            question("Add a profile photo", "Optional. It helps friends recognise you.")
            HStack {
                Spacer()
                ZStack {
                    if let image = model.avatarImage {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else if let profile = model.profile {
                        AvatarView(member: profile.summary, size: 120)
                    }
                    if model.avatarBusy { ProgressView() }
                }
                .frame(width: 120, height: 120)
                .clipShape(Circle())
                Spacer()
            }
            PhotosPicker(model.avatarPath == nil ? "Choose a photo" : "Choose a different photo", selection: $photoItem, matching: .images)
            .buttonStyle(SecondaryButtonStyle())
            .disabled(model.avatarBusy)
            .accessibilityIdentifier("choose-avatar")
            Button(model.avatarPath == nil ? "Not now" : "Continue") { model.finishPhotoStep() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.avatarBusy)
                .accessibilityIdentifier("setup-continue")
        case .home:
            question("Where's home?", "Optional. Roam uses it as your starting point for search. Home never counts as a place you've visited.")
            Button {
                showsHomePicker = true
            } label: {
                HStack {
                    Image(systemName: "house")
                    Text(model.homeCity?.displayName ?? "Choose a city")
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote)
                }
                .padding(Theme.Spacing.m)
                .frame(minHeight: Theme.minimumHitTarget)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.raisedCard))
            }
            .accessibilityIdentifier("choose-home-city")
            Button {
                Task { await model.saveHomeAndContinue() }
            } label: {
                if model.busy { ProgressView().tint(Roam.onInk) } else { Text(model.homeCity == nil ? "Skip" : "Continue") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.busy)
            .accessibilityIdentifier("setup-continue")
        case .people:
            question("Find travellers to follow", "Optional. Following someone puts their ratings in your feed. Nobody is followed unless you choose.")
            peopleList
            Button(model.following.isEmpty ? "Skip for now" : "Continue") { model.step = .visibility }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("setup-continue")
        case .visibility:
            question("Your profile is public", "Roam is social by design. Here's what other signed-in members can see.")
            VisibilityExplainer()
            Button {
                Task {
                    if let profile = await model.finish() { session.completeSetup(profile) }
                }
            } label: {
                if model.busy { ProgressView().tint(Roam.onInk) } else { Text("Start using Roam") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.busy)
            .accessibilityIdentifier("setup-finish")
        }
    }

    private func question(_ title: String, _ message: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(title).font(.roamDisplay(.title)).accessibilityAddTraits(.isHeader)
            Text(message).font(.body).foregroundStyle(Theme.secondaryText)
        }
    }

    @ViewBuilder private var handleStatus: some View {
        switch model.handleState {
        case .idle:
            EmptyView()
        case .checking:
            Label("Checking…", systemImage: "hourglass").font(.footnote).foregroundStyle(Theme.secondaryText)
        case .available:
            Label("@\(model.handle) is available", systemImage: "checkmark.circle.fill").font(.footnote).foregroundStyle(Theme.liked)
                .accessibilityIdentifier("handle-available")
        case .unavailable(let message):
            Label(message, systemImage: "xmark.circle.fill").font(.footnote).foregroundStyle(Theme.disliked)
                .accessibilityIdentifier("handle-unavailable")
        }
    }

    @ViewBuilder private var peopleList: some View {
        switch model.suggestions {
        case .idle, .loading:
            SkeletonList(rows: 3).task { if case .idle = model.suggestions { await model.loadSuggestions() } }
        case .failed(let message):
            InlineRetryView(message: message) { Task { await model.loadSuggestions() } }
        case .loaded(let rows) where rows.isEmpty:
            Text("No suggestions yet. You can find people any time from Search.").foregroundStyle(Theme.secondaryText)
        case .loaded(let rows):
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    MemberRowView(member: row.member, subtitle: row.followsViewer ? "Follows you" : nil,
                                  followState: model.pendingFollows.contains(row.member.id) ? .pending
                                      : (model.following.contains(row.member.id) ? .following : (row.followsViewer ? .followBack : .follow)),
                                  onToggleFollow: { Task { await model.toggleFollow(row.member) } })
                    Divider()
                }
            }
            .roamCard(padding: Theme.Spacing.m)
        }
    }
}

struct VisibilityExplainer: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            row("person.crop.circle", "Visible to members", "Your name, handle, photo, bio, home city, rankings and scores, Want to Go list, travel globe, and the public notes and photos on your visits.")
            row("dot.radiowaves.left.and.right", "Shared automatically", "When you finish ranking or add a visit, it appears on your profile and in your followers' feeds.")
            row("lock.fill", "Only you", "Private notes, your email, your settings and who you've blocked or muted.")
        }
        .roamCard()
    }

    private func row(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: symbol).foregroundStyle(Theme.accent).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
