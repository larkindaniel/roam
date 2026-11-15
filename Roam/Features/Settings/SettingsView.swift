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
        // White cards of standard rows with the app's own separators, like Trip invitations and Lists.
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                section("Profile") {
                    Button { router.push(.editProfile) } label: {
                        HStack(spacing: Theme.Spacing.m) {
                            if let profile = session.profile {
                                AvatarView(member: profile.summary, size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.displayName).font(.headline).foregroundStyle(Roam.ink)
                                    Text("@\(profile.handle)").font(.subheadline).foregroundStyle(Roam.inkMuted)
                                }
                            }
                            Spacer(minLength: 0)
                            Text("Edit").foregroundStyle(Roam.ink)
                        }
                        .padding(.vertical, Theme.Spacing.s)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .tapID("settings-edit-profile")
                    RowSeparator(inset: 44 + Theme.Spacing.m)
                    // What you like, for Plan with AI. Suggestions learn from your rankings instead.
                    row("Your tastes", icon: "heart", id: "settings-tastes") { router.push(.taste) }
                }
                // Kept to the essentials for now; preferences and notifications come back later.
                section("Account") {
                    if let email = session.session?.email {
                        HStack {
                            Text("Email").foregroundStyle(Roam.ink)
                            Spacer(minLength: Theme.Spacing.m)
                            Text(email).foregroundStyle(Roam.inkMuted).lineLimit(1).truncationMode(.middle)
                        }
                        .padding(.vertical, Theme.Spacing.m)
                        RowSeparator(inset: 0)
                    }
                    // Theme red rather than system red, which is 3.6:1 on white.
                    row("Sign out", tint: Theme.disliked, chevron: false, id: "settings-sign-out") { confirmSignOut = true }
                    RowSeparator(inset: 0)
                    row("Delete account", tint: Theme.disliked, id: "settings-delete-account") { router.push(.deleteAccount) }
                }
                // App Review needs blocking to be reversible and reports to be visible, so Safety stays.
                section("Safety") {
                    row("Blocked people", icon: "hand.raised", id: "settings-blocked") { router.push(.safetyList(.blocked)) }
                    RowSeparator(inset: Self.iconInset)
                    row("Muted people", icon: "speaker.slash", id: "settings-muted") { router.push(.safetyList(.muted)) }
                    RowSeparator(inset: Self.iconInset)
                    row("Your reports", icon: "flag", id: "settings-reports") { router.push(.reportHistory) }
                }
                section("About") {
                    row("Support", icon: "questionmark.circle", id: "settings-help-support") { router.push(.help(.support)) }
                    RowSeparator(inset: Self.iconInset)
                    row("Privacy", icon: "lock", id: "settings-help-privacy") { router.push(.help(.privacy)) }
                    RowSeparator(inset: Self.iconInset)
                    row("Terms of use", icon: "doc.text", id: "settings-help-terms") { router.push(.help(.terms)) }
                    RowSeparator(inset: Self.iconInset)
                    HStack(spacing: Theme.Spacing.m) {
                        Image(systemName: "info.circle").frame(width: Self.iconWidth).foregroundStyle(Roam.ink)
                        Text("Version").foregroundStyle(Roam.ink)
                        Spacer(minLength: 0)
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                            .foregroundStyle(Roam.inkMuted)
                    }
                    .padding(.vertical, Theme.Spacing.m)
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.s)
        }
        .background(Roam.paper)
        .navigationTitle("Settings")
        // Just the back button here, no tab bar.
        .roamTabBar(hidden: true)
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
                            .tapID("settings-retry")
                        Button("Dismiss") { settings.dismissError() }.tapID("settingsview.dismiss")
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

    private static let iconWidth: CGFloat = 28
    /// Where a line starts in an icon row: past the icon, at the text.
    private static var iconInset: CGFloat { iconWidth + Theme.Spacing.m }

    /// A section: its name, small and grey, over a white card of rows.
    private func section<Rows: View>(_ title: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Roam.inkMuted)
                .padding(.leading, Theme.Spacing.m)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) { rows() }
                .roamCard(padding: Theme.Spacing.m)
        }
    }

    /// One standard row: an icon (if any), the title, and a chevron when it opens a page.
    private func row(_ title: String, icon: String? = nil, tint: Color = Roam.ink, chevron: Bool = true, id: String,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.m) {
                if let icon { Image(systemName: icon).frame(width: Self.iconWidth).foregroundStyle(Roam.ink) }
                Text(title).foregroundStyle(tint)
                Spacer(minLength: 0)
                if chevron {
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Roam.inkMuted)
                }
            }
            .padding(.vertical, Theme.Spacing.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tapID(id)
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
                .tapID("settings-haptics")
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
                .tapID("settings-notify-follows")
            Toggle("Likes on your posts", isOn: Binding(get: { settings.displayed.notifyLikes },
                                                        set: { value in Task { await settings.update { $0.notifyLikes = value } } }))
                .tapID("settings-notify-likes")
            Toggle("Comments on your posts", isOn: Binding(get: { settings.displayed.notifyComments },
                                                           set: { value in Task { await settings.update { $0.notifyComments = value } } }))
                .tapID("settings-notify-comments")
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
