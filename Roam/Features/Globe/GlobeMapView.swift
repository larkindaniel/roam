import MapKit
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

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: Coordinator.pinReuse)
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: Coordinator.clusterReuse)
        map.showsUserLocation = false
        map.pointOfInterestFilter = style == .globe ? .excludingAll : .includingAll
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
            map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        }
        context.coordinator.lastFocusToken = focusToken
        context.coordinator.sync(map: map, with: self)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sync(map: map, with: self)
        context.coordinator.applyInitialCameraIfNeeded(map)
        if context.coordinator.lastFocusToken != focusToken, let focusRegion {
            context.coordinator.lastFocusToken = focusToken
            map.setRegion(focusRegion, animated: !UIAccessibility.isReduceMotionEnabled)
        }
    }

    static let startCenter = CLLocationCoordinate2D(latitude: 25, longitude: 10)

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
                // Known limitation (iOS 26.2 simulator, M1): imagery-globe annotation views only rendered
                // with this whole-earth starting camera; re-centred cameras hid them. Members can rotate,
                // switch to the flat map, or use the list alternative. Revisit in M8.
                map.camera = MKMapCamera(lookingAtCenter: GlobeMapView.startCenter, fromDistance: 20_000_000, pitch: 0, heading: 0)
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

        init(parent: GlobeMapView) {
            self.parent = parent
        }

        func sync(map: MKMapView, with view: GlobeMapView) {
            if cameraReady, view.pins != currentPins {
                let existing = map.annotations.compactMap { $0 as? ExperiencePinAnnotation }
                map.removeAnnotations(existing)
                map.addAnnotations(view.pins.map(ExperiencePinAnnotation.init(pin:)))
                currentPins = view.pins
            }
            if view.shadedCountryCodes != currentShaded {
                map.removeOverlays(map.overlays)
                let polygons = CountryGeometry.shared.polygons(for: view.shadedCountryCodes)
                map.addOverlays(polygons, level: .aboveRoads)
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
                view?.accessibilityLabel = "\(cluster.memberAnnotations.count) experiences. Double tap to zoom in."
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

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
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
            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                let teal = UIColor(named: "AccentColor") ?? .systemTeal
                // Bright fill + white outline stays legible on daylit and night-side imagery.
                renderer.fillColor = UIColor(red: 0.20, green: 0.85, blue: 0.78, alpha: 0.55)
                renderer.strokeColor = UIColor.white.withAlphaComponent(0.95)
                renderer.lineWidth = 1.2
                _ = teal
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
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
