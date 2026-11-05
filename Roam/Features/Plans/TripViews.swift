import MapKit
import SwiftUI

struct TripStatusPill: View {
    let status: TripStatus

    var body: some View {
        Text(status.title)
            .font(.caption)
            .foregroundStyle(Roam.ink)
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, 3)
            .background {
                if status == .planning || status == .upcoming {
                    Capsule().strokeBorder(Roam.ink, lineWidth: 1)
                } else {
                    Capsule().fill(Roam.fill)
                }
            }
    }
}

enum TripViewMode: String, CaseIterable, Identifiable {
    case places
    case timeline
    case topPicks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .places: return "Places"
        case .timeline: return "Timeline"
        case .topPicks: return "Top Picks"
        }
    }
}

enum TripText {
    /// The best places from a trip: ranked visits only, one per place, across types.
    static func topPicks(_ entries: [TripFeedEntry], limit: Int = 5) -> [TripFeedEntry] {
        var seen = Set<UUID>()
        return entries.filter { $0.score != nil }
            .sorted { ($0.score?.tenths ?? 0) > ($1.score?.tenths ?? 0) }
            .filter { seen.insert($0.experience.id).inserted }
            .prefix(limit).map { $0 }
    }

    static func summaryLine(_ trip: TripSummary) -> String {
        var parts: [String] = []
        if !trip.stops.isEmpty { parts.append(trip.stops.joined(separator: ", ")) }
        parts.append(dates(trip))
        parts.append("\(trip.visitedCount) visited, \(trip.plannedCount) planned")
        return parts.joined(separator: " · ")
    }

    static func dates(_ trip: TripSummary) -> String {
        switch (trip.startDate, trip.endDate) {
        case let (start?, end?): return "\(start.displayString) to \(end.displayString)"
        case let (start?, nil): return "From \(start.displayString)"
        case let (nil, end?): return "Until \(end.displayString)"
        case (nil, nil): return "No dates"
        }
    }
}

