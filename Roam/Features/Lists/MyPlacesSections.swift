import MapKit
import SwiftUI

// MARK: - Grouping

/// Which of your cities a place is in. Home cities match by country and city name, so a place still
/// counts as home when its region is spelled differently.
enum CityMatch {
    static func same(_ place: ExperienceSummary, _ city: Destination) -> Bool {
        guard let locality = place.locality, let code = place.countryCode, let cityCode = city.countryCode else { return false }
        return code.uppercased() == cityCode.uppercased() && GeographyKey.normalize(locality) == GeographyKey.normalize(city.name)
    }

    /// How far from a home city still counts as home, so nearby towns go with it.
    static let homeRadius: CLLocationDistance = 100_000

    /// The nearest home city within reach of a place, or the one it's named for.
    static func home(for place: ExperienceSummary, homes: [Destination]) -> Destination? {
        if let named = homes.first(where: { same(place, $0) }) { return named }
        let spot = CLLocation(latitude: place.latitude, longitude: place.longitude)
        return homes
            .filter { !($0.latitude == 0 && $0.longitude == 0) }
            .map { ($0, CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: spot)) }
            .filter { $0.1 <= homeRadius }
            .min { $0.1 < $1.1 }?.0
    }

    static func isHome(_ place: ExperienceSummary, homes: [Destination]) -> Bool {
        home(for: place, homes: homes) != nil
    }

    static func inHome(_ place: ExperienceSummary, _ city: Destination, homes: [Destination]) -> Bool {
        home(for: place, homes: homes)?.id == city.id
    }
}

/// Places split by country, then by city.
struct PlaceGroups {
    struct City: Identifiable {
        var name: String
        var items: [PlaceMapItem]
        var id: String { name }
    }

    struct Country: Identifiable {
        var code: String
        var title: String
        var cities: [City]
        var id: String { code }
    }

    let countries: [Country]

    init(_ items: [PlaceMapItem], extraCities: [Destination] = []) {
        var byCountry: [String: [PlaceMapItem]] = [:]
        for item in items { byCountry[item.experience.countryCode?.uppercased() ?? "", default: []].append(item) }
        for city in extraCities where byCountry[city.countryCode?.uppercased() ?? ""] == nil { byCountry[city.countryCode?.uppercased() ?? ""] = [] }
        countries = byCountry.map { code, items in
            var byCity = Dictionary(grouping: items) { $0.experience.locality ?? "Other places" }
            for city in extraCities where (city.countryCode?.uppercased() ?? "") == code && byCity[city.name] == nil { byCity[city.name] = [] }
            let name = items.compactMap(\.experience.countryName).first ?? extraCities.first { $0.countryCode?.uppercased() == code }?.countryName
            return Country(code: code, title: CountryTitle.text(name: name, code: code.isEmpty ? nil : code),
                           cities: byCity.map { City(name: $0.key, items: PlaceGroups.ordered($0.value)) }
                               .sorted { $0.items.count != $1.items.count ? $0.items.count > $1.items.count : $0.name < $1.name })
        }
        .sorted { $0.cities.count != $1.cities.count ? $0.cities.count > $1.cities.count : $0.title < $1.title }
    }

    /// Been there first, then planned, then wishlist, each by name.
    static func ordered(_ items: [PlaceMapItem]) -> [PlaceMapItem] {
        func rank(_ state: PlaceState) -> Int { state == .visited ? 0 : state == .planned ? 1 : 2 }
        return items.sorted { rank($0.state) != rank($1.state) ? rank($0.state) < rank($1.state) : $0.experience.name < $1.experience.name }
    }
}

/// Places broken down by country, then city; just by city when they're all in one country.
struct PlaceBreakdown: View {
    let items: [PlaceMapItem]
    var extraCities: [Destination] = []
    var scores: [UUID: Score] = [:]
    var onRemove: ((UUID) -> Void)?

    @Environment(AppRouter.self) private var router

    var body: some View {
        let groups = PlaceGroups(items, extraCities: extraCities)
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            ForEach(groups.countries) { country in
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    if groups.countries.count > 1 {
                        Text(country.title).font(.roamTitle()).accessibilityAddTraits(.isHeader)
                    }
                    ForEach(country.cities) { city in cityBlock(city) }
                }
            }
        }
    }

    private func cityBlock(_ city: PlaceGroups.City) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(city.name).font(.headline).foregroundStyle(Roam.ink).accessibilityAddTraits(.isHeader)
                Spacer()
                if city.items.isEmpty { Text("No places yet").font(.footnote).foregroundStyle(Roam.inkMuted) }
            }
            if !city.items.isEmpty {
                VStack(spacing: 0) {
                    ForEach(city.items) { item in
                        PlaceRow(item: item, score: scores[item.id]) { router.push(.experience(item.id)) }
                            .contextMenu {
                                if let onRemove, item.state == .planned {
                                    Button("Remove from trip", role: .destructive) { onRemove(item.id) }
                                }
                            }
                        if item.id != city.items.last?.id { Divider() }
                    }
                }
                .roamCard(padding: Theme.Spacing.m)
            }
        }
    }
}

