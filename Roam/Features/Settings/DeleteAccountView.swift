import AuthenticationServices
import Observation
import SwiftUI

/// Account deletion (R13): explanation → recent reauthentication → explicit confirmation →
/// server-owned deletion. The status shown afterwards is the server's, pending or completed.
@MainActor
@Observable
final class DeleteAccountModel {
    enum Step: Equatable {
        case explain
        case reauthenticate
        case confirm
        case deleting
        case requested(AccountDeletionStatus)
    }

    private(set) var step: Step = .explain
    var password = ""
    private(set) var busy = false
    var error: String?
    let canUsePassword: Bool
    let canUseApple: Bool

    private let auth: any AuthService
    private let account: any AccountService
    private var appleNonce: String?

    init(auth: any AuthService, account: any AccountService, providers: [AuthProviderKind]) {
        self.auth = auth
        self.account = account
        canUsePassword = providers.contains(.email)
        canUseApple = providers.contains(.apple)
    }

    func begin() {
        error = nil
        step = .reauthenticate
    }

    func confirmPassword() async {
        guard !password.isEmpty, !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await auth.reauthenticate(password: password)
            password = ""
            step = .confirm
        } catch {
            self.error = error.roamMessage
        }
    }

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = AuthFlowModel.randomNonce()
        appleNonce = nonce
        request.requestedScopes = []
        request.nonce = AuthFlowModel.sha256(nonce)
    }

    /// Signing in with Apple again renews the sign-in time the server checks.
    func completeApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let failure):
            if let authError = failure as? ASAuthorizationError, authError.code == .canceled { return }
            error = "Sign in with Apple didn't complete. Try again."
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken, let token = String(data: tokenData, encoding: .utf8),
                  let nonce = appleNonce else {
                error = "Sign in with Apple didn't return a valid identity. Try again."
                return
            }
            busy = true
            defer { busy = false; appleNonce = nil }
            do {
                _ = try await auth.signInWithApple(idToken: token, rawNonce: nonce)
                error = nil
                step = .confirm
            } catch {
                self.error = error.roamMessage
            }
        }
    }

    func delete() async {
        guard step == .confirm else { return }
        step = .deleting
        error = nil
        do {
            step = .requested(try await account.requestDeletion())
        } catch RoamError.reauthenticationRequired {
            error = RoamError.reauthenticationRequired.roamMessage
            step = .reauthenticate
        } catch {
            self.error = "Your account wasn't deleted. \(error.roamMessage)"
            step = .confirm
        }
    }

    /// Honest progress for the requested job; nothing claims completion before the server does.
    static func statusLines(_ status: AccountDeletionStatus) -> [String] {
        var lines: [String] = []
        if status.state == .completed {
            lines.append("Your account and its data have been deleted.")
        } else {
            lines.append("Your profile is hidden from everyone and you've been signed out on every device.")
            lines.append("Roam is deleting your rankings, visits, notes, photos, friends and posts. This is still in progress.")
        }
        switch status.appleRevocation {
        case "pending": lines.append("Roam will also revoke its Sign in with Apple access when deletion finishes.")
        case "completed": lines.append("Roam's Sign in with Apple access was revoked.")
        case "not_configured", "failed":
            lines.append("Roam couldn't revoke Sign in with Apple automatically. You can stop using Sign in with Apple for Roam in your Apple Account settings.")
        default: break
        }
        return lines
    }
}