struct TripDetailView: View {
    let tripID: UUID

    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var detail: LoadPhase<TripDetail> = .idle
    @State private var editing: TripDraft?
    @State private var actionError: String?
    @State private var confirmingDelete = false
    @State private var showsShare = false
    @State private var view: TripViewMode = .places
    @State private var entries: [TripFeedEntry] = []
    @State private var wishlist: [ExperienceSummary] = []
    @State private var addingFromWishlist = false
    @State private var addingCity = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                switch detail {
                case .idle, .loading:
                    SkeletonList(rows: 3)
                case .failed(let message):
                    InlineRetryView(message: message) { Task { await load() } }
                case .loaded(let value):
                    content(value)
                }
            }
            .padding(Theme.Spacing.l)
        }
        .background(Roam.paper)
        .navigationTitle(detail.value?.summary.name ?? "Trip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let summary = detail.value?.summary, summary.isOwn {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Edit trip") { editing = draft(summary) }
                        Button("Add a city") { addingCity = true }
                        Button("Share with a friend") { showsShare = true }
                        Button("Delete trip", role: .destructive) { confirmingDelete = true }
                    } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("Trip options")
                    .accessibilityIdentifier("trip-options")
                }
            }
        }
        .sheet(item: $editing) { draft in
            TripEditorSheet(draft: draft) { _ in Task { await load() } }.presentationBackground(Roam.paper)
        }
        .sheet(isPresented: $showsShare) {
            ShareSheet(target: .trip(tripID), title: detail.value?.summary.name ?? "this trip").presentationBackground(Roam.paper)
        }
        .sheet(isPresented: $addingFromWishlist) {
            if let summary = detail.value?.summary {
                PlanTripSheet(candidates: wishlist, suggestedName: summary.name, trip: summary) { Task { await load() } }
                    .presentationBackground(Roam.paper)
            }
        }
        .sheet(isPresented: $addingCity) {
            DestinationPickerSheet(purpose: .homeCity, title: "Add a city") { city in
                Task {
                    do { try await services.plans.setTripCity(tripID: tripID, city: city, present: true); await load() }
                    catch { actionError = error.roamMessage }
                }
            }
        }
        .confirmationDialog("Delete this trip?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete trip", role: .destructive) {
                Task {
                    do { try await services.plans.deleteTrip(id: tripID); dismiss() }
                    catch { actionError = error.roamMessage }
                }
            }
        } message: {
            Text("Your visits and saved places stay.")
        }
        .task { await load() }
        .refreshable { await load() }
        .screenIdentifier("trip-detail")
    }

    @ViewBuilder private func content(_ value: TripDetail) -> some View {
        header(value)
        Picker("View", selection: $view) {
            ForEach(TripViewMode.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("trip-view-mode")
        switch view {
        case .places: places(value)
        case .timeline: entryList(entries, empty: "No visits logged on this trip yet.")
        case .topPicks: entryList(TripText.topPicks(entries), empty: "Rank a place from this trip to see top picks here.")
        }
    }

    private func entryList(_ list: [TripFeedEntry], empty: String) -> some View {
        VStack(spacing: 0) {
            if list.isEmpty {
                Text(empty).font(.subheadline).foregroundStyle(Roam.inkMuted).frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(list) { entry in
                entryRow(entry)
                if entry.id != list.last?.id { Divider() }
            }
        }
        .roamCard(padding: Theme.Spacing.m)
    }

    private func entryRow(_ entry: TripFeedEntry) -> some View {
        Button { router.push(.experience(entry.experience.id)) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.experience.name).font(.headline).foregroundStyle(Roam.ink)
                    Spacer(minLength: Theme.Spacing.s)
                    if Score.isShown, let score = entry.score {
                        Text(score.formatted).font(.system(.body, design: .rounded).bold()).monospacedDigit().foregroundStyle(Roam.ink)
                    }
                }
                Text(entry.visitDate.date?.displayString ?? "Date unknown").font(.footnote).foregroundStyle(Roam.inkMuted)
                if !entry.publicNote.isEmpty { Text(entry.publicNote).font(.subheadline).foregroundStyle(Roam.ink) }
            }
            .frame(maxWidth: .infinity, minHeight: Theme.minimumHitTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("trip-entry-\(entry.experience.name)")
    }

    @ViewBuilder private func header(_ value: TripDetail) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if !value.summary.placeLine.isEmpty && value.summary.placeLine != value.summary.name { Text(value.summary.placeLine).font(.roamTitle(.title3)).foregroundStyle(Roam.ink) }
            Text(dateLine(value.summary)).font(.subheadline).foregroundStyle(Roam.inkMuted)
            if !value.summary.isOwn { Text("From \(value.summary.owner.displayName)").font(.footnote).foregroundStyle(Roam.inkMuted) }
            if !value.summary.description.isEmpty { Text(value.summary.description).font(.subheadline) }
            if let actionError { Text(actionError).font(.footnote).foregroundStyle(Roam.signal) }
        }
    }

    private func dateLine(_ trip: TripSummary) -> String {
        let today = MyTimeline.today()
        let dates = MyTimeline.range(trip.startDate, trip.endDate) ?? "No dates yet"
        if let start = trip.startDate, start > today {
            let days = MyTimeline.days(from: today, to: start)
            return "\(dates) · \(days == 1 ? "tomorrow" : "in \(days) days")"
        }
        return trip.phase(today: today) == .now ? "\(dates) · Happening now" : dates
    }

    /// The trip's places: what's already on it, plus everything you've saved in its cities (saved places show up on
    /// their own; only cities are planned).
    @ViewBuilder private func places(_ value: TripDetail) -> some View {
        let items = value.places.map { PlaceMapItem(experience: $0.experience, state: $0.state) }
            + wishlist.map { PlaceMapItem(experience: $0, state: .wishlist) }
        if !items.isEmpty {
            PlaceMapView(items: items) { router.push(.experience($0)) }
                .id(items.map(\.id))
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                .accessibilityIdentifier("trip-map")
        }
        if value.summary.isOwn {
            Button { addingCity = true } label: { PillLabel(title: "Add a city", systemImage: "plus") }
                .buttonStyle(PillButtonStyle(tint: PlaceState.planned.markerColor))
                .accessibilityIdentifier("trip-add-city")
        }
        if items.isEmpty && value.summary.cities.isEmpty {
            Text("Add a city. Places you've saved there show up here.")
                .font(.subheadline).foregroundStyle(Roam.inkMuted)
                .accessibilityIdentifier("trip-places-empty")
        } else {
            PlaceBreakdown(items: items, extraCities: value.summary.cities,
                           onRemove: value.summary.isOwn ? { id in Task { await remove(id) } } : nil)
        }
    }

    private func draft(_ summary: TripSummary) -> TripDraft {
        TripDraft(id: summary.id, name: summary.name, description: summary.description,
                  startDate: summary.startDate, endDate: summary.endDate, status: summary.status)
    }

    private func remove(_ id: UUID) async {
        do {
            try await services.plans.setTripPlace(tripID: tripID, experienceID: id, stop: "", present: false)
            await load()
        } catch { actionError = error.roamMessage }
    }

    private func load() async {
        if detail.value == nil { detail = .loading }
        do {
            let loaded = try await services.plans.trip(id: tripID)
            detail = .loaded(loaded)
            entries = (try? await services.plans.tripUpdates(ownerID: loaded.summary.owner.id, tripID: tripID)) ?? []
            if loaded.summary.isOwn, let me = session.userID {
                let onTrip = Set(loaded.places.map(\.id))
                let saved = (try? await services.lists.want(ownerID: me)) ?? []
                wishlist = saved.map(\.experience).filter { place in
                    !onTrip.contains(place.id) && loaded.summary.cities.contains { CityMatch.same(place, $0) }
                }
            }
        }
        catch { if detail.value == nil { detail = .failed(error.roamMessage) } else { actionError = error.roamMessage } }
    }
}

