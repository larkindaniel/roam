import MapKit
import XCTest
@testable import Roam

@MainActor
final class M3MapSelectionTests: XCTestCase {
    func testClosingSelectionDeselectsNativePinAndSamePinCanReopen() async {
        let pin = MapPin(id: UUID().uuidString, name: "Selection Café", category: .foodDrink, latitude: 38.72, longitude: -9.14)
        let annotation = ExperiencePinAnnotation(pin: pin)
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        map.addAnnotation(annotation)
        var view = GlobeMapView(pins: [pin], shadedCountryCodes: [], style: .standard, selectedPinID: pin.id)
        let coordinator = view.makeCoordinator()
        coordinator.sync(map: map, with: view)
        XCTAssertTrue(map.selectedAnnotations.contains { ($0 as? ExperiencePinAnnotation)?.pin.id == pin.id })
        view.selectedPinID = nil
        coordinator.sync(map: map, with: view)
        XCTAssertTrue(map.selectedAnnotations.isEmpty)
        view.selectedPinID = pin.id
        coordinator.sync(map: map, with: view)
        XCTAssertTrue(map.selectedAnnotations.contains { ($0 as? ExperiencePinAnnotation)?.pin.id == pin.id })
    }

    func testClusterSelectionZoomsToMembersWithoutSelectingAnExperience() async {
        let pins = [MapPin(id: "west", name: "West", category: .culture, latitude: 38.71, longitude: -9.16),
                    MapPin(id: "east", name: "East", category: .stays, latitude: 38.73, longitude: -9.12)]
        let annotations = pins.map(ExperiencePinAnnotation.init)
        let cluster = MKClusterAnnotation(memberAnnotations: annotations)
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        map.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 38.72, longitude: -9.14), span: MKCoordinateSpan(latitudeDelta: 5, longitudeDelta: 5)), animated: false)
        var selected: String?
        let view = GlobeMapView(pins: pins, shadedCountryCodes: [], style: .standard, onSelectPin: { selected = $0.id })
        view.makeCoordinator().mapView(map, didSelect: cluster)
        // MapKit applies the region animation on its run loop; bound the observation.
        for _ in 0..<40 {
            if map.region.span.latitudeDelta < 1 { break }
            try? await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertLessThan(map.region.span.latitudeDelta, 1)
        XCTAssertNil(selected, "A cluster navigates the viewport; it is not an experience")
    }
}
