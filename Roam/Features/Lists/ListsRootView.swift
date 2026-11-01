import MapKit
import Observation
import SwiftUI

extension PlaceMapItem {
    /// Each place appears once, in its most advanced state.
    static func items(been: [ExperienceSummary], planned: [ExperienceSummary], wishlist: [ExperienceSummary]) -> [PlaceMapItem] {
        var items: [UUID: PlaceMapItem] = [:]
        for place in wishlist { items[place.id] = PlaceMapItem(experience: place, state: .wishlist) }
        for place in planned { items[place.id] = PlaceMapItem(experience: place, state: .planned) }
        for place in been { items[place.id] = PlaceMapItem(experience: place, state: .visited) }
        return items.values.sorted { $0.experience.name < $1.experience.name }
    }
}

/// Your places in one country.
struct MyPlacesCountry: Identifiable, Hashable {
    let code: String
    let name: String
    let items: [PlaceMapItem]

    var id: String { code }
    var title: String { CountryTitle.text(name: name, code: code) }
    var coverURL: URL? { items.compactMap(\.experience.photoURL).first }

    func count(_ state: PlaceState) -> Int { items.filter { $0.state == state }.count }

    /// Countries you've been to most first, then planned, then wishlist.
    static func countries(_ items: [PlaceMapItem]) -> [MyPlacesCountry] {
        Dictionary(grouping: items.filter { $0.experience.countryCode != nil }) { $0.experience.countryCode?.uppercased() ?? "" }
            .map { code, items in
                MyPlacesCountry(code: code, name: items.compactMap(\.experience.countryName).first ?? code, items: items)
            }
            .sorted {
                let left = ($0.count(.visited), $0.count(.planned), $0.count(.wishlist)), right = ($1.count(.visited), $1.count(.planned), $1.count(.wishlist))
                return left != right ? left > right : $0.name < $1.name
            }
    }
}

@MainActor
@Observable
final class MyPlacesModel {
    private(set) var pins: [PlaceMapItem] = []
    private(set) var countries: [MyPlacesCountry] = []
    private(set) var hasLoaded = false
    private(set) var error: String?
    private let services: AppServices
    private let ownerID: UUID

    init(services: AppServices, ownerID: UUID) {
        self.services = services
        self.ownerID = ownerID
    }

    func load() async {
        do {
            async let been = services.lists.been(ownerID: ownerID)
            async let wishlist = services.lists.want(ownerID: ownerID)
            async let summaries = services.plans.myTrips()
            let (beenEntries, wishlistEntries, trips) = try await (been, wishlist, summaries)
            var planned: [ExperienceSummary] = []
            for trip in trips {
                let detail = try? await services.plans.trip(id: trip.id)
                planned += detail?.places.filter(\.isPlanned).map(\.experience) ?? []
            }
            pins = PlaceMapItem.items(been: beenEntries.map(\.experience), planned: planned, wishlist: wishlistEntries.map(\.experience))
            countries = MyPlacesCountry.countries(pins)
            hasLoaded = true
            error = nil
        } catch {
            self.error = error.roamMessage
        }
    }
}

/// How far the My Places lists come up over the globe.
enum MyPlacesSheetDetent: CaseIterable {
    case peek
    case half
    case full

    func height(in available: CGFloat) -> CGFloat {
        switch self {
        case .peek: return 112
        case .half: return available * 0.5
        case .full: return available
        }
    }
}

