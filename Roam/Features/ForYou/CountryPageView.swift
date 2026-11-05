import MapKit
import SwiftUI

/// One country, or one state or province in it, on a plain full-screen page (no map, unlike a city): its name with
/// Been / Wishlist / Plan beside it, its Google photo and Wikipedia blurb, then your home, trips, wishlist and cities
/// there, and places we think you'd enjoy.
struct CountryPageView: View {
    let code: String
    /// A state or province (Ontario) instead of the whole country: its name, its code in `region` ("ON"), its middle.
    var region: Destination?

    init(code: String, region: Destination? = nil) {
        self.code = code.uppercased()
        self.region = region
    }

    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(LibraryStore.self) private var library
    @State private var model: MyPlacesModel?
    @State private var suggestions: ForYouModel?
    @State private var savedCodes: [String] = []
    @State private var logging = false
    @State private var confirmingBeen = false
    /// Scrolled past the big name, so the small one shows at the top, as standard.
    @State private var scrolledPastTitle = false
    @State private var planningNewTrip = false
    @State private var explainingSaved = false

    static func destination(for code: String) -> Destination {
        CountryDestination.make(code: code)
            ?? Destination(name: CountryName.display(code: code), region: nil, countryCode: code,
                           countryName: nil, latitude: 20, longitude: 0, radiusMeters: 1_500_000)
    }

