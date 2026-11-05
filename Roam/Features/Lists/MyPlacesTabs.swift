import MapKit
import SwiftUI

/// My Places in two parts, coloured like the place states they hold. Upcoming trips sit on Saved.
enum MyPlacesTab: String, CaseIterable, Identifiable {
    case been
    case saved

    var id: String { rawValue }

    var title: String {
        switch self {
        case .been: return "Been"
        case .saved: return "Saved"
        }
    }

    var state: PlaceState {
        switch self {
        case .been: return .visited
        case .saved: return .wishlist
        }
    }
}

/// A segmented control: one track, with the chosen segment's pill sliding across in its place-state colour.
struct MyPlacesTabPicker: View {
    @Binding var tab: MyPlacesTab
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MyPlacesTab.allCases) { option in
                let selected = option == tab
                Button {
                    withAnimation(.spring(duration: 0.3)) { tab = option }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: option.state.markerSymbol).font(.caption.weight(.bold))
                        Text(option.title).font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(selected ? .white : Roam.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background {
                        if selected {
                            Capsule().fill(option.state.markerColor)
                                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("myplaces-tab-\(option.rawValue)")
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.gray.opacity(0.18)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Show places")
    }
}

// MARK: - Been

/// Where you've been: the passport, your home spots, then past trips.
struct BeenTab: View {
    let model: MyPlacesModel
    var onAddHome: () -> Void

    @Environment(AppRouter.self) private var router

    var body: some View {
        let countries = model.passport
        let cityCount = countries.map(\.cities.count).reduce(0, +)
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            HomeCitiesCard(model: model, onAdd: onAddHome)
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(countries.count)").font(.roamTitle()).monospacedDigit()
                    Text(countries.count == 1 ? "country" : "countries").foregroundStyle(Roam.inkMuted)
                    Text("·").foregroundStyle(Roam.inkMuted)
                    Text("\(cityCount)").font(.roamTitle()).monospacedDigit()
                    Text(cityCount == 1 ? "city" : "cities").foregroundStyle(Roam.inkMuted)
                }
                .accessibilityElement(children: .combine)
                CountryCards(count: countries.count) {
                    ForEach(countries) { country in
                        Button { router.push(.country(country.code)) } label: {
                            if countries.count < CountryCardsLayout.gridFrom {
                                CountryCoverCard(code: country.code, title: country.title, subtitle: beenLine(country))
                            } else {
                                tile(country)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("passport-\(country.code)")
                    }
                }
            }
        }
    }

    private static let tileHeight: CGFloat = 150

    /// "3 cities · 12 places" you've been to there.
    private func beenLine(_ country: PassportCountry) -> String {
        let cities = country.cities.count, places = country.placeCount
        return [cities > 0 ? (cities == 1 ? "1 city" : "\(cities) cities") : nil,
                places > 0 ? (places == 1 ? "1 place" : "\(places) places") : nil].compactMap { $0 }.joined(separator: " · ")
    }

    /// A country you've been to, pictured by the Wikipedia photo of the city you've been to most there (a country's own
    /// article leads with its flag). Away-from-home cities come first, so a home country shows somewhere you travelled.
    private func tile(_ country: PassportCountry) -> some View {
        let cover = country.cities.sorted { ($0.isHome ? 1 : 0, -$0.placeCount) < ($1.isHome ? 1 : 0, -$1.placeCount) }.first?.city
        return ZStack(alignment: .bottomLeading) {
            // The country's own Google photo, the same one its page leads with.
            AreaPhoto(name: country.name, countryCode: country.code, coordinate: cover?.coordinate ?? CLLocationCoordinate2D(),
                      symbol: "globe", height: Self.tileHeight)
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                .allowsHitTesting(false)
            Text(country.title).font(.headline).foregroundStyle(.white).lineLimit(1)
                .padding(Theme.Spacing.m)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Your home cities, each opening its spots. Shown at the top of Been and Saved.
struct HomeCitiesCard: View {
    let model: MyPlacesModel
    var onAdd: (() -> Void)?

    @Environment(AppRouter.self) private var router

    var body: some View {
        // No prompt to set a home here; it's set from a city's page.
        if !model.homeCities.isEmpty {
            VStack(spacing: 0) {
                ForEach(model.homeCities) { city in
                    Button { router.push(.city(city)) } label: {
                        HStack(spacing: Theme.Spacing.m) {
                            Image(systemName: "house.fill").foregroundStyle(Roam.home).frame(width: 24)
                            Text(city.name).font(.headline).foregroundStyle(Roam.ink)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Roam.inkMuted).accessibilityHidden(true)
                        }
                        .frame(minHeight: Theme.minimumHitTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu { Button("Remove home city", role: .destructive) { Task { await model.setHome(city, present: false) } } }
                    .accessibilityIdentifier("home-city-\(city.name)")
                    if city.id != model.homeCities.last?.id { Divider() }
                }
            }
            .roamCard(padding: Theme.Spacing.m)
        }
    }
}

/// Your upcoming trips, one row each like your homes, with + New trip as the last row: all one card.
struct UpcomingTripsCard: View {
    let model: MyPlacesModel
    var onNewTrip: () -> Void

    @Environment(AppRouter.self) private var router

    private var trips: [TripSummary] {
        let today = MyTimeline.today()
        let upcoming = model.trips.filter { $0.isOwn && $0.phase(today: today) != .past }
        // Soonest first; every trip has dates, so none should be missing one.
        return upcoming.sorted { a, b in
            guard let first = a.startDate else { return false }
            guard let second = b.startDate else { return true }
            return first < second
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(trips) { trip in
                tripRow(trip)
                Divider()
            }
            Button(action: onNewTrip) {
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: "plus").fontWeight(.semibold).frame(width: 24).accessibilityHidden(true)
                    Text("New trip").font(.headline)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(PlaceState.planned.markerColor)
                .frame(minHeight: Theme.minimumHitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("upcoming-new-trip")
        }
        .roamCard(padding: Theme.Spacing.m)
    }

    private func tripRow(_ trip: TripSummary) -> some View {
        Button { router.push(.trip(trip.id)) } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "airplane").foregroundStyle(PlaceState.planned.markerColor).frame(width: 24).accessibilityHidden(true)
                Text(trip.name).font(.headline).foregroundStyle(Roam.ink).lineLimit(1)
                Spacer(minLength: Theme.Spacing.s)
                Text(MyTimeline.range(trip.startDate, trip.endDate) ?? "").font(.footnote).foregroundStyle(Roam.inkMuted).lineLimit(1)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Roam.inkMuted).accessibilityHidden(true)
            }
            .frame(minHeight: Theme.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("upcoming-trip-\(trip.name)")
    }
}

// MARK: - Saved

/// Your wishlist as country photo tiles, and your own lists.
struct SavedTab: View {
    let model: MyPlacesModel
    var onNewTrip: () -> Void = {}

    @Environment(AppRouter.self) private var router

    /// A country on Saved: one with saved cities or places in it, or one you've wishlisted as a whole (or a state of).
    private enum SavedCountry: Identifiable {
        case group(PlaceGroups.Country, regions: [SavedRegion])
        case whole(code: String, regions: [SavedRegion])

        var id: String {
            switch self {
            case .group(let country, _): return country.code.uppercased()
            case .whole(let code, _): return code
            }
        }
    }

    // Saved places by country, for now; custom lists are set aside.
    var body: some View {
        // Saved places, whole saved cities and states, and whole saved countries, by country.
        let groups = PlaceGroups(model.travelWishlist, extraCities: model.savedCities).countries
        let groupCodes = Set(groups.map { $0.code.uppercased() })
        let regions = Dictionary(grouping: model.savedRegions) { $0.countryCode.uppercased() }
        let wholes = (model.savedCountries.map { $0.uppercased() } + model.savedRegions.map { $0.countryCode.uppercased() })
            .uniqued().filter { !groupCodes.contains($0) }
        let countries: [SavedCountry] = groups.map { .group($0, regions: regions[$0.code.uppercased()] ?? []) }
            + wholes.map { .whole(code: $0, regions: regions[$0] ?? []) }
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HomeCitiesCard(model: model)
            UpcomingTripsCard(model: model, onNewTrip: onNewTrip)
            if countries.isEmpty {
                Text("Save places you want to go. When you're ready, plan a trip from them.").font(.subheadline).foregroundStyle(Roam.inkMuted)
            } else {
                CountryCards(count: countries.count) {
                    ForEach(countries) { country in
                        if countries.count < CountryCardsLayout.gridFrom {
                            Button { router.push(.country(country.id)) } label: { card(country) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("wishlist-country-\(country.id)")
                        } else {
                            switch country {
                            case .group(let group, _): tile(group)
                            case .whole(let code, _): wholeTile(code)
                            }
                        }
                    }
                }
            }
        }
    }

    private func card(_ country: SavedCountry) -> some View {
        switch country {
        case .group(let group, let regions):
            return CountryCoverCard(code: group.code, title: group.title, subtitle: savedLine(group, regions: regions),
                                    fallbackURL: group.cities.flatMap(\.items).lazy.compactMap(\.experience.photoURL).first)
        case .whole(let code, let regions):
            // Wishlisted as a whole, or a state of it ("Ontario").
            return CountryCoverCard(code: code, title: CountryTitle.text(name: nil, code: code),
                                    subtitle: regions.isEmpty ? "Whole country" : regions.map(\.name).joined(separator: ", "))
        }
    }

    /// "2 cities · 5 places" saved there, and any states saved whole.
    private func savedLine(_ country: PlaceGroups.Country, regions: [SavedRegion] = []) -> String {
        let places = country.cities.flatMap(\.items).count
        let cities = country.cities.count
        return ([cities > 0 ? (cities == 1 ? "1 city" : "\(cities) cities") : nil,
                 places > 0 ? (places == 1 ? "1 place" : "\(places) places") : nil] + regions.map { Optional($0.name) })
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// A country saved as a whole, as a grid tile.
    private func wholeTile(_ code: String) -> some View {
        Button { router.push(.country(code)) } label: {
            ZStack(alignment: .bottomLeading) {
                AreaPhoto(name: CountryName.display(code: code), countryCode: code, coordinate: CLLocationCoordinate2D(),
                          symbol: "bookmark", height: 150)
                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                    .allowsHitTesting(false)
                Text(CountryTitle.text(name: nil, code: code)).font(.headline).foregroundStyle(.white).lineLimit(1)
                    .padding(Theme.Spacing.m)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("wishlist-country-\(code)")
    }

    private func tile(_ country: PlaceGroups.Country) -> some View {
        let cover = country.cities.flatMap(\.items).first { $0.experience.photoURL != nil }?.experience ?? country.cities.first?.items.first?.experience
        // A city you've saved there pictures the tile when you've saved no places.
        let savedCity = model.savedCities.first { $0.countryCode?.uppercased() == country.code.uppercased() && $0.name == country.cities.first?.name }
        return Button {
            router.push(.country(country.code))
        } label: {
            ZStack(alignment: .bottomLeading) {
                // The country's own Google photo, the same one its page leads with.
                let anchor = country.cities.first?.items.first?.experience
                AreaPhoto(name: country.title, countryCode: country.code,
                          coordinate: anchor?.coordinate ?? savedCity?.coordinate ?? CLLocationCoordinate2D(), fallbackURL: cover?.photoURL,
                          symbol: "bookmark", height: 150)
                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                    .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 0) {
                    Text(country.title).font(.headline).foregroundStyle(.white).lineLimit(1)
                }
                .padding(Theme.Spacing.m)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("wishlist-country-\(country.code)")
    }
}


enum CountryCardsLayout {
    /// From this many countries, they go two across in a grid of smaller tiles.
    static let gridFrom = 10
}

/// Countries on My Places: big photo cards, one under another, up to nine; from ten, a two-across grid.
struct CountryCards<Content: View>: View {
    let count: Int
    @ViewBuilder var content: () -> Content

    var body: some View {
        if count < CountryCardsLayout.gridFrom {
            LazyVStack(spacing: Theme.Spacing.l) { content() }
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.m), GridItem(.flexible(), spacing: Theme.Spacing.m)],
                      spacing: Theme.Spacing.m) { content() }
        }
    }
}

/// A big card like an upcoming trip's: the photo edge to edge, darkening at the bottom under the name and a line in white.
struct HeroPhotoCard: View {
    /// A photo stored on Roam (from a visit), else one at a URL.
    var path: String?
    var url: URL?
    let title: String
    var subtitle = ""
    var symbol = "globe"
    var location: CLLocationCoordinate2D?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            PlacePhotoView(path: path, url: url, label: "Photo of \(title)", placeholderSymbol: symbol, height: 210, showsCredit: false,
                           cornerRadius: 0, location: location)
            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: -3) {
                Text(title).font(.roamTitle()).foregroundStyle(.white).lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                }
            }
            .padding(Theme.Spacing.l)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A city as a big card, like an upcoming trip's, led by its Google photo.
struct CityHeroCard: View {
    let city: Destination
    var subtitle: String?

    @Environment(AppServices.self) private var services
    @State private var photo: AreaPhotos.Photo?

    var body: some View {
        HeroPhotoCard(url: photo?.url, title: city.name, subtitle: subtitle ?? city.subtitle, symbol: "signpost.right.and.left",
                      location: city.coordinate)
            .task(id: city.id) {
                photo = await AreaPhotos.city(services, name: city.name, region: city.region, country: city.countryName, coordinate: city.coordinate)
            }
    }
}

/// A country as a big card, like an upcoming trip's, led by its Google photo.
struct CountryCoverCard: View {
    let code: String
    let title: String
    var subtitle = ""
    var fallbackURL: URL?

    @Environment(AppServices.self) private var services
    @State private var photo: AreaPhotos.Photo?
    @State private var looked = false

    var body: some View {
        HeroPhotoCard(url: photo?.url ?? (looked ? fallbackURL : nil), title: title, subtitle: subtitle)
            .task(id: code) {
                photo = await AreaPhotos.country(services, code: code)
                looked = true
            }
    }
}
