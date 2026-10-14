import SwiftUI

struct ListsRootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(AppServices.self) private var services
    @State private var kind: ListKind = .been
    @State private var showsCoachmark = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("List", selection: $kind) {
                ForEach(ListKind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(Theme.Spacing.l)
            ScrollView {
                if kind == .been {
                    EmptyStateView(systemImage: "checkmark.seal", title: "Nothing ranked yet",
                                   message: "Log a place you've been and Roam ranks it within its category.",
                                   primaryTitle: "Search experiences", primaryAction: { router.selectedTab = .search })
                } else {
                    EmptyStateView(systemImage: "bookmark", title: "No saved experiences",
                                   message: "Save places you want to go. They'll wait here until you've been.",
                                   primaryTitle: "Explore", primaryAction: { router.selectedTab = .explore })
                }
            }
        }
        .background(Theme.groupedCanvas)
        .overlay {
            if session.profile?.hasSeenBeenIntro == false {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    BeenIntroCard {
                        Task {
                            await session.markBeenIntroSeen()
                            showsCoachmark = true
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if showsCoachmark {
                LogCoachmark { showsCoachmark = false }
            }
        }
        .navigationTitle("Your Lists")
        .screenIdentifier("lists-root")
    }
}
