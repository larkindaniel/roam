import MapKit
import simd
import SwiftUI

/// A map pin: a visited experience on the globe, or an experience/place in Explore and lists.
struct MapPin: Hashable, Identifiable, Sendable {
    let id: String
    var name: String
    var category: ExperienceCategory?
    var latitude: Double
    var longitude: Double

    init(id: String, name: String, category: ExperienceCategory?, latitude: Double, longitude: Double) {
        self.id = id
        self.name = name
        self.category = category
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ pin: GlobePin) {
        self.init(id: pin.experienceID.uuidString, name: pin.name, category: pin.category, latitude: pin.latitude, longitude: pin.longitude)
    }
}

/// Map annotation for one pin (one pin per Experience).
final class ExperiencePinAnnotation: NSObject, MKAnnotation {
    let pin: MapPin
    let coordinate: CLLocationCoordinate2D

    init(pin: MapPin) {
        self.pin = pin
        self.coordinate = CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude)
    }

    var title: String? { pin.name }
    var subtitle: String? { pin.category?.title }
}

/// A visited place drawn on the 3D globe as an overlay dot (see `GlobeMapView.Coordinator.sync`).
final class PinDotOverlay: NSObject, MKOverlay {
    let pin: MapPin
    var tint: UIColor?
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect

    init(pin: MapPin) {
        self.pin = pin
        coordinate = CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude)
        // Room for the dot at whole-earth zoom, where a few screen points span hundreds of kilometres.
        let center = MKMapPoint(coordinate)
        let half = MKMapPointsPerMeterAtLatitude(pin.latitude) * 1_500_000
        boundingMapRect = MKMapRect(x: center.x - half, y: center.y - half, width: half * 2, height: half * 2).intersection(.world)
    }
}

/// A white-ringed accent dot of constant on-screen size, legible on day and night imagery. Globe
/// overlay tiles are drawn at twice the screen's zoom scale (measured on the iOS 26.2 simulator), so
/// 14 map-render points come out about 7 screen points.
final class PinDotRenderer: MKOverlayRenderer {
    /// Small from the whole-earth view so the dots don't hide where they are, growing as you zoom in.
    var screenRadius: CGFloat = 14

    static func screenRadius(cameraDistance: CLLocationDistance) -> CGFloat {
        cameraDistance > 8_000_000 ? 6 : cameraDistance > 3_000_000 ? 9 : 14
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let dot = overlay as? PinDotOverlay else { return }
        let center = point(for: MKMapPoint(dot.coordinate))
        let bounds = rect(for: dot.boundingMapRect)
        let radius = min(screenRadius / zoomScale, bounds.width / 2, bounds.height / 2)
        let outer = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.setFillColor(UIColor.white.cgColor)
        context.fillEllipse(in: outer)
        context.setFillColor((dot.tint ?? UIColor(named: "AccentColor") ?? .systemTeal).cgColor)
        context.fillEllipse(in: outer.insetBy(dx: radius * 0.28, dy: radius * 0.28))
    }
}

/// Converts between the screen and the Earth on the imagery globe, where MapKit's own conversion uses a flat
/// projection (see `GlobeMapView.Coordinator.sync`). The sphere is centred in the map, above the camera's centre coordinate.
/// MapKit publishes none of this, so its size and position are fitted to dots measured at two map heights on
/// the iOS 26 iPhone 17 simulator. Close up the globe is nearly flat and MapKit's conversion is right.
private struct GlobeProjection {
    private static let earthRadius = 6_371_000.0
    private static let flatDistance: CLLocationDistance = 1_500_000

    private let map: MKMapView
    private let isFlat: Bool
    private let middle: CGPoint
    private let focalLength: Double
    private let distance: Double
    private let heading: Double
    private let facing: SIMD3<Double>
    private let east: SIMD3<Double>
    private let north: SIMD3<Double>

    init(map: MKMapView) {
        self.map = map
        distance = map.camera.centerCoordinateDistance
        isFlat = distance <= Self.flatDistance
        heading = map.camera.heading * .pi / 180
        let height = Double(map.bounds.height)
        middle = CGPoint(x: map.bounds.midX, y: map.bounds.midY)
        focalLength = 0.507 * height + 770
        let focus = map.convert(map.camera.centerCoordinate, toPointTo: map)
        let offset = max(Double(focus.y - middle.y), 0)
        var angle = 0.0
        while angle < .pi / 2, focalLength * Self.earthRadius * sin(angle) / (Self.earthRadius + distance - Self.earthRadius * cos(angle)) < offset { angle += 0.001 }
        let latitude = map.camera.centerCoordinate.latitude * .pi / 180 + angle
        let longitude = map.camera.centerCoordinate.longitude * .pi / 180
        facing = Self.unit(latitude, longitude)
        east = SIMD3(-sin(longitude), cos(longitude), 0)
        north = SIMD3(-sin(latitude) * cos(longitude), -sin(latitude) * sin(longitude), cos(latitude))
    }

