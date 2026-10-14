import Foundation
import MapKit

/// One country's polygons from the bundled Natural Earth 1:110m dataset (public domain, v5.1.2).
struct CountryShape: @unchecked Sendable {
    let isoCode: String
    let name: String
    let polygons: [MKPolygon]
}

/// Loads bundled low-resolution country geometry keyed by ISO 3166-1 alpha-2 code
/// (Natural Earth `ISO_A2_EH`, which assigns codes such as FR and NO that `ISO_A2` omits).
final class CountryGeometry: @unchecked Sendable {
    static let shared = CountryGeometry()

    static let sourceDescription = "Natural Earth 1:110m Admin 0 Countries v5.1.2 (public domain)"

    private let lock = NSLock()
    private var shapes: [String: CountryShape]?

    init(bundle: Bundle = .main, resource: String = "countries-110m") {
        self.bundle = bundle
        self.resource = resource
    }

    private let bundle: Bundle
    private let resource: String

    func shape(for isoCode: String) -> CountryShape? {
        loadIfNeeded()[isoCode.uppercased()]
    }

    var allCodes: [String] { Array(loadIfNeeded().keys).sorted() }

    /// Shaded polygons for visited countries. Unknown codes return nothing (pin without shading).
    func polygons(for isoCodes: Set<String>) -> [MKPolygon] {
        isoCodes.compactMap { shape(for: $0) }.flatMap(\.polygons)
    }

    @discardableResult
    private func loadIfNeeded() -> [String: CountryShape] {
        lock.lock()
        defer { lock.unlock() }
        if let shapes { return shapes }
        var result: [String: CountryShape] = [:]
        if let url = bundle.url(forResource: resource, withExtension: "geojson"),
           let data = try? Data(contentsOf: url),
           let objects = try? MKGeoJSONDecoder().decode(data) {
            for case let feature as MKGeoJSONFeature in objects {
                guard let propertyData = feature.properties,
                      let properties = try? JSONSerialization.jsonObject(with: propertyData) as? [String: Any],
                      let code = (properties["iso_a2"] as? String)?.uppercased(), code.count == 2 else { continue }
                let name = properties["name"] as? String ?? code
                var polygons: [MKPolygon] = []
                for geometry in feature.geometry {
                    if let polygon = geometry as? MKPolygon { polygons.append(polygon) }
                    if let multi = geometry as? MKMultiPolygon { polygons.append(contentsOf: multi.polygons) }
                }
                for polygon in polygons { polygon.title = code }
                result[code] = CountryShape(isoCode: code, name: name, polygons: polygons)
            }
        }
        shapes = result
        return result
    }

    /// Longitude span of a polygon's points; > 180 would mean a ring wrapped the wrong way round
    /// the antimeridian and would smear across the globe.
    static func longitudeSpan(of polygon: MKPolygon) -> Double {
        let points = polygon.points()
        var minLon = 180.0
        var maxLon = -180.0
        for index in 0..<polygon.pointCount {
            let coordinate = points[index].coordinate
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        return maxLon - minLon
    }
}
