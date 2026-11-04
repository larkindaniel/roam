import Foundation

/// The icon for a place, as detailed as Apple Maps draws it: Apple's own place type (a cup for a café, a wine glass for
/// a winery) when the place came from Apple, else Roam's broader category.
enum PlaceIcon {
    static func symbol(appleType: String?, category: ExperienceCategory?) -> String {
        if let appleType, let symbol = byAppleType[appleType.replacingOccurrences(of: "MKPOICategory", with: "")] { return symbol }
        return category?.symbolName ?? "mappin"
    }

    /// Apple's place types (MKPointOfInterestCategory, without the prefix) to SF Symbols.
    private static let byAppleType: [String: String] = [
        "Airport": "airplane", "AmusementPark": "ferriswheel", "Aquarium": "fish", "ATM": "banknote",
        "Bakery": "birthday.cake", "Bank": "building.columns", "Beach": "beach.umbrella", "Brewery": "mug",
        "Cafe": "cup.and.saucer", "Campground": "tent", "CarRental": "car", "EVCharger": "bolt.car",
        "FireStation": "flame", "FitnessCenter": "dumbbell", "FoodMarket": "basket", "GasStation": "fuelpump",
        "Hospital": "cross.case", "Hotel": "bed.double", "Laundry": "washer", "Library": "books.vertical",
        "Marina": "sailboat", "MovieTheater": "film", "Museum": "building.columns", "NationalPark": "mountain.2",
        "Nightlife": "music.note", "Park": "tree", "Parking": "parkingsign", "Pharmacy": "pills",
        "Police": "shield", "PostOffice": "envelope", "PublicTransport": "tram", "Restaurant": "fork.knife",
        "Restroom": "toilet", "School": "graduationcap", "Stadium": "sportscourt", "Store": "bag",
        "Theater": "theatermasks", "University": "graduationcap", "Winery": "wineglass", "Zoo": "pawprint",
        // Added in iOS 18.
        "AnimalService": "pawprint", "Automotive": "car", "Baseball": "baseball", "Basketball": "basketball",
        "Beauty": "comb", "Bowling": "figure.bowling", "Castle": "building.columns", "ConventionCenter": "person.3",
        "Distillery": "wineglass", "Fairground": "ferriswheel", "Fishing": "fish", "Fortress": "building.columns",
        "Golf": "figure.golf", "GoKart": "car", "Hiking": "figure.hiking", "Kayaking": "figure.water.fitness",
        "Landmark": "star", "MiniGolf": "figure.golf", "MusicVenue": "music.mic", "NationalMonument": "building.columns",
        "Planetarium": "moon.stars", "RockClimbing": "figure.climbing", "RVPark": "bus", "SkatePark": "skateboard",
        "Skating": "figure.skating", "Skiing": "figure.skiing.downhill", "Soccer": "soccerball", "Spa": "sparkles",
        "Surfing": "figure.surfing", "Swimming": "figure.pool.swim", "Tennis": "tennis.racket", "Volleyball": "volleyball",
    ]
}

extension ExperienceSummary {
    var iconName: String { PlaceIcon.symbol(appleType: providerCategory, category: category) }
}

extension PlaceCandidate {
    var iconName: String { PlaceIcon.symbol(appleType: providerCategory, category: suggestedCategory) }
}
