import Foundation

/// The seven independent Roam rankings. Raw values match the database enum.
enum ExperienceCategory: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case foodDrink = "food_drink"
    case outdoors
    case dayTrips = "day_trips"
    case culture
    case nightlife
    case activities
    case stays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .foodDrink: return "Food & Drink"
        case .outdoors: return "Outdoors"
        case .dayTrips: return "Day Trips"
        case .culture: return "Culture"
        case .nightlife: return "Nightlife"
        case .activities: return "Activities"
        case .stays: return "Stays"
        }
    }

    var symbolName: String {
        switch self {
        case .foodDrink: return "fork.knife"
        case .outdoors: return "mountain.2"
        case .dayTrips: return "signpost.right"
        case .culture: return "building.columns"
        case .nightlife: return "moon.stars"
        case .activities: return "figure.walk"
        case .stays: return "bed.double"
        }
    }

    /// Lower-case noun phrase used inside sentences ("your Outdoors list").
    var listPhrase: String { "\(title) list" }
}

/// How a member felt about an experience; selects the score band and partition.
enum Sentiment: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case liked
    case fine
    case disliked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .liked: return "I liked it"
        case .fine: return "It was fine"
        case .disliked: return "I didn't like it"
        }
    }

    var shortTitle: String {
        switch self {
        case .liked: return "Liked"
        case .fine: return "Fine"
        case .disliked: return "Didn't like"
        }
    }

    var symbolName: String {
        switch self {
        case .liked: return "hand.thumbsup.fill"
        case .fine: return "equal.circle.fill"
        case .disliked: return "hand.thumbsdown.fill"
        }
    }

    /// Partition order, best first.
    var order: Int {
        switch self {
        case .liked: return 0
        case .fine: return 1
        case .disliked: return 2
        }
    }

    /// Score band in tenths of a point: liked 6.7–10.0, fine 3.4–6.6, disliked 0.0–3.3.
    var boundsInTenths: (low: Int, high: Int) {
        switch self {
        case .liked: return (67, 100)
        case .fine: return (34, 66)
        case .disliked: return (0, 33)
        }
    }

    static let partitionOrder: [Sentiment] = [.liked, .fine, .disliked]
}
