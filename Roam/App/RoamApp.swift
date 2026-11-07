import SwiftUI
import UIKit

@main
struct RoamApp: App {
    @State private var services: AppServices
    @State private var session: SessionStore
    @State private var library: LibraryStore
    @State private var router: AppRouter
    @State private var destinations: DestinationStore
    @State private var activityChanges = ActivityChangeStore()
    @State private var settingsStore: SettingsStore

    init() {
        let services = AppServices.make()
        _services = State(initialValue: services)
        _session = State(initialValue: SessionStore(services: services))
        _library = State(initialValue: LibraryStore(services: services))
        _router = State(initialValue: AppRouter(initialTab: services.options.initialTab ?? .forYou))
        _destinations = State(initialValue: DestinationStore(storage: services.storage))
        _settingsStore = State(initialValue: SettingsStore(service: services.settings, storage: services.storage))
        let largeTitle = UIFont.preferredFont(forTextStyle: .largeTitle)
        if let rounded = largeTitle.fontDescriptor.withSymbolicTraits(.traitBold)?.withDesign(.rounded) {
            UINavigationBar.appearance().largeTitleTextAttributes = [.font: UIFont(descriptor: rounded, size: 0)]
        }
        if services.options.uiTesting {
            UIView.setAnimationsEnabled(false)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // Dragging any list or page puts the keyboard away, as in Apple's own apps.
                .scrollDismissesKeyboard(.interactively)
                .environment(services)
                .environment(session)
                .environment(library)
                .environment(router)
                .environment(destinations)
                .environment(activityChanges)
                .environment(settingsStore)
                .environment(services.images)
                .tint(Roam.ink)
                .background(Roam.paper)
                .onOpenURL { url in
                    Task { await handleOpenURL(url) }
                }
        }
    }

    /// Only `roam://auth-callback` is handled; external content deep links are deferred.
    @MainActor
    private func handleOpenURL(_ url: URL) async {
        guard url.scheme == "roam", url.host == "auth-callback" else { return }
        do {
            switch try await services.auth.handleCallback(url) {
            case .signedIn(let auth):
                await session.didAuthenticate(auth)
            case .passwordRecovery(let auth):
                session.isRecoveringPassword = true
                await session.didAuthenticate(auth)
            }
        } catch {
            session.callbackError = error.roamMessage
        }
    }
}