/// My Places tab: the globe, with your countries on a card that comes up over it.
struct MyPlacesRootView: View {
    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(LibraryStore.self) private var library
    @State private var model: MyPlacesModel?
    @State private var showsCoachmark = false
    @State private var detent = MyPlacesSheetDetent.half
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let height = sheetHeight(in: proxy.size.height)
            ZStack(alignment: .bottom) {
                globe
                    .frame(height: max(proxy.size.height - height + proxy.safeAreaInsets.top + 28, 0))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea(edges: .top)
                sheet(height: height, available: proxy.size.height)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("My Places")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
            ToolbarItem(placement: .topBarTrailing) { ProfileAvatarButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button { openWishlist() } label: { Image(systemName: "bookmark") }
                    .accessibilityLabel("Wishlist")
                    .accessibilityIdentifier("open-wishlist")
            }
            LogPlaceToolbarFallback()
        }
        .task {
            if model == nil, let me = session.userID { model = MyPlacesModel(services: services, ownerID: me) }
            await model?.load()
        }
        .onChange(of: library.revision) { _, _ in Task { await model?.load() } }
        .onChange(of: router.path(for: .myPlaces).isEmpty) { _, isRoot in if isRoot { Task { await model?.load() } } }
        .overlay {
            if session.profile?.hasSeenBeenIntro == false {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    BeenIntroCard {
                        Task {
                            await session.markBeenIntroSeen()
                            showsCoachmark = true
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if showsCoachmark { LogCoachmark { showsCoachmark = false } }
        }
        .screenIdentifier("myplaces-root")
    }

    private func openWishlist() {
        if let me = session.userID { router.push(.memberList(me, .want)) }
    }

    /// The Earth, with your countries filled in and your places as dots. Spin and zoom it freely.
    @ViewBuilder private var globe: some View {
        if let model, model.hasLoaded {
            GlobeMapView(pins: model.pins.map { MapPin(id: $0.id.uuidString, name: $0.experience.name, category: nil, latitude: $0.experience.latitude, longitude: $0.experience.longitude) },
                         shadedCountryCodes: Set(PlaceMapItem.countryTints(model.pins).keys),
                         onSelectPin: { pin in if let id = UUID(uuidString: pin.id) { router.push(.experience(id)) } },
                         globeCenter: PlaceMapItem.startingRegion(model.pins.contains { $0.state == .visited } ? model.pins.filter { $0.state == .visited } : model.pins).center,
                         countryTints: PlaceMapItem.countryTints(model.pins),
                         pinTints: Dictionary(uniqueKeysWithValues: model.pins.map { ($0.id.uuidString, UIColor($0.state.markerColor)) }),
                         onSelectCountry: { code in
                             if let country = model.countries.first(where: { $0.code == code }) { router.push(.myCountry(code: code, title: country.title)) }
                         })
                .mapAccessibility("Globe of the places you've been, planned and saved", identifier: "myplaces-map")
        } else {
            Color.black
        }
    }

    private func sheetHeight(in available: CGFloat) -> CGFloat {
        min(max(detent.height(in: available) - dragOffset, MyPlacesSheetDetent.peek.height(in: available)), available)
    }

    private func sheet(height: CGFloat, available: CGFloat) -> some View {
        VStack(spacing: 0) {
            sheetHeader(available: available)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    if let model, model.hasLoaded {
                        countriesSection(model.countries)
                        moreSection
                    } else if let error = model?.error {
                        InlineRetryView(message: error) { Task { await model?.load() } }
                    } else {
                        SkeletonList(rows: 4)
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.s)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .refreshable { await model?.load() }
            .opacity(detent == .peek && dragOffset == 0 ? 0 : 1)
        }
        .frame(height: height, alignment: .top)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous)
                .fill(Roam.paper)
                .shadow(color: .black.opacity(0.25), radius: 12, y: -2)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    /// Drag to size the sheet. Tap to swap between the lists filling the screen and sharing it with the map.
    private func sheetHeader(available: CGFloat) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            Capsule().fill(Roam.rule).frame(width: 36, height: 5).padding(.top, Theme.Spacing.s)
            HStack(alignment: .firstTextBaseline) {
                Text("My Places").font(.roamTitle()).foregroundStyle(Roam.ink).accessibilityAddTraits(.isHeader)
                Spacer()
                Image(systemName: detent == .full ? "chevron.down" : "chevron.up")
                    .font(.footnote.weight(.bold)).foregroundStyle(Roam.inkMuted).accessibilityHidden(true)
            }
            PlaceMapLegend().frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.bottom, Theme.Spacing.s)
        .contentShape(Rectangle())
        .onTapGesture { setDetent(detent == .half ? .full : .half) }
        .gesture(
            DragGesture(minimumDistance: 4)
                .updating($dragOffset) { value, offset, _ in offset = value.translation.height }
                .onEnded { value in
                    let target = detent.height(in: available) - value.predictedEndTranslation.height
                    setDetent(MyPlacesSheetDetent.allCases.min { abs($0.height(in: available) - target) < abs($1.height(in: available) - target) } ?? .half)
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("My Places")
        .accessibilityHint(detent == .full ? "Shows the map" : "Minimizes the map")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { setDetent(detent == .half ? .full : .half) }
        .accessibilityIdentifier("myplaces-sheet-header")
    }

    private func setDetent(_ next: MyPlacesSheetDetent) {
        if UIAccessibility.isReduceMotionEnabled {
            detent = next
        } else {
            withAnimation(.spring(duration: 0.35)) { detent = next }
        }
    }

    private func countriesSection(_ countries: [MyPlacesCountry]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Countries").font(.roamTitle()).accessibilityAddTraits(.isHeader)
            if countries.isEmpty {
                Text("Places you log or save appear here by country.").font(.subheadline).foregroundStyle(Roam.inkMuted)
                    .accessibilityIdentifier("countries-empty")
            } else {
                VStack(spacing: 0) {
                    ForEach(countries) { country in
                        Button { router.push(.myCountry(code: country.code, title: country.title)) } label: { countryRow(country) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("country-\(country.code)")
                        if country.id != countries.last?.id { Divider() }
                    }
                }
                .roamCard(padding: Theme.Spacing.m)
            }
        }
    }

    private func countryRow(_ country: MyPlacesCountry) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Roam.fill
                .frame(width: 52, height: 52)
                .overlay {
                    if let url = country.coverURL {
                        AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Roam.fill }
                    } else {
                        Image(systemName: "globe").foregroundStyle(Roam.inkMuted)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(country.title).font(.headline).foregroundStyle(Roam.ink)
                HStack(spacing: Theme.Spacing.s) {
                    ForEach([PlaceState.visited, .planned, .wishlist].filter { country.count($0) > 0 }, id: \.self) { state in
                        HStack(spacing: 3) {
                            Image(systemName: state.markerSymbol).font(.caption2.weight(.bold)).foregroundStyle(state.markerColor)
                            Text("\(country.count(state))").font(.footnote).foregroundStyle(Roam.inkMuted).monospacedDigit()
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(country.count(state)) \(state.markerTitle)")
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Roam.inkMuted).accessibilityHidden(true)
        }
        .padding(.vertical, Theme.Spacing.s)
        .contentShape(Rectangle())
    }

    private var moreSection: some View {
        VStack(spacing: 0) {
            Button { if let me = session.userID { router.push(.memberList(me, .been)) } } label: { linkRow("All places you've been", symbol: "mappin.and.ellipse") }
                .buttonStyle(.plain)
                .accessibilityIdentifier("open-been")
            Divider()
            Button { router.push(.lists) } label: { linkRow("Custom lists", symbol: "list.bullet") }
                .buttonStyle(.plain)
                .accessibilityIdentifier("open-lists")
        }
        .roamCard(padding: Theme.Spacing.m)
    }

    private func linkRow(_ title: String, symbol: String) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: symbol).frame(width: 24).accessibilityHidden(true)
            Text(title)
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Roam.inkMuted).accessibilityHidden(true)
        }
        .foregroundStyle(Roam.ink)
        .frame(minHeight: Theme.minimumHitTarget)
        .contentShape(Rectangle())
    }
}

