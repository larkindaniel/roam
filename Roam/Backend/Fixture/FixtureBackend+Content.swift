#if ROAM_FIXTURES
import Foundation
import MapKit

extension FixtureBackend: ExperienceService {
    func resolve(_ candidate: PlaceCandidate) async throws -> ExperienceSummary {
        let me = try await authenticatedActor()
        if let existing = existingExperience(for: candidate) { return summary(existing, viewer: me)! }
        let placeID = UUID()
        let experienceID = UUID()
        places[placeID] = PlaceRow(id: placeID, candidate: candidate, status: .active)
        experiences[experienceID] = ExperienceRow(id: experienceID, placeID: placeID, category: candidate.suggestedCategory,
                                                  categoryLocked: false, createdAt: Date())
        return summary(experienceID, viewer: me)!
    }

    /// Provider ID first; otherwise exact normalized name + full address + 6-decimal coordinate.
    func existingExperience(for candidate: PlaceCandidate) -> UUID? {
        let place = places.values.first { row in
            if let id = candidate.providerPlaceID, let rowID = row.candidate.providerPlaceID {
                return row.candidate.provider == candidate.provider && rowID == id
            }
            guard candidate.providerPlaceID == nil, row.candidate.providerPlaceID == nil else { return false }
            return PlaceIdentity.isSamePlace(row.candidate, candidate)
        }
        guard let place else { return nil }
        return experiences.values.first { $0.placeID == place.id }?.id
    }

    func matches(for candidates: [PlaceCandidate]) async throws -> [String: ExperienceSummary] {
        let me = try requireProfile()
        var result: [String: ExperienceSummary] = [:]
        for candidate in candidates {
            if let id = existingExperience(for: candidate), let summary = summary(id, viewer: me) { result[candidate.id] = summary }
        }
        return result
    }

    func detail(experienceID: UUID) async throws -> ExperienceDetail {
        let me = try await authenticatedActor()
        guard let experience = experiences[experienceID], let place = places[experience.placeID], let summary = summary(experienceID, viewer: me) else {
            throw RoamError.notFound
        }
        let myRating: MyRating? = ratings.values.first(where: { $0.owner == me && $0.experience == experienceID }).flatMap { row in
            let ranking = ranking(owner: me, category: row.category)
            guard let placement = ranking.placement(forExperience: experienceID) else { return nil }
            return MyRating(ratingID: row.id, category: row.category, sentiment: placement.sentiment, score: placement.score, rank: placement.rank,
                            groupSize: placement.groupSize, categoryCount: ranking.entryCount, firstRatedAt: row.firstRatedAt)
        }
        let myVisits = visits.values.filter { $0.owner == me && $0.experience == experienceID }.map(visitModel).sorted(by: Visit.historyOrder)
        let publicRows = activities.values.filter { $0.experience == experienceID && canSeeActivity($0, viewer: me) }
            .sorted { ($0.publishedAt, $0.id.uuidString) > ($1.publishedAt, $1.id.uuidString) }
        let c = place.candidate
        return ExperienceDetail(summary: summary, address: c.address, phone: c.phone, website: c.website, timeZoneIdentifier: c.timeZoneIdentifier,
                                provider: c.provider, providerStatus: place.status, isLocality: c.isLocality,
                                categoryLocked: experience.categoryLocked, myRating: myRating, myVisits: myVisits,
                                hasPrivateNote: privateNotes[Pair(a: me, b: experienceID)] != nil,
                                publicActivity: publicRows.prefix(Limits.pageSize).compactMap { activityItem($0, viewer: me) })
    }

    func experiences(in bounds: GeoBounds, category: ExperienceCategory?) async throws -> [ExperienceSummary] {
        let me = try await authenticatedActor()
        return experiences.values.compactMap { row -> ExperienceSummary? in
            guard let place = places[row.placeID], bounds.contains(latitude: place.candidate.latitude, longitude: place.candidate.longitude) else { return nil }
            if let category, row.category != category { return nil }
            return summary(row.id, viewer: me)
        }.sorted { $0.name < $1.name }
    }
}

