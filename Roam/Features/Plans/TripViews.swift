import SwiftUI

/// The Trips section of My Places: planning, then ongoing, then past.
struct TripsListView: View {
    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @State private var trips: LoadPhase<[TripSummary]> = .idle
    @State private var lists: [PlaceList] = []
    @State private var editing: TripDraft?

    var body: some View {
        List {
            switch trips {
            case .idle, .loading:
                Section { SkeletonList(rows: 3) }
            case .failed(let message):
                Section { InlineRetryView(message: message) { Task { await load() } } }
            case .loaded(let value):
                if value.isEmpty {
                    Section {
                        Text("No trips yet. Create one to collect places you're considering.")
                            .font(.subheadline).foregroundStyle(Roam.inkMuted)
                            .accessibilityIdentifier("trips-empty")
                    }
                    .listRowBackground(Roam.paperRaised)
                }
                ForEach(sections(value), id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.trips) { trip in
                            Button { router.push(.trip(trip.id)) } label: { TripRow(trip: trip) }
                                .accessibilityIdentifier("trip-\(trip.name)")
                        }
                    }
                    .listRowBackground(Roam.paperRaised)
                }
            }
            Section {
                Button("New trip") { editing = TripDraft() }
                    .accessibilityIdentifier("trip-new")
                Button("Custom lists (\(lists.count))") { router.push(.lists) }
                    .accessibilityIdentifier("open-lists")
            }
            .listRowBackground(Roam.paperRaised)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .sheet(item: $editing) { draft in
            TripEditorSheet(draft: draft) { Task { await load() } }
                .presentationBackground(Roam.paper)
        }
        .task { await load() }
        .refreshable { await load() }
        .screenIdentifier("trips-list")
    }

    private func sections(_ value: [TripSummary]) -> [(title: String, trips: [TripSummary])] {
        let planning = value.filter { $0.status == .planning || $0.status == .upcoming }
        let ongoing = value.filter { $0.status == .ongoing }
        let past = value.filter { $0.status == .past }
        return [("Planning and upcoming", planning), ("Ongoing", ongoing), ("Past", past)].filter { !$0.1.isEmpty }
    }

    private func load() async {
        if trips.value == nil { trips = .loading }
        do {
            trips = .loaded(try await services.plans.myTrips())
            lists = try await services.plans.myLists()
        } catch {
            if trips.value == nil { trips = .failed(error.roamMessage) }
        }
    }
}

private struct TripRow: View {
    let trip: TripSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(trip.name).font(.headline).foregroundStyle(Roam.ink)
                Spacer(minLength: Theme.Spacing.s)
                TripStatusPill(status: trip.status)
            }
            Text(TripText.summaryLine(trip)).font(.footnote).foregroundStyle(Roam.inkMuted)
        }
        .frame(minHeight: Theme.minimumHitTarget)
    }
}

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

enum TripText {
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
        case (nil, nil): return "No dates yet"
        }
    }
}

struct TripDetailView: View {
    let tripID: UUID

    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var detail: LoadPhase<TripDetail> = .idle
    @State private var editing: TripDraft?
    @State private var actionError: String?
    @State private var confirmingDelete = false
    @State private var showsShare = false

    var body: some View {
        List {
            switch detail {
            case .idle, .loading:
                Section { SkeletonList(rows: 3) }
            case .failed(let message):
                Section { InlineRetryView(message: message) { Task { await load() } } }
            case .loaded(let value):
                content(value)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Roam.paper)
        .navigationTitle(detail.value?.summary.name ?? "Trip")
        .toolbar {
            if let summary = detail.value?.summary, summary.isOwn {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Edit trip") { editing = draft(summary) }
                        Button("Share with a friend") { showsShare = true }
                        Button("Delete trip", role: .destructive) { confirmingDelete = true }
                    } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("Trip options")
                    .accessibilityIdentifier("trip-options")
                }
            }
        }
        .sheet(item: $editing) { draft in
            TripEditorSheet(draft: draft) { Task { await load() } }.presentationBackground(Roam.paper)
        }
        .sheet(isPresented: $showsShare) {
            ShareSheet(target: .trip(tripID), title: detail.value?.summary.name ?? "this trip").presentationBackground(Roam.paper)
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
        Section {
            HStack {
                TripStatusPill(status: value.summary.status)
                Text(TripText.dates(value.summary)).font(.footnote).foregroundStyle(Roam.inkMuted)
            }
            if !value.summary.isOwn { Text("From \(value.summary.owner.displayName)").font(.footnote).foregroundStyle(Roam.inkMuted) }
            if !value.summary.description.isEmpty { Text(value.summary.description) }
            if let actionError { Text(actionError).foregroundStyle(Roam.signal) }
        }
        .listRowBackground(Roam.paperRaised)
        if value.places.isEmpty {
            Section {
                Text("No places yet. Open a place and choose Add to trip.")
                    .font(.subheadline).foregroundStyle(Roam.inkMuted)
                    .accessibilityIdentifier("trip-places-empty")
            }
            .listRowBackground(Roam.paperRaised)
        }
        ForEach(value.placesByStop, id: \.stop) { group in
            Section(group.stop.isEmpty ? "Places" : group.stop) {
                ForEach(group.places) { place in
                    Button { router.push(.experience(place.id)) } label: {
                        HStack(spacing: Theme.Spacing.m) {
                            StatusMark(state: place.state)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.experience.name).font(.headline).foregroundStyle(Roam.ink)
                                Text(place.state.title).font(.footnote).foregroundStyle(Roam.inkMuted)
                            }
                        }
                        .frame(minHeight: Theme.minimumHitTarget)
                    }
                    .accessibilityIdentifier("trip-place-\(place.experience.name)")
                    .swipeActions {
                        if value.summary.isOwn && place.isPlanned {
                            Button("Remove", role: .destructive) { Task { await remove(place) } }
                        }
                    }
                }
            }
            .listRowBackground(Roam.paperRaised)
        }
    }

    private func draft(_ summary: TripSummary) -> TripDraft {
        TripDraft(id: summary.id, name: summary.name, description: summary.description,
                  startDate: summary.startDate, endDate: summary.endDate, status: summary.status)
    }

    private func remove(_ place: TripPlace) async {
        do {
            try await services.plans.setTripPlace(tripID: tripID, experienceID: place.id, stop: place.stop, present: false)
            await load()
        } catch { actionError = error.roamMessage }
    }

    private func load() async {
        if detail.value == nil { detail = .loading }
        do { detail = .loaded(try await services.plans.trip(id: tripID)) }
        catch { if detail.value == nil { detail = .failed(error.roamMessage) } else { actionError = error.roamMessage } }
    }
}

