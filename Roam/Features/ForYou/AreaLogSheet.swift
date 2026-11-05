import SwiftUI

/// Logging a country (or state) you've been to: "Where in Norway?" Search and add the cities and places you went to,
/// alike, with when you were there (Start → End, both optional). For a city it's the city's own log: how it was, when, a
/// note, and the places you went there (logged without ratings). Places are logged as visits without a rating; rank them later from their pages.
struct AreaLogSheet: View {
    /// "Norway", or "Ontario".
    let name: String
    let countryCode: String
    /// The state or province, when it's one: its code in `region` ("ON").
    var region: Destination?
    /// Where to look first for places.
    let around: Destination
    /// Logging this city itself (its places only, with a rating and a note) rather than a country or state.
    var city: Destination?
    var onSaved: () -> Void

    private enum Pick: Identifiable, Hashable {
        case city(Destination)
        case place(SearchHit)

        var id: String {
            switch self {
            case .city(let city): return "city:\(city.id)"
            case .place(let hit): return "place:\(hit.id)"
            }
        }
    }

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var placeSearch = PlaceSearch()
    @State private var picks: [Pick] = []
    @State private var start: Date?
    @State private var end: Date?
    @State private var saving = false
    @State private var error: String?
    @State private var sentiment: Sentiment?
    @State private var note = ""

    private var hasQuery: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    private func inArea(country: String?, region value: String?, town: String? = nil) -> Bool {
        guard country?.uppercased() == countryCode.uppercased() else { return false }
        if let city { return GeographyKey.normalize(town ?? "") == GeographyKey.normalize(city.name) }
        guard let region else { return true }
        guard let value, !value.isEmpty else { return false }
        return [region.region, region.name].contains { $0?.caseInsensitiveCompare(value) == .orderedSame }
    }

    private var cityResults: [Destination] {
        guard city == nil else { return [] }
        return placeSearch.cities.filter { inArea(country: $0.countryCode, region: $0.region) && !picks.contains(.city($0)) }
    }
    private var placeResults: [SearchHit] {
        (placeSearch.model?.hits ?? []).filter { hit in
            inArea(country: hit.candidate.countryCode, region: hit.candidate.region, town: hit.candidate.locality)
                && !picks.contains { $0.id == "place:\(hit.id)" }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if hasQuery {
                    results
                } else {
                    if city != nil {
                        // How it was, like a place's log.
                        Section { FeelingSlider(selection: $sentiment, enabled: true) { _ in } }
                            .floatingFormRow()
                    }
                    Section {
                        if picks.isEmpty {
                            Text(city == nil ? "Search for the cities and places you went to." : "Search for the places you went in \(name).")
                                .foregroundStyle(Roam.inkMuted)
                        }
                        ForEach(picks) { pick in pickRow(pick) }
                            .onDelete { picks.remove(atOffsets: $0) }
                    } header: {
                        Text(city == nil ? "Where you went" : "Places you went")
                    }
                    Section { DateRangeRow(start: $start, end: $end) }
                        .floatingFormRow()
                    if city != nil {
                        Section {
                            TextField("Add a note", text: $note, axis: .vertical)
                                .lineLimit(4...10)
                                .textInputAutocapitalization(.never)
                                .frame(minHeight: 90, alignment: .topLeading)
                                .accessibilityIdentifier("city-log-note")
                        }
                    }
                    if let error { Section { Text(error).foregroundStyle(Roam.signal) } }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Roam.paper)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: city == nil ? "Cities and places in \(name)" : "Places in \(name)")
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .navigationTitle(city == nil ? "Where in \(name)?" : "Log \(name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        // A city's log can be saved on its own; a country's needs somewhere in it.
                        .disabled(saving || (city == nil && picks.isEmpty))
                        .accessibilityIdentifier("area-log-save")
                }
            }
            .task(id: query) { await placeSearch.run(query, services: services, near: around, within: name) }
        }
        .roamSheetStyle()
        .presentationDetents([.large])
        .screenIdentifier("area-log")
    }

    @ViewBuilder private var results: some View {
        if cityResults.isEmpty && placeResults.isEmpty {
            if placeSearch.model?.phase == .noResults || placeSearch.model?.phase == .results {
                Text("Nothing in \(name) matches \u{201C}\(query)\u{201D}.").foregroundStyle(Roam.inkMuted)
            }
        } else {
            ForEach(cityResults) { city in
                Button { add(.city(city)) } label: {
                    row(symbol: "signpost.right.and.left", title: city.name, subtitle: city.subtitle)
                }
                .buttonStyle(.plain)
            }
            ForEach(placeResults) { hit in
                Button { add(.place(hit)) } label: {
                    row(symbol: hit.experience?.iconName ?? hit.candidate.iconName, title: hit.candidate.name,
                        subtitle: [hit.candidate.locality, CountryName.display(hit.candidate.countryName, code: hit.candidate.countryCode)]
                            .compactMap { $0 }.uniqued().joined(separator: ", "))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func pickRow(_ pick: Pick) -> some View {
        switch pick {
        case .city(let city):
            return row(symbol: "signpost.right.and.left", title: city.name, subtitle: "City")
        case .place(let hit):
            return row(symbol: hit.experience?.iconName ?? hit.candidate.iconName, title: hit.candidate.name,
                       subtitle: hit.category?.title ?? "Place")
        }
    }

    private func row(symbol: String, title: String, subtitle: String) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: symbol).foregroundStyle(Roam.inkMuted).frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: -2) {
                Text(title).font(.headline).foregroundStyle(Roam.ink).lineLimit(1)
                if !subtitle.isEmpty { Text(subtitle).font(.footnote).foregroundStyle(Roam.inkMuted).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: Theme.minimumHitTarget)
        .contentShape(Rectangle())
    }

    /// Adds it to the list and clears the search for the next one.
    private func add(_ pick: Pick) {
        if !picks.contains(pick) { picks.append(pick) }
        query = ""
    }

    private func save() async {
        saving = true
        defer { saving = false }
        error = nil
        let from = start.map { LocalDate(date: $0, timeZone: .current) }
        let to = end.map { LocalDate(date: $0, timeZone: .current) }
        do {
            if let city {
                try await services.plans.logCity(city, start: from, end: to, sentiment: sentiment, note: note)
            }
            for pick in picks {
                switch pick {
                case .city(let city):
                    try await services.plans.markCityVisited(city, start: from, end: to)
                case .place(let hit):
                    let place: ExperienceSummary
                    if let known = hit.experience { place = known } else { place = try await services.experiences.resolve(hit.candidate) }
                    // A visit with no rating; the place's own category files it.
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
