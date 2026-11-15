import SwiftUI

/// Log a place: one search for places and cities. A place goes on to its visit details; a city is simply marked as
/// somewhere you've been.
struct LogPlaceSheet: View {
    var onSaved: (LogRequest, RatingFlowCompletion) -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var library
    @State private var placeSearch = PlaceSearch()
    /// A city picked from the results, asking when you were there.
    @State private var datingCity: Destination?
    @State private var query = ""
    @State private var request: LogRequest?
    @State private var error: String?
    @FocusState private var searchFocused: Bool

    private var hasQuery: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        Group {
            if let request {
                RatingFlowView(request: request) { onSaved(request, $0) }
            } else {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                            if let error { Text(error).font(.footnote).foregroundStyle(Roam.signal) }
                            // Search 1, worldwide: a city is marked as somewhere you've been; a place goes on to its details.
                            if hasQuery {
                                PlaceSearchResults(query: query, placeSearch: placeSearch, kinds: [.places, .cities]) { pick in
                                    Task { await choose(pick) }
                                }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.l)
                        .padding(.vertical, Theme.Spacing.s)
                    }
                    .background(Roam.paper)
                    // Just the search bubble, with an × beside it that closes the sheet; no title bar.
                    .safeAreaInset(edge: .top, spacing: 0) {
                        SearchSheetBar(prompt: "Log a place", text: $query, focus: $searchFocused, identifier: "log-place-search") { dismiss() }
                    }
                    .toolbar(.hidden, for: .navigationBar)
                    .onAppear { searchFocused = true }
                }
                .roamSheetStyle()
            }
        }
        .task(id: query) { await placeSearch.run(query, services: services) }
        .sheet(item: $datingCity) { city in
            CityVisitDatesSheet(city: city) { library.noteChanged(); dismiss() }
        }
        .screenIdentifier("log-place-sheet")
    }

    private func choose(_ pick: PlaceSearchPick) async {
        do {
            let place: ExperienceSummary
            switch pick {
            case .city(let city): datingCity = city; return
            case .region, .country: return
            case .experience(let known): place = known
            case .place(let hit): place = try await placeSearch.resolve(hit)
            }
            var logRequest = try await services.makeLogRequest(experienceID: place.id)
            logRequest.startsWithDetails = true
            request = logRequest
        } catch { self.error = error.roamMessage }
    }
}
