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

/// Setup, one question per page, laid out like the app's other pages: the round back button and a thin progress bar at
/// the top, a big title with one short line, the step, and its button pinned at the bottom.
private struct SetupSteps: View {
    @Bindable var model: ProfileSetupModel
    @Environment(SessionStore.self) private var session
    @State private var photoItem: PhotosPickerItem?
    @State private var cityQuery = ""
    @State private var citySearch = PlaceSearch()
    @State private var friendQuery = ""
    @FocusState private var focused: Bool
    @Environment(AppServices.self) private var services

    var body: some View {
        // The top bar sits above the scroll view rather than in an inset over it, so its back button always takes the tap.
        VStack(spacing: 0) {
            topBar
            page
        }
        .background(Roam.paper)
        .animation(.easeInOut(duration: 0.2), value: model.step)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { await model.uploadAvatar(data) }
                photoItem = nil
            }
        }
        .task(id: cityQuery) { await citySearch.run(cityQuery, services: services) }
        .screenIdentifier("profile-setup")
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                content
                if let error = model.error { ErrorText(error) }
            }
            // Full width, so every step lines up on the same left margin.
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.l)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomButton.padding(.horizontal, Theme.Spacing.l).padding(.bottom, Theme.Spacing.s) }
    }

    /// The round back button (where there's a step to go back to) and a thin bar showing how far through you are.
    private var topBar: some View {
        HStack(spacing: Theme.Spacing.m) {
            Button { focused = false; model.goBack() } label: {
                Image(systemName: "chevron.left").font(.headline).foregroundStyle(Roam.ink).frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .floatingBubble(Circle())
            .opacity(model.canGoBack ? 1 : 0)
            .disabled(!model.canGoBack)
            .accessibilityLabel("Back")
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Roam.fill)
                    Capsule().fill(Roam.ink).frame(width: proxy.size.width * model.progress)
                }
            }
            .frame(height: 6)
            .accessibilityElement()
            .accessibilityLabel("Setup progress")
            .accessibilityValue("Step \(model.step.rawValue + 1) of \(ProfileSetupModel.Step.allCases.count)")
            Color.clear.frame(width: 48, height: 1)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.bottom, Theme.Spacing.s)
    }

    @ViewBuilder private var content: some View {
        switch model.step {
        case .name:
            title("What's your name?")
            RoamTextField(title: "Your name", text: $model.displayName, contentType: .name, identifier: "display-name-field")
                .focused($focused)
                .onChange(of: model.displayName) { _, _ in model.saveDraft() }
        case .handle:
            title("Choose your handle")
            RoamTextField(title: "Handle", text: $model.handle, identifier: "handle-field")
                .focused($focused)
                .overlay(alignment: .trailing) { handleMark.padding(.trailing, Theme.Spacing.l) }
                .onChange(of: model.handle) { _, value in
                    let normalized = Validation.normalizedHandleInput(value)
                    if normalized != value { model.handle = normalized }
                    model.saveDraft()
                }
                .task(id: model.handle) { await model.checkHandle() }
            handleStatus
        case .photo:
            title("Add a profile photo")
            PhotosPicker(selection: $photoItem, matching: .images) {
                ZStack {
                    if let image = model.avatarImage {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else if let profile = model.profile {
                        AvatarView(member: profile.summary, size: 160)
                    }
                    if model.avatarBusy { ProgressView() }
                }
                .frame(width: 160, height: 160)
                .clipShape(Circle())
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "camera.fill").font(.headline).foregroundStyle(Roam.onInk)
                        .frame(width: 44, height: 44).background(Circle().fill(Roam.ink))
                        .overlay(Circle().strokeBorder(Roam.paper, lineWidth: 3))
                }
            }
            .buttonStyle(.plain)
            .disabled(model.avatarBusy)
            .frame(maxWidth: .infinity)
            .padding(.top, Theme.Spacing.l)
            .accessibilityLabel(model.avatarPath == nil ? "Choose a photo" : "Choose a different photo")
            .accessibilityIdentifier("choose-avatar")
        case .preferences:
            title("What do you like?")
            ForEach(TasteProfile.questions) { question in
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text(question.title).font(.headline)
                    // The standard slider, as on the log screen's feeling.
                    OptionSlider(options: question.options, selection: Binding(
                        get: { model.taste[keyPath: question.keyPath] },
                        set: { model.taste[keyPath: question.keyPath] = $0 }))
                        .accessibilityLabel(question.title)
                }
            }
            .task { await model.loadTaste() }
        case .home:
            title("Where's home?")
            if let city = model.homeCity {
                HStack(spacing: Theme.Spacing.m) {
                    CityThumbnail(destination: city, size: 48)
                    VStack(alignment: .leading, spacing: -2) {
                        Text(city.name).font(.headline).lineLimit(1)
                        Text(city.subtitle).font(.footnote).foregroundStyle(Roam.inkMuted).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button { model.homeCity = nil } label: {
                        Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(Roam.inkMuted)
                            .frame(width: 32, height: 32).background(Circle().fill(Roam.fill))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Choose a different city")
                }
                .padding(.vertical, Theme.Spacing.s)
                .roamCard(padding: Theme.Spacing.m)
            } else {
                // Search 1, worldwide, cities only.
                RoamSearchField(prompt: "Search cities", text: $cityQuery, focus: $focused, identifier: "setup-home-search")
                    .frame(height: 44)
                if !cityQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                    PlaceSearchResults(query: cityQuery, placeSearch: citySearch, kinds: .cities) { pick in
                        if case .city(let city) = pick { model.homeCity = city; cityQuery = ""; focused = false }
                    }
                }
            }
        case .friends:
            title("Add friends")
            RoamSearchField(prompt: "Search for friends", text: $friendQuery, focus: $focused, identifier: "setup-friend-search")
                .frame(height: 44)
            if friendQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                peopleList
            } else {
                // Search 3: everyone, each with their own Add button.
                AccountSearchResults(query: friendQuery)
            }
        }
    }

    /// The button pinned at the bottom of each step.
    @ViewBuilder private var bottomButton: some View {
        switch model.step {
        case .name:
            primary("Continue", enabled: model.nameIssue == nil) { model.continueFromName() }
        case .handle:
            primary("Continue", enabled: Validation.handle(model.handle) == nil && model.handleState != .checking) {
                Task { await model.createProfile() }
            }
        case .photo:
            primary(model.avatarPath == nil ? "Skip for now" : "Continue", enabled: !model.avatarBusy, quiet: model.avatarPath == nil) {
                Task { await model.finishPhotoStep() }
            }
        case .preferences:
            primary(model.taste == .empty ? "Skip for now" : "Continue", enabled: true, quiet: model.taste == .empty) {
                Task { await model.savePreferences() }
            }
        case .home:
            primary(model.homeCity == nil ? "Skip for now" : "Continue", enabled: true, quiet: model.homeCity == nil) {
                Task { await model.saveHome() }
            }
        case .friends:
            Button {
                Task { if let profile = await model.finish() { session.completeSetup(profile) } }
            } label: {
                if model.busy { ProgressView().tint(Roam.onInk) } else { Text("Start using Roam") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.busy)
            .accessibilityIdentifier("setup-finish")
        }
    }

    /// Black when there's something to save; grey when it would only skip.
    @ViewBuilder private func primary(_ text: String, enabled: Bool, quiet: Bool = false, action: @escaping () -> Void) -> some View {
        let button = Button { focused = false; action() } label: {
            if model.busy { ProgressView().tint(quiet ? Roam.ink : Roam.onInk) } else { Text(text) }
        }
        .disabled(!enabled || model.busy)
        .accessibilityIdentifier("setup-continue")
        if quiet { button.buttonStyle(GreyBubbleButtonStyle()) } else { button.buttonStyle(PrimaryButtonStyle()) }
    }

    /// Just the question: no line under it.
    private func title(_ title: String) -> some View {
        Text(title).font(.roamDisplay(.title)).accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var handleMark: some View {
        switch model.handleState {
        case .checking: ProgressView()
        case .available: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.liked)
        default: EmptyView()
        }
    }

    @ViewBuilder private var handleStatus: some View {
        switch model.handleState {
        case .available:
            Text("@\(model.handle) is available").font(.footnote).foregroundStyle(Roam.inkMuted)
                .padding(.horizontal, Theme.Spacing.l)
                .accessibilityIdentifier("handle-available")
        case .unavailable(let message):
            Text(message).font(.footnote).foregroundStyle(Theme.disliked)
                .padding(.horizontal, Theme.Spacing.l)
                .accessibilityIdentifier("handle-unavailable")
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var peopleList: some View {
        switch model.suggestions {
        case .idle, .loading:
            SkeletonResults(kind: .people, rows: 3).task { if case .idle = model.suggestions { await model.loadSuggestions() } }
        case .failed(let message):
            InlineRetryView(message: message) { Task { await model.loadSuggestions() } }
        case .loaded(let rows) where rows.isEmpty:
            EmptyView()
        case .loaded(let rows):
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    MemberRowView(member: row.member, subtitle: row.friendState == .received ? "Wants to be friends" : nil,
                                  followState: model.pendingFollows.contains(row.member.id) ? .pending
                                      : (model.following.contains(row.member.id) ? .requested : FollowButtonState(row.friendState)),
                                  onToggleFollow: { Task { await model.toggleFollow(row.member) } })
                    if row.id != rows.last?.id { RowSeparator() }
                }
            }
            .roamCard(padding: Theme.Spacing.m)
        }
    }
}
