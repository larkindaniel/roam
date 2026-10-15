import SwiftUI

/// S19: expanded globe with pins, shaded countries and an equivalent list. A category, city or
/// country selection narrows the pins, shading and list together; the header totals stay all-time.
/// Nothing here needs location permission.
struct ExpandedGlobeView: View {
    let userID: UUID
    var initialFilter: TravelFilter?

    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @State private var travel: LoadPhase<TravelProfile> = .idle
    @State private var ownerName: String?
    @State private var showsList = false
    @State private var flatMap = false
    @State private var selected: GlobePin?
    @State private var filter: TravelFilter?
    @State private var focusToken = 0
    @State private var didApplyInitialFilter = false

    init(userID: UUID, initialFilter: TravelFilter? = nil) {
        self.userID = userID
        self.initialFilter = initialFilter
    }

    private var year: Int { Calendar.current.component(.year, from: Date()) }
    private var isSelf: Bool { userID == session.userID }

    var body: some View {
        VStack(spacing: 0) {
            switch travel {
            case .idle, .loading:
                ProgressView("Loading travels…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                InlineRetryView(message: message) { Task { await load() } }.padding()
                Spacer()
            case .loaded(let value):
                header(value)
                if showsList {
                    list(value)
                } else {
                    map(value)
                }
            }
        }
        .background(Theme.groupedCanvas)
        .navigationTitle(isSelf ? "Your travels" : "\(ownerName ?? "Member")'s travels")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !showsList {
                    Button(flatMap ? "Globe" : "Flat map") { flatMap.toggle(); focusToken += 1 }
                        .accessibilityIdentifier("globe-style-toggle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(showsList ? "Map" : "List") { showsList.toggle() }
                    .accessibilityIdentifier("globe-list-toggle")
            }
        }
        .task { if travel.value == nil { await load() } }
        .screenIdentifier("expanded-globe")
    }

    private func load() async {
        travel = .loading
        if !didApplyInitialFilter {
            filter = initialFilter
            flatMap = initialFilter != nil
            didApplyInitialFilter = true
        }
        do {
            travel = .loaded(try await services.travel.travelProfile(userID: userID, year: year))
            focusToken += 1
        } catch {
            travel = .failed(session.handle(error))
        }
        if isSelf {
            ownerName = session.profile?.displayName
        } else if ownerName == nil {
            ownerName = (try? await services.profiles.publicProfile(userID: userID))?.member.displayName
        }
    }

    private var isCityFilter: Bool {
        if case .city = filter { return true }
        return false
    }

    private func visiblePins(_ value: TravelProfile) -> [GlobePin] {
        guard let filter else { return value.pins }
        return value.pins.filter(filter.matches)
    }

    /// All-time totals with the active selection underneath.
    private func header(_ value: TravelProfile) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    totals(value)
                    Spacer()
                    filterMenu(value)
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    totals(value)
                    filterMenu(value)
                }
            }
            if let filter {
                HStack(spacing: Theme.Spacing.s) {
                    Text("Showing \(filter.title): \(visiblePins(value).count) \(visiblePins(value).count == 1 ? "place" : "places")")
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("globe-filter-summary")
                    Spacer()
                    Button("Show all") { self.filter = nil; selected = nil; focusToken += 1 }
                        .font(.subheadline)
                        .frame(minHeight: Theme.minimumHitTarget)
                        .accessibilityIdentifier("globe-filter-clear")
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, Theme.Spacing.s)
        .background(Theme.raisedCard)
    }

    private func totals(_ value: TravelProfile) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value.countryCount) \(value.countryCount == 1 ? "country" : "countries") · \(value.cityCount) \(value.cityCount == 1 ? "city" : "cities")")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text("All-time · \(value.pins.count) \(value.pins.count == 1 ? "place" : "places") visited")
                .font(.caption).foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("globe-totals")
    }

    private func filterMenu(_ value: TravelProfile) -> some View {
        Menu {
            Button("All places") { filter = nil; selected = nil; focusToken += 1 }
            Menu("Category") {
                ForEach(value.categories) { row in
                    Button("\(row.category?.title ?? "Uncategorized") (\(row.count))") { apply(.category(row.category)) }
                }
            }
            Menu("Country") {
                ForEach(value.countries) { row in
                    Button("\(row.name) (\(row.count))") { apply(.country(code: row.countryCode, name: row.name)) }
                }
            }
            if !value.cities.isEmpty {
                Menu("City") {
                    ForEach(value.cities) { row in
                        Button("\(row.name), \(row.countryName ?? row.countryCode) (\(row.count))") { apply(.city(key: row.cityKey, name: row.name)) }
                    }
                }
            }
        } label: {
            PillLabel(title: filter == nil ? "Filter" : "Filtered", systemImage: "line.3.horizontal.decrease.circle")
        }
        .buttonStyle(PillButtonStyle(isSelected: filter != nil))
        .accessibilityIdentifier("globe-filter")
    }

    private func apply(_ newFilter: TravelFilter) {
        filter = newFilter
        selected = nil
        focusToken += 1
    }

    @ViewBuilder private func map(_ value: TravelProfile) -> some View {
        let pins = visiblePins(value)
        // Shading follows the shown pins; a country with no bundled boundary keeps its pin unshaded.
        // A city selection zooms in past where low-resolution country outlines mean anything.
        let shaded: Set<String> = isCityFilter ? [] : Set(pins.compactMap(\.countryCode))
        ZStack(alignment: .bottom) {
            GlobeMapView(pins: pins.map(MapPin.init), shadedCountryCodes: shaded,
                         style: flatMap ? .standard : .globe,
                         interactive: true, selectedPinID: selected?.id.uuidString,
                         focusRegion: flatMap ? GlobeMapView.region(fitting: pins.map(MapPin.init)) : nil,
                         focusToken: focusToken,
                         onSelectPin: { pin in selected = value.pins.first { $0.experienceID.uuidString == pin.id } })
                .id(flatMap)
                .mapAccessibility("Travel map with \(pins.count) \(pins.count == 1 ? "place" : "places"). Use List to browse them.", identifier: "globe-map")
                .ignoresSafeArea(edges: .bottom)
            if let selected {
                pinCard(selected)
            }
        }
    }

    /// The selected pin with its owner's context; View place opens the experience.
    private func pinCard(_ pin: GlobePin) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isSelf ? "Your visits" : "\(ownerName ?? "Their") visits").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                    Text(pin.name).font(.headline)
                    HStack(spacing: 6) {
                        CategoryBadge(category: pin.category, compact: true).fixedSize()
                        if !pin.areaLine.isEmpty { Text("· \(pin.areaLine)").font(.caption).foregroundStyle(Theme.secondaryText) }
                    }
                    Text(visitLine(pin)).font(.caption).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                Button { selected = nil } label: {
                    Image(systemName: "xmark").frame(width: Theme.minimumHitTarget, height: Theme.minimumHitTarget)
                }
                .accessibilityLabel("Close")
            }
            Button("View place") { router.push(.experience(pin.experienceID)) }
                .buttonStyle(PillButtonStyle(isSelected: true))
                .accessibilityIdentifier("globe-pin-open")
        }
        .roamCard(padding: Theme.Spacing.m)
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("globe-selected-pin")
    }

    private func visitLine(_ pin: GlobePin) -> String {
        let first = pin.firstVisitDate.map { "First visited \($0.displayString)" } ?? "Visit date unknown"
        return pin.visitCount > 1 ? "\(first) · \(pin.visitCount) visits" : first
    }

    private func list(_ value: TravelProfile) -> some View {
        let pins = visiblePins(value)
        return List {
            if filter == nil {
                Section("Countries (all-time)") {
                    ForEach(value.countries) { country in
                        Button { apply(.country(code: country.countryCode, name: country.name)) } label: {
                            HStack {
                                Text(country.name).foregroundStyle(Color.primary)
                                Spacer()
                                Text("\(country.count)").monospacedDigit().foregroundStyle(Theme.secondaryText)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            Section(filter.map { "\($0.title) · \(pins.count) \(pins.count == 1 ? "place" : "places")" } ?? "Places") {
                ForEach(pins) { pin in
                    Button { router.push(.experience(pin.experienceID)) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pin.name).font(.headline).foregroundStyle(Color.primary)
                            HStack(spacing: 6) {
                                CategoryBadge(category: pin.category, compact: true).fixedSize()
                                Text(pin.areaLine.isEmpty ? "Location unavailable" : pin.areaLine).font(.caption).foregroundStyle(Theme.secondaryText)
                            }
                            Text(visitLine(pin)).font(.caption).foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .accessibilityIdentifier("globe-list-row-\(pin.name)")
                }
            }
        }
        .accessibilityIdentifier("globe-list")
    }
}
