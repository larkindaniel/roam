import SwiftUI

/// S04: search a city/locality with region/country shown to disambiguate same-name places.
/// "Use current location" asks for permission only when tapped.
struct DestinationPickerSheet: View {
    let purpose: DestinationPickerPurpose
    var title: String?
    /// When set, the chosen city goes here instead of the shared destination store.
    var onPick: ((Destination) -> Void)?

    @Environment(AppServices.self) private var services
    @Environment(DestinationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var placeSearch = PlaceSearch()
    @State private var locationMessage: String?
    @State private var locating = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    if purpose != .homeCity && query.isEmpty {
                        Button { Task { await useCurrentLocation() } } label: {
                            HStack {
                                Label("Use current location", systemImage: "location.fill")
                                Spacer()
                                if locating { ProgressView() }
                            }
                            .frame(minHeight: Theme.minimumHitTarget)
                        }
                        .disabled(locating)
                        .roamCard(padding: Theme.Spacing.m)
                        .accessibilityIdentifier("use-current-location")
                        if let locationMessage {
                            Text(locationMessage).font(.footnote).foregroundStyle(Theme.secondaryText)
                                .accessibilityIdentifier("location-message")
                        }
                    }
                    // Search 1, worldwide, keeping only its cities: a city is all this can take.
                    if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                        PlaceSearchResults(query: query, placeSearch: placeSearch, kinds: .cities) { result in
                            guard case .city(let city) = result else { return }
                            pick(city)
                            dismiss()
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.s)
            }
            .background(Roam.paper)
            .safeAreaInset(edge: .top, spacing: 0) {
                SearchSheetBar(prompt: title ?? "City or town", text: $query, focus: $searchFocused, identifier: "destination-search") { dismiss() }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { searchFocused = true }
            .task(id: query) { await placeSearch.run(query, services: services) }
        }
        .roamSheetStyle()
        .screenIdentifier("destination-picker")
    }

    private func pick(_ destination: Destination) {
        if let onPick { onPick(destination) } else { store.select(destination, for: purpose) }
    }

    private func useCurrentLocation() async {
        locating = true
        defer { locating = false }
        let outcome = await services.location.currentLocation()
        switch outcome {
        case .located(let coordinate, _):
            if let destination = try? await services.places.destination(for: coordinate) {
                pick(destination)
                locationMessage = outcome.message
                dismiss()
            } else {
                locationMessage = LocationOutcome.unavailable.message
            }
        default:
            locationMessage = outcome.message
        }
    }
}
