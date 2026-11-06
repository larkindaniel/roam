#if ROAM_FIXTURES
import Foundation

/// Builds the initial fixture tables for a scenario.
struct FixtureState {
    typealias B = FixtureBackend
    var members: [UUID: B.Member] = [:]
    var places: [UUID: B.PlaceRow] = [:]
    var experiences: [UUID: B.ExperienceRow] = [:]
    var visits: [UUID: B.VisitRow] = [:]
    var ratings: [UUID: B.RatingRow] = [:]
    var bookmarks: [B.Pair: Date] = [:]
    var media: [UUID: B.MediaRow] = [:]
    var activities: [UUID: B.ActivityRow] = [:]
    var follows: [B.Pair: Date] = [:]
    var friendRequests: [B.Pair: Date] = [:]
    var likes: [B.Pair: Date] = [:]
    var comments: [UUID: B.CommentRow] = [:]
    var notifications: [UUID: B.NotificationRow] = [:]
    var revisions: [String: Int] = [:]

    private var counter = 0

    mutating func nextID(_ kind: Int) -> UUID {
        counter += 1
        return FixtureIDs.uuid(kind, counter)
    }

    mutating func seed(scenario: String, catalog: FixturePlaceCatalog) {
        let cities = Dictionary(uniqueKeysWithValues: catalog.destinations.map { ($0.id, $0) })
        for seed in FixtureSeed.members {
            members[seed.id] = B.Member(id: seed.id, handle: seed.handle, displayName: seed.displayName, bio: seed.bio, email: seed.email,
                                        password: FixtureSeed.password, avatarPath: nil, homeCity: seed.homeCityKey.flatMap { cities[$0] },
                                        setupCheckpoint: .complete, hasSeenBeenIntro: true, createdAt: seed.joined,
                                        emailConfirmed: true, providers: [.email])
        }
        members[FixtureIDs.newcomer] = B.Member(id: FixtureIDs.newcomer, handle: nil, displayName: nil, bio: "", email: "newcomer@roam.test",
                                                password: FixtureSeed.password, avatarPath: nil, homeCity: nil, setupCheckpoint: nil,
                                                hasSeenBeenIntro: false, createdAt: FixtureSeed.referenceDate, emailConfirmed: true, providers: [.email])
        if scenario == "empty" || scenario == "new-account" { return }

        func experienceID(for key: String) -> UUID {
            let candidate = catalog.candidate(key: key)!
            if let existing = places.values.first(where: { $0.candidate.providerPlaceID == candidate.providerPlaceID }) {
                return experiences.values.first { $0.placeID == existing.id }!.id
            }
            let placeID = nextID(20)
            let expID = nextID(30)
            places[placeID] = B.PlaceRow(id: placeID, candidate: candidate, status: .active)
            experiences[expID] = B.ExperienceRow(id: expID, placeID: placeID, category: candidate.suggestedCategory, categoryLocked: false,
                                                 createdAt: FixtureSeed.daysAgo(800))
            return expID
        }

        // Ratings + their first visits + rating activity
        var ratingActivity: [(UUID, Double)] = []
        for seed in FixtureSeed.ratings {
            let expID = experienceID(for: seed.place)
            let category = catalog.candidate(key: seed.place)!.suggestedCategory!
            experiences[expID]?.category = category
            experiences[expID]?.categoryLocked = true
            let ratingID = nextID(40)
            let published = FixtureSeed.daysAgo(seed.publishedDaysAgo)
            ratings[ratingID] = B.RatingRow(id: ratingID, owner: seed.owner, experience: expID, category: category, sentiment: seed.sentiment,
                                            group: seed.group, firstRatedAt: published, updatedAt: published)
            let visitID = nextID(50)
            var mediaIDs: [UUID] = []
            for index in 0..<seed.photos {
                let mediaID = nextID(60)
                media[mediaID] = B.MediaRow(id: mediaID, owner: seed.owner, visit: visitID, purpose: .visit,
                                            path: "fixture/\(seed.owner.uuidString.lowercased())/\(mediaID.uuidString.lowercased()).jpg",
                                            width: 1600, height: 1200, position: index, attached: true, createdAt: published, data: nil,
                                            seedHue: Double((counter * 37) % 100) / 100)
                mediaIDs.append(mediaID)
            }
            visits[visitID] = B.VisitRow(id: visitID, owner: seed.owner, experience: expID, date: seed.visitDate.flatMap(LocalDate.init(isoString:)),
                                         timeZone: catalog.candidate(key: seed.place)?.timeZoneIdentifier, note: seed.note, mediaIDs: mediaIDs,
                                         createdAt: published, updatedAt: published)
            let activityID = nextID(70)
            activities[activityID] = B.ActivityRow(id: activityID, author: seed.owner, type: .rating, experience: expID, visit: visitID,
                                                   rating: ratingID, category: category, score: nil, rank: nil, sentiment: seed.sentiment,
                                                   publishedAt: published)
            ratingActivity.append((activityID, seed.publishedDaysAgo))
            let key = "\(seed.owner.uuidString)|\(category.rawValue)"
            revisions[key, default: 0] += 1
        }
        // Score snapshots as computed at seed time.
        for (activityID, _) in ratingActivity {
            guard let row = activities[activityID], let ratingID = row.rating, let rating = ratings[ratingID] else { continue }
            let ranking = rankingSnapshot(owner: rating.owner, category: rating.category)
            if let placement = ranking.placement(forExperience: rating.experience) {
                activities[activityID]?.score = placement.score
                activities[activityID]?.rank = placement.rank
            }
        }
        for seed in FixtureSeed.repeatVisits {
            let expID = experienceID(for: seed.place)
            let visitID = nextID(50)
            let published = FixtureSeed.daysAgo(seed.publishedDaysAgo)
            visits[visitID] = B.VisitRow(id: visitID, owner: seed.owner, experience: expID, date: LocalDate(isoString: seed.date),
                                         timeZone: catalog.candidate(key: seed.place)?.timeZoneIdentifier, note: seed.note, mediaIDs: [],
                                         createdAt: published, updatedAt: published)
            if let rating = ratings.values.first(where: { $0.owner == seed.owner && $0.experience == expID }) {
                let placement = rankingSnapshot(owner: seed.owner, category: rating.category).placement(forExperience: expID)
                let activityID = nextID(70)
                activities[activityID] = B.ActivityRow(id: activityID, author: seed.owner, type: .revisit, experience: expID, visit: visitID,
                                                       rating: rating.id, category: rating.category, score: placement?.score,
                                                       rank: placement?.rank, sentiment: rating.sentiment, publishedAt: published)
            }
        }
        for seed in FixtureSeed.unrankedVisits {
            let expID = experienceID(for: seed.place)
            experiences[expID]?.categoryLocked = true
            let visitID = nextID(50)
            visits[visitID] = B.VisitRow(id: visitID, owner: seed.owner, experience: expID, date: seed.date.flatMap(LocalDate.init(isoString:)),
                                         timeZone: nil, note: seed.note, mediaIDs: [], createdAt: FixtureSeed.daysAgo(270),
                                         updatedAt: FixtureSeed.daysAgo(270))
        }
        for seed in FixtureSeed.bookmarks {
            bookmarks[B.Pair(a: seed.owner, b: experienceID(for: seed.place))] = FixtureSeed.daysAgo(seed.savedDaysAgo)
        }
        for (index, pair) in FixtureSeed.friends.enumerated() {
            follows[B.Pair(a: pair.0, b: pair.1)] = FixtureSeed.daysAgo(Double(60 - index * 7))
            follows[B.Pair(a: pair.1, b: pair.0)] = FixtureSeed.daysAgo(Double(60 - index * 7))
        }
        for (index, pair) in FixtureSeed.friendRequests.enumerated() {
            friendRequests[B.Pair(a: pair.0, b: pair.1)] = FixtureSeed.daysAgo(Double(20 - index))
        }
        // Interactions on Maya's newest Harbor Lantern rating.
        if let harborActivity = activities.values.first(where: { $0.author == FixtureIDs.maya && $0.type == .rating && placeKey($0.experience) == "harbor" }) {
            likes[B.Pair(a: FixtureIDs.theo, b: harborActivity.id)] = FixtureSeed.daysAgo(1.5)
            likes[B.Pair(a: FixtureIDs.lena, b: harborActivity.id)] = FixtureSeed.daysAgo(1.2)
            let commentID = nextID(80)
            comments[commentID] = B.CommentRow(id: commentID, activity: harborActivity.id, author: FixtureIDs.theo,
                                               body: "Adding this to my Lisbon list right now.", createdAt: FixtureSeed.daysAgo(1.4), operationID: UUID())
            add(notification: .like, recipient: FixtureIDs.maya, actor: FixtureIDs.theo, activity: harborActivity.id, comment: nil,
                key: "like:\(FixtureIDs.theo):\(harborActivity.id)", daysAgo: 1.5, read: true)
            add(notification: .like, recipient: FixtureIDs.maya, actor: FixtureIDs.lena, activity: harborActivity.id, comment: nil,
                key: "like:\(FixtureIDs.lena):\(harborActivity.id)", daysAgo: 1.2, read: false)
            add(notification: .comment, recipient: FixtureIDs.maya, actor: FixtureIDs.theo, activity: harborActivity.id, comment: commentID,
                key: "comment:\(commentID)", daysAgo: 1.4, read: false)
        }
        add(notification: .friendRequest, recipient: FixtureIDs.maya, actor: FixtureIDs.lena, activity: nil, comment: nil,
            key: "friend_request:\(FixtureIDs.lena):\(FixtureIDs.maya)", daysAgo: 40, read: true)
        add(notification: .friendAccept, recipient: FixtureIDs.maya, actor: FixtureIDs.sam, activity: nil, comment: nil,
            key: "friend_accept:\(FixtureIDs.sam):\(FixtureIDs.maya)", daysAgo: 30, read: true)
        if scenario == "stress" { seedStress() }
    }

