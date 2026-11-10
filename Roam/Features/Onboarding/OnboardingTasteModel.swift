import Foundation
import MapKit
import Observation

/// Onboarding's taste steps: pick places you've been around home, then say how each was and place it among the others
/// with the same comparisons as the log screen. Each place is saved as soon as it's ranked, as a visit with no date seen
/// by friends, so it seeds your Been list without showing up on anyone's Friends tab. All of it can be skipped.
@MainActor
@Observable
final class OnboardingTasteModel {
    /// Comparisons asked across the whole of onboarding; after that, places go to the middle of where they'd fit.
    static let comparisonBudget = 10
    /// How far around home to look for places, in metres.
    static let homeRadius: CLLocationDistance = 20_000

    enum Stage: Equatable {
        case picking
        /// How was it? for the place at this index of `selected`.
        case feeling(Int)
        case comparing(Int)
        case saving(Int)
        case done
    }

    private(set) var candidates: LoadPhase<[ExperienceSummary]> = .idle
    private(set) var searchResults: [SearchHit] = []
    private(set) var selected: [ExperienceSummary] = []
    private(set) var stage: Stage = .picking
    private(set) var session: InsertionSession?
    private(set) var comparisonsUsed = 0
    private(set) var savedCount = 0
    var feeling: Sentiment?
    var error: String?

    private let services: AppServices
    private var ranking: CategoryRanking?
    private var operationID = UUID()

    init(services: AppServices) {
        self.services = services
    }

    // MARK: Picking

    /// Places around home: your friends' first. Without a home, it's search only.
    func loadCandidates(home: Destination?) async {
        guard let home else { candidates = .loaded([]); return }
        candidates = .loading
        let bounds = GeoBounds(region: MKCoordinateRegion(center: home.coordinate, latitudinalMeters: Self.homeRadius * 2,
                                                          longitudinalMeters: Self.homeRadius * 2))
        do {
            candidates = .loaded(try await services.plans.onboardingPlaces(in: bounds).filter { Self.category(of: $0) != nil })
        } catch {
            candidates = .failed(error.roamMessage)
        }
    }

    func search(_ text: String, near home: Destination?) async {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { searchResults = []; return }
        do {
            let found = try await services.places.searchPlaces(query: query, around: home).filter {
                !$0.isLocality && ($0.suggestedCategory ?? PlaceCategoryMapper.suggestedCategory(rawProviderCategory: $0.providerCategory, isLocality: false)) != nil
            }
            let known = (try? await services.experiences.matches(for: found)) ?? [:]
            guard !Task.isCancelled else { return }
            searchResults = found.prefix(8).map { SearchHit(candidate: $0, experience: known[$0.id]) }
                .filter { $0.experience.map { !$0.viewer.hasVisits && $0.viewer.myScore == nil } ?? true }
        } catch {
            searchResults = []
        }
    }

    /// Picks a search result. A place that isn't on Roam yet is added to Roam first (nothing is logged until it's ranked).
    func add(_ hit: SearchHit) async {
        do {
            let place: ExperienceSummary
            if let known = hit.experience { place = known } else { place = try await services.experiences.resolve(hit.candidate) }
            if !isSelected(place) { selected.append(place) }
            error = nil
        } catch {
            self.error = error.roamMessage
        }
    }

    func isSelected(_ place: ExperienceSummary) -> Bool { selected.contains { $0.id == place.id } }

    func toggle(_ place: ExperienceSummary) {
        if let index = selected.firstIndex(where: { $0.id == place.id }) { selected.remove(at: index) } else { selected.append(place) }
    }

    /// Starts on the first picked place, or finishes when nothing was picked.
    func startRanking() {
        stage = selected.isEmpty ? .done : .feeling(0)
        feeling = nil
    }

    // MARK: Ranking

    var currentIndex: Int? {
        switch stage {
        case .feeling(let index), .comparing(let index), .saving(let index): return index
        case .picking, .done: return nil
        }
    }

    var current: ExperienceSummary? { currentIndex.map { selected[$0] } }

    /// "2 of 4".
    var progressLabel: String? { currentIndex.map { "\($0 + 1) of \(selected.count)" } }

    /// The place this one is being compared with.
    var comparison: RankedEntry? { session?.currentComparison }
    var canUndo: Bool { session?.canUndo == true }

    func pick(_ sentiment: Sentiment) async {
        guard case .feeling(let index) = stage, let category = Self.category(of: selected[index]) else { return }
        feeling = sentiment
        error = nil
        do {
            let current = try await services.ranking.categoryRanking(category)
            ranking = current
            session = InsertionSession(sentiment: sentiment, groups: current.groups(for: sentiment))
            operationID = UUID()
            stage = .comparing(index)
            await advanceIfDone()
        } catch {
            self.error = error.roamMessage
        }
    }

    func choose(_ choice: ComparisonChoice) async {
        guard case .comparing = stage, session?.isComplete == false else { return }
        session?.choose(choice)
        comparisonsUsed += 1
        await advanceIfDone()
    }

    func undo() {
        guard canUndo else { return }
        session?.undo()
        comparisonsUsed = max(0, comparisonsUsed - 1)
    }

    /// Saves the place once its spot is known. Out of comparisons, it goes to the middle of where it could still be.
    private func advanceIfDone() async {
        guard case .comparing(let index) = stage, var session else { return }
        if !session.isComplete && comparisonsUsed >= Self.comparisonBudget {
            session.choose(.skip)
            self.session = session
        }
        guard session.isComplete else { return }
        await save(index)
    }

    /// Retries a save that didn't go through.
    func retry() async {
        guard let index = currentIndex else { return }
        await save(index)
    }

    private func save(_ index: Int) async {
        guard let session, let ranking, let sentiment = feeling, let category = Self.category(of: selected[index]) else { return }
        stage = .saving(index)
        error = nil
        let request = RatingCommitRequest(operationID: operationID, intent: .firstLog, experienceID: selected[index].id, category: category,
                                          sentiment: sentiment, baseRevision: ranking.revision, answers: session.answers,
                                          visit: VisitPayload(date: nil, timeZoneIdentifier: nil, publicNote: "", mediaIDs: [], audience: .friends))
        do {
            _ = try await services.ranking.commitRating(request)
            savedCount += 1
            next(after: index)
        } catch RoamError.staleRevision {
            // The list changed under us: compare again against the fresh one.
            stage = .feeling(index)
            await pick(sentiment)
        } catch {
            stage = .comparing(index)
            self.error = error.roamMessage
        }
    }

    private func next(after index: Int) {
        session = nil
        ranking = nil
        feeling = nil
        stage = index + 1 < selected.count ? .feeling(index + 1) : .done
    }

    /// Stops ranking; places already saved stay saved.
    func skipRest() {
        session = nil
        stage = .done
    }

    /// The place's category, or Apple's best guess at it.
    static func category(of place: ExperienceSummary) -> ExperienceCategory? {
        guard place.category != .dayTrips else { return nil }
        return place.category ?? PlaceCategoryMapper.suggestedCategory(rawProviderCategory: place.providerCategory, isLocality: false)
    }
}
