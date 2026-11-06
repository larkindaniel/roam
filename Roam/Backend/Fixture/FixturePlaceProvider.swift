#if ROAM_FIXTURES
import CoreLocation
import Foundation
import MapKit
import UIKit

/// Test-only place provider over the fictional catalogue. Never used by Release builds,
/// whose places always come from MapKit.
final class FixturePlaceProvider: PlaceSearchProviding, @unchecked Sendable {
    private let catalog: FixturePlaceCatalog
    private let latency: UInt64
    /// Per-query artificial delays (milliseconds) for search-race tests.
    private let queryDelays: [String: Int]

    init(catalog: FixturePlaceCatalog, latencyMilliseconds: Int, queryDelays: [String: Int] = [:]) {
        self.catalog = catalog
        self.latency = UInt64(max(0, latencyMilliseconds)) * 1_000_000
        self.queryDelays = queryDelays
    }

    private func wait(for query: String) async throws {
        let extra = queryDelays[query.lowercased()].map { UInt64($0) * 1_000_000 } ?? 0
        let total = latency + extra
        if total > 0 { try await Task.sleep(nanoseconds: total) }
        try Task.checkCancellation()
    }

    func searchPlaces(query: String, around destination: Destination?) async throws -> [PlaceCandidate] {
        try await wait(for: query)
        let needle = GeographyKey.normalize(query)
        guard !needle.isEmpty else { return [] }
        if needle == "offline" { throw RoamError.offline }
        let matches = catalog.candidates.values.filter {
            GeographyKey.normalize($0.name).contains(needle) || GeographyKey.normalize($0.locality ?? "").contains(needle)
                || GeographyKey.normalize($0.suggestedCategory?.title ?? "").contains(needle)
        }
        return sort(matches, near: destination)
    }

    func searchDestinations(query: String) async throws -> [Destination] {
        try await wait(for: query)
        let needle = GeographyKey.normalize(query)
        guard !needle.isEmpty else { return [] }
        return catalog.destinations.filter { GeographyKey.normalize($0.name).hasPrefix(needle) || GeographyKey.normalize($0.displayName).contains(needle) }
    }

    func pointsOfInterest(in region: MKCoordinateRegion, category: ExperienceCategory?) async throws -> [PlaceCandidate] {
        try await wait(for: "")
        let bounds = GeoBounds(region: region)
        let matches = catalog.candidates.values.filter { candidate in
            bounds.contains(latitude: candidate.latitude, longitude: candidate.longitude)
                && (category == nil || candidate.suggestedCategory == category)
        }
        return sort(Array(matches), near: nil)
    }

    func destination(for coordinate: CLLocationCoordinate2D) async throws -> Destination? {
        try await wait(for: "")
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return catalog.destinations.min {
            location.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
                < location.distance(from: CLLocation(latitude: $1.latitude, longitude: $1.longitude))
        }
    }

    private func sort(_ candidates: [PlaceCandidate], near destination: Destination?) -> [PlaceCandidate] {
        guard let destination else { return candidates.sorted { ($0.name, $0.address ?? "") < ($1.name, $1.address ?? "") } }
        let origin = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        return candidates.sorted {
            origin.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
                < origin.distance(from: CLLocation(latitude: $1.latitude, longitude: $1.longitude))
        }
    }
}

/// Original generated artwork for fixture visit photos (no stock or captured imagery).
enum FixtureArtwork {
    static func photo(hue: Double, seed: Int) -> Data {
        let size = CGSize(width: 800, height: 600)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let top = UIColor(hue: hue, saturation: 0.45, brightness: 0.95, alpha: 1)
            let bottom = UIColor(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.65, brightness: 0.55, alpha: 1)
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            // Simple layered "hills" so photos are distinguishable.
            for layer in 0..<3 {
                let path = UIBezierPath()
                let base = size.height * (0.55 + CGFloat(layer) * 0.12)
                path.move(to: CGPoint(x: 0, y: size.height))
                path.addLine(to: CGPoint(x: 0, y: base))
                let wobble = CGFloat((seed >> (layer * 3)) & 0x3F) + 30
                path.addCurve(to: CGPoint(x: size.width, y: base - 20), controlPoint1: CGPoint(x: size.width * 0.3, y: base - wobble),
                              controlPoint2: CGPoint(x: size.width * 0.7, y: base + wobble / 2))
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                UIColor(white: 0.1, alpha: 0.18 + Double(layer) * 0.1).setFill()
                path.fill()
            }
            UIColor(white: 1, alpha: 0.85).setFill()
            UIBezierPath(ovalIn: CGRect(x: size.width * 0.72, y: size.height * 0.16, width: 70, height: 70)).fill()
        }
        return image.jpegData(compressionQuality: 0.8) ?? Data()
    }
}
#endif
