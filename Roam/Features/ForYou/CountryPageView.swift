import MapKit
import SwiftUI

/// One country, on a plain full-screen page (no map, unlike a city): its name with Been / Wishlist / Plan beside it,
/// its Google photo and Wikipedia blurb, then the cities you've been to, your trips there, your wishlist there, and places we think
/// you'd enjoy.
struct CountryPageView: View {
    let code: String

    init(code: String) {
        self.code = code.uppercased()
    }

    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(LibraryStore.self) private var library
    @State private var model: MyPlacesModel?
    @State private var suggestions: ForYouModel?
    @State private var savedCodes: [String] = []
    @State private var pickingCity = false
    /// The city picked for Been, asked for its dates once the picker has gone.
    @State private var pickedCity: Destination?
    @State private var datesFor: Destination?
    @State private var confirmingBeen = false
    /// Scrolled past the big name, so the small one shows at the top, as standard.
    @State private var scrolledPastTitle = false
    /// Sections folded away, by title.
    @State private var collapsed: Set<String> = []

    static func destination(for code: String) -> Destination {
        CountryDestination.make(code: code)
            ?? Destination(name: Locale.current.localizedString(forRegionCode: code) ?? code, region: nil, countryCode: code,
                           countryName: nil, latitude: 20, longitude: 0, radiusMeters: 1_500_000)
    }

    private var destination: Destination { Self.destination(for: code) }
    private var name: String { Locale.current.localizedString(forRegionCode: code) ?? code }
    private func isHere(_ place: ExperienceSummary) -> Bool { place.countryCode?.uppercased() == code }

