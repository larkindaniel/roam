import SwiftUI

struct ListsRootView: View {
    @Environment(AppRouter.self) private var router
    @State private var kind: ListKind = .been

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
        .navigationTitle("Your Lists")
        .screenIdentifier("lists-root")
    }
}
