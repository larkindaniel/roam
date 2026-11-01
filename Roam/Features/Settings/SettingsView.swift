import SwiftUI

/// S26 settings: Profile, Account, Preferences, in-app Notifications, Safety and About & help.
/// Only actions the account's providers support appear (no password rows for Apple-only accounts,
/// no phone, payment, referral or push rows).
struct SettingsView: View {
    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(SettingsStore.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router
    @Environment(DestinationStore.self) private var destinations
    @Environment(ActivityChangeStore.self) private var activityChanges
    @State private var resetMessage: String?
    @State private var confirmSignOut = false

    var body: some View {
        List {
            Section("Your tastes") {
                Button("Edit Your Tastes") { router.push(.taste) }
                    .accessibilityIdentifier("open-taste")
            }
            Section("Profile") {
                Button { router.push(.editProfile) } label: {
                    HStack(spacing: Theme.Spacing.m) {
                        if let profile = session.profile {
                            AvatarView(member: profile.summary, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.displayName).font(.headline).foregroundStyle(Color.primary)
                                Text("@\(profile.handle)").font(.subheadline).foregroundStyle(Theme.secondaryText)
                            }
                        }
                        Spacer()
                        Text("Edit").foregroundStyle(Theme.accent)
                    }
                }
                .accessibilityIdentifier("settings-edit-profile")
            }
            accountSection
            preferencesSection
            notificationsSection
            Section("Safety") {
                NavigationLink(value: AppRoute.safetyList(.blocked)) { Label("Blocked members", systemImage: "hand.raised") }
                    .accessibilityIdentifier("settings-blocked")
                NavigationLink(value: AppRoute.safetyList(.muted)) { Label("Muted members", systemImage: "speaker.slash") }
                    .accessibilityIdentifier("settings-muted")
                NavigationLink(value: AppRoute.reportHistory) { Label("Your reports", systemImage: "flag") }
                    .accessibilityIdentifier("settings-reports")
            }
            Section("About & help") {
                NavigationLink(value: AppRoute.help(.ranking)) { Label("How ranking and posts work", systemImage: "list.number") }
                    .accessibilityIdentifier("settings-help-ranking")
                NavigationLink(value: AppRoute.help(.privacy)) { Label("Privacy", systemImage: "lock") }
                    .accessibilityIdentifier("settings-help-privacy")
                NavigationLink(value: AppRoute.help(.terms)) { Label("Terms of use", systemImage: "doc.text") }
                    .accessibilityIdentifier("settings-help-terms")
                NavigationLink(value: AppRoute.help(.support)) { Label("Support", systemImage: "questionmark.bubble") }
                    .accessibilityIdentifier("settings-help-support")
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
            }
        }
        .navigationTitle("Settings")
        .safeAreaInset(edge: .bottom) {
            if let error = settings.saveError {
                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.fine).accessibilityHidden(true)
                    Text("Couldn't save, so your previous setting is back. \(error)")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("settings-save-error-message")
                    Spacer(minLength: 0)
                    VStack(spacing: 0) {
                        Button("Retry") { Task { await settings.retry() } }
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: Theme.minimumHitTarget)
                            .accessibilityIdentifier("settings-retry")
                        Button("Dismiss") { settings.dismissError() }
                            .font(.subheadline)
                            .frame(minHeight: Theme.minimumHitTarget)
                    }
                }
                .padding(Theme.Spacing.m)
                .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.fineFill))
                .padding(.horizontal)
                .padding(.bottom, Theme.Spacing.s)
            }
        }
        .confirmationDialog("Sign out of Roam?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                Task {
                    await session.signOut()
                    library.reset()
                    destinations.reset()
                    activityChanges.reset()
                    settings.reset()
                    router.reset(initialTab: .forYou)
                }
            }
        } message: {
            Text("Drafts and cached data on this device are removed. Everything you've saved to Roam stays in your account.")
        }
        .task { if let userID = session.userID, !settings.hasLoaded { await settings.load(userID: userID) } }
        .screenIdentifier("settings")
    }

    private var accountSection: some View {
        Section("Account") {
            if let email = session.session?.email {
                LabeledContent("Email", value: email)
            }
            LabeledContent("Signed in with", value: providerText)
            if session.session?.providers.contains(.email) == true {
                Button("Email me a password reset code") { Task { await sendReset() } }
                    .accessibilityIdentifier("settings-password-reset")
                if let resetMessage {
                    Text(resetMessage).font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            }
            // Theme red rather than system red, which is 3.6:1 on white.
            Button { confirmSignOut = true } label: { Text("Sign out").foregroundStyle(Theme.disliked) }
                .accessibilityIdentifier("settings-sign-out")
            NavigationLink(value: AppRoute.deleteAccount) {
                Text("Delete account").foregroundStyle(Theme.disliked)
            }
            .accessibilityIdentifier("settings-delete-account")
        }
    }

    private var preferencesSection: some View {
        Section {
            Picker("Distance", selection: Binding(get: { settings.displayed.distanceUnit },
                                                  set: { unit in Task { await settings.update { $0.distanceUnit = unit } } })) {
                ForEach(DistanceUnit.allCases) { Text($0.title).tag($0) }
            }
            .accessibilityIdentifier("settings-distance-unit")
            Toggle("Haptics", isOn: Binding(get: { settings.displayed.hapticsEnabled },
                                            set: { value in Task { await settings.update { $0.hapticsEnabled = value } } }))
                .accessibilityIdentifier("settings-haptics")
        } header: {
            Text("Preferences")
        } footer: {
            saveStatus
        }
        .disabled(settings.isSaving)
    }

    private var notificationsSection: some View {
        Section {
            Toggle("Friend requests", isOn: Binding(get: { settings.displayed.notifyFollows },
                                                  set: { value in Task { await settings.update { $0.notifyFollows = value } } }))
                .accessibilityIdentifier("settings-notify-follows")
            Toggle("Likes on your posts", isOn: Binding(get: { settings.displayed.notifyLikes },
                                                        set: { value in Task { await settings.update { $0.notifyLikes = value } } }))
                .accessibilityIdentifier("settings-notify-likes")
            Toggle("Comments on your posts", isOn: Binding(get: { settings.displayed.notifyComments },
                                                           set: { value in Task { await settings.update { $0.notifyComments = value } } }))
                .accessibilityIdentifier("settings-notify-comments")
        } header: {
            Text("In-app notifications")
        } footer: {
            Text("These choose what appears in Notifications from now on. Roam doesn't send push notifications.")
        }
        .disabled(settings.isSaving)
    }

    @ViewBuilder private var saveStatus: some View {
        if settings.isSaving {
            Label("Saving…", systemImage: "arrow.triangle.2.circlepath").accessibilityIdentifier("settings-saving")
        } else if let error = settings.loadError, !settings.hasLoaded {
            Text("Showing your last saved settings. \(error)")
        } else {
            Text("Distances in lists use this unit. Haptics are the small taps when you like, add a friend, save or compare.")
        }
    }

    private var providerText: String {
        let providers = session.session?.providers ?? []
        return providers.map { $0 == .apple ? "Apple" : "Email" }.joined(separator: " and ")
    }

    private func sendReset() async {
        guard let email = session.session?.email else { return }
        do {
            try await services.auth.requestPasswordReset(email: email)
            resetMessage = "We sent a reset code to \(email)."
        } catch {
            resetMessage = session.handle(error)
        }
    }
}