struct PlaceRow: View {
    let item: PlaceMapItem
    var score: Score?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.m) {
                ZStack(alignment: .bottomTrailing) {
                    PlaceThumbnail(id: item.id.uuidString, url: item.experience.photoURL, coordinate: item.experience.coordinate,
                                   symbol: item.experience.category?.symbolName ?? "mappin", size: 48)
                    StatusMark(state: item.state).scaleEffect(0.75).offset(x: 6, y: 6)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.experience.name).font(.headline).foregroundStyle(Roam.ink).multilineTextAlignment(.leading)
                    Text(item.experience.category?.title ?? item.state.markerTitle).font(.footnote).foregroundStyle(Roam.inkMuted)
                }
                Spacer(minLength: 0)
                if let score {
                    Text(score.formatted).font(.system(.headline, design: .rounded)).monospacedDigit().foregroundStyle(Roam.ink)
                }
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Roam.inkMuted).accessibilityHidden(true)
            }
            .padding(.vertical, Theme.Spacing.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("place-row-\(item.experience.name)")
    }
}

// MARK: - Timeline

/// One stop on your travel timeline: a trip, or visits away from home that weren't logged to a trip,
/// grouped by country and time.
struct TimelineEntry: Identifiable, Hashable {
    enum Kind: Hashable {
        case trip(UUID)
        case journey
    }

    var id: String
    var kind: Kind
    var title: String
    var placeLine: String
    var start: LocalDate?
    var end: LocalDate?
    var places: [ExperienceSummary]
    var bestScore: Score?
}

enum MyTimeline {
    /// Visits further apart than this start a new journey.
    static let journeyGapDays = 21

    static func today() -> LocalDate { LocalDate(date: Date(), timeZone: .current) }

    /// Past trips and journeys, newest first. Home-city visits are left out.
    static func past(been: [ListEntry], trips: [TripSummary], details: [UUID: TripDetail], homes: [Destination], today: LocalDate) -> [TimelineEntry] {
        let visitDates = Dictionary(been.map { ($0.id, $0.latestVisitDate) }, uniquingKeysWith: { first, _ in first })
        let scores = Dictionary(been.compactMap { entry in entry.ownerScore.map { (entry.id, $0) } }, uniquingKeysWith: { first, _ in first })
        var onTrips = Set<UUID>()
        var entries: [TimelineEntry] = []
        for trip in trips {
            let visited = details[trip.id]?.places.filter(\.isVisited).map(\.experience) ?? []
            onTrips.formUnion(visited.map(\.id))
            guard trip.phase(today: today) == .past else { continue }
            let dates = visited.compactMap { visitDates[$0.id] ?? nil }
            entries.append(TimelineEntry(id: trip.id.uuidString, kind: .trip(trip.id), title: trip.name, placeLine: trip.placeLine,
                                         start: trip.startDate ?? dates.min(), end: trip.endDate ?? dates.max(), places: visited,
                                         bestScore: visited.compactMap { scores[$0.id] }.max()))
        }
        let loose = been.filter { !onTrips.contains($0.id) && !CityMatch.isHome($0.experience, homes: homes) }
        for (code, group) in Dictionary(grouping: loose, by: { $0.experience.countryCode?.uppercased() ?? "" }) {
            let dated = group.filter { $0.latestVisitDate != nil }.sorted { $0.latestVisitDate! < $1.latestVisitDate! }
            var runs: [[ListEntry]] = []
            for entry in dated {
                if let last = runs.last?.last?.latestVisitDate, days(from: last, to: entry.latestVisitDate!) <= journeyGapDays {
                    runs[runs.count - 1].append(entry)
                } else {
                    runs.append([entry])
                }
            }
            let undated = group.filter { $0.latestVisitDate == nil }
            if !undated.isEmpty { runs.append(undated) }
            for run in runs {
                let places = run.map(\.experience)
                let start = run.compactMap(\.latestVisitDate).min()
                entries.append(TimelineEntry(id: "\(code)-\(start?.isoString ?? "undated")", kind: .journey,
                                             title: CountryTitle.text(name: places.compactMap(\.countryName).first, code: code.isEmpty ? nil : code),
                                             placeLine: places.compactMap(\.locality).uniqued().prefix(4).joined(separator: ", "),
                                             start: start, end: run.compactMap(\.latestVisitDate).max(), places: places,
                                             bestScore: run.compactMap(\.ownerScore).max()))
            }
        }
        return entries.sorted {
            switch ($0.end ?? $0.start, $1.end ?? $1.start) {
            case let (left?, right?): return left > right
            case (nil, nil): return $0.title < $1.title
            case (nil, _): return false
            case (_, nil): return true
            }
        }
    }

    static func days(from: LocalDate, to: LocalDate) -> Int {
        Calendar(identifier: .gregorian).dateComponents([.day], from: from.date(), to: to.date()).day ?? 0
    }

    /// "Jun 3 – 12, 2026", "Jun 28 – Jul 4, 2026" or "Jun 3, 2026".
    static func range(_ start: LocalDate?, _ end: LocalDate?) -> String? {
        guard let first = start ?? end else { return nil }
        let last = end ?? first
        let short = Date.FormatStyle.dateTime.month(.abbreviated).day()
        if first == last { return first.date().formatted(short.year()) }
        if first.year == last.year {
            let tail = first.month == last.month ? "\(last.day), \(last.year)" : last.date().formatted(short.year())
            return "\(first.date().formatted(short)) – \(tail)"
        }
        return "\(first.date().formatted(short.year())) – \(last.date().formatted(short.year()))"
    }
}

