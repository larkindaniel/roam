import SwiftUI

/// S26 settings. M2 provides the account foundations (identity, provider, password reset, sign out).
struct SettingsView: View {
    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router
    @Environment(DestinationStore.self) private var destinations
    @State private var resetMessage: String?
    @State private var confirmSignOut = false

    var body: some View {
        List {
            Section("Account") {
                if let email = session.session?.email {
                    LabeledContent("Email", value: email)
                }
                LabeledContent("Signed in with", value: providerText)
                if session.session?.providers.contains(.email) == true {
                    Button("Email me a password reset code") { Task { await sendReset() } }
                        .accessibilityIdentifier("settings-password-reset")
                    if let resetMessage {
                        Text(resetMessage).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Button("Sign out", role: .destructive) { confirmSignOut = true }
                    .accessibilityIdentifier("settings-sign-out")
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Sign out of Roam?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                Task {
                    await session.signOut()
                    library.reset()
                    destinations.reset()
                    router.reset(initialTab: .feed)
                }
            }
        } message: {
            Text("Drafts and cached data on this device are removed. Everything you've saved to Roam stays in your account.")
        }
        .screenIdentifier("settings")
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
