import SwiftUI

/// Travel Profile rows are counts and filters only (D17): no city scores, confidence, guides or
/// leaderboards.
enum TravelBreakdown: String, CaseIterable, Identifiable, Hashable {
    case categories
    case cities
    case countries

    var id: String { rawValue }
    var title: String {
        switch self {
        case .categories: return "Categories"
        case .cities: return "Cities"
        case .countries: return "Countries"
        }
    }
}

enum TravelSort: String, CaseIterable, Identifiable, Hashable {
    case count
    case name

    var id: String { rawValue }
    var title: String { self == .count ? "Most places" : "Name" }
}

/// One Travel Profile row: what it is, how many visited experiences it has, and its filter.
struct TravelRow: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let count: Int
    let filter: TravelFilter

    static func rows(_ travel: TravelProfile, breakdown: TravelBreakdown, sort: TravelSort) -> [TravelRow] {
        let rows: [TravelRow]
        switch breakdown {
        case .categories:
            rows = travel.categories.map {
                TravelRow(id: "category-\($0.id)", title: $0.category?.title ?? "Uncategorized", subtitle: nil, count: $0.count,
                          filter: .category($0.category))
            }
        case .cities:
            rows = travel.cities.map { city in
                let subtitle = [city.region, city.countryName ?? city.countryCode].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
                return TravelRow(id: "city-\(city.cityKey)", title: city.name, subtitle: subtitle.isEmpty ? nil : subtitle, count: city.count,
                                 filter: .city(key: city.cityKey, name: city.name))
            }
        case .countries:
            rows = travel.countries.map {
                TravelRow(id: "country-\($0.countryCode)", title: $0.name, subtitle: nil, count: $0.count,
                          filter: .country(code: $0.countryCode, name: $0.name))
            }
        }
        switch sort {
        case .count:
            return rows.sorted { ($0.count, $1.title.lowercased(), $1.id) > ($1.count, $0.title.lowercased(), $0.id) }
        case .name:
            return rows.sorted { ($0.title.localizedLowercase, $0.subtitle ?? "", $0.id) < ($1.title.localizedLowercase, $1.subtitle ?? "", $1.id) }
        }
    }
}

