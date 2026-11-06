import CoreLocation
import PhotosUI
import SwiftUI

/// Somewhere you went on a city's log: a place, or a town or neighbourhood near it (West Vancouver, from Vancouver).
enum CityLogPick: Identifiable, Hashable {
    case place(SearchHit)
    case town(Destination)

    var id: String {
        switch self {
        case .place(let hit): return "place:\(hit.id)"
        case .town(let town): return "town:\(town.id)"
        }
    }
}

/// Logging a city, laid out like logging a place: its name and where it is, how it was, when, a note and Save. The one
/// difference is the places you went there (or nearby towns), added with a full-width button: places are logged as visits
/// without ratings, and a town is marked as been too.
struct CityLogSheet: View {
    let city: Destination
    var onSaved: () -> Void

    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var photos: PhotoDraftModel?
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var sentiment: Sentiment? = .fine
    @State private var start: Date?
    @State private var end: Date?
    @State private var note = ""
    @State private var places: [CityLogPick] = []
    @State private var addingPlaces = false
    @State private var saving = false
    @State private var error: String?
    @State private var confirmingDiscard = false

    private var hasChanges: Bool {
        sentiment != .fine || start != nil || end != nil || !note.isEmpty || !places.isEmpty || !(photos?.assets.isEmpty ?? true)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(city.name).font(.roamTitle())
                        Text(city.subtitle).font(.subheadline).foregroundStyle(Theme.secondaryText)
                    }
                    .accessibilityElement(children: .combine)
                    FeelingSlider(selection: $sentiment, enabled: true) { _ in }
                    DateRangeRow(start: $start, end: $end)
                    // The places you went here: rows with the add button as the last thing in the same card, like upcoming
                    // trips on My Places; with none yet, just the button.
                    if places.isEmpty {
                        addPlacesButton
                    } else {
                        VStack(spacing: 0) {
                            ForEach(places) { pick in
                                pickRow(pick)
                                if pick.id != places.last?.id { RowSeparator() }
                            }
                            addPlacesButton.padding(.top, Theme.Spacing.s)
                        }
                        .roamCard(padding: Theme.Spacing.m)
                    }
                    // Photos after the places, right above the note.
                    photoSection
                    NoteBox(text: $note)
                        .accessibilityIdentifier("city-log-note")
                    if let error { Text(error).font(.footnote).foregroundStyle(Roam.signal) }
                }
                .padding(Theme.Spacing.l)
            }
            .background(Roam.paper)
            .navigationTitle("Log a city")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { if hasChanges { confirmingDiscard = true } else { dismiss() } } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                        .disabled(saving)
                        // Pops up from the ×.
                        .confirmationDialog("Discard this log?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                            Button("Discard", role: .destructive) { Task { await photos?.discard(); dismiss() } }
                            Button("Keep editing", role: .cancel) {}
                        }
                }
            }
            // Save where the place log's is: see-through glass in the bottom buttons' spot.
            .tabBarSpotButton(true, title: saving ? "Saving…" : "Save", identifier: "city-log-save", systemImage: nil, tint: nil,
                              enabled: !saving && photos?.canCommit != false) {
                Task { await save() }
            }
            .sheet(isPresented: $addingPlaces) {
                CityPlacePicker(city: city, picked: $places)
            }
            .task {
                guard photos == nil, let userID = account.userID else { return }
                photos = PhotoDraftModel(ownerID: userID, draftID: "city-log-\(city.id)-photos", existingMedia: [],
                                         storage: services.storage, media: services.media, currentAccount: { account.userID })
            }
        }
        .roamSheetStyle()
        .presentationDetents([.large])
        .interactiveDismissDisabled(hasChanges)
        .screenIdentifier("city-log")
    }

    /// Photos as on a place's log: Add photos opens the picker; once there are some, they show one at a time.
    @ViewBuilder private var photoSection: some View {
        if let photos {
            Group {
                if photos.assets.isEmpty {
                    // The same grey, centred button as Add places, led by a photo icon.
                    PhotosPicker(selection: $pickedPhotos, selectionBehavior: .ordered, matching: .images) {
                        Label("Add photos", systemImage: "photo.on.rectangle")
                            .font(.subheadline.weight(.semibold))
                            .imageScale(.small)
                            .foregroundStyle(Roam.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Capsule().fill(Roam.fill))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    PhotoCarousel(model: photos) {
                        PhotosPicker(selection: $pickedPhotos, selectionBehavior: .ordered, matching: .images) {
                            Label("Add more", systemImage: "plus")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .frame(height: 36)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .floatingBubble(Capsule())
                        .environment(\.colorScheme, .dark)
                    }
                }
            }
            .accessibilityIdentifier("city-log-photos")
            .onChange(of: pickedPhotos) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    await PhotoImport.add(items, to: photos)
                    pickedPhotos = []
                }
            }
        }
    }

    private var addPlacesButton: some View {
        Button { addingPlaces = true } label: {
            Label(places.isEmpty ? "Add places" : "Add more places", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .imageScale(.small)
                // Black words on light grey.
                .foregroundStyle(Roam.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Capsule().fill(Roam.fill))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("city-log-add-places")
    }

    /// Somewhere you went, as the other rows look: its photo square with the green been mark, its name; the × takes it off.
    private func pickRow(_ pick: CityLogPick) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            ZStack(alignment: .bottomTrailing) {
                switch pick {
                case .place(let hit):
                    PlaceThumbnail(id: hit.id, url: hit.experience?.photoURL, coordinate: hit.candidate.coordinate,
                                   symbol: hit.experience?.iconName ?? hit.candidate.iconName, size: 48)
                case .town(let town):
                    PlaceThumbnail(id: "town-\(town.id)", url: nil, coordinate: town.coordinate, symbol: "signpost.right.and.left", size: 48)
                }
                StatusMark(state: .visited).scaleEffect(0.75).offset(x: 6, y: 6)
            }
            VStack(alignment: .leading, spacing: 2) {
                switch pick {
                case .place(let hit):
                    Text(hit.candidate.name).font(.headline).foregroundStyle(Roam.ink).lineLimit(1)
                    if let category = hit.category?.title { Text(category).font(.footnote).foregroundStyle(Roam.inkMuted) }
                case .town(let town):
                    Text(town.name).font(.headline).foregroundStyle(Roam.ink).lineLimit(1)
                    Text("City").font(.footnote).foregroundStyle(Roam.inkMuted)
                }
            }
            Spacer(minLength: 0)
            Button { places.removeAll { $0.id == pick.id } } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(Roam.inkFaint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove")
        }
        .padding(.vertical, Theme.Spacing.s)
    }

    private func save() async {
        saving = true
        defer { saving = false }
        error = nil
        let from = start.map { LocalDate(date: $0, timeZone: .current) }
        let to = end.map { LocalDate(date: $0, timeZone: .current) }
        do {
            let mediaIDs = try photos?.attachmentIDs() ?? []
            try await services.plans.logCity(city, start: from, end: to, sentiment: sentiment, note: note, mediaIDs: mediaIDs)
            photos?.committed()
            for pick in places {
                switch pick {
                case .town(let town):
                    // A nearby town you went to is somewhere you've been too, with the same dates.
                    try await services.plans.markCityVisited(town, start: from, end: to)
                case .place(let hit):
                    let place: ExperienceSummary
                    if let known = hit.experience { place = known } else { place = try await services.experiences.resolve(hit.candidate) }
                    // A visit with no rating; the place's own category files it (and its town counts as been).
                    let visit = VisitPayload(date: from, timeZoneIdentifier: TimeZone.current.identifier, publicNote: "", mediaIDs: [],
                                             audience: .public)
                    _ = try await services.ranking.addVisit(AddVisitRequest(operationID: UUID(), experienceID: place.id, visit: visit,
                                                                            category: place.category ?? hit.category ?? .activities))
                }
            }
            onSaved()
            dismiss()
        } catch { self.error = error.roamMessage }
    }
}

