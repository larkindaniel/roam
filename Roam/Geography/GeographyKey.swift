import Foundation

/// Canonical geography keys shared with the database (`app_private.city_key`).
enum GeographyKey {
    /// Lowercased, accent-folded, whitespace-collapsed text used in keys and dedup.
    static func normalize(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let mapped = folded.lowercased().map { ch -> Character in
            ch.isLetter || ch.isNumber ? ch : " "
        }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    /// `cc|region|locality`, e.g. `us|oregon|portland`. Nil when there is no valid country or locality,
    /// so remote places count toward their country without inventing a city.
    static func cityKey(countryCode: String?, region: String?, locality: String?) -> String? {
        guard let countryCode, countryCode.count == 2, let locality, !normalize(locality).isEmpty else { return nil }
        return [countryCode.lowercased(), normalize(region ?? ""), normalize(locality)].joined(separator: "|")
    }
}

/// Place identity rules (SPEC R06, D24): provider ID first, else exact normalized
/// name + full address + coordinate rounded to six decimals. Never name alone.
enum PlaceIdentity {
    static func roundedCoordinate(_ value: Double) -> String {
        String(format: "%.6f", (value * 1_000_000).rounded() / 1_000_000)
    }

    static func fallbackKey(name: String, address: String?, latitude: Double, longitude: Double) -> String {
        [GeographyKey.normalize(name), GeographyKey.normalize(address ?? ""), roundedCoordinate(latitude), roundedCoordinate(longitude)]
            .joined(separator: "|")
    }

    /// True only when two candidates denote the same provider place under the dedup rules.
    static func isSamePlace(_ lhs: PlaceCandidate, _ rhs: PlaceCandidate) -> Bool {
        if let l = lhs.providerPlaceID, let r = rhs.providerPlaceID {
            return lhs.provider == rhs.provider && l == r
        }
        // MapKit returns no identifier for localities (Day Trip destinations), so a locality is
        // identified by its canonical city key; same-name localities in other regions stay distinct.
        if lhs.isLocality || rhs.isLocality {
            guard lhs.isLocality, rhs.isLocality,
                  let l = localityKey(lhs), let r = localityKey(rhs) else { return false }
            return l == r
        }
        guard lhs.address?.isEmpty == false, rhs.address?.isEmpty == false else { return false }
        return fallbackKey(name: lhs.name, address: lhs.address, latitude: lhs.latitude, longitude: lhs.longitude)
            == fallbackKey(name: rhs.name, address: rhs.address, latitude: rhs.latitude, longitude: rhs.longitude)
    }

    static func localityKey(_ candidate: PlaceCandidate) -> String? {
        guard candidate.isLocality else { return nil }
        return GeographyKey.cityKey(countryCode: candidate.countryCode, region: candidate.region, locality: candidate.locality ?? candidate.name)
    }
}