/// A trip that's happening now, coming up, or still being planned.
struct TripCard: View {
    let trip: TripSummary
    var cover: ExperienceSummary?

    @Environment(AppRouter.self) private var router

    var body: some View {
        let today = MyTimeline.today()
        Button { router.push(.trip(trip.id)) } label: {
            HStack(spacing: Theme.Spacing.m) {
                Group {
                    if let city = trip.coverCity {
                        WikipediaPhoto(name: city.name, region: city.region, country: city.countryName, coordinate: city.coordinate,
                                       fallbackURL: cover?.photoURL, symbol: "airplane", height: 56)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else if let cover {
                        PlaceThumbnail(id: cover.id.uuidString, url: cover.photoURL, coordinate: cover.coordinate, symbol: "airplane", size: 56)
                    } else {
                        Roam.fill.frame(width: 56, height: 56)
                            .overlay { Image(systemName: "airplane").foregroundStyle(PlaceState.planned.markerColor) }
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(trip.name).font(.headline).foregroundStyle(Roam.ink).multilineTextAlignment(.leading)
                    if !trip.placeLine.isEmpty && trip.placeLine != trip.name { Text(trip.placeLine).font(.subheadline).foregroundStyle(Roam.ink).lineLimit(1) }
                    Text(detailLine(today: today)).font(.footnote).foregroundStyle(Roam.inkMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Roam.inkMuted).accessibilityHidden(true)
            }
            .padding(.vertical, Theme.Spacing.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("trip-card-\(trip.name)")
    }

    private func detailLine(today: LocalDate) -> String {
        var parts: [String] = []
        if let dates = MyTimeline.range(trip.startDate, trip.endDate) { parts.append(dates) } else { parts.append("No dates yet") }
        if let start = trip.startDate, start > today {
            let days = MyTimeline.days(from: today, to: start)
            parts.append(days == 1 ? "tomorrow" : "in \(days) days")
        }
        parts.append("\(trip.plannedCount) planned")
        return parts.joined(separator: " · ")
    }
}

/// Your trips: now, coming up, being planned, then everything you've done, newest first.
struct TripsTimelineSection: View {
    enum Part {
        /// Trips happening now, coming up or being planned.
        case ahead
        /// Everything you've done, newest first.
        case past
    }

    let model: MyPlacesModel
    var part: Part
    var onNewTrip: () -> Void = {}

    @Environment(AppRouter.self) private var router

    var body: some View {
        let today = MyTimeline.today()
        let now = model.trips.filter { $0.phase(today: today) == .now }
        let upcoming = model.trips.filter { $0.phase(today: today) == .upcoming }.sorted { ($0.startDate ?? $0.endDate!) < ($1.startDate ?? $1.endDate!) }
        let planning = model.trips.filter { $0.phase(today: today) == .planning }
        let past = model.timeline
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            if part == .ahead {
                if !now.isEmpty { tripGroup("On the go", now) }
                // Dated trips first, soonest first; trips without dates yet after them.
                if !(upcoming + planning).isEmpty { tripGroup("Coming up", upcoming + planning) }
                Button(action: onNewTrip) { PillLabel(title: "New trip", systemImage: "plus") }
                    .buttonStyle(PillButtonStyle(tint: PlaceState.planned.markerColor))
                    .accessibilityIdentifier("new-trip")
            } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("Past").font(.roamTitle()).accessibilityAddTraits(.isHeader)
                if past.isEmpty {
                    Text("Places you log away from home show up here, grouped into trips.").font(.subheadline).foregroundStyle(Roam.inkMuted)
                } else {
                    VStack(spacing: 0) {
                        ForEach(past) { entry in timelineRow(entry, isLast: entry.id == past.last?.id) }
                    }
                }
            }
            }
        }
    }

    private func tripGroup(_ title: String, _ trips: [TripSummary]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(title).font(.roamTitle()).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(trips) { trip in
                    TripCard(trip: trip, cover: model.tripDetails[trip.id]?.places.first?.experience)
                    if trip.id != trips.last?.id { Divider() }
                }
            }
            .roamCard(padding: Theme.Spacing.m)
        }
    }

    private func timelineRow(_ entry: TimelineEntry, isLast: Bool) -> some View {
        Button { open(entry) } label: {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                VStack(spacing: 0) {
                    Circle().fill(PlaceState.visited.markerColor).frame(width: 12, height: 12).padding(.top, 5)
                    if !isLast { Rectangle().fill(Roam.rule).frame(width: 2).frame(maxHeight: .infinity) }
                }
                .frame(width: 12)
                VStack(alignment: .leading, spacing: 3) {
                    Text(MyTimeline.range(entry.start, entry.end) ?? "Date unknown").font(.caption.weight(.semibold)).foregroundStyle(Roam.inkMuted)
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(entry.title).font(.headline).foregroundStyle(Roam.ink).multilineTextAlignment(.leading)
                        if case .trip = entry.kind { Image(systemName: "airplane").font(.caption).foregroundStyle(PlaceState.planned.markerColor) }
                    }
                    if !entry.placeLine.isEmpty { Text(entry.placeLine).font(.subheadline).foregroundStyle(Roam.ink).lineLimit(2) }
                    HStack(spacing: Theme.Spacing.s) {
                        if let best = entry.bestScore { Text("Best \(best.formatted)") }
                    }
                    .font(.footnote).foregroundStyle(Roam.inkMuted)
                }
                Spacer(minLength: 0)
                if let cover = entry.places.first {
                    PlaceThumbnail(id: cover.id.uuidString, url: cover.photoURL, coordinate: cover.coordinate,
                                   symbol: cover.category?.symbolName ?? "mappin", size: 56)
                        .padding(.vertical, Theme.Spacing.xs)
                }
            }
            .padding(.bottom, isLast ? 0 : Theme.Spacing.l)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("timeline-\(entry.title)")
    }

    private func open(_ entry: TimelineEntry) {
        switch entry.kind {
        case .trip(let id): router.push(.trip(id))
        case .journey: router.push(.placeGroup(title: entry.title, subtitle: MyTimeline.range(entry.start, entry.end), ids: entry.places.map(\.id)))
        }
    }
}

