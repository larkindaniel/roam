import MapKit
import SwiftUI

/// Apple Maps' own listing for a Roam place, used for a Look Around picture and Apple's place card when
/// nobody on Roam has a photo. MapKit shares no listing photos or descriptions, only these.
@MainActor
enum AppleMapsLookup {
    private static var items: [UUID: MKMapItem] = [:]

    /// The listing by its Apple Maps identifier, or else the nearest search match with the same name.
    static func mapItem(for place: ExperienceSummary) async -> MKMapItem? {
        if let cached = items[place.id] { return cached }
        var found: MKMapItem?
        if let raw = place.providerPlaceID, let identifier = MKMapItem.Identifier(rawValue: raw) {
            found = try? await MKMapItemRequest(mapItemIdentifier: identifier).mapItem
        }
        if found == nil {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = place.name
            request.region = MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 3_000, longitudinalMeters: 3_000)
            let target = CLLocation(latitude: place.latitude, longitude: place.longitude)
            let matches = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
            found = matches
                .map { ($0, $0.placemark.location?.distance(from: target) ?? .infinity) }
                .filter { $0.1 < 500 }
                .min { $0.1 < $1.1 }?.0
        }
        if let found { items[place.id] = found }
        return found
    }

    /// The Look Around scene at the spot, where Apple has street-level imagery of it.
    static func lookAroundScene(item: MKMapItem?, coordinate: CLLocationCoordinate2D) async -> MKLookAroundScene? {
        if let item, let scene = try? await MKLookAroundSceneRequest(mapItem: item).scene { return scene }
        return try? await MKLookAroundSceneRequest(coordinate: coordinate).scene
    }

}

/// Apple's own place card for a listing: photos, hours, ratings and description.
struct AppleMapsCard: UIViewControllerRepresentable, Identifiable {
    let item: MKMapItem
    let id = UUID()

    func makeUIViewController(context: Context) -> UINavigationController {
        let detail = MKMapItemDetailViewController(mapItem: item)
        detail.delegate = context.coordinator
        context.coordinator.dismiss = context.environment.dismiss
        return UINavigationController(rootViewController: detail)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {
        context.coordinator.dismiss = context.environment.dismiss
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Apple's card has its own close button; it reports here rather than dismissing itself.
    final class Coordinator: NSObject, MKMapItemDetailViewControllerDelegate {
        var dismiss: DismissAction?

        func mapItemDetailViewControllerDidFinish(_ detailViewController: MKMapItemDetailViewController) {
            dismiss?()
        }
    }
}

/// Apple's street-level view of a spot. Tap it to look around full screen.
struct LookAroundCard: View {
    let scene: MKLookAroundScene
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            LookAroundPreview(initialScene: scene, allowsNavigation: true, badgePosition: .bottomTrailing)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                .accessibilityLabel(label)
            Text("Tap to look around in Apple Maps").font(.caption2).foregroundStyle(Roam.inkMuted)
        }
    }
}

/// A city's Wikipedia summary and lead photo.
struct CityGuide: Hashable {
    var title: String
    var extract: String
    var photoURL: URL?
    var pageURL: URL?

    private struct Summary: Decodable {
        struct Image: Decodable { var source: URL }
        struct Coordinates: Decodable { var lat: Double; var lon: Double }
        struct Pages: Decodable { struct Page: Decodable { var page: URL }; var mobile: Page? }
        var type: String
        var title: String
        var extract: String
        var thumbnail: Image?
        var coordinates: Coordinates?
        var content_urls: Pages?
    }

    @MainActor private static var cache: [String: CityGuide] = [:]

    /// Tries the plain name, then the name with its region and country, and keeps only an article whose
    /// coordinates are near the city, so "Paris" in Ontario doesn't get the French capital.
    @MainActor static func load(name: String, region: String?, country: String?, coordinate: CLLocationCoordinate2D) async -> CityGuide? {
        let key = "\(name)|\(region ?? "")|\(country ?? "")"
        if let cached = cache[key] { return cached }
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        for title in [name, region.map { "\(name), \($0)" }, country.map { "\(name), \($0)" }].compactMap({ $0 }) {
            guard let summary = await fetch(title), summary.type == "standard", let at = summary.coordinates,
                  CLLocation(latitude: at.lat, longitude: at.lon).distance(from: target) < 80_000 else { continue }
            // Wikimedia serves any width of a thumbnail by changing the size in its path.
            let photo = summary.thumbnail.flatMap { URL(string: $0.source.absoluteString.replacingOccurrences(of: #"/\d+px-"#, with: "/960px-", options: .regularExpression)) }
            let guide = CityGuide(title: summary.title, extract: summary.extract, photoURL: photo, pageURL: summary.content_urls?.mobile?.page)
            cache[key] = guide
            return guide
        }
        return nil
    }

    private static func fetch(_ title: String) async -> Summary? {
        let path = title.replacingOccurrences(of: " ", with: "_").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/")))
        guard let path, let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(path)") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Roam/1.0 (iOS travel app)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(Summary.self, from: data)
    }
}

/// About a city, from Wikipedia. Shows nothing when no matching article is found.
struct CityGuideCard: View {
    let name: String
    var region: String?
    var country: String?
    let coordinate: CLLocationCoordinate2D

    @State private var guide: CityGuide?
    @Environment(\.openURL) private var openURL

    var body: some View {
        // A stack, not a Group: a Group with nothing in it yet would never run the task that loads it.
        VStack(spacing: 0) {
            if let guide {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    if let photo = guide.photoURL {
                        PlacePhotoView(url: photo, credit: "Wikimedia Commons", label: "Photo of \(guide.title)", placeholderSymbol: "building.2", height: 180)
                    }
                    Text("About \(name)").font(.roamTitle(.title3)).accessibilityAddTraits(.isHeader)
                    Text(guide.extract).font(.subheadline).foregroundStyle(Roam.ink).lineLimit(7)
                    HStack {
                        Text("From Wikipedia").font(.caption).foregroundStyle(Roam.inkMuted)
                        Spacer()
                        if let page = guide.pageURL {
                            Button("Read more") { openURL(page) }.font(.caption.weight(.semibold))
                                .accessibilityIdentifier("city-guide-more")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .roamCard()
                .accessibilityIdentifier("city-guide")
            }
        }
        .task(id: "\(name)|\(region ?? "")|\(country ?? "")") {
            guide = await CityGuide.load(name: name, region: region, country: country, coordinate: coordinate)
        }
    }
}