    private static func unit(_ latitude: Double, _ longitude: Double) -> SIMD3<Double> {
        SIMD3(cos(latitude) * cos(longitude), cos(latitude) * sin(longitude), sin(latitude))
    }

    /// Nil on the far side of the Earth.
    func point(latitude: Double, longitude: Double) -> CGPoint? {
        if isFlat { return map.convert(CLLocationCoordinate2D(latitude: latitude, longitude: longitude), toPointTo: map) }
        let radius = Self.earthRadius
        let point = Self.unit(latitude * .pi / 180, longitude * .pi / 180)
        guard simd_dot(point, facing) > radius / (radius + distance) else { return nil }
        let scale = focalLength * radius / (radius + distance - radius * simd_dot(point, facing))
        let right = simd_dot(point, east) * scale, up = simd_dot(point, north) * scale
        return CGPoint(x: middle.x + right * cos(heading) - up * sin(heading), y: middle.y - right * sin(heading) - up * cos(heading))
    }

    /// Nil off the edge of the Earth.
    func coordinate(at point: CGPoint) -> CLLocationCoordinate2D? {
        if isFlat { return map.convert(point, toCoordinateFrom: map) }
        let x = Double(point.x - middle.x), y = Double(middle.y - point.y)
        let right = x * cos(heading) - y * sin(heading), up = x * sin(heading) + y * cos(heading)
        let radius = Self.earthRadius
        let ray = simd_normalize(east * (right / focalLength) + north * (up / focalLength) - facing)
        let camera = facing * (radius + distance)
        let along = simd_dot(camera, ray)
        let discriminant = along * along - simd_dot(camera, camera) + radius * radius
        guard discriminant >= 0 else { return nil }
        let surface = simd_normalize(camera + ray * (-along - discriminant.squareRoot()))
        return CLLocationCoordinate2D(latitude: asin(surface.z) * 180 / .pi, longitude: atan2(surface.y, surface.x) * 180 / .pi)
    }
}

/// UIKit-backed map used for the profile globe and Explore. SwiftUI `Map` cannot cluster
/// annotations, so an MKMapView wrapper provides clustering, cluster zoom, pin selection and
/// country polygon shading while the app structure stays SwiftUI.
struct GlobeMapView: UIViewRepresentable {
    enum Style: Equatable {
        /// Zoomed-out 3D globe with realistic elevation.
        case globe
        /// Flat standard map for city-scale browsing.
        case standard
    }