extension FixtureBackend: ListService {
    func library() async throws -> UserLibrary {
        let me = try requireProfile()
        var rated: [UUID: ExperienceCategory] = [:]
        for row in ratings.values where row.owner == me { rated[row.experience] = row.category }
        return UserLibrary(bookmarked: Set(bookmarks.keys.filter { $0.a == me }.map(\.b)), rated: rated,
                           visited: Set(visits.values.filter { $0.owner == me }.map(\.experience)))
    }

    func setBookmark(experienceID: UUID, saved: Bool) async throws -> Bool {
        let me = try await authenticatedActor()
        guard experiences[experienceID] != nil else { throw RoamError.notFound }
        let key = Pair(a: me, b: experienceID)
        if saved {
            if ratings.values.contains(where: { $0.owner == me && $0.experience == experienceID }) { throw RoamError.alreadyRated }
            if bookmarks[key] == nil { bookmarks[key] = Date() }
        } else {
            bookmarks[key] = nil
        }
        return bookmarks[key] != nil
    }

    private func listEntry(_ experienceID: UUID, owner: UUID, viewer: UUID, savedAt: Date?) -> ListEntry? {
        guard let summary = summary(experienceID, viewer: viewer), let experience = experiences[experienceID],
              let place = places[experience.placeID] else { return nil }
        let rating = ratings.values.first { $0.owner == owner && $0.experience == experienceID }
        let placement = rating.flatMap { ranking(owner: owner, category: $0.category).placement(forExperience: experienceID) }
        let ownerVisits = visits.values.filter { $0.owner == owner && $0.experience == experienceID }.map(visitModel).sorted(by: Visit.historyOrder)
        let c = place.candidate
        return ListEntry(experience: summary, ownerCategory: rating?.category ?? experience.category, ownerSentiment: placement?.sentiment,
                         ownerScore: placement?.score, ownerRank: placement?.rank, ownerFirstRatedAt: rating?.firstRatedAt,
                         isRanked: rating != nil,
                         latestVisitDate: ownerVisits.first?.visitDate.date, latestVisitAt: ownerVisits.map(\.createdAt).max(),
                         savedAt: savedAt, viewerSavedAt: bookmarks[Pair(a: viewer, b: experienceID)],
                         cityKey: GeographyKey.cityKey(countryCode: c.countryCode, region: c.region, locality: c.locality),
                         cityName: c.locality)
    }

    func been(ownerID: UUID) async throws -> [ListEntry] {
        let me = try await authenticatedActor()
        guard ownerID == me || isVisibleMember(ownerID, to: me) else { throw RoamError.notFound }
        let visible = visits.values.filter { $0.owner == ownerID && audienceAllows(owner: $0.owner, audience: $0.audience, viewer: me) }.map(\.experience)
        let hidden = Set(visits.values.filter { $0.owner == ownerID && !audienceAllows(owner: $0.owner, audience: $0.audience, viewer: me) }.map(\.experience))
        let experienceIDs = Set(ratings.values.filter { $0.owner == ownerID && !hidden.contains($0.experience) }.map(\.experience)).union(visible)
        return experienceIDs.compactMap { listEntry($0, owner: ownerID, viewer: me, savedAt: nil) }
    }

    func want(ownerID: UUID) async throws -> [ListEntry] {
        let me = try await authenticatedActor()
        guard ownerID == me || isVisibleMember(ownerID, to: me) else { throw RoamError.notFound }
        return bookmarks.filter { $0.key.a == ownerID }.compactMap { listEntry($0.key.b, owner: ownerID, viewer: me, savedAt: $0.value) }
    }

    func sharedWants(with otherUserID: UUID) async throws -> [ListEntry] {
        let me = try await authenticatedActor()
        guard isVisibleMember(otherUserID, to: me), otherUserID != me else { throw RoamError.notFound }
        let mine = bookmarks.filter { $0.key.a == me }
        let theirs = Set(bookmarks.keys.filter { $0.a == otherUserID }.map(\.b))
        return mine.filter { theirs.contains($0.key.b) }
            .sorted { ($0.value, $0.key.b.uuidString) > ($1.value, $1.key.b.uuidString) }
            .compactMap { listEntry($0.key.b, owner: me, viewer: me, savedAt: $0.value) }
    }
}

