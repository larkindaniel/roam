import SwiftUI

/// S01 welcome (expanded with Apple sign-in, sign-up and recovery in M2).
struct WelcomeFlowView: View {
    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @State private var email = ""
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.l) {
                    Text("Roam").font(.system(size: 48, weight: .bold, design: .serif)).foregroundStyle(Theme.accent)
                    Text("Rank every place you've been. Remember every trip.")
                        .font(.title3).multilineTextAlignment(.center)
                    TextField("Email", text: $email)
                        .textContentType(.username).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                        .padding().background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .padding().background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
                    if let error { Text(error).font(.footnote).foregroundStyle(Theme.disliked) }
                    Button(busy ? "Signing in…" : "Sign in") { Task { await signIn() } }
                        .buttonStyle(PrimaryButtonStyle()).disabled(busy || email.isEmpty || password.isEmpty)
                }
                .padding(Theme.Spacing.xl)
            }
        }
    }

    private func signIn() async {
        busy = true
        defer { busy = false }
        do {
            let auth = try await services.auth.signIn(email: email, password: password)
            await session.didAuthenticate(auth)
        } catch {
            self.error = error.roamMessage
        }
    }
}

/// Minimal profile setup (expanded in M2).
struct ProfileSetupFlowView: View {
    let auth: AuthSession
    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @State private var name = ""
    @State private var handle = ""
    @State private var error: String?

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            TextField("Display name", text: $name)
            TextField("Handle", text: $handle).textInputAutocapitalization(.never)
            if let error { Text(error).foregroundStyle(Theme.disliked) }
            Button("Continue") {
                Task {
                    do {
                        _ = try await services.profiles.createProfile(displayName: name, handle: handle)
                        let profile = try await services.profiles.setSetupCheckpoint(.complete)
                        session.completeSetup(profile)
                    } catch { self.error = error.roamMessage }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding()
    }
}

struct SetNewPasswordView: View {
    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @State private var password = ""
    @State private var error: String?

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            SecureField("New password", text: $password).textContentType(.newPassword)
            if let error { Text(error).foregroundStyle(Theme.disliked) }
            Button("Save password") {
                Task {
                    do {
                        try await services.auth.updatePassword(password)
                        session.isRecoveringPassword = false
                    } catch { self.error = error.roamMessage }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding()
    }
}