/// S18 Travel Profile tab: New this year (S28), then category/city/country rows.
struct TravelProfileSection: View {
    let userID: UUID
    let travel: TravelProfile?
    let error: String?
    let isSelf: Bool
    let ownerName: String
    let retry: () -> Void

    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var breakdown: TravelBreakdown = .categories
    @State private var sort: TravelSort = .count

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if let travel {
                if travel.pins.isEmpty {
                    emptyState
                } else {
                    newThisYear(travel.newThisYear)
                    breakdownCard(travel)
                }
            } else if let error {
                InlineRetryView(message: error, retry: retry)
            } else {
                SkeletonList(rows: 3)
            }
        }
        .padding(.horizontal)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: "globe.europe.africa").font(.largeTitle).foregroundStyle(Theme.accent).accessibilityHidden(true)
            Text(isSelf ? "Your globe fills in as you log places you've been. Bookmarks and your home city don't count."
                        : "\(ownerName) hasn't logged any visits yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if isSelf {
                Button("Find a place to log") { router.selectedTab = .search }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("travel-empty-log")
            }
        }
        .frame(maxWidth: .infinity)
        .roamCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("travel-empty")
    }

    private func newThisYear(_ value: NewThisYear) -> some View {
        Button { router.push(.newThisYear(userID, value.year)) } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack {
                    Text(verbatim: "New this year · \(value.year)").font(.headline).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                    Text("\(value.count)").font(.system(.largeTitle, design: .rounded).weight(.bold)).foregroundStyle(Theme.accent)
                    Text(value.count == 1 ? "place first visited this year" : "places first visited this year")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if value.unknownDateCount > 0 {
                    Text("\(value.unknownDateCount) \(value.unknownDateCount == 1 ? "place" : "places") with an unknown visit date \(value.unknownDateCount == 1 ? "isn't" : "aren't") counted.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .roamCard()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows the places")
        .accessibilityIdentifier("new-this-year")
    }

    private func breakdownCard(_ travel: TravelProfile) -> some View {
        let rows = TravelRow.rows(travel, breakdown: breakdown, sort: sort)
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Picker("Breakdown", selection: $breakdown) {
                ForEach(TravelBreakdown.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("travel-breakdown")
            ViewThatFits(in: .horizontal) {
                HStack {
                    rowCount(rows.count)
                    Spacer()
                    sortMenu
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    rowCount(rows.count)
                    sortMenu
                }
            }
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    Button { router.push(.travelFilter(userID, row.filter)) } label: { rowLabel(row) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("travel-row-\(row.id)")
                    if row.id != rows.last?.id { Divider() }
                }
            }
            if breakdown == .cities && travel.placesWithoutCity > 0 {
                Label("\(travel.placesWithoutCity) \(travel.placesWithoutCity == 1 ? "place has" : "places have") no city (City unavailable). \(travel.placesWithoutCity == 1 ? "It counts" : "They count") toward countries and the globe.",
                      systemImage: "mappin.slash")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("travel-no-city")
            }
            Text("Counts are visited places, all-time. Tap a row to see them.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .roamCard()
    }

    private func rowCount(_ count: Int) -> some View {
        Text("\(count) \(breakdown.title.lowercased())").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $sort) {
                ForEach(TravelSort.allCases) { Text($0.title).tag($0) }
            }
        } label: {
            PillLabel(title: "Sort: \(sort.title)", systemImage: "arrow.up.arrow.down")
        }
        .buttonStyle(PillButtonStyle())
        .accessibilityIdentifier("travel-sort")
    }

    /// Name, area and count side by side; stacked at accessibility sizes so nothing squeezes.
    private func rowLabel(_ row: TravelRow) -> some View {
        let count = Text("\(row.count) \(row.count == 1 ? "place" : "places")").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
        return HStack(spacing: Theme.Spacing.m) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title).font(.body.weight(.medium)).foregroundStyle(.primary)
                    if let subtitle = row.subtitle { Text(subtitle).font(.footnote).foregroundStyle(.secondary) }
                    count
                }
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title).font(.body.weight(.medium)).foregroundStyle(.primary)
                    if let subtitle = row.subtitle { Text(subtitle).font(.footnote).foregroundStyle(.secondary) }
                }
                Spacer()
                count
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
        }
        .padding(.vertical, Theme.Spacing.s)
        .frame(minHeight: Theme.minimumHitTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// S28: the places first visited in one calendar year, newest first.
struct NewThisYearView: View {
    let userID: UUID
    let year: Int

    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @State private var phase: LoadPhase<TravelProfile> = .idle

    var body: some View {
        Group {
            switch phase {
            case .idle, .loading:
                SkeletonList(rows: 4).padding().frame(maxHeight: .infinity, alignment: .top)
            case .failed(let message):
                EmptyStateView(systemImage: "exclamationmark.triangle", title: "Couldn't load this year", message: message,
                               primaryTitle: "Try again", primaryAction: { Task { await load() } })
                    .frame(maxHeight: .infinity, alignment: .top)
            case .loaded(let travel):
                list(travel)
            }
        }
        .navigationTitle(Text(verbatim: "New in \(year)"))
        .navigationBarTitleDisplayMode(.inline)
        .background(Theme.groupedCanvas)
        .task { if phase.value == nil { await load() } }
        .screenIdentifier("new-this-year-list")
    }

    private func load() async {
        phase = .loading
        do {
            phase = .loaded(try await services.travel.travelProfile(userID: userID, year: year))
        } catch {
            phase = .failed(session.handle(error))
        }
    }

    private func list(_ travel: TravelProfile) -> some View {
        let byID = Dictionary(uniqueKeysWithValues: travel.pins.map { ($0.experienceID, $0) })
        let pins = travel.newThisYear.experienceIDs.compactMap { byID[$0] }
        return List {
            Section {
                if pins.isEmpty {
                    Text(verbatim: "No places were first visited in \(year) yet.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("new-this-year-empty")
                }
                ForEach(pins) { pin in
                    Button { router.push(.experience(pin.experienceID)) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(pin.name).font(.headline).foregroundStyle(Color.primary)
                            HStack(spacing: 6) {
                                CategoryBadge(category: pin.category, compact: true).fixedSize()
                                if !pin.areaLine.isEmpty { Text("· \(pin.areaLine)").font(.caption).foregroundStyle(Color.secondary) }
                            }
                            if let date = pin.firstVisitDate {
                                Text("First visited \(date.displayString)").font(.caption).foregroundStyle(Color.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .accessibilityIdentifier("new-this-year-row-\(pin.name)")
                }
            } header: {
                Text(verbatim: "\(travel.newThisYear.count) \(travel.newThisYear.count == 1 ? "place" : "places") first visited in \(year)")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Each place counts once, in the year of its earliest known visit. Later visits don't count again.")
                    if travel.newThisYear.unknownDateCount > 0 {
                        let one = travel.newThisYear.unknownDateCount == 1
                        Text("\(travel.newThisYear.unknownDateCount) \(one ? "place has" : "places have") only visits with an unknown date, so \(one ? "it isn't" : "they aren't") counted."
                             + (userID == session.userID ? " Add a date from the place's visit history to count \(one ? "it" : "them")." : ""))
                    }
                }
            }
        }
    }
}
