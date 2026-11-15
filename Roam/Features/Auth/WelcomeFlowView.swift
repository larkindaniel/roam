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

/// The first screen: the Roam logo (the app icon), the name and what it's for, then Continue with Apple and a grey
/// "I already have an account" bubble pinned at the bottom, like the app's other bottom buttons.
struct WelcomeView: View {
    @Bindable var model: AuthFlowModel
    @Environment(SessionStore.self) private var session
    @Environment(AppServices.self) private var services
    /// The name, big under the logo; it scales with Dynamic Type.
    @ScaledMetric(relativeTo: .largeTitle) private var wordmarkSize: CGFloat = 64

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Theme.Spacing.xl)
            VStack(spacing: Theme.Spacing.l) {
                // As big as the screen allows: the full width inside the margins, short of crowding the words and buttons.
                GeometryReader { proxy in
                    RoamLogo(size: min(proxy.size.width, proxy.size.height))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxHeight: 340)
                VStack(spacing: Theme.Spacing.s) {
                    Text("Roam")
                        .font(.system(size: wordmarkSize, weight: .bold, design: .rounded))
                        .foregroundStyle(Roam.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("Find places you love\nfrom people you trust.")
                        .font(.title3)
                        .foregroundStyle(Roam.inkMuted)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
            Spacer(minLength: Theme.Spacing.xl)
            VStack(spacing: Theme.Spacing.m) {
                if let error = model.error ?? session.callbackError {
                    ErrorText(error)
                }
                if let notice = session.deletionNotice {
                    Label(notice, systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("deletion-notice")
                }
                SignInWithAppleButton(.continue) { request in
                    model.prepareAppleRequest(request)
                } onCompletion: { result in
                    Task { await model.completeApple(result) }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .clipShape(Capsule())
                .accessibilityIdentifier("sign-in-with-apple")

                // Email sign-up is hidden for the beta (no hosted email sender yet). The flow stays
                // in the app; Debug UI tests still reach it to keep it covered.
                if showsEmailSignUp {
                    Button("Continue with email") { model.path.append(.signUp) }
                        .buttonStyle(GreyBubbleButtonStyle())
                        .accessibilityIdentifier("continue-with-email")
                }

                Button("I already have an account") { model.path.append(.signIn) }
                    .buttonStyle(GreyBubbleButtonStyle())
                    .accessibilityIdentifier("existing-account")
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Roam.paper)
        .toolbar(.hidden, for: .navigationBar)
        .screenIdentifier("welcome")
    }

    private var showsEmailSignUp: Bool {
        #if ROAM_FIXTURES
        return services.options.uiTesting
        #else
        return false
        #endif
    }
}

/// The Roam logo: the app icon, with its rounded-square corners and a soft shadow.
struct RoamLogo: View {
    var size: CGFloat = 180

    var body: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 18, y: 8)
            .accessibilityLabel("Roam")
    }
}

/// A full-width grey capsule, 50pt like the black one above it: the app's quieter bottom button.
struct GreyBubbleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Roam.ink)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Capsule().fill(Roam.fill))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
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
            .foregroundStyle(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("auth-info")
    }
}

/// Shared form chrome, like the app's other pages: the system's round glass back button, a big title, the fields, and
/// the black action pinned at the bottom.
struct AuthFormScaffold<Fields: View, Footer: View>: View {
    let title: String
    let actionTitle: String
    let actionEnabled: Bool
    let busy: Bool
    let action: () -> Void
    @ViewBuilder var fields: Fields
    @ViewBuilder var footer: Footer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                // Just the title: no line under it.
                Text(title).font(.roamDisplay(.title)).accessibilityAddTraits(.isHeader)
                VStack(spacing: Theme.Spacing.s) { fields }
                footer
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.s)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Roam.paper)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: action) {
                if busy { ProgressView().tint(Roam.onInk) } else { Text(actionTitle) }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!actionEnabled || busy)
            .accessibilityIdentifier("auth-primary")
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.s)
        }
        // The system back button: on iOS 26 it's the same round glass button as the rest of the app's pages.
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A form field like the app's search: a grey capsule with the prompt inside it, no border or label above.
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
            .padding(.horizontal, Theme.Spacing.l)
            .frame(height: 50)
            .background(Capsule().fill(Roam.fill))
            .accessibilityLabel(title)
            .accessibilityIdentifier(identifier)
            if let hint {
                Text(hint).font(.caption).foregroundStyle(Roam.inkMuted).padding(.horizontal, Theme.Spacing.l)
            }
        }
    }
}
