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
    @State private var results: LoadPhase<[Destination]> = .idle
    @State private var locationMessage: String?
    @State private var locating = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            List { Group {
                if purpose != .homeCity {
                    Section {
                        Button {
                            Task { await useCurrentLocation() }
                        } label: {
                            HStack {
                                Label("Use current location", systemImage: "location.fill")
                                Spacer()
                                if locating { ProgressView() }
                            }
                        }
                        .disabled(locating)
                        .accessibilityIdentifier("use-current-location")
                        if let locationMessage {
                            Text(locationMessage).font(.footnote).foregroundStyle(Theme.secondaryText)
                                .accessibilityIdentifier("location-message")
                        }
                    }
                }
                Section {
                    switch results {
                    case .idle:
                        EmptyView()
                    case .loading:
                        HStack { ProgressView(); Text("Searching…").foregroundStyle(Theme.secondaryText) }
                    case .failed(let message):
                        InlineRetryView(message: message) { Task { await search(query) } }
                    case .loaded(let destinations) where destinations.isEmpty:
                        Text("No places match “\(query)”.").foregroundStyle(Theme.secondaryText)
                            .accessibilityIdentifier("destination-no-results")
                    case .loaded(let destinations):
                        ForEach(destinations) { destination in
                            Button {
                                pick(destination)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(destination.name).font(.headline).foregroundStyle(.primary)
                                    if !destination.subtitle.isEmpty {
                                        Text(destination.subtitle).font(.subheadline).foregroundStyle(Theme.secondaryText)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(minHeight: Theme.minimumHitTarget)
                            }
                            .accessibilityIdentifier("destination-\(destination.name)-\(destination.region ?? "")")
                        }
                    }
                }
            }
            .listRowBackground(Roam.paperRaised)
            }
            // Just a search bar with an × beside it that closes the sheet; no title bar.
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: Theme.Spacing.s) {
                    HStack(spacing: Theme.Spacing.s) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Roam.inkMuted).accessibilityHidden(true)
                        TextField(title ?? "City or town", text: $query)
                            .focused($searchFocused)
                            .submitLabel(.search)
                            // Type as you like: no capitalising or correcting.
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("destination-search")
                    }
                    .padding(.horizontal, Theme.Spacing.m)
                    .frame(height: 44)
                    .background(Capsule().fill(Roam.ink.opacity(0.08)))
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.headline).foregroundStyle(Roam.ink).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .floatingBubble(Circle())
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("close-destination-picker")
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.s)
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { searchFocused = true }
            .task(id: query) {
                // 300 ms debounce; a newer query cancels this task, so stale results never land.
                let current = query
                guard !current.trimmingCharacters(in: .whitespaces).isEmpty else { results = .idle; return }
                try? await Task.sleep(for: Limits.searchDebounce)
                guard !Task.isCancelled else { return }
                await search(current)
            }
        }
        .roamSheetStyle()
        .screenIdentifier("destination-picker")
    }

    private func pick(_ destination: Destination) {
        if let onPick { onPick(destination) } else { store.select(destination, for: purpose) }
    }

    private func search(_ text: String) async {
        services.location.requestAccessIfNeeded()
        results = .loading
        do {
            let found = try await services.places.searchDestinations(query: text)
            guard !Task.isCancelled, text == query else { return }
            results = .loaded(found)
        } catch is CancellationError {
        } catch {
            guard text == query else { return }
            results = .failed(error.roamMessage)
        }
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
