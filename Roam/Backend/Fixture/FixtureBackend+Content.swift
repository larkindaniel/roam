#if ROAM_FIXTURES
import Foundation
import MapKit

extension FixtureBackend: ExperienceService {
    func resolve(_ candidate: PlaceCandidate) async throws -> ExperienceSummary {
        await pause()
        let me = try requireProfile()
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
        await pause()
        let me = try requireProfile()
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
        await pause()
        let me = try requireProfile()
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
        await pause()
        let me = try requireProfile()
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
                         ownerScore: placement?.score, ownerRank: placement?.rank, isRanked: rating != nil,
                         latestVisitDate: ownerVisits.first?.visitDate.date, latestVisitAt: ownerVisits.map(\.createdAt).max(),
                         savedAt: savedAt, viewerSavedAt: bookmarks[Pair(a: viewer, b: experienceID)],
                         cityKey: GeographyKey.cityKey(countryCode: c.countryCode, region: c.region, locality: c.locality),
                         cityName: c.locality)
    }

    func been(ownerID: UUID) async throws -> [ListEntry] {
        await pause()
        let me = try requireProfile()
        guard ownerID == me || isVisibleMember(ownerID, to: me) else { throw RoamError.notFound }
        let experienceIDs = Set(ratings.values.filter { $0.owner == ownerID }.map(\.experience))
            .union(visits.values.filter { $0.owner == ownerID }.map(\.experience))
        return experienceIDs.compactMap { listEntry($0, owner: ownerID, viewer: me, savedAt: nil) }
    }

    func want(ownerID: UUID) async throws -> [ListEntry] {
        await pause()
        let me = try requireProfile()
        guard ownerID == me || isVisibleMember(ownerID, to: me) else { throw RoamError.notFound }
        return bookmarks.filter { $0.key.a == ownerID }.compactMap { listEntry($0.key.b, owner: ownerID, viewer: me, savedAt: $0.value) }
    }

    func sharedWants(with otherUserID: UUID) async throws -> [ListEntry] {
        await pause()
        let me = try requireProfile()
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
        await pause()
        return ranking(owner: try requireProfile(), category: category)
    }

    private func receiptKey(_ owner: UUID, _ operation: UUID) -> String { "\(owner.uuidString)|\(operation.uuidString)" }

    func commitRating(_ request: RatingCommitRequest) async throws -> RatingCommitResult {
        await pause()
        let me = try requireProfile()
        let key = receiptKey(me, request.operationID)
        if let receipt = receipts[key] {
            guard receipt.hash == request.hashValue, let result = receipt.result as? RatingCommitResult else {
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
            throw RoamError.staleRevision
        }
        // Validate media before any write so failure leaves no partial effect.
        if let visit = request.visit {
            if let issue = Validation.publicNote(visit.publicNote) { throw RoamError.validation(issue.localizedDescription) }
            let zone = visit.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
            if Validation.visitDate(visit.date, today: LocalDate.today(in: zone)) != nil { throw RoamError.validation(ValidationIssue.futureDate.localizedDescription) }
            guard visit.mediaIDs.count <= Limits.photosPerVisit,
                  visit.mediaIDs.allSatisfy({ media[$0]?.owner == me && media[$0]?.attached == false && media[$0]?.purpose == .visit }) else {
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
                                        createdAt: now, updatedAt: now)
            for (index, mediaID) in payload.mediaIDs.enumerated() {
                media[mediaID]?.attached = true
                media[mediaID]?.visit = newVisit
                media[mediaID]?.position = index
            }
            visitID = newVisit
            bookmarks[Pair(a: me, b: request.experienceID)] = nil
        } else {
            visitID = visits.values.filter { $0.owner == me && $0.experience == request.experienceID }.map(visitModel)
                .sorted(by: Visit.historyOrder).first?.id
        }
        let placement = updated.placement(forExperience: request.experienceID)!
        let activityID = UUID()
        activities[activityID] = ActivityRow(id: activityID, author: me, type: request.intent == .firstLog ? .rating : .rerank,
                                             experience: request.experienceID, visit: visitID, rating: ratingID, category: request.category,
                                             score: placement.score, rank: placement.rank, sentiment: placement.sentiment, publishedAt: now)
        let result = RatingCommitResult(ratingID: ratingID, visitID: request.intent == .firstLog ? visitID : nil, activityID: activityID,
                                        category: request.category, sentiment: placement.sentiment, score: placement.score, rank: placement.rank,
                                        groupSize: placement.groupSize, categoryCount: updated.entryCount, revision: updated.revision)
        receipts[key] = (request.hashValue, result)
        return result
    }

    func addVisit(_ request: AddVisitRequest) async throws -> AddVisitResult {
        await pause()
        let me = try requireProfile()
        let key = receiptKey(me, request.operationID)
        if let receipt = receipts[key] {
            guard receipt.hash == request.hashValue, let result = receipt.result as? AddVisitResult else {
                throw RoamError.conflict("This save was already used for a different change.")
            }
            return result
        }
        guard let rating = ratings.values.first(where: { $0.owner == me && $0.experience == request.experienceID }) else {
            throw RoamError.validation("Rank this experience first, then add more visits.")
        }
        if let issue = Validation.publicNote(request.visit.publicNote) { throw RoamError.validation(issue.localizedDescription) }
        guard request.visit.mediaIDs.allSatisfy({ media[$0]?.owner == me && media[$0]?.attached == false }) else {
            throw RoamError.validation("A photo isn't finished uploading. Remove it or try again.")
        }
        let now = Date()
        let visitID = UUID()
        visits[visitID] = VisitRow(id: visitID, owner: me, experience: request.experienceID, date: request.visit.date,
                                   timeZone: request.visit.timeZoneIdentifier, note: request.visit.publicNote, mediaIDs: request.visit.mediaIDs,
                                   createdAt: now, updatedAt: now)
        for (index, mediaID) in request.visit.mediaIDs.enumerated() {
            media[mediaID]?.attached = true
            media[mediaID]?.visit = visitID
            media[mediaID]?.position = index
        }
        let placement = ranking(owner: me, category: rating.category).placement(forExperience: request.experienceID)
        let activityID = UUID()
        activities[activityID] = ActivityRow(id: activityID, author: me, type: .revisit, experience: request.experienceID, visit: visitID,
                                             rating: rating.id, category: rating.category, score: placement?.score, rank: placement?.rank,
                                             sentiment: placement?.sentiment, publishedAt: now)
        let result = AddVisitResult(visitID: visitID, activityID: activityID)
        receipts[key] = (request.hashValue, result)
        return result
    }

    func removeRating(experienceID: UUID, operationID: UUID) async throws {
        await pause()
        let me = try requireProfile()
        guard let rating = ratings.values.first(where: { $0.owner == me && $0.experience == experienceID }) else { return }
        removeRatingInternal(rating, owner: me)
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

    func deleteVisit(visitID: UUID, operationID: UUID) async throws -> DeleteVisitResult {
        await pause()
        let me = try requireProfile()
        guard let visit = visits[visitID] else { return DeleteVisitResult(removedRating: false) }
        guard visit.owner == me else { throw RoamError.forbidden }
        visits[visitID] = nil
        for mediaID in visit.mediaIDs { media[mediaID] = nil }
        for activity in activities.values where activity.visit == visitID { deleteActivityCascade(activity.id) }
        let remaining = visits.values.contains { $0.owner == me && $0.experience == visit.experience }
        if !remaining, let rating = ratings.values.first(where: { $0.owner == me && $0.experience == visit.experience }) {
            removeRatingInternal(rating, owner: me)
            return DeleteVisitResult(removedRating: true)
        }
        return DeleteVisitResult(removedRating: false)
    }
}

extension FixtureBackend: MemoryService {
    func updateVisit(visitID: UUID, note: String, date: VisitDate, mediaIDs: [UUID]) async throws -> Visit {
        await pause()
        let me = try requireProfile()
        guard var visit = visits[visitID] else { throw RoamError.notFound }
        guard visit.owner == me else { throw RoamError.forbidden }
        if let issue = Validation.publicNote(note) { throw RoamError.validation(issue.localizedDescription) }
        let zone = date.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
        if Validation.visitDate(date.date, today: LocalDate.today(in: zone)) != nil { throw RoamError.validation(ValidationIssue.futureDate.localizedDescription) }
        guard mediaIDs.count <= Limits.photosPerVisit,
              mediaIDs.allSatisfy({ media[$0]?.owner == me && (media[$0]?.attached == false || media[$0]?.visit == visitID) }) else {
            throw RoamError.validation("A photo isn't finished uploading. Remove it or try again.")
        }
        for removed in visit.mediaIDs where !mediaIDs.contains(removed) { media[removed] = nil }
        for (index, id) in mediaIDs.enumerated() {
            media[id]?.attached = true
            media[id]?.visit = visitID
            media[id]?.position = index
        }
        visit.note = note
        visit.date = date.date
        visit.timeZone = date.timeZoneIdentifier
        visit.mediaIDs = mediaIDs
        visit.updatedAt = Date()
        visits[visitID] = visit
        return visitModel(visit)
    }

    func privateNote(experienceID: UUID) async throws -> PrivateNote? {
        await pause()
        return privateNotes[Pair(a: try requireProfile(), b: experienceID)]
    }

    func savePrivateNote(experienceID: UUID, text: String) async throws -> PrivateNote {
        await pause()
        let me = try requireProfile()
        if let issue = Validation.privateNote(text) { throw RoamError.validation(issue.localizedDescription) }
        let note = PrivateNote(experienceID: experienceID, text: text, updatedAt: Date())
        privateNotes[Pair(a: me, b: experienceID)] = note
        return note
    }

    func deletePrivateNote(experienceID: UUID) async throws {
        await pause()
        privateNotes[Pair(a: try requireProfile(), b: experienceID)] = nil
    }
}

extension FixtureBackend: MediaService {
    func stage(jpegData: Data, width: Int, height: Int, purpose: MediaPurpose) async throws -> StagedMedia {
        await pause()
        let me = try requireProfile()
        guard jpegData.count <= Limits.photoMaxBytes, max(width, height) <= Limits.photoLongestSide else {
            throw RoamError.validation("This photo is too large to upload.")
        }
        let id = UUID()
        let path = "fixture/\(me.uuidString.lowercased())/\(id.uuidString.lowercased()).jpg"
        media[id] = MediaRow(id: id, owner: me, visit: nil, purpose: purpose, path: path, width: width, height: height, position: 0,
                             attached: purpose == .avatar, createdAt: Date(), data: jpegData, seedHue: 0.5)
        return StagedMedia(id: id, path: path, width: width, height: height)
    }

    func discardStaged(mediaID: UUID) async throws {
        let me = try requireProfile()
        if let row = media[mediaID], row.owner == me, !row.attached || row.purpose == .avatar { media[mediaID] = nil }
    }

    func imageData(path: String) async throws -> Data {
        await pause()
        let me = try requireProfile()
        guard let row = media.values.first(where: { $0.path == path }) else { throw RoamError.notFound }
        guard row.owner == me || (row.attached && isVisibleMember(row.owner, to: me)) else { throw RoamError.forbidden }
        if let data = row.data { return data }
        let data = FixtureArtwork.photo(hue: row.seedHue, seed: row.id.hashValue)
        media[row.id]?.data = data
        return data
    }
}
#endif
