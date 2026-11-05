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
    /// Countries whose name (or a word of it) starts with the search, as ISO codes.
    private(set) var countries: [String] = []
    /// States and provinces (Ontario, Kerala).
    private(set) var regions: [Destination] = []

    func run(_ query: String, services: AppServices) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { model?.query = ""; cities = []; countries = []; regions = []; return }
        try? await Task.sleep(for: Limits.searchDebounce)
        guard !Task.isCancelled else { return }
        if model == nil { model = ExperienceSearchModel(services: services) }
        async let found = services.places.searchDestinations(query: query)
        async let areas = services.places.searchRegions(query: query)
        await model?.search(query, near: nil)
        let hits = Array(((try? await found) ?? []).prefix(3))
        let regionHits = (try? await areas) ?? []
        guard !Task.isCancelled else { return }
        cities = hits
        regions = regionHits
        countries = Self.countries(matching: query)
    }

    private static let groupings: Set<String> = ["EU", "EZ", "UN", "QO", "XA", "XB"]

    private static func countries(matching query: String) -> [String] {
        let needle = " " + query.trimmingCharacters(in: .whitespaces)
        guard needle.count > 2 else { return [] }
        let found: [(code: String, name: String)] = Locale.Region.isoRegions.compactMap { region in
            let code = region.identifier
            // Every two-letter country or territory, small ones too (Hong Kong, Singapore aren't on the world outline map),
            // but not groupings like the EU or UN.
            guard code.count == 2, code.allSatisfy(\.isLetter), !Self.groupings.contains(code),
                  case let name = CountryName.display(code: code),
                  (" " + name).range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil else { return nil }
            return (code, name)
        }
        // "nor" puts Norway ahead of North Korea: the closest to what's typed first.
        return found.sorted { $0.name.count < $1.name.count }.prefix(2).map(\.code)
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
            if matchedMine.isEmpty && placeSearch.countries.isEmpty && placeSearch.regions.isEmpty && cityHits.isEmpty && others.isEmpty {
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
                    ForEach(placeSearch.countries, id: \.self) { code in
                        let name = CountryName.display(code: code)
                        row(flag: TripTitle.flag(code), symbol: "flag", tint: Roam.inkMuted, title: name, subtitle: "Country") {
                            router.push(.country(code))
                        }
                    }
                    ForEach(placeSearch.regions) { area in
                        row(symbol: "map", tint: Roam.inkMuted, title: area.name, subtitle: CountryName.display(area.countryName, code: area.countryCode) ?? "") { router.push(.city(area)) }
                    }
                    ForEach(cityHits) { city in
                        row(symbol: "signpost.right.and.left", tint: Roam.inkMuted, title: city.name, subtitle: city.subtitle) { router.push(.city(city)) }
                    }
                    ForEach(others) { hit in
                        row(symbol: hit.experience?.iconName ?? hit.candidate.iconName, tint: Roam.inkMuted, title: hit.candidate.name,
                            subtitle: [hit.candidate.locality, CountryName.display(hit.candidate.countryName, code: hit.candidate.countryCode)].compactMap { $0 }.uniqued().joined(separator: ", ")) {
                            Task { if let place = try? await search?.resolve(hit) { router.push(.experience(place.id)) } }
                        }
                    }
                }
                .roamCard(padding: Theme.Spacing.m)
            }
        }
    }

    private func row(flag: String? = nil, symbol: String, tint: Color, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.m) {
                Group {
                    if let flag { Text(flag).font(.title3) } else { Image(systemName: symbol).foregroundStyle(tint) }
                }
                .frame(width: 24).accessibilityHidden(true)
                // Name and where it is sit tight together, so the rows read apart.
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
