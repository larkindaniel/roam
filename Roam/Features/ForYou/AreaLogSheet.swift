import SwiftUI

/// Logging a country (or state) you've been to: "Where in Norway?" Search and add the cities and places you went to,
/// alike, with when you were there (Start → End, both optional). A city has its own log (CityLogSheet). Places are logged as visits without a rating; rank them later from their pages.
struct AreaLogSheet: View {
    /// "Norway", or "Ontario".
    let name: String
    let countryCode: String
    /// The state or province, when it's one: its code in `region` ("ON").
    var region: Destination?
    /// Where to look first for places.
    let around: Destination
    var onSaved: () -> Void

    private typealias Pick = PlaceSearchPick

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var placeSearch = PlaceSearch()
    @State private var picks: [Pick] = []
    @State private var start: Date?
    @State private var end: Date?
    @State private var saving = false
    @State private var error: String?
    @FocusState private var searchFocused: Bool

    private var hasQuery: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    private var scope: PlaceSearchScope { .area(name: name, countryCode: countryCode, region: region, around: around) }

    var body: some View {
        NavigationStack {
            Group {
                if hasQuery {
                    // Search 2, inside the country or state: its cities and places, nothing else.
                    ScrollView {
                        PlaceSearchResults(query: query, placeSearch: placeSearch, kinds: [.places, .cities],
                                           excluding: Set(picks.map(\.id))) { add($0) }
                            .padding(.horizontal, Theme.Spacing.l)
                            .padding(.vertical, Theme.Spacing.s)
                    }
                } else {
                    List {
                    Section {
                        if picks.isEmpty {
                            Text("Search for the cities and places you went to.").foregroundStyle(Roam.inkMuted)
                        }
                        ForEach(picks) { pick in pickRow(pick) }
                            .onDelete { picks.remove(atOffsets: $0) }
                    } header: {
                        Text("Where you went")
                    }
                    Section { DateRangeRow(start: $start, end: $end) }
                        .floatingFormRow()
                    if let error { Section { Text(error).foregroundStyle(Roam.signal) } }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Roam.paper)
            .safeAreaInset(edge: .top, spacing: 0) {
                RoamSearchField(prompt: "Cities and places in \(name)", text: $query, focus: $searchFocused, identifier: "area-search")
                    .frame(height: 44)
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.vertical, Theme.Spacing.s)
            }
            .navigationTitle("Where in \(name)?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(saving || picks.isEmpty)
                        .accessibilityIdentifier("area-log-save")
                }
            }
            .task(id: query) { await placeSearch.run(query, services: services, scope: scope) }
        }
        .roamSheetStyle()
        .presentationDetents([.large])
        .screenIdentifier("area-log")
    }

    private func pickRow(_ pick: Pick) -> some View {
        row(symbol: pick.symbol, title: pick.title, subtitle: pick.kind)
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
            for pick in picks { try await pick.logAsBeen(services: services, start: from, end: to) }
            onSaved()
            dismiss()
        } catch { self.error = error.roamMessage }
    }
}