extension FixtureBackend: RankingService {
    func categoryRanking(_ category: ExperienceCategory) async throws -> CategoryRanking {
        return ranking(owner: try await authenticatedActor(), category: category)
    }

    private func receiptKey(_ owner: UUID, _ operation: UUID) -> String { "\(owner.uuidString)|\(operation.uuidString)" }

    func commitRating(_ request: RatingCommitRequest) async throws -> RatingCommitResult {
        let me = try await authenticatedActor()
        let key = receiptKey(me, request.operationID)
        let digest = try MutationFingerprint.digest(request)
        if let receipt = receipts[key] {
            guard receipt.hash == digest, let result = receipt.result as? RatingCommitResult else {
                throw RoamError.conflict("This save was already used for a different change.")
            }
            return result
        }
        guard let experience = experiences[request.experienceID] else { throw RoamError.notFound }
        if experience.categoryLocked, let canonical = experience.category, canonical != request.category {
            throw RoamError.validation("This experience is ranked in \(canonical.title).")
        }
        let existing = ratings.values.first { $0.owner == me && $0.experience == request.experienceID }
        switch request.intent {
        case .firstLog where existing != nil: throw RoamError.alreadyRated
        case .rerank where existing == nil: throw RoamError.notFound
        case .rerank where existing?.category != request.category: throw RoamError.validation("Category can't change when ranking again.")
        default: break
        }
        let current = ranking(owner: me, category: request.category)
        guard current.revision == request.baseRevision else { throw RoamError.staleRevision }
        let base = request.intent == .rerank ? current.removing(experienceID: request.experienceID) : current
        let outcome: InsertionOutcome
        do {
            outcome = try InsertionSession.replay(sentiment: request.sentiment, groups: base.groups(for: request.sentiment), answers: request.answers)
        } catch {
            throw RoamError.validation("The comparisons no longer match this ranking. Compare again.")
        }
        let anchor = visits.values.filter { $0.owner == me && $0.experience == request.experienceID }.map(visitModel).sorted(by: Visit.historyOrder).first
        if request.intent == .rerank, request.visit != nil, anchor == nil { throw RoamError.validation("No retained visit is available to edit.") }
        // Validate all enrichment before any write so failure leaves no partial effect.
        if let visit = request.visit {
            if let issue = Validation.publicNote(visit.publicNote) { throw RoamError.validation(issue.localizedDescription) }
            let zone = try visitTimeZone(visit.timeZoneIdentifier)
            if Validation.visitDate(visit.date, today: LocalDate.today(in: zone)) != nil { throw RoamError.validation(ValidationIssue.futureDate.localizedDescription) }
            guard visit.mediaIDs.count <= Limits.photosPerVisit, Set(visit.mediaIDs).count == visit.mediaIDs.count,
                  visit.mediaIDs.allSatisfy({ media[$0]?.owner == me && media[$0]?.purpose == .visit
                      && (media[$0]?.attached == false || (request.intent == .rerank && media[$0]?.visit == anchor?.id)) }) else {
                throw RoamError.validation("A photo isn't finished uploading. Remove it or try again.")
            }
        }
        let now = Date()
        let ratingID = existing?.id ?? UUID()
        let entry = RankedEntry(ratingID: ratingID, experienceID: request.experienceID, name: placeName(request.experienceID), locality: nil,
                                firstRatedAt: existing?.firstRatedAt ?? now)
        var updated = base.applying(outcome, entry: entry, sentiment: request.sentiment)
        updated.revision = current.revision + 1
        // Clear this category's rows and rewrite.
        for row in ratings.values where row.owner == me && row.category == request.category && !updated.contains(experienceID: row.experience) {
            ratings[row.id] = nil
        }
        store(updated, owner: me, now: now)
        ratings[ratingID]?.updatedAt = now
        revisions[revisionKey(me, request.category)] = updated.revision
        experiences[request.experienceID]?.category = request.category
        experiences[request.experienceID]?.categoryLocked = true

        var visitID: UUID?
        if request.intent == .firstLog {
            let newVisit = UUID()
            let payload = request.visit ?? VisitPayload(date: nil, timeZoneIdentifier: nil, publicNote: "", mediaIDs: [])
            visits[newVisit] = VisitRow(id: newVisit, owner: me, experience: request.experienceID, date: payload.date,
                                        timeZone: payload.timeZoneIdentifier, note: payload.publicNote, mediaIDs: payload.mediaIDs,
                                        createdAt: now, updatedAt: now, audience: payload.audience ?? .friends, tripID: payload.tripID)
            for (index, mediaID) in payload.mediaIDs.enumerated() {
                media[mediaID]?.attached = true
                media[mediaID]?.visit = newVisit
                media[mediaID]?.position = index
            }
            visitID = newVisit
            bookmarks[Pair(a: me, b: request.experienceID)] = nil
        } else {
            visitID = anchor?.id
            if let visitID, let payload = request.visit, var retained = visits[visitID] {
                for removed in retained.mediaIDs where !payload.mediaIDs.contains(removed) { media[removed] = nil }
                for (position, mediaID) in payload.mediaIDs.enumerated() {
                    media[mediaID]?.attached = true
                    media[mediaID]?.visit = visitID
                    media[mediaID]?.position = position
                }
                retained.date = payload.date
                retained.timeZone = payload.timeZoneIdentifier
                retained.note = payload.publicNote
                retained.mediaIDs = payload.mediaIDs
                retained.updatedAt = now
                visits[visitID] = retained
            }
        }
        let placement = updated.placement(forExperience: request.experienceID)!
        let activityID = UUID()
        activities[activityID] = ActivityRow(id: activityID, author: me, type: request.intent == .firstLog ? .rating : .rerank,
                                             experience: request.experienceID, visit: visitID, rating: ratingID, category: request.category,
                                             score: placement.score, rank: placement.rank, sentiment: placement.sentiment, publishedAt: now)
        let result = RatingCommitResult(ratingID: ratingID, visitID: request.intent == .firstLog ? visitID : nil, activityID: activityID,
                                        category: request.category, sentiment: placement.sentiment, score: placement.score, rank: placement.rank,
                                        groupSize: placement.groupSize, categoryCount: updated.entryCount, revision: updated.revision)
        receipts[key] = (digest, result)
        return result
    }

