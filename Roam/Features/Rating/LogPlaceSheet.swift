import MapKit
import SwiftUI

/// + Add a place: one search for places and cities. A place goes on to its visit details; a city is simply marked as
/// somewhere you've been.
struct LogPlaceSheet: View {
    var onSaved: (LogRequest, RatingFlowCompletion) -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var library
    @State private var model: ExperienceSearchModel?
    @State private var cities: [Destination] = []
    /// A city picked from the results, asking when you were there.
    @State private var datingCity: Destination?
    @State private var query = ""
    @State private var request: LogRequest?
    @State private var opening: String?
    @State private var error: String?
    @State private var onRoam: [ExperienceSummary] = []
    @State private var addingPlace = false

    var body: some View {
        Group {
            if let request {
                RatingFlowView(request: request) { onSaved(request, $0) }
            } else {
                NavigationStack {
                    searchList
                        .scrollContentBackground(.hidden)
                        .background(Roam.paper)
                        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "A place or a city")
                        // Type as you like: no capitalising or correcting.
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .navigationTitle("Add a place")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { dismiss() }.accessibilityIdentifier("log-place-close")
                            }
                        }
                }
        .roamSheetStyle()
            }
        }
        .task { if model == nil { model = ExperienceSearchModel(services: services) } }
        .task(id: query) {
            if !query.isEmpty { services.location.requestAccessIfNeeded() }
            guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { model?.query = ""; onRoam = []; cities = []; return }
            try? await Task.sleep(for: Limits.searchDebounce)
            guard !Task.isCancelled else { return }
            async let known = services.plans.searchRoamPlaces(query: query)
            async let foundCities = services.places.searchDestinations(query: query)
            await model?.search(query, near: nil)
            onRoam = ((try? await known) ?? []).filter { $0.category != .dayTrips }
            cities = Array(((try? await foundCities) ?? []).prefix(3))
        }
        .sheet(item: $datingCity) { city in
            CityVisitDatesSheet(city: city) { library.noteChanged(); dismiss() }
        }
        .sheet(isPresented: $addingPlace) {
            AddCustomPlaceSheet(initialName: query) { place in Task { await choose(place) } }
                .presentationBackground(Roam.paper)
        }
        .screenIdentifier("log-place-sheet")
    }

    private var searchList: some View {
        List { Group {
            if let error { Text(error).foregroundStyle(Roam.signal).listRowBackground(Roam.paperRaised) }
            // Cities first: choosing one marks it as somewhere you've been, no place needed.
            ForEach(cities) { city in
                Button { datingCity = city } label: {
                    HStack(spacing: Theme.Spacing.m) {
                        Image(systemName: "building.2").foregroundStyle(PlaceState.visited.markerColor).frame(width: 24).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(city.name).font(.headline).foregroundStyle(Roam.ink)
                            Text(city.subtitle).font(.footnote).foregroundStyle(Roam.inkMuted)
                        }
                        Spacer(minLength: Theme.Spacing.s)
                        if opening == city.id { ProgressView() }
                    }
                    .frame(maxWidth: .infinity, minHeight: Theme.minimumHitTarget, alignment: .leading)
                }
                .disabled(opening != nil)
                .accessibilityIdentifier("log-place-city-\(city.name)")
                .listRowBackground(Roam.paperRaised)
            }
            ForEach(onRoam) { place in
                Button { Task { await choose(place) } } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name).font(.headline).foregroundStyle(Roam.ink)
                        Text(place.areaLine).font(.footnote).foregroundStyle(Roam.inkMuted)
                    }
                    .frame(maxWidth: .infinity, minHeight: Theme.minimumHitTarget, alignment: .leading)
                }
                .accessibilityIdentifier("log-place-known-\(place.name)")
                .listRowBackground(Roam.paperRaised)
            }
            switch model?.phase ?? .idle {
            case .idle:
                EmptyView()
            case .loading:
                HStack { ProgressView(); Text("Searching…").foregroundStyle(Roam.inkMuted) }.listRowBackground(Roam.paperRaised)
            case .failed(let message):
                InlineRetryView(message: message) { Task { await model?.search(query, near: nil) } }.listRowBackground(Roam.paperRaised)
            case .noResults:
                if onRoam.isEmpty {
                    Text("No places match \u{201C}\(query)\u{201D}.").foregroundStyle(Roam.inkMuted)
                        .accessibilityIdentifier("log-place-no-results").listRowBackground(Roam.paperRaised)
                }
            case .results:
                ForEach((model?.hits ?? []).filter { hit in !onRoam.contains { $0.name.lowercased() == hit.candidate.name.lowercased() } }) { hit in
                    Button { Task { await choose(hit) } } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hit.candidate.name).font(.headline).foregroundStyle(Roam.ink)
                                Text(hit.candidate.address ?? [hit.candidate.locality, hit.candidate.countryName].compactMap { $0 }.joined(separator: ", "))
                                    .font(.footnote).foregroundStyle(Roam.inkMuted).lineLimit(2)
                            }
                            Spacer(minLength: Theme.Spacing.s)
                            if opening == hit.id { ProgressView() }
                        }
                        .frame(minHeight: Theme.minimumHitTarget)
                    }
                    .disabled(opening != nil)
                    .accessibilityIdentifier("log-place-result-\(hit.candidate.name)")
                    .listRowBackground(Roam.paperRaised)
                }
            }
        }
        .listRowBackground(Roam.paperRaised)
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) {
            if !query.isEmpty {
                Button("Can't find it? Add it yourself") { addingPlace = true }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .padding(.bottom, Theme.Spacing.s)
                    .accessibilityIdentifier("log-place-add-custom")
            }
        }
    }

    private func choose(_ place: ExperienceSummary) async {
        do {
            var logRequest = try await services.makeLogRequest(experienceID: place.id)
            logRequest.startsWithDetails = true
            request = logRequest
        } catch { self.error = error.roamMessage }
    }

    private func choose(_ hit: SearchHit) async {
        opening = hit.id
        defer { opening = nil }
        do {
            guard let model else { return }
            let summary = try await model.resolve(hit)
            var logRequest = try await services.makeLogRequest(experienceID: summary.id)
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
