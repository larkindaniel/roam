import SwiftUI

struct RootView: View {
    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router
    @Environment(DestinationStore.self) private var destinations
    @Environment(ActivityChangeStore.self) private var activityChanges
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        Group {
            #if ROAM_FIXTURES
            if services.options.showComponentCatalog {
                ComponentCatalogView()
            } else {
                content
            }
            #else
            content
            #endif
        }
        .environment(\.roamDistanceUnit, settingsStore.applied.distanceUnit)
        .environment(\.roamHapticsEnabled, settingsStore.applied.hapticsEnabled)
        .task { await session.bootstrap() }
        .onChange(of: session.userID) { _, _ in
            library.reset()
            destinations.reset()
            activityChanges.reset()
            settingsStore.reset()
            router.reset(initialTab: services.options.initialTab ?? .feed)
        }
    }

    @ViewBuilder private var content: some View {
        if session.isRecoveringPassword && session.userID != nil {
            SetNewPasswordView()
        } else {
            switch session.phase {
            case .launching:
                LaunchView()
            case .notConfigured:
                ConfigurationMissingView()
            case .restoreFailed(let message):
                RestoreFailedView(message: message)
            case .signedOut:
                WelcomeFlowView()
            case .needsProfile(let auth):
                ProfileSetupFlowView(auth: auth)
                    .id(auth.userID)
            case .ready:
                MainTabView()
                    .id(session.userID)
                    .task(id: session.userID) {
                        let owner = session.userID
                        if let owner { Task { await settingsStore.load(userID: owner) } }
                        await library.refresh()
                        guard owner == session.userID else { return }
                        if let userID = session.userID {
                            destinations.load(userID: userID, home: session.profile?.homeCity)
                        }
                        if session.consumeJustCompletedSetup() {
                            router.reset(initialTab: .lists)
                        }
                        if let retained = session.pendingRouteAfterReauth {
                            session.pendingRouteAfterReauth = nil
                            router.push(retained)
                        }
                        #if ROAM_FIXTURES
                        if services.options.initialRoute == "globe", let userID = session.userID {
                            router.push(.globe(userID))
                        }
                        #endif
                    }
            }
        }
    }
}

struct LaunchView: View {
    @ScaledMetric(relativeTo: .largeTitle) private var wordmarkSize: CGFloat = 44

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Text("Roam")
                .font(.system(size: wordmarkSize, weight: .bold, design: .serif))
                .foregroundStyle(Theme.accent)
            ProgressView("Opening your travels…")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.groupedCanvas)
        .screenIdentifier("launch-view")
    }
}

struct RestoreFailedView: View {
    let message: String
    @Environment(SessionStore.self) private var session

    var body: some View {
        EmptyStateView(systemImage: "wifi.exclamationmark", title: "Couldn't open Roam", message: message,
                       primaryTitle: "Try again", primaryAction: { Task { await session.bootstrap() } },
                       secondaryTitle: "Sign in again", secondaryAction: { Task { await session.signOut() } })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.groupedCanvas)
    }
}

struct ConfigurationMissingView: View {
    var body: some View {
        EmptyStateView(systemImage: "gearshape.2", title: "Roam isn't configured",
                       message: "This build has no backend URL or publishable key. Run scripts/configure-local.sh, then rebuild.")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.groupedCanvas)
    }
}
