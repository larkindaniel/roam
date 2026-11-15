import SwiftUI

struct SignUpView: View {
    @Bindable var model: AuthFlowModel

    var body: some View {
        AuthFormScaffold(title: "Create your account", message: "We'll email you a code to confirm it.",
                         actionTitle: "Create account", actionEnabled: model.emailIssue == nil && model.passwordIssue == nil,
                         busy: model.busy, action: { Task { await model.signUp() } }) {
            RoamTextField(title: "Email", text: $model.email, contentType: .username, keyboard: .emailAddress, identifier: "email-field")
            RoamTextField(title: "Password", text: $model.password, isSecure: true, contentType: .newPassword,
                          hint: "\(Limits.passwordMin)–\(Limits.passwordMax) characters. A passphrase works well.", identifier: "password-field")
            if let error = model.error { ErrorText(error) }
        } footer: {
            Button("I already have an account") { model.path = [.signIn] }
                .buttonStyle(QuietButtonStyle())
        }
        .navigationTitle("")
        .screenIdentifier("sign-up")
    }
}

struct VerifyEmailView: View {
    @Bindable var model: AuthFlowModel

    var body: some View {
        AuthFormScaffold(title: "Check your email", message: "Enter the 6-digit code we sent to \(model.email).",
                         actionTitle: "Confirm email", actionEnabled: model.code.count == 6, busy: model.busy,
                         action: { Task { await model.verifySignUp() } }) {
            RoamTextField(title: "Code", text: $model.code, contentType: .oneTimeCode, keyboard: .numberPad, identifier: "code-field")
                .onChange(of: model.code) { _, value in model.code = String(value.filter(\.isNumber).prefix(6)) }
            if let info = model.info { InfoText(info) }
            if let error = model.error { ErrorText(error) }
        } footer: {
            Button("Send a new code") { Task { await model.resendCode() } }
                .buttonStyle(QuietButtonStyle())
                .disabled(model.busy)
                .accessibilityIdentifier("resend-code")
        }
        .screenIdentifier("verify-email")
    }
}

struct SignInView: View {
    @Bindable var model: AuthFlowModel

    var body: some View {
        AuthFormScaffold(title: "Welcome back", message: "", actionTitle: "Sign in",
                         actionEnabled: model.emailIssue == nil && !model.password.isEmpty, busy: model.busy,
                         action: { Task { await model.signIn() } }) {
            RoamTextField(title: "Email", text: $model.email, contentType: .username, keyboard: .emailAddress, identifier: "email-field")
            RoamTextField(title: "Password", text: $model.password, isSecure: true, contentType: .password, identifier: "password-field")
            if let error = model.error { ErrorText(error) }
        } footer: {
            Button("Forgot password?") { model.path.append(.forgot) }
                .buttonStyle(QuietButtonStyle())
                .accessibilityIdentifier("forgot-password")
        }
        .screenIdentifier("sign-in")
    }
}

struct ForgotPasswordView: View {
    @Bindable var model: AuthFlowModel

    var body: some View {
        AuthFormScaffold(title: "Reset your password", message: "We'll email you a 6-digit code.",
                         actionTitle: "Send reset code", actionEnabled: model.emailIssue == nil, busy: model.busy,
                         action: { Task { await model.requestReset() } }) {
            RoamTextField(title: "Email", text: $model.email, contentType: .username, keyboard: .emailAddress, identifier: "email-field")
            if let error = model.error { ErrorText(error) }
        } footer: { EmptyView() }
        .screenIdentifier("forgot-password-screen")
    }
}

struct ResetCodeView: View {
    @Bindable var model: AuthFlowModel

    var body: some View {
        AuthFormScaffold(title: "Enter your code", message: "Then you'll choose a new password.",
                         actionTitle: "Continue", actionEnabled: model.code.count == 6, busy: model.busy,
                         action: { Task { await model.verifyReset() } }) {
            if let info = model.info { InfoText(info) }
            RoamTextField(title: "Code", text: $model.code, contentType: .oneTimeCode, keyboard: .numberPad, identifier: "code-field")
                .onChange(of: model.code) { _, value in model.code = String(value.filter(\.isNumber).prefix(6)) }
            if let error = model.error { ErrorText(error) }
        } footer: {
            Button("Send another code") { Task { await model.requestReset() } }
                .buttonStyle(QuietButtonStyle())
                .disabled(model.busy)
        }
        .screenIdentifier("reset-code")
    }
}

/// Shown after a recovery code or link: the member must choose a new password before continuing.
struct SetNewPasswordView: View {
    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            AuthFormScaffold(title: "Choose a new password", message: "Use \(Limits.passwordMin)–\(Limits.passwordMax) characters.",
                             actionTitle: "Save password", actionEnabled: Validation.password(password) == nil, busy: busy,
                             action: { Task { await save() } }) {
                RoamTextField(title: "New password", text: $password, isSecure: true, contentType: .newPassword, identifier: "new-password-field")
                if let error { ErrorText(error) }
            } footer: {
                Button("Cancel and sign out") { Task { await session.signOut() } }
                    .buttonStyle(QuietButtonStyle())
            }
        }
        .screenIdentifier("set-new-password")
    }

    private func save() async {
        busy = true
        defer { busy = false }
        do {
            try await services.auth.updatePassword(password)
            password = ""
            session.isRecoveringPassword = false
        } catch {
            self.error = error.roamMessage
        }
    }
}
