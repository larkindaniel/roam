import Foundation
import Observation

enum RatingFlowCompletion: Hashable {
    case rating(RatingCommitResult)
    case visit(AddVisitResult)
}

enum RatingFlowStep: String, Codable {
    case sentiment, details, loading, comparison, saving, retry, result
}

private struct RatingFlowDraft: Codable {
    let accountID: UUID
    let experienceID: UUID
    let mode: String
    var updatedAt: Date
    var operationID: UUID
    var category: ExperienceCategory?
    var sentiment: Sentiment?
    var visit: VisitPayload
    let initialVisit: VisitPayload
    var step: RatingFlowStep
    var ranking: CategoryRanking?
    var answers: [ComparisonAnswer]
    var pendingRating: RatingCommitRequest?
    var pendingVisit: AddVisitRequest?
}

/// S08–S11. A durable draft and an immutable pending request survive interrupted saves.
/// Only acknowledged service results can enter the numeric-result step.
@MainActor
@Observable
final class RatingFlowModel {
    let request: LogRequest
    let accountID: UUID
    let photos: PhotoDraftModel?
    private(set) var step: RatingFlowStep
    private(set) var category: ExperienceCategory?
    private(set) var sentiment: Sentiment?
    private(set) var visit: VisitPayload
    private(set) var skipsRanking = false
    private(set) var operationID: UUID
    private(set) var session: InsertionSession?
    private(set) var completion: RatingFlowCompletion?
    private(set) var message: String?
    private(set) var authError: RoamError?
    private(set) var persistenceError: String?
    private var ranking: CategoryRanking?
    private var pendingRating: RatingCommitRequest?
    private var pendingVisit: AddVisitRequest?
    private let initialVisit: VisitPayload
    private let service: any RankingService
    private let storage: AccountStorage
    private let currentAccount: () -> UUID?
    private let now: () -> Date
    private var generation = 0

    var draftName: String { "rating-draft-\(request.experience.id.uuidString.lowercased())-\(request.mode.rawValue)" }
    /// What the place already is, from Roam or from Apple's place type.
    private var knownCategory: ExperienceCategory? { request.experience.category ?? request.suggestedCategory }
    /// A place that's already categorised isn't asked again; only one with no category gets the picker.
    var categoryLocked: Bool { request.mode != .firstLog || request.categoryLocked || knownCategory != nil }
    var isBusy: Bool { step == .saving || step == .loading }
    var hasPendingSave: Bool { pendingRating != nil || pendingVisit != nil }
    var canEdit: Bool { !isBusy && !hasPendingSave && completion == nil }
    var canUndo: Bool { step == .comparison && session?.canUndo == true }
    var hasNonemptyDraft: Bool {
        sentiment != nil || visit != initialVisit || hasPendingSave
            || category != (request.experience.category ?? request.suggestedCategory)
            || photos?.assets.contains(where: { $0.status != .existing }) == true
            || (photos.map { $0.assets.compactMap { $0.existing?.id } != initialVisit.mediaIDs } ?? false)
    }
    var timeZone: TimeZone {
        (visit.timeZoneIdentifier ?? request.destinationTimeZone).flatMap(TimeZone.init(identifier:)) ?? .current
    }
    var today: LocalDate { .today(in: timeZone, now: now()) }
    var comparison: RankedEntry? { session?.currentComparison }

