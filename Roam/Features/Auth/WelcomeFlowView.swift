import AuthenticationServices
import SwiftUI

/// S01: welcome, Apple/email sign-in, sign-up with verification and password recovery.
struct WelcomeFlowView: View {
    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @State private var model: AuthFlowModel?

    var body: some View {
        Group {
            if let model {
                WelcomeNavigation(model: model)
            } else {
                Color.clear
            }
        }
        .task {
            if model == nil { model = AuthFlowModel(services: services, session: session) }
        }
    }
}

private struct WelcomeNavigation: View {
    @Bindable var model: AuthFlowModel
    @Environment(SessionStore.self) private var session

    var body: some View {
        NavigationStack(path: $model.path) {
            WelcomeView(model: model)
                .navigationDestination(for: AuthRoute.self) { route in
                    switch route {
                    case .signUp: SignUpView(model: model)
                    case .signIn: SignInView(model: model)
                    case .verify: VerifyEmailView(model: model)
                    case .forgot: ForgotPasswordView(model: model)
                    case .resetCode: ResetCodeView(model: model)
                    }
                }
        }
        .onChange(of: model.path) { _, _ in model.clearMessages() }
        .overlay(alignment: .top) {
            if session.sessionExpired {
                Text("Your session expired. Sign in again to continue — your drafts are kept.")
                    .font(.footnote.weight(.semibold))
                    .padding(Theme.Spacing.m)
                    .frame(maxWidth: .infinity)
                    .background(Theme.fineFill)
                    .accessibilityIdentifier("session-expired-banner")
            }
        }
    }
}

struct WelcomeView: View {
    @Bindable var model: AuthFlowModel
    @Environment(SessionStore.self) private var session

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                WelcomeArtwork()
                    .frame(height: 260)
                    .accessibilityHidden(true)
                VStack(spacing: Theme.Spacing.s) {
                    Text("Roam")
                        .font(.system(size: 46, weight: .bold, design: .serif))
                        .foregroundStyle(Theme.accent)
                        .accessibilityAddTraits(.isHeader)
                    Text("Rank the places that made your trips.")
                        .font(.roamTitle(.title2))
                        .multilineTextAlignment(.center)
                    Text("Log trails, cafés, museums, stays and day trips. Compare them two at a time and Roam gives each a score out of 10.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)

                VStack(spacing: Theme.Spacing.m) {
                    SignInWithAppleButton(.continue) { request in
                        model.prepareAppleRequest(request)
                    } onCompletion: { result in
                        Task { await model.completeApple(result) }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .clipShape(Capsule())
                    .accessibilityIdentifier("sign-in-with-apple")

                    Button("Continue with email") { model.path.append(.signUp) }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("continue-with-email")

                    Button("I already have an account") { model.path.append(.signIn) }
                        .font(.headline)
                        .frame(minHeight: Theme.minimumHitTarget)
                        .accessibilityIdentifier("existing-account")
                }
                .padding(.horizontal, Theme.Spacing.xl)

                if let error = model.error ?? session.callbackError {
                    ErrorText(error)
                }

                Text("Profiles, ratings and public visit notes and photos are visible to other signed-in members. Private notes stay private.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
            }
            .padding(.vertical, Theme.Spacing.xl)
        }
        .background(Theme.groupedCanvas)
        .toolbar(.hidden, for: .navigationBar)
        .screenIdentifier("welcome")
    }
}

/// Original Roam artwork: a stylised globe with floating score markers.
struct WelcomeArtwork: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Theme.accent.opacity(0.85), Theme.accent.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 200, height: 200)
            Image(systemName: "globe.europe.africa.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 170, height: 170)
                .foregroundStyle(.white.opacity(0.9))
            marker("9.1", .liked).offset(x: -110, y: -70)
            marker("7.4", .liked).offset(x: 105, y: -95)
            marker("5.0", .fine).offset(x: 120, y: 50)
            marker("8.4", .liked).offset(x: -95, y: 85)
        }
    }

    private func marker(_ text: String, _ sentiment: Sentiment) -> some View {
        Text(text)
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(Theme.color(for: sentiment))
            .background(Capsule().fill(Theme.raisedCard))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }
}

struct ErrorText: View {
    let message: String
    init(_ message: String) { self.message = message }

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.disliked)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal)
            .accessibilityIdentifier("auth-error")
    }
}

struct InfoText: View {
    let message: String
    init(_ message: String) { self.message = message }

    var body: some View {
        Label(message, systemImage: "envelope.badge")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("auth-info")
    }
}

/// Shared form chrome: serif question title, explanation, fields, primary action.
struct AuthFormScaffold<Fields: View, Footer: View>: View {
    let title: String
    let message: String
    let actionTitle: String
    let actionEnabled: Bool
    let busy: Bool
    let action: () -> Void
    @ViewBuilder var fields: Fields
    @ViewBuilder var footer: Footer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Text(title).font(.roamDisplay(.title)).accessibilityAddTraits(.isHeader)
                Text(message).font(.body).foregroundStyle(.secondary)
                fields
                Button(action: action) {
                    if busy { ProgressView().tint(.white) } else { Text(actionTitle) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!actionEnabled || busy)
                .accessibilityIdentifier("auth-primary")
                footer
            }
            .padding(Theme.Spacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.groupedCanvas)
    }
}

struct RoamTextField: View {
    let title: String
    @Binding var text: String
    var isSecure = false
    var contentType: UITextContentType?
    var keyboard: UIKeyboardType = .default
    var hint: String?
    var identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            Group {
                if isSecure {
                    SecureField(title, text: $text)
                } else {
                    TextField(title, text: $text)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .textContentType(contentType)
            .padding(Theme.Spacing.m)
            .frame(minHeight: Theme.minimumHitTarget)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.raisedCard))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.hairline))
            .accessibilityIdentifier(identifier)
            if let hint {
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