/// Your places in one country: a map, then the places you've been, planned and saved.
struct MyCountryView: View {
    let code: String
    let title: String

    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @State private var model: MyPlacesModel?

    private var items: [PlaceMapItem] { model?.countries.first { $0.code == code }?.items ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                if let model, model.hasLoaded {
                    if items.isEmpty {
                        Text("No places here yet.").font(.subheadline).foregroundStyle(Roam.inkMuted)
                    } else {
                        PlaceMapView(items: items) { router.push(.experience($0)) }
                            .id(items.map(\.id))
                            .frame(height: 240)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                    }
                    ForEach([PlaceState.visited, .planned, .wishlist], id: \.self) { state in
                        let places = items.filter { $0.state == state }
                        if !places.isEmpty { section(state, places) }
                    }
                } else if let error = model?.error {
                    InlineRetryView(message: error) { Task { await model?.load() } }
                } else {
                    SkeletonList(rows: 4)
                }
            }
            .padding(Theme.Spacing.l)
        }
        .background(Roam.paper)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil, let me = session.userID { model = MyPlacesModel(services: services, ownerID: me) }
            await model?.load()
        }
        .refreshable { await model?.load() }
        .screenIdentifier("my-country")
    }

    private func section(_ state: PlaceState, _ places: [PlaceMapItem]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(state.markerTitle).font(.roamTitle()).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(places) { item in
                    Button { router.push(.experience(item.id)) } label: {
                        HStack(spacing: Theme.Spacing.m) {
                            StatusMark(state: item.state)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.experience.name).font(.headline).foregroundStyle(Roam.ink).multilineTextAlignment(.leading)
                                if let line = [item.experience.category?.title, item.experience.locality].compactMap({ $0 }).joined(separator: " · ").nilIfEmpty {
                                    Text(line).font(.footnote).foregroundStyle(Roam.inkMuted)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Roam.inkMuted).accessibilityHidden(true)
                        }
                        .padding(.vertical, Theme.Spacing.s)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("country-place-\(item.experience.name)")
                    if item.id != places.last?.id { Divider() }
                }
            }
            .roamCard(padding: Theme.Spacing.m)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