    init(request: LogRequest, accountID: UUID, ranking service: any RankingService, storage: AccountStorage,
         currentAccount: (() -> UUID?)? = nil, now: @escaping () -> Date = Date.init, photos: PhotoDraftModel? = nil) {
        self.request = request
        self.accountID = accountID
        self.photos = photos
        self.service = service
        self.storage = storage
        self.currentAccount = currentAccount ?? { accountID }
        self.now = now
        let date = VisitDate.today(destinationTimeZone: request.destinationTimeZone, now: now())
        let initial: VisitPayload
        if request.mode == .rerank, let anchor = request.existingVisit {
            initial = VisitPayload(date: anchor.visitDate.date, timeZoneIdentifier: anchor.visitDate.timeZoneIdentifier,
                                   publicNote: anchor.publicNote, mediaIDs: anchor.media.map(\.id))
        } else {
            initial = VisitPayload(date: date.date, timeZoneIdentifier: date.timeZoneIdentifier, publicNote: "", mediaIDs: [], audience: .friends)
        }
        let name = "rating-draft-\(request.experience.id.uuidString.lowercased())-\(request.mode.rawValue)"
        storage.purgeExpired(userID: accountID, prefix: "rating-draft-", lifetime: 30 * 86_400, now: now())
        if let draft = storage.read(RatingFlowDraft.self, name: name, userID: accountID),
           draft.accountID == accountID, draft.experienceID == request.experience.id, draft.mode == request.mode.rawValue,
           now().timeIntervalSince(draft.updatedAt) <= 30 * 86_400 {
            operationID = draft.operationID
            let known = request.experience.category ?? request.suggestedCategory
            category = (request.mode != .firstLog || request.categoryLocked || known != nil) ? known : draft.category
            sentiment = draft.sentiment
            visit = draft.visit
            initialVisit = draft.initialVisit
            ranking = draft.ranking
            pendingRating = draft.pendingRating
            pendingVisit = draft.pendingVisit
            step = (draft.pendingRating != nil || draft.pendingVisit != nil) ? .retry : draft.step
            if step == .saving || step == .loading || step == .result { step = request.mode == .addVisit ? .details : .sentiment }
            if draft.pendingRating == nil, draft.pendingVisit == nil,
               request.mode != .firstLog || request.categoryLocked,
               let canonical = request.experience.category,
               draft.category != canonical || (draft.ranking.map { $0.category != canonical } ?? false) {
                // A first logger may have locked the category while this local draft was open.
                // Old comparisons cannot be replayed against a different canonical category.
                ranking = nil
                session = nil
                step = .details
                message = "This place is now ranked in \(canonical.title). Your details are kept; tap Okay to refresh comparisons."
            }
            if step == .comparison, let categoryRanking = draft.ranking, let chosen = draft.sentiment {
                let base = request.mode == .rerank ? categoryRanking.removing(experienceID: request.experience.id) : categoryRanking
                var restored = InsertionSession(sentiment: chosen, groups: base.groups(for: chosen))
                for answer in draft.answers {
                    guard restored.currentComparison?.ratingID == answer.comparedRatingID else { break }
                    restored.choose(answer.choice)
                }
                session = restored
                if restored.isComplete {
                    // No immutable request was recorded, so completion had not been sent.
                    // Refresh comparisons after Okay instead of showing an empty question.
                    step = .details
                    session = nil
                }
            }
            if step == .retry { message = "Saving wasn't confirmed. Retry with the same details to check the original save." }
        } else {
            storage.remove(name: name, userID: accountID)
            operationID = UUID()
            category = request.experience.category ?? request.suggestedCategory
            sentiment = nil
            visit = initial
            initialVisit = initial
            step = request.mode == .addVisit ? .details : .sentiment
        }
        if request.startsWithDetails, request.mode == .firstLog, step == .sentiment { step = .details }
        // A visit with no feeling chosen is an unranked log, including one restored from a draft.
        skipsRanking = request.mode == .firstLog && step == .details && sentiment == nil
    }

    /// Logging never requires ranking: the visit saves now and can be ranked later.
    func logWithoutRanking() {
        guard canEdit, category != nil, request.mode == .firstLog else { return }
        skipsRanking = true
        step = .details
        persist()
    }

    func setTrip(_ tripID: UUID?) {
        guard canEdit else { return }
        visit.tripID = tripID
        persist()
    }

    func setAudience(_ audience: Audience) {
        guard canEdit else { return }
        visit.audience = audience
        persist()
    }

    func selectCategory(_ value: ExperienceCategory) {
        guard canEdit, !categoryLocked else { return }
        category = value
        session = nil
        ranking = nil
        persist()
    }

    func selectSentiment(_ value: Sentiment) {
        guard canEdit, category != nil, request.mode != .addVisit else { return }
        sentiment = value
        session = nil
        ranking = nil
        message = nil
        step = .details
        persist()
    }

    @discardableResult
    func updateDetails(note: String, date: LocalDate?, mediaIDs: [UUID]? = nil) -> Bool {
        guard canEdit else { return false }
        guard Validation.characterCount(note) <= 5_000 else { message = "Public notes can have up to 5,000 characters."; return false }
        guard date.map({ $0 <= today }) ?? true else { message = "Choose today or an earlier visit date."; return false }
        let assets = mediaIDs ?? visit.mediaIDs
        guard assets.count <= 6 else { message = "A visit can have up to six photos."; return false }
        visit.publicNote = note
        visit.date = date
        if date != nil && visit.timeZoneIdentifier == nil { visit.timeZoneIdentifier = timeZone.identifier }
        visit.mediaIDs = assets
        message = nil
        persist()
        return persistenceError == nil
    }

    func backToSentiment() {
        guard canEdit, request.mode != .addVisit else { return }
        skipsRanking = false
        step = .sentiment
        session = nil
        ranking = nil
        persist()
    }

    func okay() async {
        guard canEdit, step == .details, accountMatches() else { return }
        if let photos {
            do { visit.mediaIDs = try photos.attachmentIDs() }
            catch { message = error.roamMessage; return }
        }
        guard Validation.characterCount(visit.publicNote) <= 5_000, visit.date.map({ $0 <= today }) ?? true else {
            message = "Check the note length and choose today or an earlier visit date."
            return
        }
        if request.mode == .addVisit || skipsRanking {
            pendingVisit = AddVisitRequest(operationID: operationID, experienceID: request.experience.id, visit: visit,
                                           category: skipsRanking ? category : nil)
            await submitPending()
        } else {
            await refreshComparisons()
        }
    }

