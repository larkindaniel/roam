import MapKit
import SwiftUI

/// My Places in three parts, coloured like the place states they hold.
enum MyPlacesTab: String, CaseIterable, Identifiable {
    case been
    case going
    case saved

    var id: String { rawValue }

    var title: String {
        switch self {
        case .been: return "Been"
        case .going: return "Going"
        case .saved: return "Saved"
        }
    }

    var state: PlaceState {
        switch self {
        case .been: return .visited
        case .going: return .planned
        case .saved: return .wishlist
        }
    }
}

/// A three-way segmented control: one track, with the chosen segment's pill sliding across in its place-state colour.
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

// MARK: - Going

/// What's ahead: the next trip large, the rest below it.
struct GoingTab: View {
    let model: MyPlacesModel

    @Environment(AppRouter.self) private var router

    private var trips: [TripSummary] {
        let today = MyTimeline.today()
        let ahead = model.trips.filter { $0.phase(today: today) != .past }
        func order(_ trip: TripSummary) -> (Int, LocalDate) {
            switch trip.phase(today: today) {
            case .now: return (0, trip.startDate ?? today)
            case .upcoming: return (1, trip.startDate ?? trip.endDate ?? today)
            default: return (2, today)
            }
        }
        return ahead.sorted { order($0) < order($1) }
    }

    var body: some View {
        let trips = trips
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            if let next = trips.first {
                hero(next)
                if trips.count > 1 {
                    VStack(spacing: 0) {
                        ForEach(trips.dropFirst()) { trip in
                            TripCard(trip: trip, cover: model.tripDetails[trip.id]?.places.first?.experience)
                            if trip.id != trips.last?.id { Divider() }
                        }
                    }
                    .roamCard(padding: Theme.Spacing.m)
                }
            } else {
                Text("No trips yet. Plan one from your saved places, or start fresh.").font(.subheadline).foregroundStyle(Roam.inkMuted)
            }
        }
    }

    private func hero(_ trip: TripSummary) -> some View {
        let cover = model.tripDetails[trip.id]?.places.first?.experience
        let location = cover?.coordinate ?? trip.cities.first.map(\.coordinate)
        return Button { router.push(.trip(trip.id)) } label: {
            ZStack(alignment: .bottomLeading) {
                if let city = trip.coverCity {
                    AreaPhoto(name: city.name, region: city.region, country: city.countryName, coordinate: city.coordinate,
                              fallbackURL: cover?.photoURL, symbol: "airplane", height: 210)
                } else {
                    PlacePhotoView(url: cover?.photoURL, label: "Photo for \(trip.name)", placeholderSymbol: "airplane", height: 210,
                                   showsCredit: false, cornerRadius: 0, location: location)
                }
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                    .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(trip.name).font(.roamTitle()).foregroundStyle(.white)
                    Text([trip.placeLine.isEmpty || trip.placeLine == trip.name ? nil : trip.placeLine,
                          MyTimeline.range(trip.startDate, trip.endDate)].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                }
                .padding(Theme.Spacing.l)
            }
            .overlay(alignment: .topTrailing) {
                Text(countdown(trip))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Capsule().fill(PlaceState.planned.markerColor))
                    .padding(Theme.Spacing.m)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("trip-hero-\(trip.name)")
    }

    private func countdown(_ trip: TripSummary) -> String {
        let today = MyTimeline.today()
        switch trip.phase(today: today) {
        case .now: return "Now"
        case .upcoming:
            guard let start = trip.startDate else { return "Upcoming" }
            let days = MyTimeline.days(from: today, to: start)
            return days == 1 ? "Tomorrow" : "In \(days) days"
        default: return "No dates yet"
        }
    }
}

// MARK: - Saved

/// Your wishlist as country photo tiles, and your own lists.
struct SavedTab: View {
    let model: MyPlacesModel

    @Environment(AppRouter.self) private var router

    // Saved places by country, for now; custom lists are set aside.
    var body: some View {
        // Saved places and whole saved cities, by country.
        let countries = PlaceGroups(model.travelWishlist, extraCities: model.savedCities).countries
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HomeCitiesCard(model: model)
            if countries.isEmpty {
                Text("Save places you want to go. When you're ready, plan a trip from them.").font(.subheadline).foregroundStyle(Roam.inkMuted)
            } else {
                CountryCards(count: countries.count) {
                    ForEach(countries) { country in
                        if countries.count < CountryCardsLayout.gridFrom {
                            Button { router.push(.country(country.code)) } label: {
                                CountryCoverCard(code: country.code, title: country.title, subtitle: savedLine(country),
                                                 fallbackURL: country.cities.flatMap(\.items).lazy.compactMap(\.experience.photoURL).first)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("wishlist-country-\(country.code)")
                        } else {
                            tile(country)
                        }
                    }
                }
            }
        }
    }

    /// "2 cities · 5 places" saved there.
    private func savedLine(_ country: PlaceGroups.Country) -> String {
        let places = country.cities.flatMap(\.items).count
        let cities = country.cities.count
        return [cities > 0 ? (cities == 1 ? "1 city" : "\(cities) cities") : nil,
                places > 0 ? (places == 1 ? "1 place" : "\(places) places") : nil].compactMap { $0 }.joined(separator: " · ")
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
    static let gridFrom = 8
}

/// Countries on My Places: big photo cards, one under another, while there are a few; from eight, a two-across grid.
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
            VStack(alignment: .leading, spacing: 2) {
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