// MARK: - Home

/// Your home cities: your local spots, kept off the travel timeline.
struct HomeCitiesSection: View {
    let model: MyPlacesModel
    var onAddHome: () -> Void

    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Home").font(.roamTitle()).accessibilityAddTraits(.isHeader)
            Text("Places in the cities you live in. They stay off your travel timeline.").font(.subheadline).foregroundStyle(Roam.inkMuted)
            if !model.homeCities.isEmpty {
                VStack(spacing: 0) {
                    ForEach(model.homeCities) { city in
                        row(city)
                        if city.id != model.homeCities.last?.id { Divider() }
                    }
                }
                .roamCard(padding: Theme.Spacing.m)
            }
            Button(action: onAddHome) { PillLabel(title: "Add a home city", systemImage: "house") }
                .buttonStyle(PillButtonStyle(tint: PlaceState.visited.markerColor))
                .accessibilityIdentifier("add-home-city")
        }
    }

    private func row(_ city: Destination) -> some View {
        let been = model.pins.filter { $0.state == .visited && CityMatch.inHome($0.experience, city, homes: model.homeCities) }
        let top = been.max { (model.scores[$0.id]?.tenths ?? 0) < (model.scores[$1.id]?.tenths ?? 0) }
        return Button { router.push(.homeCity(city)) } label: {
            HStack(spacing: Theme.Spacing.m) {
                if let cover = top?.experience {
                    PlaceThumbnail(id: cover.id.uuidString, url: cover.photoURL, coordinate: cover.coordinate, symbol: "house", size: 56)
                } else {
                    Roam.fill.frame(width: 56, height: 56).overlay { Image(systemName: "house").foregroundStyle(Roam.inkMuted) }
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(city.name).font(.headline).foregroundStyle(Roam.ink)
                    Text(been.isEmpty ? "No places yet" : "Your spots")
                        .font(.footnote).foregroundStyle(Roam.inkMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Roam.inkMuted).accessibilityHidden(true)
            }
            .padding(.vertical, Theme.Spacing.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Remove home city", role: .destructive) { Task { await model.setHome(city, present: false) } }
        }
        .accessibilityIdentifier("home-city-\(city.name)")
    }
}

/// Your spots in a home city, best first, then the ones you want to try.
struct HomeCityView: View {
    let city: Destination

    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @State private var model: MyPlacesModel?

    private var been: [PlaceMapItem] {
        guard let model else { return [] }
        return model.pins.filter { $0.state == .visited && CityMatch.inHome($0.experience, city, homes: model.homeCities) }
            .sorted { (model.scores[$0.id]?.tenths ?? -1) > (model.scores[$1.id]?.tenths ?? -1) }
    }
    private var wanted: [PlaceMapItem] {
        guard let model else { return [] }
        return model.pins.filter { $0.state != .visited && CityMatch.inHome($0.experience, city, homes: model.homeCities) }
    }

    var body: some View {
        PlacesMapScreen(title: city.name, items: been + wanted, onRefresh: { await model?.load() }) {
            if let model, model.hasLoaded {
                list("Your spots", been, empty: "Log a place here and it shows up in your home spots.", scores: model.scores)
                if !wanted.isEmpty { list("Want to try", wanted, empty: "", scores: [:]) }
            } else {
                SkeletonList(rows: 4)
            }
        }
        .task {
            if model == nil, let me = session.userID { model = MyPlacesModel(services: services, ownerID: me) }
            await model?.load()
        }
        .screenIdentifier("home-city")
    }

    private func list(_ title: String, _ items: [PlaceMapItem], empty: String, scores: [UUID: Score]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(title).font(.roamTitle()).accessibilityAddTraits(.isHeader)
            if items.isEmpty {
                Text(empty).font(.subheadline).foregroundStyle(Roam.inkMuted)
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        PlaceRow(item: item, score: scores[item.id]) { router.push(.experience(item.id)) }
                        if item.id != items.last?.id { Divider() }
                    }
                }
                .roamCard(padding: Theme.Spacing.m)
            }
        }
    }
}

// MARK: - Saved

/// Your wishlist by country, and your own lists.
struct SavedSection: View {
    let model: MyPlacesModel

    @Environment(AppRouter.self) private var router
    @State private var creatingList = false
    @State private var newTitle = ""