    private func placeKey(_ experienceID: UUID) -> String? {
        guard let exp = experiences[experienceID], let place = places[exp.placeID] else { return nil }
        return place.candidate.providerPlaceID?.replacingOccurrences(of: "fixture-", with: "")
    }

    private mutating func add(notification type: NotificationType, recipient: UUID, actor: UUID, activity: UUID?, comment: UUID?,
                              key: String, daysAgo: Double, read: Bool) {
        let id = nextID(90)
        let created = FixtureSeed.daysAgo(daysAgo)
        notifications[id] = B.NotificationRow(id: id, recipient: recipient, actor: actor, type: type, activity: activity, comment: comment,
                                              eventKey: key, createdAt: created, readAt: read ? created.addingTimeInterval(3600) : nil)
    }

    func rankingSnapshot(owner: UUID, category: ExperienceCategory) -> CategoryRanking {
        var ranking = CategoryRanking(category: category)
        let rows = ratings.values.filter { $0.owner == owner && $0.category == category }
        for sentiment in Sentiment.partitionOrder {
            let grouped = Dictionary(grouping: rows.filter { $0.sentiment == sentiment }, by: \.group)
            ranking.setGroups(grouped.keys.sorted().map { key in
                TieGroup(entries: grouped[key]!.map { RankedEntry(ratingID: $0.id, experienceID: $0.experience, name: "", locality: nil, firstRatedAt: $0.firstRatedAt) })
            }, for: sentiment)
        }
        return ranking
    }
}

