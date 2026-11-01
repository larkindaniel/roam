import MapKit
import SwiftUI

extension PlaceState {
    var markerColor: Color {
        switch self {
        case .wishlist: return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.961, green: 0.690, blue: 0.227, alpha: 1) : UIColor(red: 0.941, green: 0.627, blue: 0.125, alpha: 1) })
        case .planned: return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.302, green: 0.525, blue: 0.941, alpha: 1) : UIColor(red: 0.184, green: 0.435, blue: 0.894, alpha: 1) })
        case .visited: return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.247, green: 0.710, blue: 0.416, alpha: 1) : UIColor(red: 0.180, green: 0.620, blue: 0.333, alpha: 1) })
        }
    }

    var markerSymbol: String {
        switch self {
        case .wishlist: return "bookmark.fill"
        case .planned: return "airplane"
        case .visited: return "checkmark"
        }
    }

    var markerTitle: String { self == .visited ? "Been there" : title }
}

/// How a place draws on a map: a dot from afar, a symbol marker up close, a pin when selected.
enum PlaceMarkerStage: Equatable {
    case dot
    case marker
    case pin

    /// Street level, where dots grow into markers.
    static let markerSpan: CLLocationDegrees = 0.06

    static func stage(isSelected: Bool, latitudeSpan: CLLocationDegrees) -> PlaceMarkerStage {
        if isSelected { return .pin }
        return latitudeSpan <= markerSpan ? .marker : .dot
    }
}

struct PlaceMarkerView: View {
    let state: PlaceState
    let stage: PlaceMarkerStage
    @Environment(\.colorScheme) private var scheme

    private var border: Color { scheme == .dark ? Roam.paperRaised : .white }

    var body: some View {
        switch stage {
        case .dot:
            Circle().fill(state.markerColor).frame(width: 12, height: 12)
                .overlay(Circle().strokeBorder(border, lineWidth: 2))
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        case .marker:
            Circle().fill(state.markerColor).frame(width: 32, height: 32)
                .overlay(Circle().strokeBorder(border, lineWidth: 3))
                .overlay(Image(systemName: state.markerSymbol).font(.system(size: 14, weight: .bold)).foregroundStyle(.white))
        case .pin:
            PinShape().fill(state.markerColor)
                .overlay(PinShape().stroke(border, lineWidth: 2.5))
                .overlay(alignment: .top) {
                    Image(systemName: state.markerSymbol).font(.system(size: 22, weight: .bold)).foregroundStyle(.white).frame(height: 44)
                }
                .frame(width: 44, height: 60)
                .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
        }
    }
}

/// A round head tapering to a point at the bottom centre.
struct PinShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = rect.width / 2
        let center = CGPoint(x: rect.midX, y: rect.minY + radius)
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.minX, y: center.y),
                      control1: CGPoint(x: rect.midX - radius * 0.2, y: rect.maxY - radius * 0.45),
                      control2: CGPoint(x: rect.minX, y: center.y + radius * 0.85))
        path.addArc(center: center, radius: radius, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        path.addCurve(to: CGPoint(x: rect.midX, y: rect.maxY),
                      control1: CGPoint(x: rect.maxX, y: center.y + radius * 0.85),
                      control2: CGPoint(x: rect.midX + radius * 0.2, y: rect.maxY - radius * 0.45))
        path.closeSubpath()
        return path
    }
}

struct PlaceMapItem: Identifiable, Hashable {
    let experience: ExperienceSummary
    let state: PlaceState

    var id: UUID { experience.id }

    /// Start on the largest group of nearby places, so a map isn't zoomed out to nothing by one far-off trip.
    static func startingRegion(_ items: [PlaceMapItem]) -> MKCoordinateRegion {
        let group = items.map { item in
            items.filter { abs($0.experience.latitude - item.experience.latitude) < 3 && abs($0.experience.longitude - item.experience.longitude) < 3 }
        }.max { $0.count < $1.count } ?? []
        guard let minLat = group.map(\.experience.latitude).min(), let maxLat = group.map(\.experience.latitude).max(),
              let minLon = group.map(\.experience.longitude).min(), let maxLon = group.map(\.experience.longitude).max() else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 20, longitude: 0), span: MKCoordinateSpan(latitudeDelta: 120, longitudeDelta: 300))
        }
        return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
                                  span: MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.5, 0.04), longitudeDelta: max((maxLon - minLon) * 1.5, 0.04)))
    }
}

/// The shared places map. Tap a marker to see its pin and name, then tap the name to open the place.
struct PlaceMapView: View {
    let items: [PlaceMapItem]
    var onOpen: (UUID) -> Void

    @State private var position: MapCameraPosition
    @State private var latitudeSpan: CLLocationDegrees
    @State private var selectedID: UUID?

    init(items: [PlaceMapItem], onOpen: @escaping (UUID) -> Void) {
        self.items = items
        self.onOpen = onOpen
        let region = PlaceMapItem.startingRegion(items)
        _position = State(initialValue: .region(region))
        _latitudeSpan = State(initialValue: region.span.latitudeDelta)
    }

    var body: some View {
        Map(position: $position) {
            ForEach(items) { item in
                let selected = selectedID == item.id
                Annotation(item.experience.name, coordinate: item.experience.coordinate, anchor: selected ? .bottom : .center) {
                    Button {
                        if selected { onOpen(item.id) } else { selectedID = item.id }
                    } label: {
                        PlaceMarkerView(state: item.state, stage: PlaceMarkerStage.stage(isSelected: selected, latitudeSpan: latitudeSpan))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.experience.name), \(item.state.markerTitle)")
                    .accessibilityIdentifier("map-marker-\(item.experience.name)")
                }
                .annotationTitles(.hidden)
            }
        }
        .onMapCameraChange(frequency: .onEnd) { latitudeSpan = $0.region.span.latitudeDelta }
        .overlay(alignment: .bottom) {
            if let selected = items.first(where: { $0.id == selectedID }) {
                Button { onOpen(selected.id) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(selected.experience.name).font(.subheadline.weight(.semibold)).foregroundStyle(Roam.ink).lineLimit(1)
                            Text(selected.state.markerTitle).font(.caption.weight(.medium)).foregroundStyle(selected.state.markerColor)
                        }
                        Spacer(minLength: Theme.Spacing.s)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Roam.inkMuted).accessibilityHidden(true)
                    }
                    .padding(.horizontal, Theme.Spacing.m)
                    .frame(minHeight: Theme.minimumHitTarget + 8)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Roam.paperRaised))
                }
                .buttonStyle(.plain)
                .padding(Theme.Spacing.s)
                .accessibilityIdentifier("map-selected-place")
            }
        }
    }
}

struct PlaceMapLegend: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.l) {
            ForEach([PlaceState.visited, .planned, .wishlist], id: \.self) { state in
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: state.markerSymbol).font(.caption2.weight(.bold)).foregroundStyle(state.markerColor)
                    Text(state.markerTitle).font(.caption).foregroundStyle(Roam.inkMuted)
                }
            }
        }
    }
}
