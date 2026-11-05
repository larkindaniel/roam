import SwiftUI

/// Logging a country (or state) you've been to: "Where in Norway?" Search and add the cities and places you went to,
/// alike, with when you were there. Places are logged as visits without a rating; rank them later from their pages.
struct AreaLogSheet: View {
    /// "Norway", or "Ontario".
    let name: String
    let countryCode: String
    /// The state or province, when it's one: its code in `region` ("ON").
    var region: Destination?
    /// Where to look first for places.
    let around: Destination
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

    private var hasQuery: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    private func inArea(country: String?, region value: String?) -> Bool {
        guard country?.uppercased() == countryCode.uppercased() else { return false }
        guard let region else { return true }
        guard let value, !value.isEmpty else { return false }
        return [region.region, region.name].contains { $0?.caseInsensitiveCompare(value) == .orderedSame }
    }

    private var cityResults: [Destination] {
        placeSearch.cities.filter { inArea(country: $0.countryCode, region: $0.region) && !picks.contains(.city($0)) }
    }
    private var placeResults: [SearchHit] {
        (placeSearch.model?.hits ?? []).filter { hit in
            inArea(country: hit.candidate.countryCode, region: hit.candidate.region) && !picks.contains { $0.id == "place:\(hit.id)" }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if hasQuery {
                    results
                } else {
                    Section {
                        if picks.isEmpty {
                            Text("Search for the cities and places you went to.").foregroundStyle(Roam.inkMuted)
                        }
                        ForEach(picks) { pick in pickRow(pick) }
                            .onDelete { picks.remove(atOffsets: $0) }
                    } header: {
                        Text("Where you went")
                    }
                    Section {
                        TripDatesRow(start: $start, end: $end)
                    } header: {
                        Text("When were you there?")
                    } footer: {
                        Text("Optional. You can rate places later from their pages.")
                    }
                    if let error { Section { Text(error).foregroundStyle(Roam.signal) } }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Roam.paper)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Cities and places in \(name)")
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .navigationTitle("Where in \(name)?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(saving || picks.isEmpty)
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
            for pick in picks {
                switch pick {
                case .city(let city):
                    try await services.plans.markCityVisited(city, start: from, end: to)
                case .place(let hit):
                    let place: ExperienceSummary
                    if let known = hit.experience { place = known } else { place = try await services.experiences.resolve(hit.candidate) }
                    // A visit with no rating; the place's own category files it.
                    let visit = VisitPayload(date: from, timeZoneIdentifier: TimeZone.current.identifier, publicNote: "", mediaIDs: [])
                    _ = try await services.ranking.addVisit(AddVisitRequest(operationID: UUID(), experienceID: place.id, visit: visit,
                                                                            category: place.category ?? hit.category ?? .activities))
                }
            }
            onSaved()
            dismiss()
        } catch { self.error = error.roamMessage }
    }
}