    private func refreshComparisons() async {
        guard let category, let sentiment, accountMatches() else { return }
        generation += 1
        let token = generation
        step = .loading
        do {
            let current = try await service.categoryRanking(category)
            guard token == generation else { return }
            if Task.isCancelled {
                returnToDetailsAfterCancelledLoad()
                return
            }
            guard accountMatches() else { step = .details; return }
            ranking = current
            let base = request.mode == .rerank ? current.removing(experienceID: request.experience.id) : current
            session = InsertionSession(sentiment: sentiment, groups: base.groups(for: sentiment))
            step = .comparison
            persist()
            if session?.isComplete == true { await finishComparisons() }
        } catch {
            guard token == generation else { return }
            if error is CancellationError || Task.isCancelled {
                returnToDetailsAfterCancelledLoad()
                return
            }
            step = .details
            record(error)
            persist()
        }
    }

    private func returnToDetailsAfterCancelledLoad() {
        step = .details
        message = "Loading was interrupted. Your details are kept; tap Okay to retry."
        persist()
    }

    func choose(_ choice: ComparisonChoice) async {
        guard canEdit, step == .comparison, accountMatches() else { return }
        session?.choose(choice)
        persist()
        if session?.isComplete == true { await finishComparisons() }
    }

    func undo() {
        guard canUndo, canEdit else { return }
        session?.undo()
        persist()
    }

    private func finishComparisons() async {
        guard let category, let sentiment, let ranking, let session, session.isComplete else { return }
        pendingRating = RatingCommitRequest(operationID: operationID, intent: request.mode == .rerank ? .rerank : .firstLog,
                                            experienceID: request.experience.id, category: category, sentiment: sentiment,
                                            baseRevision: ranking.revision, answers: session.answers,
                                            visit: request.mode == .rerank && visit == initialVisit ? nil : visit)
        await submitPending()
    }

    func retrySave() async {
        guard step == .retry, hasPendingSave else { return }
        await submitPending()
    }

    private func submitPending() async {
        guard !isBusy, completion == nil, accountMatches() else { return }
        // Persist the exact request before sending; retries and process restarts reuse it.
        step = .retry
        persist()
        guard persistenceError == nil else { return }
        step = .saving
        message = nil
        do {
            let acknowledged: RatingFlowCompletion
            if let pendingRating { acknowledged = .rating(try await service.commitRating(pendingRating)) }
            else if let pendingVisit { acknowledged = .visit(try await service.addVisit(pendingVisit)) }
            else { step = .details; return }
            guard accountMatches() else { step = .retry; return }
            completion = acknowledged
            step = .result
            photos?.committed()
            pendingRating = nil
            pendingVisit = nil
            storage.remove(name: draftName, userID: accountID)
        } catch {
            guard currentAccount() == accountID else { step = .retry; return }
            if let roam = error as? RoamError, roam == .staleRevision {
                // The server definitively rejected this operation; enrichment stays intact.
                pendingRating = nil
                pendingVisit = nil
                operationID = UUID()
                message = "Your category list changed. Your note and visit date are kept; compare again with the refreshed list."
                step = .details
                session = nil
                ranking = nil
                persist()
            } else if let roam = error as? RoamError, Self.isDefiniteRejection(roam) {
                pendingRating = nil
                pendingVisit = nil
                operationID = UUID()
                step = .details
                if roam == .mediaExpired { photos?.expireStagedUploads() }
                record(error)
                persist()
            } else {
                step = .retry
                record(error)
                message = "Saving wasn't confirmed. Your details are kept. Retry checks the same save. \(error.roamMessage)"
                persist()
            }
        }
    }

    private static func isDefiniteRejection(_ error: RoamError) -> Bool {
        switch error {
        case .validation, .conflict, .alreadyRated, .forbidden, .notFound, .mediaExpired: return true
        default: return false
        }
    }

    func keepDraft() { if completion == nil { persist() } }

    func discardDraft() {
        guard !isBusy, !hasPendingSave else { return }
        generation += 1
        storage.remove(name: draftName, userID: accountID)
    }

    private func accountMatches() -> Bool {
        guard currentAccount() == accountID else { message = "Sign in to the account that owns this draft to continue."; return false }
        return true
    }

    private func record(_ error: Error) {
        message = error.roamMessage
        if let error = error as? RoamError, error == .sessionExpired || error == .notSignedIn { authError = error }
    }

    private func persist() {
        guard currentAccount() == accountID, completion == nil else { return }
        let draft = RatingFlowDraft(accountID: accountID, experienceID: request.experience.id, mode: request.mode.rawValue,
                                     updatedAt: now(), operationID: operationID, category: category, sentiment: sentiment,
                                     visit: visit, initialVisit: initialVisit, step: step, ranking: ranking,
                                     answers: session?.answers ?? [], pendingRating: pendingRating, pendingVisit: pendingVisit)
        do {
            try storage.write(draft, name: draftName, userID: accountID)
            persistenceError = nil
        } catch {
            persistenceError = "Your draft couldn't be kept on this device. Free some storage and retry before saving."
        }
    }
}
