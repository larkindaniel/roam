import MapKit
import SwiftUI

/// Apple Maps' own listing for a Roam place, used to find its Look Around imagery. MapKit shares no listing
/// photos or descriptions with apps.
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

/// A small square picture for a list row: the place's own photo, else a Look Around still of the spot, else
/// its category symbol. Apple Maps doesn't share listing photos, so Look Around is the only Apple picture.
struct PlaceThumbnail: View {
    let id: String
    /// A photo from a Roam visit, which leads when there is one.
    var path: String? = nil
    var url: URL?
    let coordinate: CLLocationCoordinate2D
    var symbol = "mappin"
    var size: CGFloat = 64

    @MainActor private static var stills: [String: UIImage] = [:]
    @State private var still: UIImage?

    var body: some View {
        Roam.fill
            .frame(width: size, height: size)
            .overlay {
                if let path {
                    RemoteImageView(path: path, accessibilityLabel: "")
                } else if let url {
                    AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Roam.fill }
                } else if let still {
                    Image(uiImage: still).resizable().scaledToFill()
                } else {
                    Image(systemName: symbol).foregroundStyle(Roam.inkMuted)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
            .task(id: id) {
                guard url == nil, path == nil else { return }
                if let cached = Self.stills[id] { still = cached; return }
                guard let scene = try? await MKLookAroundSceneRequest(coordinate: coordinate).scene else { return }
                let options = MKLookAroundSnapshotter.Options()
                options.size = CGSize(width: size * 2, height: size * 2)
                if let image = try? await MKLookAroundSnapshotter(scene: scene, options: options).snapshot.image {
                    Self.stills[id] = image
                    still = image
                }
            }
    }
}

/// Apple's Look Around of a spot as a still picture, filling its frame; the symbol where Apple has no imagery.
struct LookAroundStill: View {
    let coordinate: CLLocationCoordinate2D
    var symbol = "mappin"

    @MainActor private static var stills: [String: UIImage] = [:]
    @MainActor private static var missing: Set<String> = []
    @State private var still: UIImage?
    @State private var looked = false

    private var key: String { String(format: "%.5f,%.5f", coordinate.latitude, coordinate.longitude) }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let still {
                    Image(uiImage: still).resizable().scaledToFill().frame(width: proxy.size.width, height: proxy.size.height).clipped()
                } else if looked {
                    Image(systemName: symbol).font(.largeTitle).foregroundStyle(Roam.inkMuted)
                } else {
                    ProgressView()
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .task(id: key) {
                if let cached = Self.stills[key] { still = cached; looked = true; return }
                guard !Self.missing.contains(key), let scene = try? await MKLookAroundSceneRequest(coordinate: coordinate).scene else {
                    Self.missing.insert(key); looked = true; return
                }
                let options = MKLookAroundSnapshotter.Options()
                options.size = CGSize(width: max(proxy.size.width, 1) * 2, height: max(proxy.size.height, 1) * 2)
                if let image = try? await MKLookAroundSnapshotter(scene: scene, options: options).snapshot.image {
                    Self.stills[key] = image
                    still = image
                }
                looked = true
            }
        }
        .accessibilityLabel("Look Around view of the spot")
    }
}

/// One picture of a place: Apple's Look Around, its linked photo, or a photo from someone's visit.
enum PlaceGalleryItem: Identifiable {
    case lookAround(MKLookAroundScene)
    case photo(URL, credit: String?)
    case visitPhoto(path: String)

    var id: String {
        switch self {
        case .lookAround: return "look-around"
        case .photo(let url, _): return url.absoluteString
        case .visitPhoto(let path): return path
        }
    }
}

/// A place's pictures, Look Around first. The arrow in the corner steps to the next one.
struct PlaceGallery: View {
    let items: [PlaceGalleryItem]
    let placeName: String

    @State private var index = 0

    private var current: PlaceGalleryItem? { items.isEmpty ? nil : items[min(index, items.count - 1)] }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ZStack(alignment: .topTrailing) {
                Roam.fill
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .overlay {
                        switch current {
                        case .lookAround(let scene):
                            LookAroundPreview(initialScene: scene, allowsNavigation: true, badgePosition: .bottomTrailing)
                                .accessibilityLabel("Look Around at \(placeName)")
                        case .photo(let url, _):
                            PlacePhotoView(url: url, label: "Photo of \(placeName)", height: 220, showsCredit: false, cornerRadius: 0)
                        case .visitPhoto(let path):
                            RemoteImageView(path: path, accessibilityLabel: "Photo from a visit to \(placeName)")
                        case nil:
                            EmptyView()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                if items.count > 1 {
                    Button { index = (min(index, items.count - 1) + 1) % items.count } label: {
                        HStack(spacing: 4) {
                            Text("\(min(index, items.count - 1) + 1)/\(items.count)").monospacedDigit()
                            Image(systemName: "chevron.right")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .frame(minWidth: Theme.minimumHitTarget, minHeight: Theme.minimumHitTarget)
                    }
                    .buttonStyle(.plain)
                    .padding(Theme.Spacing.xs)
                    .accessibilityLabel("Next picture, \(min(index, items.count - 1) + 1) of \(items.count)")
                    .accessibilityIdentifier("place-gallery-next")
                }
            }
            switch current {
            case .lookAround:
                Text("Tap to look around in Apple Maps").font(.caption2).foregroundStyle(Roam.inkMuted)
            case .photo(_, let credit?):
                Text("Photo: \(credit)").font(.caption2).foregroundStyle(Roam.inkMuted)
            default:
                EmptyView()
            }
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
        // "New York" is the state's article, so "New York City" is tried too.
        for title in [name, region.map { "\(name), \($0)" }, country.map { "\(name), \($0)" }, "\(name) City"].compactMap({ $0 }) {
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
    var showsPhoto = true

    @State private var guide: CityGuide?
    @Environment(\.openURL) private var openURL

    var body: some View {
        // A stack, not a Group: a Group with nothing in it yet would never run the task that loads it.
        VStack(spacing: 0) {
            if let guide, !showsPhoto {
                // Under a city's own header: just the blurb, no card or title.
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(guide.extract).font(.subheadline).foregroundStyle(Roam.ink).lineLimit(6)
                    HStack(spacing: Theme.Spacing.s) {
                        Text("From Wikipedia").font(.caption).foregroundStyle(Roam.inkMuted)
                        if let page = guide.pageURL {
                            Button("Read more") { openURL(page) }.font(.caption.weight(.semibold))
                                .accessibilityIdentifier("city-guide-more")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("city-guide")
            } else if let guide {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    if showsPhoto, let photo = guide.photoURL {
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
