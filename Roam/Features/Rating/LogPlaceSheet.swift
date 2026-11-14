import MapKit
import SwiftUI

/// + Add a place: one search for places and cities. A place goes on to its visit details; a city is simply marked as
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
    @State private var addingPlace = false
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
                    .safeAreaInset(edge: .top, spacing: 0) {
                        RoamSearchField(prompt: "A place or a city", text: $query, focus: $searchFocused, identifier: "log-place-search")
                            .frame(height: 44)
                            .padding(.horizontal, Theme.Spacing.l)
                            .padding(.vertical, Theme.Spacing.s)
                    }
                    .safeAreaInset(edge: .bottom) {
                        if hasQuery {
                            Button("Can't find it? Add it yourself") { addingPlace = true }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                                .padding(.bottom, Theme.Spacing.s)
                                .accessibilityIdentifier("log-place-add-custom")
                        }
                    }
                    .navigationTitle("Add a place")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { dismiss() }.accessibilityIdentifier("log-place-close")
                        }
                    }
                    .onAppear { searchFocused = true }
                }
                .roamSheetStyle()
            }
        }
        .task(id: query) { await placeSearch.run(query, services: services) }
        .sheet(item: $datingCity) { city in
            CityVisitDatesSheet(city: city) { library.noteChanged(); dismiss() }
        }
        .sheet(isPresented: $addingPlace) {
            AddCustomPlaceSheet(initialName: query) { place in Task { await choose(.experience(place)) } }
                .presentationBackground(Roam.paper)
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

/// Adds a place no provider has: a name, a category and a position on the map.
struct AddCustomPlaceSheet: View {
    @State var name: String
    var onAdded: (ExperienceSummary) -> Void

    @Environment(AppServices.self) private var services
    @Environment(DestinationStore.self) private var destinations
    @Environment(\.dismiss) private var dismiss
    @State private var category: ExperienceCategory?
    @State private var center: CLLocationCoordinate2D?
    @State private var camera: MapCameraPosition = .automatic
    @State private var saving = false
    @State private var error: String?

    init(initialName: String, onAdded: @escaping (ExperienceSummary) -> Void) {
        _name = State(initialValue: initialName)
        self.onAdded = onAdded
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && category != nil && center != nil && !saving
    }

    var body: some View {
        NavigationStack {
            Form { Group {
                Section {
                    TextField("Place name", text: $name).accessibilityIdentifier("custom-place-name")
                    Picker("Category", selection: $category) {
                        Text("Choose").tag(ExperienceCategory?.none)
                        ForEach(ExperienceCategory.allCases) { Text($0.title).tag(Optional($0)) }
                    }
                    .accessibilityIdentifier("custom-place-category")
                }
                .listRowBackground(Roam.paperRaised)
                Section("Move the map so the pin is on the place") {
                    Map(position: $camera)
                        .onMapCameraChange(frequency: .onEnd) { center = $0.region.center }
                        .overlay { Image(systemName: "mappin").font(.title).foregroundStyle(Roam.ink).offset(y: -12).allowsHitTesting(false) }
                        .frame(height: 280)
                        .listRowInsets(EdgeInsets())
                        .accessibilityLabel("Map for choosing where this place is")
                }
                if let error { Section { Text(error).foregroundStyle(Roam.signal) }.listRowBackground(Roam.paperRaised) }
            }
            .listRowBackground(Roam.paperRaised)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Add a place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await save() } }.disabled(!canSave).accessibilityIdentifier("custom-place-save")
                }
            }
            .onAppear {
                let start = destinations.lastSelected?.coordinate ?? CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38)
                camera = .region(MKCoordinateRegion(center: start, latitudinalMeters: 8_000, longitudinalMeters: 8_000))
                center = start
            }
        }
        .roamSheetStyle()
    }

    private func save() async {
        guard let center, let category else { return }
        saving = true
        defer { saving = false }
        do {
            let area = try? await services.places.destination(for: center)
            let place = try await services.plans.addCustomPlace(name: name, coordinate: center, category: category, area: area)
            dismiss()
            onAdded(place)
        } catch { self.error = error.roamMessage }
    }
}