    var body: some View {
        let countries = PlaceGroups(model.travelWishlist).countries
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("Wishlist").font(.roamTitle()).accessibilityAddTraits(.isHeader)
                if countries.isEmpty {
                    Text("Save places you want to go. When you're ready, plan a trip from them.").font(.subheadline).foregroundStyle(Roam.inkMuted)
                } else {
                    VStack(spacing: 0) {
                        ForEach(countries) { country in
                            Button { router.push(.wishlistCountry(code: country.code, title: country.title)) } label: { countryRow(country) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("wishlist-country-\(country.code)")
                            if country.id != countries.last?.id { Divider() }
                        }
                    }
                    .roamCard(padding: Theme.Spacing.m)
                }
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack {
                    Text("Lists").font(.roamTitle()).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button { newTitle = ""; creatingList = true } label: { Label("New list", systemImage: "plus") }
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("saved-new-list")
                }
                if model.lists.isEmpty {
                    Text("Make your own lists, like date-night spots or ramen to try.").font(.subheadline).foregroundStyle(Roam.inkMuted)
                } else {
                    VStack(spacing: 0) {
                        ForEach(model.lists) { list in
                            Button { router.push(.list(list.id)) } label: {
                                HStack {
                                    Image(systemName: "list.bullet").frame(width: 24).foregroundStyle(Roam.inkMuted).accessibilityHidden(true)
                                    Text(list.title).font(.headline).foregroundStyle(Roam.ink)
                                    Spacer()
                                    Text("\(list.itemCount)").font(.footnote).foregroundStyle(Roam.inkMuted).monospacedDigit()
                                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Roam.inkMuted).accessibilityHidden(true)
                                }
                                .frame(minHeight: Theme.minimumHitTarget)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if list.id != model.lists.last?.id { Divider() }
                        }
                    }
                    .roamCard(padding: Theme.Spacing.m)
                }
            }
        }
        .alert("New list", isPresented: $creatingList) {
            TextField("Title", text: $newTitle).accessibilityIdentifier("saved-list-title")
            Button("Create") {
                Task { if let list = await model.createList(title: newTitle) { router.push(.list(list.id)) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Like date-night spots or ramen to try.")
        }
    }

    private func countryRow(_ country: PlaceGroups.Country) -> some View {
        let count = country.cities.map(\.items.count).reduce(0, +)
        let cover = country.cities.first?.items.first?.experience
        return HStack(spacing: Theme.Spacing.m) {
            if let cover {
                PlaceThumbnail(id: cover.id.uuidString, url: cover.photoURL, coordinate: cover.coordinate, symbol: "bookmark", size: 52)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(country.title).font(.headline).foregroundStyle(Roam.ink)
                Text(country.cities.map(\.name).prefix(3).joined(separator: ", ")).font(.footnote).foregroundStyle(Roam.inkMuted).lineLimit(1)
            }
            Spacer(minLength: 0)
            Text("\(count)").font(.subheadline).foregroundStyle(Roam.inkMuted).monospacedDigit()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Roam.inkMuted).accessibilityHidden(true)
        }
        .padding(.vertical, Theme.Spacing.s)
        .contentShape(Rectangle())
    }
}

/// Your wishlist in one country, by city, with the trips you've planned there and a way to plan a new one.
struct WishlistCountryView: View {
    let code: String
    let title: String

    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @State private var model: MyPlacesModel?
    @State private var planning = false

    private var wishlist: [PlaceMapItem] { model?.travelWishlist.filter { $0.experience.countryCode?.uppercased() == code } ?? [] }
    private var trips: [TripSummary] {
        model?.trips.filter { trip in
            trip.phase(today: MyTimeline.today()) != .past && trip.cities.contains { $0.countryCode?.uppercased() == code }
        } ?? []
    }

    var body: some View {
        PlacesMapScreen(title: title, items: wishlist, onRefresh: { await model?.load() }) {
            if let model, model.hasLoaded {
                if !wishlist.isEmpty {
                    Button { planning = true } label: {
                        Label("Plan a trip", systemImage: "airplane").font(.headline).frame(maxWidth: .infinity).frame(minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PlaceState.planned.markerColor)
                    .accessibilityIdentifier("plan-trip")
                }
                if !trips.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("Your trips here").font(.roamTitle()).accessibilityAddTraits(.isHeader)
                        VStack(spacing: 0) {
                            ForEach(trips) { trip in
                                TripCard(trip: trip, cover: model.tripDetails[trip.id]?.places.first?.experience)
                                if trip.id != trips.last?.id { Divider() }
                            }
                        }
                        .roamCard(padding: Theme.Spacing.m)
                    }
                }
                if wishlist.isEmpty {
                    Text("Nothing left on your wishlist here.").font(.subheadline).foregroundStyle(Roam.inkMuted)
                } else {
                    PlaceBreakdown(items: wishlist)
                }
            } else {
                SkeletonList(rows: 4)
            }
        }
        .sheet(isPresented: $planning) {
            PlanTripSheet(candidates: wishlist.map(\.experience), suggestedName: wishlist.first?.experience.countryName ?? title, trip: nil) {
                Task { await model?.load() }
            }
            .presentationBackground(Roam.paper)
        }
        .task {
            if model == nil, let me = session.userID { model = MyPlacesModel(services: services, ownerID: me) }
            await model?.load()
        }
        .screenIdentifier("wishlist-country")
    }
}