/// The fixture place provider's catalogue: fictional places and the destinations they sit in.
final class FixturePlaceCatalog: @unchecked Sendable {
    let candidates: [String: PlaceCandidate]
    let destinations: [Destination]

    init() {
        var map: [String: PlaceCandidate] = [:]
        for seed in FixtureSeed.places {
            map[seed.key] = PlaceCandidate(provider: .fixture, providerPlaceID: "fixture-\(seed.key)", name: seed.name, address: seed.address,
                                           locality: seed.locality, region: seed.region, countryCode: seed.countryCode, countryName: seed.countryName,
                                           latitude: seed.latitude, longitude: seed.longitude, phone: seed.phone,
                                           website: seed.website.flatMap(URL.init(string:)), providerCategory: seed.providerCategory,
                                           timeZoneIdentifier: seed.timeZone, isLocality: seed.isLocality, suggestedCategory: seed.category)
        }
        // Same-name distinct businesses with no provider IDs: must never merge (SPEC R06).
        map["tide-a"] = PlaceCandidate(provider: .fixture, providerPlaceID: nil, name: "Morning Tide Bakery", address: "5 Rua Nova, Lisbon, Portugal",
                                       locality: "Lisbon", region: "Lisboa", countryCode: "PT", countryName: "Portugal", latitude: 38.7110, longitude: -9.1400,
                                       phone: nil, website: nil, providerCategory: "MKPOICategoryBakery", timeZoneIdentifier: "Europe/Lisbon",
                                       isLocality: false, suggestedCategory: .foodDrink)
        map["tide-b"] = PlaceCandidate(provider: .fixture, providerPlaceID: nil, name: "Morning Tide Bakery", address: "77 Rua Velha, Lisbon, Portugal",
                                       locality: "Lisbon", region: "Lisboa", countryCode: "PT", countryName: "Portugal", latitude: 38.7201, longitude: -9.1502,
                                       phone: nil, website: nil, providerCategory: "MKPOICategoryBakery", timeZoneIdentifier: "Europe/Lisbon",
                                       isLocality: false, suggestedCategory: .foodDrink)
        candidates = map
        func city(_ name: String, _ region: String?, _ code: String, _ country: String, _ lat: Double, _ lon: Double) -> Destination {
            Destination(name: name, region: region, countryCode: code, countryName: country, latitude: lat, longitude: lon, radiusMeters: 15_000)
        }
        destinations = [
            city("Lisbon", "Lisboa", "PT", "Portugal", 38.7223, -9.1393),
            city("Banff", "Alberta", "CA", "Canada", 51.1784, -115.5708),
            city("Kyoto", "Kyoto", "JP", "Japan", 35.0116, 135.7681),
            city("Tokyo", "Tokyo", "JP", "Japan", 35.6762, 139.6503),
            city("Copenhagen", "Capital Region", "DK", "Denmark", 55.6761, 12.5683),
            city("Portland", "Oregon", "US", "United States", 45.5152, -122.6784),
            city("Portland", "Maine", "US", "United States", 43.6591, -70.2568),
            city("Wellington", "Wellington", "NZ", "New Zealand", -41.2865, 174.7762),
            city("Queenstown", "Otago", "NZ", "New Zealand", -45.0312, 168.6626),
            city("Cape Town", "Western Cape", "ZA", "South Africa", -33.9249, 18.4241),
            city("Reykjavík", "Capital Region", "IS", "Iceland", 64.1466, -21.9426),
            city("Edinburgh", "Scotland", "GB", "United Kingdom", 55.9533, -3.1883),
            city("Singapore", nil, "SG", "Singapore", 1.3521, 103.8198),
            city("Matei", "Northern", "FJ", "Fiji", -16.6900, -179.8820),
        ]
    }

    func candidate(key: String) -> PlaceCandidate? { candidates[key] }
}
#endif