    var pins: [MapPin]
    var shadedCountryCodes: Set<String>
    var style: Style = .globe
    var interactive = true
    var selectedPinID: String?
    /// Region to show when `focusToken` changes; nil keeps the user's camera.
    var focusRegion: MKCoordinateRegion?
    var focusToken: Int = 0
    var onSelectPin: ((MapPin) -> Void)?
    var onRegionChange: ((MKCoordinateRegion) -> Void)?
    /// Where the globe first faces; nil uses `startCenter`.
    var globeCenter: CLLocationCoordinate2D?
    /// Colours by ISO country code for shaded countries, and by pin id for globe dots. Missing entries use the default look.
    var countryTints: [String: UIColor] = [:]
    var pinTints: [String: UIColor] = [:]
    var onSelectCountry: ((String) -> Void)?
    /// When set, Apple Maps' own places on a standard map can be tapped, and report their listing here.
    var onSelectMapFeature: ((MKMapItem) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: Coordinator.pinReuse)
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: Coordinator.clusterReuse)
        map.showsUserLocation = false
        map.pointOfInterestFilter = style == .globe ? .excludingAll : .includingAll
        if style == .standard, onSelectMapFeature != nil { map.selectableMapFeatures = [.pointsOfInterest] }
        map.isRotateEnabled = interactive
        map.isPitchEnabled = false
        map.isScrollEnabled = interactive
        map.isZoomEnabled = interactive
        map.isUserInteractionEnabled = interactive
        map.accessibilityIdentifier = style == .globe ? "globe-map" : "map-view"
        switch style {
        case .globe:
            // MapKit only draws the zoomed-out 3D globe for imagery-based configurations; standard
            // styling stays a flat projection (verified on the iOS 26.2 simulator in M1).
            map.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .realistic)
        case .standard:
            map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .realistic, emphasisStyle: .default)
        }
        if style == .globe {
            let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleGlobeTap(_:)))
            map.addGestureRecognizer(tap)
        }
        context.coordinator.lastFocusToken = focusToken
        context.coordinator.sync(map: map, with: self)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sync(map: map, with: self)
        context.coordinator.applyInitialCameraIfNeeded(map)
        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            if style == .globe, focusRegion == nil {
                // Back to the starting view of the whole Earth.
                map.setCamera(MKMapCamera(lookingAtCenter: globeCenter ?? Self.startCenter, fromDistance: 20_000_000, pitch: 0, heading: 0),
                              animated: !UIAccessibility.isReduceMotionEnabled)
            } else if let focusRegion {
                map.setRegion(focusRegion, animated: !UIAccessibility.isReduceMotionEnabled)
            }
        }
    }

    static let startCenter = CLLocationCoordinate2D(latitude: 25, longitude: 10)

    /// A region that frames the pins (used by list and Shared Wishlist maps). A phone-sized flat map
    /// cannot zoom out far enough for places on opposite sides of the world, so a spread-out set
    /// frames its densest group instead of opening on empty ocean; the others are a pan away and
    /// the list view always shows every place.
    static func region(fitting pins: [MapPin]) -> MKCoordinateRegion? {
        guard !pins.isEmpty else { return nil }
        let lats = pins.map(\.latitude), lons = pins.map(\.longitude)
        if lats.max()! - lats.min()! <= 100, lons.max()! - lons.min()! <= 120 {
            let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2)
            let span = MKCoordinateSpan(latitudeDelta: max(0.05, (lats.max()! - lats.min()!) * 1.4),
                                        longitudeDelta: max(0.05, (lons.max()! - lons.min()!) * 1.4))
            return MKCoordinateRegion(center: center, span: span)
        }
        func near(_ a: MapPin, _ b: MapPin) -> Bool {
            let lon = abs(a.longitude - b.longitude)
            return abs(a.latitude - b.latitude) <= 50 && min(lon, 360 - lon) <= 60
        }
        // Stable choice: the first pin with the most neighbours.
        var best = pins[0], bestCount = 0
        for pin in pins {
            let count = pins.filter { near(pin, $0) }.count
            if count > bestCount { best = pin; bestCount = count }
        }
        let group = pins.filter { near(best, $0) && abs($0.longitude - best.longitude) <= 180 }
        guard var region = region(fitting: group) else { return nil }
        region.span.latitudeDelta = max(region.span.latitudeDelta, 30)
        region.span.longitudeDelta = max(region.span.longitudeDelta, 30)
        return region
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        static let pinReuse = "roam.pin"
        static let clusterReuse = "roam.cluster"

        var parent: GlobeMapView
        var lastFocusToken = 0
        private var didApplyInitialCamera = false

        /// The camera is applied once the map has a real size; setting it on a zero-sized map
        /// left globe annotations unrendered on the iOS 26.2 simulator.
        func applyInitialCameraIfNeeded(_ map: MKMapView) {
            guard !didApplyInitialCamera else { return }
            guard map.bounds.width > 0, map.bounds.height > 0 else {
                DispatchQueue.main.async { [weak self, weak map] in
                    guard let self, let map else { return }
                    self.applyInitialCameraIfNeeded(map)
                }
                return
            }
            didApplyInitialCamera = true
            switch parent.style {
            case .globe:
                map.camera = MKMapCamera(lookingAtCenter: parent.globeCenter ?? GlobeMapView.startCenter, fromDistance: 20_000_000, pitch: 0, heading: 0)
            case .standard:
                if let region = parent.focusRegion { map.setRegion(region, animated: false) }
            }
            // Annotation views added before a camera change kept stale screen positions on the
            // 3D globe (iOS 26.2 simulator), so (re)add them after the camera is in place.
            DispatchQueue.main.async { [weak self, weak map] in
                guard let self, let map else { return }
                self.cameraReady = true
                self.currentPins = []
                self.sync(map: map, with: self.parent)
            }
        }

        private var cameraReady = false
        fileprivate var currentPins: [MapPin] = []
        private var currentShaded: Set<String> = []
        private var currentCountryTints: [String: UIColor] = [:]
        private var currentPinTints: [String: UIColor] = [:]
        private var countryOverlays: [MKOverlay] = []
        private var pinOverlays: [MKOverlay] = []

        init(parent: GlobeMapView) {
            self.parent = parent
        }

        func sync(map: MKMapView, with view: GlobeMapView) {
            if view.style == .globe {
                // On the imagery globe MapKit places annotation views (and converts points) with a flat
                // projection, so markers land in the wrong place or vanish (iOS 26.2 simulator, M1/M7
                // probes). Overlays are projected onto the globe correctly, so globe pins are dots.
                // Selecting a pin happens on the flat map or in the list.
                if view.pins != currentPins || view.pinTints != currentPinTints {
                    map.removeOverlays(pinOverlays)
                    pinOverlays = view.pins.map { pin in
                        let dot = PinDotOverlay(pin: pin)
                        dot.tint = view.pinTints[pin.id]
                        return dot
                    }
                    currentPinTints = view.pinTints
                    map.addOverlays(pinOverlays, level: .aboveLabels)
                    currentPins = view.pins
                }
            } else if cameraReady, view.pins != currentPins {
                let existing = map.annotations.compactMap { $0 as? ExperiencePinAnnotation }
                map.removeAnnotations(existing)
                map.addAnnotations(view.pins.map(ExperiencePinAnnotation.init(pin:)))
                currentPins = view.pins
            }
            if view.shadedCountryCodes != currentShaded || view.countryTints != currentCountryTints {
                currentCountryTints = view.countryTints
                map.removeOverlays(countryOverlays)
                countryOverlays = CountryGeometry.shared.polygons(for: view.shadedCountryCodes)
                map.addOverlays(countryOverlays, level: .aboveRoads)
                currentShaded = view.shadedCountryCodes
            }
            for annotation in map.selectedAnnotations {
                if let pin = annotation as? ExperiencePinAnnotation, pin.pin.id != view.selectedPinID {
                    map.deselectAnnotation(annotation, animated: false)
                }
            }
            if let selected = view.selectedPinID,
               let annotation = map.annotations.compactMap({ $0 as? ExperiencePinAnnotation }).first(where: { $0.pin.id == selected }),
               !map.selectedAnnotations.contains(where: { ($0 as? ExperiencePinAnnotation)?.pin.id == selected }) {
                map.selectAnnotation(annotation, animated: false)
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let cluster = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: Self.clusterReuse, for: cluster) as? MKMarkerAnnotationView
                view?.markerTintColor = UIColor(named: "AccentColor") ?? .systemTeal
                view?.glyphText = "\(cluster.memberAnnotations.count)"
                view?.displayPriority = .required
                view?.accessibilityLabel = "\(cluster.memberAnnotations.count) places. Double tap to zoom in."
                return view
            }
            guard let pinAnnotation = annotation as? ExperiencePinAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: Self.pinReuse, for: pinAnnotation) as? MKMarkerAnnotationView
            view?.clusteringIdentifier = "roam.experiences"
            view?.markerTintColor = UIColor(named: "AccentColor") ?? .systemTeal
            view?.glyphImage = UIImage(systemName: pinAnnotation.pin.category?.symbolName ?? "mappin")
            view?.displayPriority = .required
            view?.titleVisibility = .adaptive
            view?.accessibilityLabel = [pinAnnotation.pin.name, pinAnnotation.pin.category?.title].compactMap { $0 }.joined(separator: ", ")
            view?.accessibilityIdentifier = "map-pin-\(pinAnnotation.pin.name)"
            return view
        }

        /// Opens the dot under a tap, or else the country under it. Dots close together zoom in to separate them first.
        @objc func handleGlobeTap(_ tap: UITapGestureRecognizer) {
            guard let map = tap.view as? MKMapView else { return }
            let location = tap.location(in: map)
            let projection = GlobeProjection(map: map)
            let hits = parent.pins.compactMap { pin -> (pin: MapPin, distance: CGFloat)? in
                guard let point = projection.point(latitude: pin.latitude, longitude: pin.longitude) else { return nil }
                let distance = hypot(point.x - location.x, point.y - location.y)
                return distance <= Self.globeHitRadius ? (pin, distance) : nil
            }.sorted { $0.distance < $1.distance }
            guard let nearest = hits.first?.pin else {
                if let coordinate = projection.coordinate(at: location),
                   let code = CountryGeometry.shared.code(at: coordinate, among: Set(CountryGeometry.shared.allCodes)) {
                    parent.onSelectCountry?(code)
                }
                return
            }
            let cameraDistance = map.camera.centerCoordinateDistance
            guard hits.count > 1, cameraDistance > Self.closestGlobeZoom else {
                parent.onSelectPin?(nearest)
                return
            }
            let locations = hits.map { CLLocation(latitude: $0.pin.latitude, longitude: $0.pin.longitude) }
            let spread = locations.map { $0.distance(from: locations[0]) }.max() ?? 0
            let center = CLLocationCoordinate2D(latitude: locations.map(\.coordinate.latitude).reduce(0, +) / Double(locations.count),
                                                longitude: locations.map(\.coordinate.longitude).reduce(0, +) / Double(locations.count))
            let camera = MKMapCamera(lookingAtCenter: center, fromDistance: min(cameraDistance / 3, max(spread * 3, Self.closestGlobeZoom)), pitch: 0, heading: 0)
            map.setCamera(camera, animated: !UIAccessibility.isReduceMotionEnabled)
        }

        private static let globeHitRadius: CGFloat = 30
        private static let closestGlobeZoom: CLLocationDistance = 30_000

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            if let feature = annotation as? MKMapFeatureAnnotation {
                Task { @MainActor in
                    if let item = try? await MKMapItemRequest(mapFeatureAnnotation: feature).mapItem { self.parent.onSelectMapFeature?(item) }
                }
                return
            }
            if let cluster = annotation as? MKClusterAnnotation {
                mapView.deselectAnnotation(cluster, animated: false)
                mapView.showAnnotations(cluster.memberAnnotations, animated: !UIAccessibility.isReduceMotionEnabled)
                return
            }
            if let pinAnnotation = annotation as? ExperiencePinAnnotation {
                parent.onSelectPin?(pinAnnotation.pin)
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let dot = overlay as? PinDotOverlay {
                let renderer = PinDotRenderer(overlay: dot)
                renderer.screenRadius = dotRadius
                return renderer
            }
            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                style(renderer, code: polygon.title)
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        /// Countries are filled only from far enough out to see whole countries; closer in, the map is left clear.
        private static let countryLevelDistance: CLLocationDistance = 1_200_000
        private var showsCountries = true
        private var dotRadius: CGFloat = PinDotRenderer.screenRadius(cameraDistance: 20_000_000)

        private func style(_ renderer: MKPolygonRenderer, code: String?) {
            guard showsCountries else {
                renderer.fillColor = .clear
                renderer.strokeColor = .clear
                return
            }
            if let code, let tint = parent.countryTints[code] {
                renderer.fillColor = tint.withAlphaComponent(0.5)
                renderer.strokeColor = tint
                renderer.lineWidth = 1.5
                return
            }
            // Bright fill + white outline stays legible on daylit and night-side imagery.
            renderer.fillColor = UIColor(red: 0.93, green: 0.925, blue: 0.898, alpha: 0.55)
            renderer.strokeColor = UIColor.white.withAlphaComponent(0.95)
            renderer.lineWidth = 1.2
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            let distance = mapView.camera.centerCoordinateDistance
            let radius = PinDotRenderer.screenRadius(cameraDistance: distance)
            let countries = distance > Self.countryLevelDistance
            guard radius != dotRadius || countries != showsCountries else { return }
            let restyleCountries = countries != showsCountries
            dotRadius = radius
            showsCountries = countries
            for overlay in mapView.overlays {
                if let renderer = mapView.renderer(for: overlay) as? PinDotRenderer, renderer.screenRadius != radius {
                    renderer.screenRadius = radius
                    renderer.setNeedsDisplay()
                } else if restyleCountries, let polygon = overlay as? MKPolygon, let renderer = mapView.renderer(for: polygon) as? MKPolygonRenderer {
                    style(renderer, code: polygon.title)
                    renderer.setNeedsDisplay()
                }
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.onRegionChange?(mapView.region)
        }
    }
}

extension View {
    /// Presents a hosted MapKit view as one labelled accessibility element. Enumerating MapKit's
    /// own accessibility children hid every sibling control from VoiceOver/XCUITest on the
    /// iOS 26.2 simulator; pins remain reachable through each screen's List view.
    func mapAccessibility(_ label: String, identifier: String) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isImage)
            .accessibilityIdentifier(identifier)
    }
}