    func addVisit(_ request: AddVisitRequest) async throws -> AddVisitResult {
        let me = try await authenticatedActor()
        let key = receiptKey(me, request.operationID)
        let digest = try MutationFingerprint.digest(request)
        if let receipt = receipts[key] {
            guard receipt.hash == digest, let result = receipt.result as? AddVisitResult else {
                throw RoamError.conflict("This save was already used for a different change.")
            }
            return result
        }
        let rating = ratings.values.first(where: { $0.owner == me && $0.experience == request.experienceID })
        guard let category = rating?.category ?? request.category ?? experiences[request.experienceID]?.category else {
            throw RoamError.validation("Choose a category for this place.")
        }
        if experiences[request.experienceID]?.category == nil { experiences[request.experienceID]?.category = category }
        if let issue = Validation.publicNote(request.visit.publicNote) { throw RoamError.validation(issue.localizedDescription) }
        let zone = try visitTimeZone(request.visit.timeZoneIdentifier)
        if Validation.visitDate(request.visit.date, today: LocalDate.today(in: zone)) != nil { throw RoamError.validation(ValidationIssue.futureDate.localizedDescription) }
        guard request.visit.mediaIDs.count <= Limits.photosPerVisit, Set(request.visit.mediaIDs).count == request.visit.mediaIDs.count,
              request.visit.mediaIDs.allSatisfy({ media[$0]?.owner == me && media[$0]?.attached == false && media[$0]?.purpose == .visit }) else {
            throw RoamError.validation("A photo isn't finished uploading. Remove it or try again.")
        }
        let now = Date()
        let visitID = UUID()
        visits[visitID] = VisitRow(id: visitID, owner: me, experience: request.experienceID, date: request.visit.date,
                                   timeZone: request.visit.timeZoneIdentifier, note: request.visit.publicNote, mediaIDs: request.visit.mediaIDs,
                                   createdAt: now, updatedAt: now, audience: request.visit.audience ?? .friends, tripID: request.visit.tripID)
        for (index, mediaID) in request.visit.mediaIDs.enumerated() {
            media[mediaID]?.attached = true
            media[mediaID]?.visit = visitID
            media[mediaID]?.position = index
        }
        let placement = ranking(owner: me, category: category).placement(forExperience: request.experienceID)
        let activityID = UUID()
        activities[activityID] = ActivityRow(id: activityID, author: me, type: .revisit, experience: request.experienceID, visit: visitID,
                                             rating: rating?.id, category: category, score: placement?.score, rank: placement?.rank,
                                             sentiment: placement?.sentiment, publishedAt: now)
        let result = AddVisitResult(visitID: visitID, activityID: activityID)
        receipts[key] = (digest, result)
        return result
    }

