import CoreLocation
import PhotosUI
import SwiftUI

/// Somewhere you went on a city's log: a place, or a town or neighbourhood near it (West Vancouver, from Vancouver).
/// Somewhere you went in or near a city: a place or a nearby town, picked from the city search.
typealias CityLogPick = PlaceSearchPick

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
        .tapID("city-log-add-places")
    }

    /// Somewhere you went, as the other rows look: its photo square with the green been mark, its name; the × takes it off.
    private func pickRow(_ pick: CityLogPick) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            ZStack(alignment: .bottomTrailing) {
                PlaceThumbnail(id: pick.id, url: pick.photoURL, coordinate: pick.coordinate ?? city.coordinate, symbol: pick.symbol, size: 48)
                StatusMark(state: .visited).scaleEffect(0.75).offset(x: 6, y: 6)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(pick.title).font(.headline).foregroundStyle(Roam.ink).lineLimit(1)
                Text(pick.kind).font(.footnote).foregroundStyle(Roam.inkMuted)
            }
            Spacer(minLength: 0)
            Button { places.removeAll { $0.id == pick.id } } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(Roam.inkFaint)
            }.tapID("citylogsheet.xmark-circle-fill")
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
            // A nearby town counts as been too, with the same dates; places get a visit with no rating.
            for pick in places { try await pick.logAsBeen(services: services, start: from, end: to) }
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

    var body: some View {
        NavigationStack {
            ScrollView {
                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    PlaceSearchResults(query: query, placeSearch: placeSearch, kinds: [.places, .cities],
                                       excluding: Set(picked.map(\.id))) { pick in
                        picked.append(pick)
                        dismiss()
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.vertical, Theme.Spacing.s)
                }
            }
            .background(Roam.paper)
            .safeAreaInset(edge: .top, spacing: 0) {
                SearchSheetBar(prompt: "Places near \(city.name)", text: $query, focus: $searchFocused, identifier: "city-place-search") { dismiss() }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { searchFocused = true }
            .task(id: query) { await placeSearch.run(query, services: services, scope: .city(city)) }
        }
        .roamSheetStyle()
        .presentationDetents([.large])
    }
}