    private var been: PassportCountry? { model?.passport.first { $0.code.uppercased() == code } }
    private var hasBeen: Bool { been != nil }
    private var isSaved: Bool { savedCodes.contains(code) }
    private var pins: [PlaceMapItem] { (model?.pins ?? []).filter { isHere($0.experience) } }
    /// Every trip with a city here, past and ahead, in date order; ones with no dates yet last.
    private var trips: [TripSummary] {
        (model?.trips ?? []).filter { trip in trip.cities.contains { $0.countryCode?.uppercased() == code } }
            .sorted { a, b in
                switch (a.startDate, b.startDate) {
                case let (x?, y?): return x < y
                case (nil, _?): return false
                case (_?, nil): return true
                case (nil, nil): return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                }
            }
    }
    private var wishlistCities: [Destination] { (model?.savedCities ?? []).filter { $0.countryCode?.uppercased() == code } }
    private var wishlistPlaces: [PlaceMapItem] { (model?.travelWishlist ?? []).filter { isHere($0.experience) } }
    /// Places others loved here that aren't already yours.
    private var recommended: [DiscoverPlace] {
        guard case .loaded(let sections) = suggestions?.phase else { return [] }
        let mine = Set(pins.map(\.id))
        return (sections.friends + sections.highlyRated + sections.more).uniqued { $0.id }
            .filter { isHere($0.experience) && !mine.contains($0.id) }
    }
    /// Google's photo of a place here, for when the country's own has none.
    private var fallbackPhoto: URL? {
        (pins.map(\.experience) + recommended.map(\.experience)).lazy.compactMap(\.photoURL).first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header
                countryInfo
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 44 } action: { _, past in
            withAnimation(.easeInOut(duration: 0.2)) { scrolledPastTitle = past }
        }
        .background(Roam.paper)
        .refreshable { await reload() }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(name).font(.headline).opacity(scrolledPastTitle ? 1 : 0).accessibilityHidden(!scrolledPastTitle)
            }
        }
            .task(id: code) { await reload() }
            .onChange(of: library.revision) { _, _ in Task { await model?.load() } }
            .sheet(isPresented: $pickingCity, onDismiss: {
                if let pickedCity { datesFor = pickedCity; self.pickedCity = nil }
            }) {
                DestinationPickerSheet(purpose: .homeCity, title: "Which city in \(name)?") { city in pickedCity = city }
            }
            .sheet(item: $datesFor) { city in
                CityVisitDatesSheet(city: city) { library.noteChanged(); Task { await model?.load() } }
            }
            .screenIdentifier("country-page")
    }

    // MARK: Header

    /// The name with its flag just under it, centred against the three actions on the same line.
    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(.roamDisplay(.title)).lineLimit(2).minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
                if let flag = TripTitle.flag(code) { Text(flag).font(.title3).accessibilityHidden(true) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            actionRow
        }
    }

    /// Been (green), Wishlist (yellow, greyed once you've been) and Plan with AI (pink), as on a city.
    private var actionRow: some View {
        HStack(spacing: Theme.Spacing.m) {
            circle(hasBeen ? "checkmark" : "plus", tint: PlaceState.visited.markerColor, filled: hasBeen,
                   caption: hasBeen ? "Been" : "Log", identifier: "country-log") {
                // Been comes from the cities you've been to, so logging asks which one.
                if hasBeen { confirmingBeen = true } else { pickingCity = true }
            }
            .alert("You've been to \(name)", isPresented: $confirmingBeen) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("It counts as somewhere you've been while you have cities there. Remove them from their pages to take it off.")
            }
            circle(isSaved ? "bookmark.fill" : "bookmark", tint: hasBeen ? Roam.inkFaint : PlaceState.wishlist.markerColor,
                   filled: isSaved && !hasBeen, caption: isSaved ? "Saved" : "Wishlist", identifier: "country-wishlist") {
                if !hasBeen { Task { await setSaved(!isSaved) } }
            }
            circle("sparkles", tint: .pink, filled: false, caption: "Plan", identifier: "country-plan") {
                router.sheet = .researchBrief(destination)
            }
        }
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
        CountryPhoto(code: code, name: name, fallback: fallbackPhoto)
        CityGuideCard(name: name, coordinate: destination.coordinate, showsPhoto: false, within: 3_000_000)
        if let model, model.hasLoaded {
            if let been, !been.cities.isEmpty {
                section(model.ownerIDValue == session.userID ? "Cities you've been to" : "Cities") {
                    ForEach(been.cities.filter(\.isHome) + been.cities.filter { !$0.isHome }) { city in
                        cityCard(city.city, isHome: city.isHome)
                    }
                }
            }
            if !trips.isEmpty {
                section("Your trips") {
                    VStack(spacing: 0) {
                        ForEach(trips) { trip in
                            TripCard(trip: trip, cover: model.tripDetails[trip.id]?.places.first?.experience)
                            if trip.id != trips.last?.id { Divider() }
                        }
                    }
                    .roamCard(padding: Theme.Spacing.m)
                }
            }
            if !wishlistCities.isEmpty || !wishlistPlaces.isEmpty {
                section("Your wishlist") {
                    ForEach(wishlistCities) { city in cityCard(city, isHome: false) }
                    if !wishlistPlaces.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(wishlistPlaces) { item in
                                PlaceRow(item: item) { router.push(.experience(item.id)) }
                                if item.id != wishlistPlaces.last?.id { Divider() }
                            }
                        }
                        .roamCard(padding: Theme.Spacing.m)
                    }
                }
            }
        } else {
            SkeletonList(rows: 3)
        }
        switch suggestions?.phase ?? .loading {
        case .idle, .loading:
            EmptyView()
        case .failed(let message):
            InlineRetryView(message: message) { Task { await suggestions?.load(destination) } }
        case .loaded:
            if !recommended.isEmpty {
                section("Places we think you'd enjoy") {
                    LazyVStack(spacing: Theme.Spacing.l) {
                        ForEach(recommended) { place in
                            DiscoverPlaceCard(experience: place.experience, path: place.coverPath, evidence: place.friendEvidence,
                                              score: (place.friendEvidence != nil ? place.experience.followingScore : nil) ?? place.communityScore) {
                                router.push(.experience(place.id))
                            }
                        }
                    }
                }
            }
        }
    }

    private func cityCard(_ city: Destination, isHome: Bool) -> some View {
        Button { router.push(.city(city)) } label: {
            CityPhotoCard(destination: city, isHome: isHome).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("country-city-\(city.name)")
    }

    /// A section whose title, with a chevron, folds it away and back, as on a city.
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        let isCollapsed = collapsed.contains(title)
        return VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Button {
                withAnimation(.snappy(duration: 0.25)) {
                    if isCollapsed { collapsed.remove(title) } else { collapsed.insert(title) }
                }
            } label: {
                HStack {
                    Text(title).font(.roamTitle()).foregroundStyle(Roam.ink)
                    Spacer(minLength: Theme.Spacing.s)
                    Image(systemName: "chevron.down").font(.headline).foregroundStyle(Roam.inkMuted)
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHint(isCollapsed ? "Shows the list" : "Hides the list")
            if !isCollapsed { content() }
        }
    }

    // MARK: Loading

    private func reload() async {
        if model == nil, let me = session.userID { model = MyPlacesModel(services: services, ownerID: me) }
        if suggestions == nil { suggestions = ForYouModel(plans: services.plans) }
        async let mine: Void = model?.load() ?? ()
        async let saved = services.plans.savedCountries()
        savedCodes = (try? await saved) ?? savedCodes
        await mine
        await suggestions?.load(destination)
    }

    /// A whole country on your wishlist.
    private func setSaved(_ present: Bool) async {
        savedCodes = (try? await services.plans.setCountrySaved(code: code, name: name, present: present)) ?? savedCodes
        library.noteChanged()
    }
}

/// A country's photo from its own Google entry, else Google's photo of a place there.
struct CountryPhoto: View {
    let code: String
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
        .task(id: code) {
            photo = await services.plans.countryPhoto(code: code, name: name)
            looked = true
        }
    }
}
