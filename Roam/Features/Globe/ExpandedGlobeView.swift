import SwiftUI

/// S19: expanded globe with pins, shaded countries and an equivalent list.
struct ExpandedGlobeView: View {
    let userID: UUID

    @Environment(AppServices.self) private var services
    @State private var travel: LoadPhase<TravelProfile> = .idle
    @State private var showsList = false
    @State private var flatMap = false
    @State private var selected: GlobePin?

    private var year: Int { Calendar.current.component(.year, from: Date()) }

    var body: some View {
        ZStack(alignment: .bottom) {
            switch travel {
            case .idle, .loading:
                ProgressView("Loading travels…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                InlineRetryView(message: message) { Task { await load() } }.padding()
            case .loaded(let value):
                if showsList {
                    list(value)
                } else {
                    GlobeMapView(pins: value.pins, shadedCountryCodes: Set(value.countries.map(\.countryCode)),
                                 style: flatMap ? .standard : .globe,
                                 interactive: true, selectedPinID: selected?.id,
                                 onSelectPin: { selected = $0 })
                        .id(flatMap)
                        .ignoresSafeArea(edges: .bottom)
                    if let selected {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(selected.name).font(.headline)
                                CategoryBadge(category: selected.category, compact: true)
                            }
                            Spacer()
                            Button { self.selected = nil } label: {
                                Image(systemName: "xmark").frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Close")
                        }
                        .roamCard(padding: Theme.Spacing.m)
                        .padding()
                        .accessibilityIdentifier("globe-selected-pin")
                    }
                }
            }
        }
        .navigationTitle(travel.value.map { "\($0.countryCount) countries · \($0.cityCount) cities" } ?? "Travels")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !showsList {
                    Button(flatMap ? "Globe" : "Flat map") { flatMap.toggle() }
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
        do {
            travel = .loaded(try await services.travel.travelProfile(userID: userID, year: year))
        } catch {
            travel = .failed(error.roamMessage)
        }
    }

    private func list(_ value: TravelProfile) -> some View {
        List {
            Section("Countries (all-time)") {
                ForEach(value.countries) { country in
                    HStack {
                        Text(country.name)
                        Spacer()
                        Text("\(country.count)").monospacedDigit().foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Section("Experiences") {
                ForEach(value.pins) { pin in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pin.name).font(.headline)
                        CategoryBadge(category: pin.category, compact: true)
                    }
                }
            }
        }
        .accessibilityIdentifier("globe-list")
    }
}
