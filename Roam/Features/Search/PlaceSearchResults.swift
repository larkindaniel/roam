import SwiftUI

/// One search, shown the same way everywhere (My Places and Discover): your own places first, then cities, then
/// everything else Apple knows, each a row with its icon, name and where it is.
/// The running search. The page owns it, not the results view, so a card rebuilding its content as it rises (My Places)
/// can't cancel a search halfway and leave it blank.
@MainActor
@Observable
final class PlaceSearch {
    private(set) var model: ExperienceSearchModel?
    private(set) var cities: [Destination] = []

    func run(_ query: String, services: AppServices) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { model?.query = ""; cities = []; return }
        try? await Task.sleep(for: Limits.searchDebounce)
        guard !Task.isCancelled else { return }
        if model == nil { model = ExperienceSearchModel(services: services) }
        async let found = services.places.searchDestinations(query: query)
        await model?.search(query, near: nil)
        let hits = Array(((try? await found) ?? []).prefix(3))
        guard !Task.isCancelled else { return }
        cities = hits
    }
}

struct PlaceSearchResults: View {
    let query: String
    let placeSearch: PlaceSearch
    /// Your places to match by name first (been, going, saved); empty where they aren't to hand.
    var mine: [PlaceMapItem] = []

    @Environment(AppRouter.self) private var router
    private var search: ExperienceSearchModel? { placeSearch.model }
    private var cityHits: [Destination] { placeSearch.cities }

    var body: some View {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let matchedMine = mine.filter { $0.experience.name.lowercased().contains(needle) }.uniqued { $0.id }
        let others = (search?.hits ?? []).filter { hit in !matchedMine.contains { $0.id == hit.experience?.id } }
        Group {
            // No empty card while nothing has matched: just a line once the search has finished.
            if matchedMine.isEmpty && cityHits.isEmpty && others.isEmpty {
                if case .failed(let message) = search?.phase {
                    InlineRetryView(message: message) { Task { await search?.search(query, near: nil) } }
                } else if search?.phase == .noResults || search?.phase == .results {
                    Text("No places match \u{201C}\(query)\u{201D}.").font(.subheadline).foregroundStyle(Roam.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(matchedMine.prefix(8)) { item in
                        row(symbol: item.experience.iconName, tint: item.state.markerColor, title: item.experience.name,
                            subtitle: item.experience.areaLine) { router.push(.experience(item.id)) }
                    }
                    ForEach(cityHits) { city in
                        row(symbol: "building.2", tint: Roam.inkMuted, title: city.name, subtitle: city.subtitle) { router.push(.city(city)) }
                    }
                    ForEach(others) { hit in
                        row(symbol: hit.experience?.iconName ?? hit.candidate.iconName, tint: Roam.inkMuted, title: hit.candidate.name,
                            subtitle: [hit.candidate.locality, hit.candidate.countryName].compactMap { $0 }.uniqued().joined(separator: ", ")) {
                            Task { if let place = try? await search?.resolve(hit) { router.push(.experience(place.id)) } }
                        }
                    }
                }
                .roamCard(padding: Theme.Spacing.m)
            }
        }
    }

    private func row(symbol: String, tint: Color, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: symbol).foregroundStyle(tint).frame(width: 24).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
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