struct DeleteAccountView: View {
    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(SettingsStore.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router
    @Environment(DestinationStore.self) private var destinations
    @Environment(ActivityChangeStore.self) private var activityChanges
    @State private var model: DeleteAccountModel?
    @State private var showsFinalConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                if let model { content(model) }
            }
            .padding()
        }
        .background(Theme.groupedCanvas)
        .navigationTitle("Delete account")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isFinished)
        // After the request the account can't act anywhere; Done is the only way on.
        .roamTabBar(hidden: isFinished)
        .task {
            if model == nil {
                model = DeleteAccountModel(auth: services.auth, account: services.account, providers: session.session?.providers ?? [])
            }
        }
        .confirmationDialog("Delete your account permanently?", isPresented: $showsFinalConfirmation, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) { Task { await model?.delete() } }
                .accessibilityIdentifier("delete-account-final")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
        .screenIdentifier("delete-account")
    }

    private var isFinished: Bool {
        if case .requested = model?.step { return true }
        return false
    }

    @ViewBuilder private func content(_ model: DeleteAccountModel) -> some View {
        switch model.step {
        case .explain:
            explanation
            Button("Continue") { model.begin() }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("delete-account-continue")
        case .reauthenticate:
            reauthentication(model)
        case .confirm:
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Label("You're confirmed", systemImage: "checkmark.shield").font(.headline)
                Text("Deleting now removes your profile for everyone straight away. The rest of your data is deleted on Roam's server.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .roamCard()
            errorText(model)
            Button("Delete my account", role: .destructive) { showsFinalConfirmation = true }
                .buttonStyle(PrimaryButtonStyle(fill: Theme.destructive))
                .accessibilityIdentifier("delete-account-confirm")
        case .deleting:
            ProgressView("Deleting your account…")
                .frame(maxWidth: .infinity)
                .padding(.top, Theme.Spacing.xl)
                .accessibilityIdentifier("delete-account-progress")
        case .requested(let status):
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Label(status.state == .completed ? "Account deleted" : "Account deletion started",
                      systemImage: status.state == .completed ? "checkmark.circle" : "hourglass")
                    .font(.headline)
                ForEach(DeleteAccountModel.statusLines(status), id: \.self) { line in
                    Text(line).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .roamCard()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("delete-account-status")
            Button("Done") { Task { await finish(status) } }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("delete-account-done")
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Deleting your account permanently removes:").font(.headline)
            ForEach(["Your rankings and scores", "Your visits, public and private notes, and photos", "Your wishlist, plans and lists",
                     "Your friends and friend requests", "Your posts, likes and comments"], id: \.self) { item in
                Label(item, systemImage: "minus.circle").foregroundStyle(.primary)
            }
            Text("Your profile disappears for everyone straight away and you're signed out on every device. Text you've already shared outside Roam can't be recalled. Reports you've filed stay with Roam's operators without your name.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .roamCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("delete-account-explanation")
    }

    @ViewBuilder private func reauthentication(_ model: DeleteAccountModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Confirm it's you").font(.headline)
            Text("For your security, sign in again before deleting your account.")
                .font(.subheadline).foregroundStyle(Theme.secondaryText)
            if model.canUsePassword {
                SecureField("Password", text: Bindable(model).password)
                    .textContentType(.password)
                    .submitLabel(.continue)
                    .onSubmit { Task { await model.confirmPassword() } }
                    .padding(Theme.Spacing.m)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.subtleFill))
                    .accessibilityIdentifier("delete-account-password")
                Button {
                    Task { await model.confirmPassword() }
                } label: {
                    if model.busy { ProgressView().tint(Roam.onInk) } else { Text("Confirm password") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.password.isEmpty || model.busy)
                .accessibilityIdentifier("delete-account-reauth")
            }
            if model.canUseApple {
                SignInWithAppleButton(.signIn) { request in
                    model.prepareAppleRequest(request)
                } onCompletion: { result in
                    Task { await model.completeApple(result) }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .clipShape(Capsule())
                .accessibilityIdentifier("delete-account-apple")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .roamCard()
        errorText(model)
    }

    @ViewBuilder private func errorText(_ model: DeleteAccountModel) -> some View {
        if let error = model.error {
            Text(error)
                .font(.subheadline)
                .foregroundStyle(Theme.destructive)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("delete-account-error")
        }
    }

    /// The server already revoked the sessions; drop the local session, caches and drafts.
    private func finish(_ status: AccountDeletionStatus) async {
        let notice = status.state == .completed
            ? "Your Roam account was deleted."
            : "Your Roam account is being deleted. Your profile is already hidden; the rest of your data is removed on Roam's server."
        library.reset()
        destinations.reset()
        activityChanges.reset()
        settings.reset()
        router.reset(initialTab: .forYou)
        await session.accountDeleted(notice: notice)
    }
}