/// Adding somewhere you went in or near a city: the standard search (a bar and an × on one line), with anything within
/// about 60 km, towns and neighbourhoods included. Tapping a result adds it and closes.
private struct CityPlacePicker: View {
    let city: Destination
    @Binding var picked: [CityLogPick]

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var placeSearch = PlaceSearch()
    @FocusState private var searchFocused: Bool

    private static let nearby: CLLocationDistance = 60_000
    private var centre: CLLocation { CLLocation(latitude: city.latitude, longitude: city.longitude) }
    private func isNear(_ coordinate: CLLocationCoordinate2D) -> Bool {
        CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude).distance(from: centre) <= Self.nearby
    }

    private var towns: [Destination] {
        placeSearch.cities.filter { town in
            isNear(town.coordinate) && !(GeographyKey.normalize(town.name) == GeographyKey.normalize(city.name))
                && !picked.contains(.town(town))
        }
    }
    private var places: [SearchHit] {
        (placeSearch.model?.hits ?? []).filter { hit in isNear(hit.candidate.coordinate) && !picked.contains(.place(hit)) }
    }
    private var finished: Bool { placeSearch.model?.phase == .noResults || placeSearch.model?.phase == .results }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if !towns.isEmpty || !places.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(towns) { town in
                                row(symbol: "signpost.right.and.left", title: town.name, subtitle: town.subtitle) { add(.town(town)) }
                            }
                            ForEach(places) { hit in
                                row(symbol: hit.experience?.iconName ?? hit.candidate.iconName, title: hit.candidate.name,
                                    subtitle: [hit.candidate.locality, CountryName.display(hit.candidate.countryName, code: hit.candidate.countryCode)]
                                        .compactMap { $0 }.uniqued().joined(separator: ", ")) { add(.place(hit)) }
                            }
                        }
                        .roamCard(padding: Theme.Spacing.m)
                    } else if !query.trimmingCharacters(in: .whitespaces).isEmpty, finished {
                        Text("Nothing near \(city.name) matches \u{201C}\(query)\u{201D}.").font(.subheadline).foregroundStyle(Roam.inkMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.s)
            }
            .background(Roam.paper)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: Theme.Spacing.s) {
                    HStack(spacing: Theme.Spacing.s) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Roam.inkMuted).accessibilityHidden(true)
                        TextField("Places near \(city.name)", text: $query)
                            .focused($searchFocused)
                            .submitLabel(.search)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("city-place-search")
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
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.s)
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { searchFocused = true }
            .task(id: query) { await placeSearch.run(query, services: services, near: city) }
        }
        .roamSheetStyle()
        .presentationDetents([.large])
    }

    private func add(_ pick: CityLogPick) {
        picked.append(pick)
        dismiss()
    }

    /// A result as the main search shows one: its icon, name and where it is.
    private func row(symbol: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: symbol).foregroundStyle(Roam.inkMuted).frame(width: 24).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: -2) {
                    Text(title).font(.headline).foregroundStyle(Roam.ink).lineLimit(1)
                    if !subtitle.isEmpty { Text(subtitle).font(.footnote).foregroundStyle(Roam.inkMuted).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: Theme.minimumHitTarget)
            .padding(.vertical, Theme.Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
