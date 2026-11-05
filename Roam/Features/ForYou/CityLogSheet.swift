import PhotosUI
import SwiftUI

/// Logging a city, laid out like logging a place: its name and where it is, how it was, when, a note and Save. The one
/// difference is the places you went there, added with a full-width button and logged as visits without ratings.
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
    @State private var places: [SearchHit] = []
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
                    photoSection
                    // The places you went here, as rows, then the button to add more (as on a trip's page).
                    if !places.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(places) { hit in
                                placeRow(hit)
                                if hit.id != places.last?.id { RowSeparator() }
                            }
                        }
                        .roamCard(padding: Theme.Spacing.m)
                    }
                    Button { addingPlaces = true } label: {
                        Label(places.isEmpty ? "Add places" : "Add more places", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .imageScale(.small)
                            .foregroundStyle(Roam.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Capsule().fill(Roam.fill))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("city-log-add-places")
                    TextField("Add a note", text: $note, axis: .vertical)
                        .lineLimit(5...12)
                        .textInputAutocapitalization(.never)
                        .frame(minHeight: 110, alignment: .topLeading)
                        .roamCard(padding: Theme.Spacing.m)
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
                    PhotosPicker(selection: $pickedPhotos, selectionBehavior: .ordered, matching: .images) {
                        HStack(spacing: 5) {
                            Image(systemName: "photo.on.rectangle").font(.footnote).foregroundStyle(Roam.inkMuted)
                            Text("Add photos").font(.footnote.weight(.semibold)).foregroundStyle(Roam.ink)
                            Spacer(minLength: 0)
                            Image(systemName: "plus").font(.caption2.weight(.semibold)).foregroundStyle(Roam.inkMuted)
                        }
                        .padding(.horizontal, Theme.Spacing.m)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .roamCard(padding: 0)
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

    /// A place you went, as the other rows look: its photo square with the green been mark, its name; the × takes it off.
    private func placeRow(_ hit: SearchHit) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            ZStack(alignment: .bottomTrailing) {
                PlaceThumbnail(id: hit.id, url: hit.experience?.photoURL, coordinate: hit.candidate.coordinate,
                               symbol: hit.experience?.iconName ?? hit.candidate.iconName, size: 48)
                StatusMark(state: .visited).scaleEffect(0.75).offset(x: 6, y: 6)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.candidate.name).font(.headline).foregroundStyle(Roam.ink).lineLimit(1)
                if let category = hit.category?.title { Text(category).font(.footnote).foregroundStyle(Roam.inkMuted) }
            }
            Spacer(minLength: 0)
            Button { places.removeAll { $0.id == hit.id } } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(Roam.inkFaint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(hit.candidate.name)")
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
            for hit in places {
                let place: ExperienceSummary
                if let known = hit.experience { place = known } else { place = try await services.experiences.resolve(hit.candidate) }
                // A visit with no rating; the place's own category files it.
                let visit = VisitPayload(date: from, timeZoneIdentifier: TimeZone.current.identifier, publicNote: "", mediaIDs: [],
                                         audience: .public)
                _ = try await services.ranking.addVisit(AddVisitRequest(operationID: UUID(), experienceID: place.id, visit: visit,
                                                                        category: place.category ?? hit.category ?? .activities))
            }
            onSaved()
            dismiss()
        } catch { self.error = error.roamMessage }
    }
}

/// Picking the places you went in a city: search its places and tick them, then Done.
private struct CityPlacePicker: View {
    let city: Destination
    @Binding var picked: [SearchHit]

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var placeSearch = PlaceSearch()
    @FocusState private var searchFocused: Bool

    private var results: [SearchHit] {
        (placeSearch.model?.hits ?? []).filter { hit in
            hit.candidate.countryCode?.uppercased() == city.countryCode?.uppercased()
                && GeographyKey.normalize(hit.candidate.locality ?? "") == GeographyKey.normalize(city.name)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !query.trimmingCharacters(in: .whitespaces).isEmpty, results.isEmpty, placeSearch.model?.phase == .noResults || placeSearch.model?.phase == .results {
                    Text("Nothing in \(city.name) matches \u{201C}\(query)\u{201D}.").foregroundStyle(Roam.inkMuted)
                }
                ForEach(results) { hit in
                    let chosen = picked.contains { $0.id == hit.id }
                    Button {
                        if chosen { picked.removeAll { $0.id == hit.id } } else { picked.append(hit) }
                    } label: {
                        HStack(spacing: Theme.Spacing.m) {
                            Image(systemName: hit.experience?.iconName ?? hit.candidate.iconName).foregroundStyle(Roam.inkMuted).frame(width: 24)
                            VStack(alignment: .leading, spacing: -2) {
                                Text(hit.candidate.name).font(.headline).foregroundStyle(Roam.ink).lineLimit(1)
                                if let category = hit.category?.title { Text(category).font(.footnote).foregroundStyle(Roam.inkMuted) }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(chosen ? PlaceState.visited.markerColor : Roam.inkFaint)
                        }
                        .frame(minHeight: Theme.minimumHitTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Roam.paper)
            // Just a search bar with an × beside it, as when adding a city; tapping places ticks them.
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: Theme.Spacing.s) {
                    HStack(spacing: Theme.Spacing.s) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Roam.inkMuted).accessibilityHidden(true)
                        TextField("Places in \(city.name)", text: $query)
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
            .task(id: query) { await placeSearch.run(query, services: services, near: city, within: city.name) }
        }
        .roamSheetStyle()
        .presentationDetents([.large])
    }
}