    /// A country too small for the world outline map (Hong Kong) is found by name instead.
    @State private var lookedUp: Destination?
    private var destination: Destination { region ?? CountryDestination.make(code: code) ?? lookedUp ?? Self.destination(for: code) }
    private var countryName: String { CountryName.display(code: code) }
    private var name: String { region?.name ?? countryName }
    /// How saved regions are keyed: "CA|ON".
    private var savedKey: String { region.map { "\(code)|\($0.region ?? $0.name)" } ?? code }
    /// In the region, when this is one: places and cities carry its code ("ON") or, now and then, its name.
    private func inRegion(_ value: String?) -> Bool {
        guard let region else { return true }
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return false }
        return [region.region, region.name].contains { $0?.caseInsensitiveCompare(value) == .orderedSame }
    }
    private func isHere(_ place: ExperienceSummary) -> Bool { place.countryCode?.uppercased() == code && inRegion(place.region) }
    private func isHere(_ city: Destination) -> Bool { city.countryCode?.uppercased() == code && inRegion(city.region) }

    private var been: PassportCountry? { model?.passport.first { $0.code.uppercased() == code } }
    /// The cities you've been to here.
    private var beenCities: [PassportCity] { (been?.cities ?? []).filter { isHere($0.city) } }
    private var hasBeen: Bool { region == nil ? been != nil : !beenCities.isEmpty }
    /// Saved itself, or you've saved a city or place here and haven't been.
    private var isSaved: Bool { savedCodes.contains(savedKey) || savedHereCount > 0 }
    private var savedHereCount: Int { wishlistCities.count + wishlistPlaces.count + wishlistRegions.count }
    private var pins: [PlaceMapItem] { (model?.pins ?? []).filter { isHere($0.experience) } }
    private var upcomingTrips: [TripSummary] { trips.filter { $0.phase(today: MyTimeline.today()) != .past } }
    private var pastTrips: [TripSummary] { trips.filter { $0.phase(today: MyTimeline.today()) == .past } }
    private var homes: [Destination] { (model?.homeCities ?? []).filter(isHere) }
    /// Every trip with a city here, past and ahead, in date order; ones with no dates yet last.
    private var trips: [TripSummary] {
        (model?.trips ?? []).filter { trip in region == nil ? trip.covers(country: code) : trip.cities.contains(where: isHere) }
            .sorted { a, b in
                switch (a.startDate, b.startDate) {
                case let (x?, y?): return x < y
                case (nil, _?): return false
                case (_?, nil): return true
                case (nil, nil): return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                }
            }
    }
    private var wishlistCities: [Destination] { (model?.savedCities ?? []).filter(isHere) }
    private var wishlistPlaces: [PlaceMapItem] { (model?.travelWishlist ?? []).filter { isHere($0.experience) } }
    /// The cities on your wishlist here: saved whole, or where you've saved places, with how many places.
    private var wishlistCityRows: [(city: Destination, places: Int)] {
        var rows: [(city: Destination, places: Int)] = wishlistCities.map { city in
            (city, wishlistPlaces.filter { CityMatch.same($0.experience, city) }.count)
        }
        let byTown = Dictionary(grouping: wishlistPlaces.filter { !($0.experience.locality ?? "").isEmpty }) {
            GeographyKey.normalize($0.experience.locality ?? "")
        }
        for (_, items) in byTown.sorted(by: { $0.key < $1.key }) {
            guard let first = items.first?.experience, !rows.contains(where: { CityMatch.same(first, $0.city) }) else { continue }
            let latitude = items.map(\.experience.latitude).reduce(0, +) / Double(items.count)
            let longitude = items.map(\.experience.longitude).reduce(0, +) / Double(items.count)
            rows.append((Destination(name: first.locality ?? "", region: first.region, countryCode: first.countryCode,
                                     countryName: first.countryName, latitude: latitude, longitude: longitude, radiusMeters: 12_000), items.count))
        }
        return rows
    }

    /// States you've saved in this country (on a country's page only).
    private var wishlistRegions: [SavedRegion] {
        region == nil ? (model?.savedRegions ?? []).filter { $0.countryCode.uppercased() == code } : []
    }
    /// Places others loved here that aren't already yours.
    private var recommended: [DiscoverPlace] {
        guard case .loaded(let sections) = suggestions?.phase else { return [] }
        let mine = Set(pins.map(\.id))
        return (sections.friends + sections.highlyRated + sections.more).uniqued { $0.id }
            .filter { isHere($0.experience) && !mine.contains($0.id) }
    }
    /// Google's photo of a place here, for when the country's (or region's) own has none.
    private var fallbackPhoto: URL? {
        (pins.map(\.experience) + recommended.map(\.experience)).lazy.compactMap(\.photoURL).first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header
                if !homes.isEmpty { homeLinks }
                countryInfo
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.s)
            // Clear of the tab bar floating over the bottom.
            .padding(.bottom, Theme.Spacing.xxl + RoamTabBar.reservedHeight)
        }
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 44 } action: { _, past in
            withAnimation(.easeInOut(duration: 0.2)) { scrolledPastTitle = past }
        }
        .background(Roam.paper)
        .refreshable { await reload() }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        // However you got here, Discover / Friends / My Places are at the bottom.
        .roamTabBarShown()
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(name).font(.headline).opacity(scrolledPastTitle ? 1 : 0).accessibilityHidden(!scrolledPastTitle)
            }
        }
            .task(id: savedKey) { await reload() }
            .onChange(of: library.revision) { _, _ in Task { await model?.load() } }
            // "Where in Norway?": the cities and places you went to, alike.
            .sheet(isPresented: $logging) {
                AreaLogSheet(name: name, countryCode: code, region: region, around: destination) {
                    library.noteChanged()
                    Task { await model?.load() }
                }
            }
            .alert("You've saved \(savedHereCount) \(savedHereCount == 1 ? "city or place" : "cities and places") here", isPresented: $explainingSaved) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("\(name) stays on your wishlist while they're saved. Remove them to take it off.")
            }
            .sheet(isPresented: $planningNewTrip) {
                TripEditorSheet(draft: TripDraft(), initialCountries: [code]) { trip in
                    library.noteChanged()
                    router.push(.trip(trip.id))
                }
                .presentationBackground(Roam.paper)
            }
            .screenIdentifier("country-page")
    }

    // MARK: Header

    /// The name with its flag just under it (a region has a chip to its country instead), centred against the actions on
    /// the same line.
    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: region == nil ? -6 : Theme.Spacing.xs) {
                Text(name)
                    .font(.roamDisplay(.title)).lineLimit(2).minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
                if region != nil {
                    Button { router.push(.country(code)) } label: {
                        HStack(spacing: 3) {
                            Text([TripTitle.flag(code), countryName].compactMap { $0 }.joined(separator: " ")).lineLimit(1)
                            Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Roam.ink)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(Roam.ink.opacity(0.08)))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("region-open-country")
                } else if let flag = TripTitle.flag(code) {
                    Text(flag).font(.title3).accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            actionRow
        }
    }

    /// Your own trips still ahead that don't already go here, to add the country to.
    private var tripsToAddTo: [TripSummary] {
        (model?.trips ?? []).filter { $0.isOwn && $0.phase(today: MyTimeline.today()) != .past && !$0.covers(country: code) }
    }

    /// Been (green), Wishlist (yellow, greyed once you've been), Trip (blue) and Plan with AI (pink), as on a city.
    private var actionRow: some View {
        HStack(spacing: Theme.Spacing.m) {
            circle(hasBeen ? "checkmark" : "plus", tint: PlaceState.visited.markerColor, filled: hasBeen,
                   caption: hasBeen ? "Been" : "Log", identifier: "country-log") {
                // Been comes from the cities and places you've been to, so logging asks where.
                if hasBeen { confirmingBeen = true } else { logging = true }
            }
            .alert("You've been to \(name)", isPresented: $confirmingBeen) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("It counts as somewhere you've been while you have places there. Remove them from their pages to take it off.")
            }
            circle(isSaved ? "bookmark.fill" : "bookmark", tint: hasBeen ? Roam.inkFaint : PlaceState.wishlist.markerColor,
                   filled: isSaved && !hasBeen, caption: isSaved ? "Saved" : "Wishlist", identifier: "country-wishlist") {
                guard !hasBeen else { return }
                // Saved because of cities or places saved here: it comes off with them, so tapping explains instead.
                if isSaved && !savedCodes.contains(savedKey) { explainingSaved = true } else { Task { await setSaved(!isSaved) } }
            }
            // A trip can go to the whole country before any of its cities or places are picked (not yet to a region).
            if region == nil { tripMenu }
            circle("sparkles", tint: .pink, filled: false, caption: "Plan", identifier: "country-plan") {
                router.sheet = .researchBrief(destination)
            }
        }
    }

    private var tripMenu: some View {
            Menu {
                ForEach(tripsToAddTo) { trip in Button(trip.name) { Task { await add(to: trip) } } }
                Button("New trip", systemImage: "plus") { planningNewTrip = true }
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "airplane")
                        .font(.headline)
                        .foregroundStyle(PlaceState.planned.markerColor)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(PlaceState.planned.markerColor.opacity(0.15)))
                    Text("Trip").font(.caption2).foregroundStyle(Roam.ink).lineLimit(1).fixedSize()
                }
                .frame(minWidth: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Add to a trip")
            .accessibilityIdentifier("country-trip")
    }

    private func circle(_ symbol: String, tint: Color, filled: Bool, caption: String, identifier: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.headline)
                    .foregroundStyle(filled ? .white : tint)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(filled ? tint : tint.opacity(0.15)))
                Text(caption).font(.caption2).foregroundStyle(Roam.ink).lineLimit(1).fixedSize()
            }
            .frame(minWidth: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(caption)
        .accessibilityIdentifier(identifier)
    }

    // MARK: Content

    @ViewBuilder private var countryInfo: some View {
        // The blurb sits snug under its photo.
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            CountryPhoto(code: code, region: region.map { $0.region ?? $0.name }, name: region == nil ? name : "\(name), \(countryName)",
                         fallback: fallbackPhoto)
            CityGuideCard(name: name, country: region == nil ? nil : countryName, coordinate: destination.coordinate, showsPhoto: false,
                          within: region == nil ? 3_000_000 : 1_500_000)
        }
        if let model, model.hasLoaded {
            if !upcomingTrips.isEmpty {
                section("Upcoming trips") { tripList(upcomingTrips, model: model) }
            }
            if !pastTrips.isEmpty {
                section("Past trips") { tripList(pastTrips, model: model) }
            }
            // No titles: the marks on the rows say which is which. Where you want to go, then where you've been.
            wishlistCard
            beenCard
        } else {
            SkeletonList(rows: 3)
        }
        switch suggestions?.phase ?? .loading {
        case .idle, .loading:
            EmptyView()
        case .failed(let message):
            InlineRetryView(message: message) { Task { await suggestions?.load(destination) } }
        case .loaded:
            // A level down from a country or state: cities, not places.
            let cities = DiscoverCity.cities(from: recommended)
            if !cities.isEmpty {
                section("Places we think you'd enjoy") {
                    LazyVStack(spacing: Theme.Spacing.l) {
                        ForEach(cities) { city in
                            Button { router.push(.city(city.destination)) } label: {
                                CityHeroCard(city: city.destination, subtitle: suggestionLine(city))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("country-suggested-\(city.destination.name)")
                        }
                    }
                }
            }
        }
    }

    /// "Dhyan has been", or where it is when no friend has.
    private func suggestionLine(_ city: DiscoverCity) -> String {
        let names = city.friendNames.compactMap { $0.split(separator: " ").first.map(String.init) }
        guard let first = names.first else { return city.destination.region ?? "" }
        return names.count == 1 ? "\(first) has been" : (names.count == 2 ? "\(first) and \(names[1]) have been" : "\(first) and \(names.count - 1) others have been")
    }

    /// Your home here first, as a plain link to its page.
    private var homeLinks: some View {
        VStack(spacing: 0) {
            ForEach(homes) { home in
                Button { router.push(.city(home)) } label: {
                    HStack(spacing: Theme.Spacing.m) {
                        Image(systemName: "house.fill").foregroundStyle(Roam.home).frame(width: 24).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(home.name).font(.headline).foregroundStyle(Roam.ink)
                            Text("Home").font(.footnote).foregroundStyle(Roam.inkMuted)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Roam.inkFaint)
                    }
                    .frame(minHeight: Theme.minimumHitTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Home: \(home.name)")
                .accessibilityIdentifier("country-home-\(home.name)")
                if home.id != homes.last?.id { Divider() }
            }
        }
        .roamCard(padding: Theme.Spacing.m)
    }

    private func tripList(_ list: [TripSummary], model: MyPlacesModel) -> some View {
        VStack(spacing: 0) {
            ForEach(list) { trip in
                TripCard(trip: trip, cover: model.tripDetails[trip.id]?.places.first?.experience)
                if trip.id != list.last?.id { Divider() }
            }
        }
        .roamCard(padding: Theme.Spacing.m)
    }

    private func cityCard(_ city: Destination, isHome: Bool) -> some View {
        Button { router.push(.city(city)) } label: {
            CityPhotoCard(destination: city, isHome: isHome).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("country-city-\(city.name)")
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Text(title).font(.roamTitle()).foregroundStyle(Roam.ink).accessibilityAddTraits(.isHeader)
            content()
        }
    }

    /// The cities you've been to here, as rows (homes have their own link at the top).
    @ViewBuilder private var beenCard: some View {
        let cities = beenCities.filter { !$0.isHome }
        if !cities.isEmpty {
            VStack(spacing: 0) {
                ForEach(cities) { city in
                    CityRow(city: city.city, state: .visited) {
                        router.push(.city(city.city))
                    }
                    if city.id != cities.last?.id { RowSeparator() }
                }
            }
            .roamCard(padding: Theme.Spacing.m)
        }
    }

    /// Where you want to go here, one level down: states you've saved (on a country), then cities saved whole or where
    /// you've saved places; a saved place with no town stays a place.
    @ViewBuilder private var wishlistCard: some View {
        let rows = wishlistCityRows
        let loose = wishlistPlaces.filter { ($0.experience.locality ?? "").isEmpty }
        let total = wishlistRegions.count + rows.count + loose.count
        if total > 0 {
            VStack(spacing: 0) {
                ForEach(Array(wishlistRegions.enumerated()), id: \.element.id) { index, saved in
                    regionRow(saved)
                    if index < total - 1 { RowSeparator() }
                }
                ForEach(Array(rows.enumerated()), id: \.element.city.id) { index, row in
                    CityRow(city: row.city, state: .wishlist) {
                        router.push(.city(row.city))
                    }
                    if wishlistRegions.count + index < total - 1 { RowSeparator() }
                }
                ForEach(Array(loose.enumerated()), id: \.element.id) { index, item in
                    PlaceRow(item: item) { router.push(.experience(item.id)) }
                    if wishlistRegions.count + rows.count + index < total - 1 { RowSeparator() }
                }
            }
            .roamCard(padding: Theme.Spacing.m)
        }
    }

    private func regionRow(_ saved: SavedRegion) -> some View {
        Button { if let area = saved.destination { router.push(.region(area)) } } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "map").foregroundStyle(PlaceState.wishlist.markerColor).frame(width: 48)
                    .accessibilityHidden(true)
                Text(saved.name).font(.headline).foregroundStyle(Roam.ink)
                Spacer(minLength: 0)
                if saved.destination != nil {
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Roam.inkMuted)
                }
            }
            .padding(.vertical, Theme.Spacing.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("country-saved-region-\(saved.region)")
    }

    // MARK: Loading

    private func reload() async {
        if region == nil, CountryDestination.make(code: code) == nil, lookedUp == nil,
           let found = try? await CLGeocoder().geocodeAddressString(name).first(where: { $0.isoCountryCode?.uppercased() == code }),
           let at = found.location?.coordinate {
            lookedUp = Destination(name: name, region: nil, countryCode: code, countryName: name,
                                   latitude: at.latitude, longitude: at.longitude, radiusMeters: 60_000)
        }
        if model == nil, let me = session.userID { model = MyPlacesModel(services: services, ownerID: me) }
        if suggestions == nil { suggestions = ForYouModel(plans: services.plans) }
        async let mine: Void = model?.load() ?? ()
        async let saved = region == nil ? services.plans.savedCountries() : services.plans.savedRegions()
        savedCodes = (try? await saved) ?? savedCodes
        await mine
        await suggestions?.load(destination)
    }

    private func add(to trip: TripSummary) async {
        try? await services.plans.setTripCountry(tripID: trip.id, code: code, name: name, present: true)
        library.noteChanged()
        router.push(.trip(trip.id))
    }

    /// A whole country (or region) on your wishlist.
    private func setSaved(_ present: Bool) async {
        if let region {
            savedCodes = (try? await services.plans.setRegionSaved(country: code, region: region.region ?? region.name, name: name,
                                                                   area: region, present: present)) ?? savedCodes
        } else {
            savedCodes = (try? await services.plans.setCountrySaved(code: code, name: name, present: present)) ?? savedCodes
        }
        library.noteChanged()
    }
}

/// A country's (or region's) photo from its own Google entry, else Google's photo of a place there.
struct CountryPhoto: View {
    let code: String
    var region: String?
    let name: String
    var fallback: URL?
    @Environment(AppServices.self) private var services
    @State private var photo: (url: URL, credit: String?)?
    @State private var looked = false

    var body: some View {
        ZStack {
            if let url = photo?.url ?? (looked ? fallback : nil) {
                PlacePhotoView(url: url, credit: photo?.credit, label: "Photo of \(name)", placeholderSymbol: "globe", height: 220,
                               showsCredit: photo?.credit != nil)
            }
        }
        .task(id: "\(code)|\(region ?? "")") {
            photo = await services.plans.countryPhoto(code: code, region: region, name: name)
            looked = true
        }
    }
}
