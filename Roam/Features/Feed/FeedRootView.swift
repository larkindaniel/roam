import SwiftUI

struct FeedRootView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView {
            EmptyStateView(systemImage: "person.2.wave.2", title: "Your feed is quiet",
                           message: "Follow travellers to see their rankings here, newest first. Your own ratings appear here too.",
                           primaryTitle: "Find people", primaryAction: { router.showFindPeople() },
                           secondaryTitle: "Search experiences", secondaryAction: { router.selectedTab = .search })
                .padding(.top, Theme.Spacing.xxl)
        }
        .background(Theme.groupedCanvas)
        .navigationTitle("Feed")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Roam").font(.system(.title2, design: .serif).weight(.bold)).foregroundStyle(Theme.accent)
                    .fixedSize()
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel("Roam feed")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .screenIdentifier("feed-root")
    }
}
