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
    @State private var entries: [TripFeedEntry] = []
    @State private var wishlist: [ExperienceSummary] = []
    @State private var addingFromWishlist = false
    @State private var addingCity = false
    /// Scrolled past the big name, so the small one shows at the top, as standard.
    @State private var scrolledPastTitle = false

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
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 44 } action: { _, past in
            withAnimation(.easeInOut(duration: 0.2)) { scrolledPastTitle = past }
        }
        .background(Roam.paper)
        .navigationTitle(detail.value?.summary.name ?? "Trip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(detail.value?.summary.name ?? "").font(.headline)
                    .opacity(scrolledPastTitle ? 1 : 0).accessibilityHidden(!scrolledPastTitle)
            }
            // Edit and Delete as their own buttons, not tucked in a menu.
            if let summary = detail.value?.summary, summary.isOwn {
                ToolbarItem(placement: .topBarTrailing) {
                    // Square and pencil: the same boxy weight as the bin beside it (a bare pencil read oddly).
                    Button { editing = draft(summary) } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("Edit trip")
                        .accessibilityIdentifier("trip-edit")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) { confirmingDelete = true } label: { Image(systemName: "trash").foregroundStyle(.red) }
                        // Attached to the bin, so the confirmation pops up from it rather than mid-screen.
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
                        .accessibilityLabel("Delete trip")
                        .accessibilityIdentifier("trip-delete")
                }
            }
        }
        .sheet(item: $editing) { draft in
            TripEditorSheet(draft: draft) { _ in Task { await load() } }.presentationBackground(Roam.paper)
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
        // Your own trip: an "Add to trip" button takes the tab bar's spot and opens the city search.
        .roamTabBar(hidden: detail.value?.summary.isOwn == true)
        .tabBarSpotButton(detail.value?.summary.isOwn == true, title: "Add to trip", identifier: "trip-add-city") { addingCity = true }
        .task { await load() }
        .refreshable { await load() }
        .screenIdentifier("trip-detail")
    }

    @ViewBuilder private func content(_ value: TripDetail) -> some View {
        header(value)
        // Just the places; no timeline or top picks views.
        places(value)
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

    /// Just the trip's name and its dates (a friend's trip says whose).
    @ViewBuilder private func header(_ value: TripDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value.summary.name).font(.roamDisplay(.title)).lineLimit(2).minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)
            Text(dateLine(value.summary)).font(.subheadline).foregroundStyle(Roam.inkMuted)
            if !value.summary.isOwn { Text("From \(value.summary.owner.displayName)").font(.footnote).foregroundStyle(Roam.inkMuted) }
            if let actionError { Text(actionError).font(.footnote).foregroundStyle(Roam.signal).padding(.top, Theme.Spacing.xs) }
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

    /// The trip's countries and cities, each a photo card (like My Places' and Discover's) that opens its page. No map
    /// and no list of spots: those are on each city's page.
    @ViewBuilder private func places(_ value: TripDetail) -> some View {
        let cities = value.summary.cities
        let countries = value.summary.countries.filter { code in !cities.contains { $0.countryCode?.uppercased() == code.uppercased() } }
        // Every country the trip goes to: named for it, or where one of its cities is.
        let allCountries = (cities.compactMap { $0.countryCode?.uppercased() } + value.summary.countries.map { $0.uppercased() }).uniqued()
        if allCountries.count > 1 {
            // Several countries: one card each, the country's photo on top and its cities as rows under it.
            ForEach(allCountries, id: \.self) { code in
                countryGroup(code, cities: cities.filter { $0.countryCode?.uppercased() == code })
            }
        } else {
            ForEach(countries, id: \.self) { code in
                Button { router.push(.country(code)) } label: {
                    CountryCoverCard(code: code, title: CountryTitle.text(name: nil, code: code), subtitle: "Pick cities and places as you go")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("trip-country-\(code)")
            }
            ForEach(cities) { city in
                Button { router.push(.city(city)) } label: { CityHeroCard(city: city) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("trip-city-\(city.name)")
            }
        }
        if cities.isEmpty && countries.isEmpty {
            Text("Add a city to start.")
                .font(.subheadline).foregroundStyle(Roam.inkMuted)
                .accessibilityIdentifier("trip-places-empty")
        }
    }

    /// One country on a trip to several: a white card holding the country's photo as its own rounded picture (opening
    /// its page), then its cities as rows with the trip mark.
    private func countryGroup(_ code: String, cities: [Destination]) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            Button { router.push(.country(code)) } label: {
                // Its corners follow the card's at the same distance (the card's radius less the margin), so the two
                // curves read as one roundness.
                CountryCoverCard(code: code, title: CountryTitle.text(name: nil, code: code),
                                 subtitle: cities.isEmpty ? "Pick cities and places as you go" : "",
                                 cornerRadius: Theme.cornerRadius - Self.groupMargin)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("trip-country-\(code)")
            if !cities.isEmpty {
                VStack(spacing: 0) {
                    ForEach(cities) { city in
                        CityRow(city: city, state: .planned) { router.push(.city(city)) }
                        if city.id != cities.last?.id { RowSeparator() }
                    }
                }
                // The rows keep the usual inset; only the photo sits close to the card's edge.
                .padding(.horizontal, Theme.Spacing.m - Self.groupMargin)
            }
        }
        .roamCard(padding: Self.groupMargin)
    }

    /// The tight margin round a country's photo in its trip card.
    private static let groupMargin: CGFloat = 6

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
    /// Whole countries a new trip starts with (planning from a country's page), before any cities are picked.
    var initialCountries: [String] = []
    var onSaved: (TripSummary) -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    // Dates start empty; both are needed to save.
    @State private var start: Date?
    @State private var end: Date?
    @State private var cities: [Destination] = []
    @State private var countries: [String] = []
    @State private var pickingCity = false
    @State private var error: String?
    @State private var saving = false
    @State private var confirmingDiscard = false
    /// What the sheet opened with, to tell whether closing loses anything.
    @State private var opened: (name: String, description: String, start: Date?, end: Date?, cities: [Destination], countries: [String])?

    private var hasChanges: Bool {
        guard let opened else { return false }
        return draft.name != opened.name || draft.description != opened.description || start != opened.start || end != opened.end
            || cities != opened.cities || countries != opened.countries
    }
    /// A name, both dates and, for a new trip, somewhere to go: a city, or a whole country planned from its page.
    private var canSave: Bool {
        !saving && !draft.name.trimmingCharacters(in: .whitespaces).isEmpty && start != nil && end != nil
            && (draft.id != nil || !cities.isEmpty || !countries.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section {
                        TextField("Trip name", text: $draft.name)
                            .textInputAutocapitalization(.never)
                            .accessibilityIdentifier("trip-name")
                        TextField("Description (optional)", text: $draft.description, axis: .vertical)
                            .textInputAutocapitalization(.never)
                    }
                    // Both dates needed, on their own row just under the name card: Start → End, each opening a calendar;
                    // the end never before the start. Before any city is added, + Add a city sits right under them.
                    Section {
                        VStack(spacing: Theme.Spacing.l) {
                            DateRangeRow(start: $start, end: $end)
                            if draft.id == nil, cities.isEmpty, countries.isEmpty { addCityButton }
                        }
                    }
                    .floatingFormRow()
                    if let error { Section { Text(error).foregroundStyle(Roam.signal) } }
                }
                .listRowBackground(Roam.paperRaised)
                if draft.id == nil, !cities.isEmpty || !countries.isEmpty { destinations }
                // Once there are cities, + Add a city goes right under the last one.
                if draft.id == nil, !cities.isEmpty || !countries.isEmpty {
                    Section { addCityButton }
                        .floatingFormRow()
                }
            }
            .scrollContentBackground(.hidden)
            // Tighter gaps between the name, the dates and the cities.
            .listSectionSpacing(.compact)
            // Save sits at the bottom, where the other bottom buttons do.
            .tabBarSpotButton(true, title: "Save", identifier: "trip-save", systemImage: nil, tint: nil, enabled: canSave) {
                Task { await save() }
            }
            .navigationTitle(draft.id == nil ? "New trip" : "Edit trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // Closing with changes asks first.
                    Button { if hasChanges { confirmingDiscard = true } else { dismiss() } } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                        .accessibilityIdentifier("trip-close")
                        // Attached to the ×, so it pops up from it rather than mid-screen.
                        .confirmationDialog("Discard your changes?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                            Button("Discard changes", role: .destructive) { dismiss() }
                            Button("Keep editing", role: .cancel) {}
                        }
                }
            }
            .sheet(isPresented: $pickingCity) {
                DestinationPickerSheet(purpose: .homeCity, title: "Add a city") { city in
                    if !cities.contains(city) { cities.append(city) }
                }
            }
            .onAppear {
                guard opened == nil else { return }
                start = draft.startDate?.date()
                end = draft.endDate?.date()
                cities = initialCities
                countries = initialCountries
                opened = (draft.name, draft.description, start, end, cities, countries)
            }
        }
        .roamSheetStyle()
        // Opens fully up; swiping it away with changes asks first too.
        .presentationDetents([.large])
        .interactiveDismissDisabled(hasChanges)
    }

    /// Full width, the same height, text and icon size as the Start and End bubbles.
    private var addCityButton: some View {
        Button { pickingCity = true } label: {
            Label("Add a city", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .imageScale(.small)
                .foregroundStyle(PlaceState.planned.markerColor)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Capsule().fill(PlaceState.planned.markerColor.opacity(0.15)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("trip-editor-add-city")
    }

    /// Where the trip goes, as the same photo cards its page shows; swipe one away to take it off.
    private var destinations: some View {
        Section {
            ForEach(countries, id: \.self) { code in
                CountryCoverCard(code: code, title: CountryTitle.text(name: nil, code: code), subtitle: "Pick cities and places as you go")
            }
            .onDelete { countries.remove(atOffsets: $0) }
            ForEach(cities) { city in CityHeroCard(city: city) }
                .onDelete { cities.remove(atOffsets: $0) }
        }
        .listRowInsets(EdgeInsets(top: Theme.Spacing.s, leading: 0, bottom: Theme.Spacing.s, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func save() async {
        guard let start, let end else { return }
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
            for code in countries {
                try await services.plans.setTripCountry(tripID: saved.id, code: code, name: CountryName.display(code: code), present: true)
            }
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


extension View {
    /// A light blue glass button in the tab bar's own spot: as wide and tall as it, the same gap from the bottom of the
    /// screen, with room left above it for the content.
    /// `systemImage` leads the title; `tint` colours the glass and text (nil: see-through glass with dark text, like the
    /// tab bar); `enabled` false fades it and stops taps.
    @ViewBuilder func tabBarSpotButton(_ shown: Bool, title: String, identifier: String, systemImage: String? = "plus",
                                       tint: Color? = PlaceState.planned.markerColor, enabled: Bool = true,
                                       action: @escaping () -> Void) -> some View {
        if shown {
            safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: RoamTabBar.reservedHeight) }
                .overlay {
                    // As the tab bar is placed: a stack reaching the very bottom of the screen (not the home indicator),
                    // the button just above it.
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Button(action: action) {
                            HStack(spacing: Theme.Spacing.s) {
                                if let systemImage { Image(systemName: systemImage) }
                                Text(title)
                            }
                            .font(.headline)
                            .foregroundStyle(tint ?? Roam.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: RoamTabBar.height)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .floatingBubble(Capsule(), tint: tint?.opacity(0.18))
                        .opacity(enabled ? 1 : 0.4)
                        .disabled(!enabled)
                        .padding(.horizontal, RoamTabBar.sideMargin)
                        // A touch higher than the tab bar's gap.
                        .padding(.bottom, RoamTabBar.margin + 6)
                        .accessibilityIdentifier(identifier)
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
        } else {
            self
        }
    }
}
