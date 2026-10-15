import Foundation

/// Plain text for the native share sheet (S17). Only public values: no private notes, email,
/// settings, report/block data or draft assets, and no profile link (Roam has no hosted pages).
enum ShareText {
    /// "Harbor Lantern Café — Food & Drink · Lisbon, Portugal", then the sharer's own current
    /// score (labelled, only when they rated it) and an Apple Maps link.
    static func experience(_ summary: ExperienceSummary, ownRating: MyRating?) -> String {
        var lines = [summary.name]
        let category = ownRating?.category ?? summary.category
        let place = [category?.title, summary.areaLine.isEmpty ? nil : summary.areaLine].compactMap { $0 }.joined(separator: " · ")
        if !place.isEmpty { lines.append(place) }
        if let ownRating {
            lines.append("My Roam score: \(ownRating.score.formatted)/10 in \(ownRating.category.title)")
        }
        lines.append(appleMapsURL(name: summary.name, latitude: summary.latitude, longitude: summary.longitude).absoluteString)
        return lines.joined(separator: "\n")
    }

    /// "Maya Chen (@mayaroams) on Roam" and their public travel totals.
    static func profile(displayName: String, handle: String, countryCount: Int, cityCount: Int) -> String {
        let countries = "\(countryCount) \(countryCount == 1 ? "country" : "countries")"
        let cities = "\(cityCount) \(cityCount == 1 ? "city" : "cities")"
        return "\(displayName) (@\(handle)) on Roam\nVisited \(countries) · \(cities)"
    }

    /// A real Apple Maps URL that drops a labelled pin at the place's coordinate.
    static func appleMapsURL(name: String, latitude: Double, longitude: Double) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "maps.apple.com"
        components.path = "/"
        components.queryItems = [
            URLQueryItem(name: "q", value: name),
            URLQueryItem(name: "ll", value: String(format: "%.6f,%.6f", latitude, longitude)),
        ]
        return components.url!
    }
}