extension TripDraft: Identifiable {
}

/// Names and dates a trip. A new trip also takes its cities here; its status follows its dates.
struct TripEditorSheet: View {
    @State var draft: TripDraft
    /// Cities a new trip starts with (planning from a city's page).
    var initialCities: [Destination] = []
    var onSaved: (TripSummary) -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var start = Calendar.current.startOfDay(for: Date())
    @State private var end = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    @State private var cities: [Destination] = []
    @State private var pickingCity = false
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form { Group {
                Section {
                    TextField("Trip name", text: $draft.name).accessibilityIdentifier("trip-name")
                    TextField("Description (optional)", text: $draft.description, axis: .vertical)
                        .textInputAutocapitalization(.never)
                }
                // Dates are required: the standard date rows, the end never before the start.
                Section("Dates") {
                    DatePicker("Start", selection: $start, displayedComponents: .date)
                        .accessibilityIdentifier("trip-start")
                    DatePicker("End", selection: $end, in: start..., displayedComponents: .date)
                        .accessibilityIdentifier("trip-end")
                }
                .onChange(of: start) { _, value in if end < value { end = value } }
                if draft.id == nil {
                    // Like adding a phone number in Contacts: each city a row, then a green add row.
                    Section("Cities") {
                        ForEach(cities) { city in
                            HStack {
                                Text(city.name)
                                Spacer()
                                Text(city.countryName ?? "").foregroundStyle(Roam.inkMuted)
                            }
                        }
                        .onDelete { cities.remove(atOffsets: $0) }
                        Button { pickingCity = true } label: {
                            Label {
                                Text("Add a city").foregroundStyle(Roam.ink)
                            } icon: {
                                Image(systemName: "plus.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, Color.green)
                            }
                        }
                        .accessibilityIdentifier("trip-editor-add-city")
                    }
                }
                if let error { Section { Text(error).foregroundStyle(Roam.signal) } }
            }
            .listRowBackground(Roam.paperRaised)
            }
            .scrollContentBackground(.hidden)
            .onAppear { if cities.isEmpty { cities = initialCities } }
            .navigationTitle(draft.id == nil ? "New trip" : "Edit trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(saving || draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("trip-save")
                }
            }
            .sheet(isPresented: $pickingCity) {
                DestinationPickerSheet(purpose: .homeCity, title: "Add a city") { city in
                    if !cities.contains(city) { cities.append(city) }
                }
            }
            .onAppear {
                if let saved = draft.startDate?.date() { start = saved }
                if let saved = draft.endDate?.date() { end = saved }
            }
        }
        .roamSheetStyle()
        // Opens fully up.
        .presentationDetents([.large])
    }

    private func save() async {
        var value = draft
        value.startDate = LocalDate(date: start, timeZone: .current)
        value.endDate = LocalDate(date: end, timeZone: .current)
        value.status = TripSummary.status(start: value.startDate, end: value.endDate, today: MyTimeline.today())
        if let message = value.validationMessage { error = message; return }
        saving = true
        defer { saving = false }
        do {
            let saved = try await services.plans.saveTrip(value)
            for city in cities { try await services.plans.setTripCity(tripID: saved.id, city: city, present: true) }
            onSaved(saved)
            dismiss()
        } catch { self.error = error.roamMessage }
    }
}