    func removeRating(experienceID: UUID, operationID: UUID) async throws {
        let me = try await authenticatedActor()
        let key = receiptKey(me, operationID)
        let digest = try MutationFingerprint.digest(FixtureRemovalIntent(kind: "remove_rating", id: experienceID))
        if let receipt = receipts[key] {
            guard receipt.hash == digest, receipt.result is FixtureRemovalReceipt else { throw RoamError.conflict("This save was already used for a different change.") }
            return
        }
        guard experiences[experienceID] != nil else { throw RoamError.notFound }
        if let rating = ratings.values.first(where: { $0.owner == me && $0.experience == experienceID }) { removeRatingInternal(rating, owner: me) }
        receipts[key] = (digest, FixtureRemovalReceipt())
    }

    func removeRatingInternal(_ rating: RatingRow, owner: UUID) {
        let current = ranking(owner: owner, category: rating.category)
        var updated = current.removing(experienceID: rating.experience)
        updated.revision = current.revision + 1
        ratings[rating.id] = nil
        store(updated, owner: owner, now: Date())
        revisions[revisionKey(owner, rating.category)] = updated.revision
        for activity in activities.values where activity.rating == rating.id { deleteActivityCascade(activity.id) }
    }

    func deleteVisit(visitID: UUID, operationID: UUID, allowRatingRemoval: Bool) async throws -> DeleteVisitResult {
        let me = try await authenticatedActor()
        let key = receiptKey(me, operationID)
        let digest = try MutationFingerprint.digest(FixtureVisitDeletionIntent(id: visitID, allowRatingRemoval: allowRatingRemoval))
        if let receipt = receipts[key] {
            guard receipt.hash == digest, let result = receipt.result as? DeleteVisitResult else { throw RoamError.conflict("This save was already used for a different change.") }
            return result
        }
        guard let visit = visits[visitID] else {
            let result = DeleteVisitResult(removedRating: false)
            receipts[key] = (digest, result)
            return result
        }
        guard visit.owner == me else { throw RoamError.forbidden }
        let hasOtherVisits = visits.values.contains { $0.owner == me && $0.experience == visit.experience && $0.id != visitID }
        if !hasOtherVisits, !allowRatingRemoval,
           ratings.values.contains(where: { $0.owner == me && $0.experience == visit.experience }) {
            throw RoamError.lastVisitConfirmationRequired
        }
        visits[visitID] = nil
        for mediaID in visit.mediaIDs { media[mediaID] = nil }
        for activity in activities.values where activity.visit == visitID { deleteActivityCascade(activity.id) }
        let remaining = visits.values.contains { $0.owner == me && $0.experience == visit.experience }
        if !remaining, let rating = ratings.values.first(where: { $0.owner == me && $0.experience == visit.experience }) {
            removeRatingInternal(rating, owner: me)
            let result = DeleteVisitResult(removedRating: true)
            receipts[key] = (digest, result)
            return result
        }
        let result = DeleteVisitResult(removedRating: false)
        receipts[key] = (digest, result)
        return result
    }

    private func visitTimeZone(_ identifier: String?) throws -> TimeZone {
        guard let identifier else { return .current }
        guard let zone = TimeZone(identifier: identifier) else { throw RoamError.validation("Choose a valid visit time zone.") }
        return zone
    }
}

private struct FixtureRemovalIntent: Encodable { let kind: String; let id: UUID }
private struct FixtureVisitDeletionIntent: Encodable { let kind = "delete_visit"; let id: UUID; let allowRatingRemoval: Bool }
private struct FixtureRemovalReceipt {}

#endif