struct PlanTripSheet: View {
    let candidates: [ExperienceSummary]
    let suggestedName: String
    let trip: TripSummary?
    var onDone: () -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var start: Date?
    @State private var end: Date?
    @State private var selected: Set<UUID> = []
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form { Group {
                if trip == nil {
                    Section {
                        TextField("Trip name", text: $name).accessibilityIdentifier("plan-trip-name")
                        TripDatesRow(start: $start, end: $end)
                    }
                }
                ForEach(PlaceGroups(candidates.map { PlaceMapItem(experience: $0, state: .wishlist) }).countries) { country in
                    ForEach(country.cities) { city in
                        Section(city.name) {
                            ForEach(city.items) { item in
                                Button { toggle(item.id) } label: {
                                    HStack {
                                        Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selected.contains(item.id) ? Roam.ink : Roam.inkMuted)
                                        Text(item.experience.name).foregroundStyle(Roam.ink)
                                        Spacer()
                                        Text(item.experience.category?.title ?? "").font(.footnote).foregroundStyle(Roam.inkMuted)
                                    }
                                }
                                .accessibilityIdentifier("plan-pick-\(item.experience.name)")
                            }
                        }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(Roam.signal) } }
            }
            .listRowBackground(Roam.paperRaised)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle(trip == nil ? "Plan a trip" : "Add from wishlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(trip == nil ? "Create" : "Add") { Task { await save() } }
                        .disabled(saving || (trip == nil && name.trimmingCharacters(in: .whitespaces).isEmpty) || (trip != nil && selected.isEmpty))
                        .accessibilityIdentifier("plan-trip-save")
                }
            }
            .onAppear { if name.isEmpty { name = suggestedName } }
        }
        .roamSheetStyle()
        .presentationDetents([.large])
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            let target: TripSummary
            if let trip {
                target = trip
            } else {
                let today = MyTimeline.today()
                let startDate = start.map { LocalDate(date: $0, timeZone: .current) }
                let endDate = end.map { LocalDate(date: $0, timeZone: .current) }
                target = try await services.plans.saveTrip(TripDraft(name: name, startDate: startDate, endDate: endDate,
                                                                    status: TripSummary.status(start: startDate, end: endDate, today: today)))
            }
            for id in selected {
                try await services.plans.setTripPlace(tripID: target.id, experienceID: id, stop: "", present: true)
            }
            onDone()
            dismiss()
        } catch { self.error = error.roamMessage }
    }
}

// MARK: - Passport

/// Every country and city someone has been to. Friends see the whole passport, but open only the places
/// shared with them.
struct PassportSection: View {
    let ownerID: UUID
    let countries: [PassportCountry]
    var isSelf: Bool
    var onMarkCity: (() -> Void)?

    @Environment(AppRouter.self) private var router

    var body: some View {
        let cityCount = countries.map(\.cities.count).reduce(0, +)
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.l) {
                stat(countries.count, countries.count == 1 ? "country" : "countries")
                stat(cityCount, cityCount == 1 ? "city" : "cities")
                Spacer()
            }
            if countries.isEmpty {
                Text(isSelf ? "Log a place or mark a city you've been to and it gets stamped here." : "No stamps yet.")
                    .font(.subheadline).foregroundStyle(Roam.inkMuted)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.s), GridItem(.flexible(), spacing: Theme.Spacing.s)], spacing: Theme.Spacing.s) {
                    ForEach(countries) { country in
                        Button { router.push(PassportCountry.route(ownerID: ownerID, country: country)) } label: { stamp(country) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("passport-\(country.code)")
                    }
                }
            }
            if let onMarkCity {
                Button(action: onMarkCity) { PillLabel(title: "Add a city you've been to", systemImage: "plus") }
                    .buttonStyle(PillButtonStyle(tint: PlaceState.visited.markerColor))
                    .accessibilityIdentifier("mark-city")
            }
        }
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(value)").font(.roamTitle()).monospacedDigit()
            Text(label).font(.subheadline).foregroundStyle(Roam.inkMuted)
        }
        .accessibilityElement(children: .combine)
    }

    private func stamp(_ country: PassportCountry) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(TripTitle.flag(country.code) ?? "🌐").font(.system(size: 30))
            Text(country.name).font(.headline).foregroundStyle(Roam.ink).lineLimit(1)
            Text("\(country.cities.count) \(country.cities.count == 1 ? "city" : "cities")").font(.footnote).foregroundStyle(Roam.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.m)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).fill(Theme.raisedCard))
        .shadow(color: .black.opacity(0.07), radius: 10, y: 2)
        .accessibilityElement(children: .combine)
    }
}

/// Someone's passport on its own screen, opened from their profile.
struct PassportView: View {
    let ownerID: UUID
    let name: String

    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @State private var countries: LoadPhase<[PassportCountry]> = .idle
    @State private var marking = false

    private var isSelf: Bool { session.userID == ownerID }