/// Puts a place on one of your trips, or takes it off. Planning never creates a visit or a rating.
struct AddToTripSheet: View {
    let experienceID: UUID
    let placeName: String

    @Environment(AppServices.self) private var services
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var trips: LoadPhase<[TripSummary]> = .idle
    @State private var holding: Set<UUID> = []
    @State private var error: String?
    @State private var creating: TripDraft?

    var body: some View {
        NavigationStack {
            List { Group {
                Section {
                    switch trips {
                    case .idle, .loading: ProgressView()
                    case .failed(let message): Text(message).foregroundStyle(Roam.signal)
                    case .loaded(let value):
                        if value.isEmpty { Text("No trips yet.").foregroundStyle(Roam.inkMuted) }
                        ForEach(value) { trip in
                            Button { Task { await toggle(trip) } } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(trip.name).font(.headline).foregroundStyle(Roam.ink)
                                        Text([trip.placeLine.isEmpty ? nil : trip.placeLine, MyTimeline.range(trip.startDate, trip.endDate) ?? "No dates yet"]
                                            .compactMap { $0 }.joined(separator: " · "))
                                            .font(.footnote).foregroundStyle(Roam.inkMuted)
                                    }
                                    Spacer()
                                    if holding.contains(trip.id) { Image(systemName: "checkmark").foregroundStyle(Roam.ink) }
                                }
                                .frame(minHeight: Theme.minimumHitTarget)
                            }
                            .accessibilityIdentifier("add-to-trip-\(trip.name)")
                        }
                    }
                    Button { creating = TripDraft() } label: { Label("New trip", systemImage: "plus") }.accessibilityIdentifier("add-to-trip-new")
                }
                if let error { Section { Text(error).foregroundStyle(Roam.signal) } }
            }
            .listRowBackground(Roam.paperRaised)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Add \(placeName) to a trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $creating) { draft in
                TripEditorSheet(draft: draft) { trip in Task { await add(to: trip) } }.presentationBackground(Roam.paper)
            }
            .task { await load() }
        }
        .roamSheetStyle()
        .presentationDetents([.medium, .large])
    }

    private func load() async {
        do {
            let all = try await services.plans.myTrips().filter { $0.phase(today: MyTimeline.today()) != .past }
            var held: Set<UUID> = []
            for trip in all where (try? await services.plans.trip(id: trip.id))?.places.contains(where: { $0.id == experienceID && $0.isPlanned }) == true {
                held.insert(trip.id)
            }
            holding = held
            trips = .loaded(all)
        } catch { trips = .failed(error.roamMessage) }
    }

    private func toggle(_ trip: TripSummary) async {
        let present = !holding.contains(trip.id)
        do {
            try await services.plans.setTripPlace(tripID: trip.id, experienceID: experienceID, stop: "", present: present)
            if present { holding.insert(trip.id) } else { holding.remove(trip.id) }
            library.noteChanged()
        } catch { self.error = error.roamMessage }
    }

    private func add(to trip: TripSummary) async {
        do {
            try await services.plans.setTripPlace(tripID: trip.id, experienceID: experienceID, stop: "", present: true)
            library.noteChanged()
            await load()
        } catch { self.error = error.roamMessage }
    }
}
