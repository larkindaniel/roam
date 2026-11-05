import Foundation

/// Taking somewhere off where you've been when you've logged places there: every visit to those places goes (and the
/// ranking with the last one), then the cities themselves are un-marked. Home cities aren't touched.
@MainActor
enum BeenClearing {
    static func clear(places: [UUID], cities: [Destination], services: AppServices, library: LibraryStore) async throws {
        for id in places {
            let detail = try await services.experiences.detail(experienceID: id)
            for visit in detail.myVisits {
                let result = try await services.ranking.deleteVisit(visitID: visit.id, operationID: UUID(), allowRatingRemoval: true)
                if result.removedRating { library.applyRatingRemoved(id) }
            }
            // A ranking with no visits left (logged without dated visits) goes too.
            if detail.myRating != nil, detail.myVisits.isEmpty {
                try await services.ranking.removeRating(experienceID: id, operationID: UUID())
                library.applyRatingRemoved(id)
            }
        }
        for city in cities { try await services.plans.setCityVisited(city, present: false) }
        await library.refresh()
        library.noteChanged()
    }
}