    var body: some View {
        ScrollView {
            Group {
                switch countries {
                case .idle, .loading: SkeletonList(rows: 4)
                case .failed(let message): InlineRetryView(message: message) { Task { await load() } }
                case .loaded(let value):
                    PassportSection(ownerID: ownerID, countries: value, isSelf: isSelf, onMarkCity: isSelf ? { marking = true } : nil)
                }
            }
            .padding(Theme.Spacing.l)
        }
        .background(Roam.paper)
        .navigationTitle(isSelf ? "Your passport" : "\(name)'s passport")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $marking) {
            DestinationPickerSheet(purpose: .homeCity, title: "City you've been to") { city in
                Task { try? await services.plans.setCityVisited(city, present: true); await load() }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .screenIdentifier("passport")
    }

    private func load() async {
        do { countries = .loaded(try await services.plans.passport(ownerID: ownerID)) }
        catch { if countries.value == nil { countries = .failed(error.roamMessage) } }
    }
}

extension PassportCountry {
    /// A country with just one city you can open goes straight to that city.
    static func route(ownerID: UUID, country: PassportCountry) -> AppRoute {
        if country.cities.count == 1, country.otherPlaceCount == 0, let city = country.cities.first, city.visibleCount > 0 {
            return .passportCity(ownerID: ownerID, city: city)
        }
        return .passportCountry(ownerID: ownerID, country: country)
    }
}

/// The cities in one country of someone's passport.
struct PassportCountryView: View {
    let ownerID: UUID
    let country: PassportCountry

    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @State private var expanded: Set<String> = []
    @State private var entries: [ListEntry] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                // Your homes in one card, the places you travelled to in another.
                let homes = country.cities.filter(\.isHome)
                let away = country.cities.filter { !$0.isHome }
                if !homes.isEmpty { card(homes) }
                if !away.isEmpty { card(away) }
                if country.otherPlaceCount > 0 {
                    Text("Plus \(country.otherPlaceCount) \(country.otherPlaceCount == 1 ? "place" : "places") outside a city.").font(.footnote).foregroundStyle(Roam.inkMuted)
                }
            }
            .padding(Theme.Spacing.l)
        }
        .background(Roam.paper)
        .navigationTitle(country.title)
        .navigationBarTitleDisplayMode(.inline)
        .screenIdentifier("passport-country")
        .task { entries = (try? await services.lists.been(ownerID: ownerID)) ?? [] }
    }

    private func card(_ cities: [PassportCity]) -> some View {
        VStack(spacing: 0) {
            ForEach(cities) { city in
                let opens = city.visibleCount > 0
                let isOpen = expanded.contains(city.id)
                // A city opens in place to show its spots.
                Button {
                    withAnimation(.snappy) { if isOpen { expanded.remove(city.id) } else { expanded.insert(city.id) } }
                } label: { row(city, opens: opens, isOpen: isOpen) }
                    .buttonStyle(.plain)
                    .allowsHitTesting(opens)
                    .accessibilityIdentifier("passport-city-\(city.city.name)")
                if isOpen { spots(in: city) }
                // Every separator starts under the names, so the lines run the same between each row.
                if city.id != cities.last?.id { Divider().padding(.leading, Self.iconWidth + Theme.Spacing.m) }
            }
        }
        .roamCard(padding: Theme.Spacing.m)
    }

    @ViewBuilder private func spots(in city: PassportCity) -> some View {
        let items = entries.filter { CityMatch.same($0.experience, city.city) }
            .sorted { ($0.ownerScore?.tenths ?? -1) > ($1.ownerScore?.tenths ?? -1) }
        VStack(spacing: 0) {
            ForEach(items) { entry in
                Divider()
                PlaceRow(item: PlaceMapItem(experience: entry.experience, state: .visited), score: entry.ownerScore) {
                    router.push(.experience(entry.id))
                }
            }
            if city.placeCount > items.count, session.userID != ownerID {
                Text("\(city.placeCount - items.count) more kept private.").font(.footnote).foregroundStyle(Roam.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Theme.Spacing.s)
            }
        }
        .padding(.leading, Self.iconWidth + Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.xs)
        .transition(.opacity)
    }

    private static let iconWidth: CGFloat = 24

    private func row(_ city: PassportCity, opens: Bool, isOpen: Bool) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: city.isHome ? "house.fill" : "mappin.circle.fill").foregroundStyle(PlaceState.visited.markerColor)
                .frame(width: Self.iconWidth).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(city.city.name).font(.headline).foregroundStyle(Roam.ink)
                if let detail = detail(city) { Text(detail).font(.footnote).foregroundStyle(Roam.inkMuted) }
            }
            Spacer(minLength: 0)
            if opens {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Roam.inkMuted)
                    .rotationEffect(.degrees(isOpen ? 90 : 0)).accessibilityHidden(true)
            }
        }
        .frame(minHeight: Theme.minimumHitTarget)
        .padding(.vertical, Theme.Spacing.xs)
        .contentShape(Rectangle())
    }

    /// Just the name, so the spots have room; on a friend's passport, a note when they've kept places private.
    private func detail(_ city: PassportCity) -> String? {
        guard session.userID != ownerID, city.placeCount > 0, city.visibleCount < city.placeCount else { return nil }
        return city.visibleCount == 0 ? "Kept private" : "Some kept private"
    }
}

