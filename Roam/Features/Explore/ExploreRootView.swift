import MapKit
import SwiftUI

struct ExploreRootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(DestinationStore.self) private var destinations

    var body: some View {
        VStack(spacing: 0) {
            Button {
                router.sheet = .destinationPicker(.explore)
            } label: {
                HStack {
                    Image(systemName: "mappin.and.ellipse")
                    Text(destinations.explore?.displayName ?? "Choose a destination")
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down").font(.footnote)
                }
                .font(.subheadline.weight(.semibold))
                .padding(Theme.Spacing.m)
                .frame(minHeight: Theme.minimumHitTarget)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.s)
            .accessibilityIdentifier("explore-destination-button")

            if let destination = destinations.explore {
                GlobeMapView(pins: [], shadedCountryCodes: [], style: .standard, interactive: true,
                             focusRegion: MKCoordinateRegion(center: destination.coordinate, latitudinalMeters: destination.radiusMeters * 2,
                                                             longitudinalMeters: destination.radiusMeters * 2),
                             focusToken: destination.id.hashValue)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                ScrollView {
                    EmptyStateView(systemImage: "map", title: "Explore anywhere",
                                   message: "Pick a destination to browse places on the map. Location access is optional.",
                                   primaryTitle: "Choose a destination", primaryAction: { router.sheet = .destinationPicker(.explore) })
                }
            }
        }
        .background(Theme.groupedCanvas)
        .navigationTitle("Explore")
        .navigationBarTitleDisplayMode(.inline)
        .screenIdentifier("explore-root")
    }
}
