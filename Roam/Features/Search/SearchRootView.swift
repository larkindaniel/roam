import SwiftUI

struct SearchRootView: View {
    @Environment(AppRouter.self) private var router
    @State private var segment: SearchSegment = .experiences

    var body: some View {
        VStack(spacing: 0) {
            Picker("Search for", selection: $segment) {
                ForEach(SearchSegment.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(Theme.Spacing.l)
            ScrollView {
                EmptyStateView(systemImage: segment == .experiences ? "magnifyingglass" : "person.2",
                               title: segment == .experiences ? "Search experiences" : "Find members",
                               message: segment == .experiences ? "Search restaurants, trails, museums, stays and day trips anywhere."
                                   : "Search by name or @handle.")
            }
        }
        .background(Theme.groupedCanvas)
        .navigationTitle("Search")
        .onChange(of: router.searchSegmentRequest) { _, request in
            if let request { segment = request; router.searchSegmentRequest = nil }
        }
        .screenIdentifier("search-root")
    }
}