/// The places someone has been in one city that they've shared with you.
struct PassportCityView: View {
    let ownerID: UUID
    let city: PassportCity

    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @State private var entries: LoadPhase<[ListEntry]> = .idle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                switch entries {
                case .idle, .loading: SkeletonList(rows: 4)
                case .failed(let message): InlineRetryView(message: message) { Task { await load() } }
                case .loaded(let value):
                    let items = value.filter { CityMatch.same($0.experience, city.city) }
                        .sorted { ($0.ownerScore?.tenths ?? -1) > ($1.ownerScore?.tenths ?? -1) }
                    if items.isEmpty {
                        Text("No shared places here.").font(.subheadline).foregroundStyle(Roam.inkMuted)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(items) { entry in
                                PlaceRow(item: PlaceMapItem(experience: entry.experience, state: .visited), score: entry.ownerScore) {
                                    router.push(.experience(entry.id))
                                }
                                if entry.id != items.last?.id { Divider() }
                            }
                        }
                        .roamCard(padding: Theme.Spacing.m)
                    }
                    if city.placeCount > items.count {
                        Text("\(city.placeCount - items.count) more kept private.").font(.footnote).foregroundStyle(Roam.inkMuted)
                    }
                }
            }
            .padding(Theme.Spacing.l)
        }
        .background(Roam.paper)
        .navigationTitle(city.city.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .screenIdentifier("passport-city")
    }

    private func load() async {
        do { entries = .loaded(try await services.lists.been(ownerID: ownerID)) }
        catch { entries = .failed(error.roamMessage) }
    }
}

// MARK: - A group of your places

/// A set of your places, such as a journey on your timeline, broken down by country and city.
struct PlaceGroupView: View {
    let title: String
    let subtitle: String?
    let ids: [UUID]

    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @State private var model: MyPlacesModel?

    private var items: [PlaceMapItem] {
        let wanted = Set(ids)
        return model?.pins.filter { wanted.contains($0.id) } ?? []
    }

    var body: some View {
        PlacesMapScreen(title: title, subtitle: subtitle, items: items, onRefresh: { await model?.load() }) {
            if let model, model.hasLoaded {
                PlaceBreakdown(items: items, scores: model.scores)
            } else {
                SkeletonList(rows: 4)
            }
        }
        .task {
            if model == nil, let me = session.userID { model = MyPlacesModel(services: services, ownerID: me) }
            await model?.load()
        }
        .screenIdentifier("place-group")
    }
}

/// A full-screen map of places, with their list on a card you swipe up over it, like the My Places globe.
struct PlacesMapScreen<Content: View>: View {
    let title: String
    var subtitle: String?
    let items: [PlaceMapItem]
    var onRefresh: () async -> Void = {}
    @ViewBuilder var content: () -> Content

    @Environment(AppRouter.self) private var router
    @State private var detent = GlobeSheetDetent.half

    var body: some View {
        GlobeSheetLayout(detent: $detent, peekHeight: 104, headerLabel: title, headerIdentifier: "places-sheet-header", onRefresh: onRefresh) {
            if items.isEmpty {
                Roam.fill
            } else {
                PlaceMapView(items: items) { router.push(.experience($0)) }
                    .id(items.map(\.id))
            }
        } header: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.roamTitle()).foregroundStyle(Roam.ink).lineLimit(1).accessibilityAddTraits(.isHeader)
                    if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(Roam.inkMuted) }
                }
                Spacer()
                GlobeSheetChevron(detent: detent)
            }
        } content: {
            content()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) } }
    }
}


/// Optional start and end dates side by side. Each is blank until tapped, and can be cleared again.
struct TripDatesRow: View {
    @Binding var start: Date?
    @Binding var end: Date?

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            slot("Start", date: $start, from: nil) { picked in
                if let end, end < picked { self.end = picked }
            }
            slot("End", date: $end, from: start) { _ in }
        }
    }

    private func slot(_ title: String, date: Binding<Date?>, from minimum: Date?, onPick: @escaping (Date) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Roam.inkMuted)
            if let value = date.wrappedValue {
                HStack(spacing: 4) {
                    DatePicker(title, selection: Binding(get: { value }, set: { date.wrappedValue = $0; onPick($0) }),
                               in: (minimum ?? .distantPast)..., displayedComponents: .date)
                        .labelsHidden()
                    Button { date.wrappedValue = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Roam.inkMuted) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear \(title.lowercased()) date")
                }
            } else {
                Button {
                    let picked = minimum ?? Calendar.current.startOfDay(for: Date())
                    date.wrappedValue = picked
                    onPick(picked)
                } label: { Label("Add", systemImage: "calendar") }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Add \(title.lowercased()) date")
                    .accessibilityIdentifier("trip-\(title.lowercased())-date")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The country the My Places globe is zoomed in on: your trips there and your places by city.
struct CountryFocusSection: View {
    let model: MyPlacesModel
    let code: String
    let title: String

    var body: some View {
        let items = model.countries.first { $0.code == code }?.items ?? []
        let trips = model.trips.filter { trip in
            trip.phase(today: MyTimeline.today()) != .past && trip.cities.contains { $0.countryCode?.uppercased() == code }
        }
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            if !trips.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Trips").font(.roamTitle()).accessibilityAddTraits(.isHeader)
                    VStack(spacing: 0) {
                        ForEach(trips) { trip in
                            TripCard(trip: trip, cover: model.tripDetails[trip.id]?.places.first?.experience)
                            if trip.id != trips.last?.id { Divider() }
                        }
                    }
                    .roamCard(padding: Theme.Spacing.m)
                }
            }
            if !items.isEmpty {
                PlaceBreakdown(items: items, scores: model.scores)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