extension TripDraft: Identifiable {
}

struct TripEditorSheet: View {
    @State var draft: TripDraft
    var onSaved: () -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var hasStart = false
    @State private var hasEnd = false
    @State private var start = Date()
    @State private var end = Date()
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Trip name", text: $draft.name).accessibilityIdentifier("trip-name")
                    TextField("Description (optional)", text: $draft.description, axis: .vertical)
                }
                .listRowBackground(Roam.paperRaised)
                Section("Status") {
                    Picker("Status", selection: $draft.status) {
                        ForEach(TripStatus.allCases) { Text($0.title).tag($0) }
                    }
                }
                .listRowBackground(Roam.paperRaised)
                Section("Dates (optional)") {
                    Toggle("Start date", isOn: $hasStart)
                    if hasStart { DatePicker("Starts", selection: $start, displayedComponents: .date) }
                    Toggle("End date", isOn: $hasEnd)
                    if hasEnd { DatePicker("Ends", selection: $end, displayedComponents: .date) }
                }
                .listRowBackground(Roam.paperRaised)
                if let error { Section { Text(error).foregroundStyle(Roam.signal) }.listRowBackground(Roam.paperRaised) }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle(draft.id == nil ? "New trip" : "Edit trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(saving).accessibilityIdentifier("trip-save")
                }
            }
            .onAppear {
                if let date = draft.startDate?.date() { hasStart = true; start = date }
                if let date = draft.endDate?.date() { hasEnd = true; end = date }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        var value = draft
        value.startDate = hasStart ? LocalDate(date: start, timeZone: .current) : nil
        value.endDate = hasEnd ? LocalDate(date: end, timeZone: .current) : nil
        if let message = value.validationMessage { error = message; return }
        saving = true
        defer { saving = false }
        do {
            _ = try await services.plans.saveTrip(value)
            onSaved()
            dismiss()
        } catch { self.error = error.roamMessage }
    }
}

/// Adds a place to a trip as a plan. Planning never creates a visit or a rating.
struct AddToTripSheet: View {
    let experienceID: UUID
    let placeName: String

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var trips: LoadPhase<[TripSummary]> = .idle
    @State private var stop = ""
    @State private var error: String?
    @State private var creating: TripDraft?

    var body: some View {
        NavigationStack {
            List {
                Section("Stop or city (optional)") {
                    TextField("Lisbon", text: $stop).accessibilityIdentifier("add-to-trip-stop")
                }
                .listRowBackground(Roam.paperRaised)
                Section("Add to") {
                    switch trips {
                    case .idle, .loading: ProgressView()
                    case .failed(let message): Text(message).foregroundStyle(Roam.signal)
                    case .loaded(let value):
                        if value.isEmpty { Text("No trips yet.").foregroundStyle(Roam.inkMuted) }
                        ForEach(value) { trip in
                            Button(trip.name) { Task { await add(to: trip) } }
                                .accessibilityIdentifier("add-to-trip-\(trip.name)")
                        }
                    }
                    Button("New trip") { creating = TripDraft() }.accessibilityIdentifier("add-to-trip-new")
                }
                .listRowBackground(Roam.paperRaised)
                if let error { Section { Text(error).foregroundStyle(Roam.signal) }.listRowBackground(Roam.paperRaised) }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Add \(placeName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(item: $creating) { draft in
                TripEditorSheet(draft: draft) { Task { await load() } }.presentationBackground(Roam.paper)
            }
            .task { await load() }
        }
        .presentationDetents([.medium, .large])
    }

    private func load() async {
        do { trips = .loaded(try await services.plans.myTrips()) }
        catch { trips = .failed(error.roamMessage) }
    }

    private func add(to trip: TripSummary) async {
        do {
            try await services.plans.setTripPlace(tripID: trip.id, experienceID: experienceID, stop: stop, present: true)
            dismiss()
        } catch { self.error = error.roamMessage }
    }
}
