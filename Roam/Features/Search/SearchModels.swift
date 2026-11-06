import Foundation
import Observation

struct SearchHit: Identifiable, Hashable, Sendable {
    let candidate: PlaceCandidate
    var experience: ExperienceSummary?

    var id: String { candidate.id }
    var category: ExperienceCategory? { experience?.category ?? candidate.suggestedCategory }
}

/// Experience search: 300 ms debounce (by the caller's task), cancellation, and
/// latest-query/destination-wins so a slow older response never replaces newer results.
@MainActor
@Observable
final class ExperienceSearchModel {
    enum Phase: Equatable {
        case idle
        case loading
        case results
        case noResults
        case failed(String)
    }

    var query = "" {
        didSet {
            guard query != oldValue else { return }
            // Invalidate immediately, before the view's debounce starts the next request.
            generation += 1
            isRefreshing = false
            refreshError = nil
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                hits = []
                phase = .idle
                lastQuery = ""
            }
        }
    }
    private(set) var phase: Phase = .idle
    private(set) var hits: [SearchHit] = []
    private(set) var isRefreshing = false
    private(set) var lastQuery = ""
    private(set) var refreshError: String?
    private var generation = 0
    private var projectionGeneration = 0
    private var foregroundLoading = false
    private var projectionRefreshQueued = false
    private let searchPlaces: (String, Destination?) async throws -> [PlaceCandidate]
    private let matchExperiences: ([PlaceCandidate]) async throws -> [String: ExperienceSummary]
    private let resolvePlace: (PlaceCandidate) async throws -> ExperienceSummary

    convenience init(services: AppServices) {
        self.init(searchPlaces: services.places.searchPlaces, matchExperiences: services.experiences.matches,
                  resolvePlace: services.experiences.resolve)
    }

    /// Feature-local injection keeps failure/race tests independent of the shared backend harness.
    init(searchPlaces: @escaping (String, Destination?) async throws -> [PlaceCandidate],
         matchExperiences: @escaping ([PlaceCandidate]) async throws -> [String: ExperienceSummary],
         resolvePlace: @escaping (PlaceCandidate) async throws -> ExperienceSummary) {
        self.searchPlaces = searchPlaces
        self.matchExperiences = matchExperiences
        self.resolvePlace = resolvePlace
    }

    func search(_ text: String, near destination: Destination?) async {
        query = text
        generation += 1
        let current = generation
        foregroundLoading = true
        defer {
            if current == generation {
                foregroundLoading = false
                isRefreshing = false
                if projectionRefreshQueued {
                    projectionRefreshQueued = false
                    Task { await self.refreshMatches() }
                }
            }
        }
        refreshError = nil
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            hits = []
            phase = .idle
            isRefreshing = false
            return
        }
        if hits.isEmpty { phase = .loading } else { isRefreshing = true }
        do {
            let candidates = try await searchPlaces(trimmed, destination)
            try Task.checkCancellation()
            guard current == generation else { return }
            // A backend failure is not evidence that a place is unrated or unsaved.
            let matches = try await matchExperiences(candidates)
            try Task.checkCancellation()
            guard current == generation else { return }
            hits = candidates.map { SearchHit(candidate: $0, experience: matches[$0.id]) }
            lastQuery = trimmed
            phase = hits.isEmpty ? .noResults : .results
        } catch is CancellationError {
            if current == generation { phase = hits.isEmpty ? .idle : .results }
        } catch {
            guard current == generation else { return }
            guard !Task.isCancelled else { return }
            if hits.isEmpty {
                phase = .failed(error.roamMessage)
            } else {
                refreshError = error.roamMessage
                phase = .results
            }
        }
    }

    func refreshMatches() async {
        if foregroundLoading { projectionRefreshQueued = true; return }
        guard !hits.isEmpty else { return }
        projectionGeneration += 1
        let projection = projectionGeneration
        let current = generation
        let candidates = hits.map(\.candidate)
        isRefreshing = true
        defer { if current == generation && projection == projectionGeneration { isRefreshing = false } }
        do {
            let matches = try await matchExperiences(candidates)
            try Task.checkCancellation()
            guard current == generation, projection == projectionGeneration else { return }
            hits = candidates.map { SearchHit(candidate: $0, experience: matches[$0.id]) }
            refreshError = nil
        } catch {
            guard current == generation, projection == projectionGeneration else { return }
            refreshError = error.roamMessage
        }
    }

    /// Resolves a hit into its one Roam experience (first save/log/open only).
    func resolve(_ hit: SearchHit) async throws -> ExperienceSummary {
        if let experience = hit.experience { return experience }
        let summary = try await resolvePlace(hit.candidate)
        if let index = hits.firstIndex(where: { $0.id == hit.id }) { hits[index].experience = summary }
        return summary
    }
}

/// Member search with stable, cursor-paginated results.
@MainActor
@Observable
final class MemberSearchModel {
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            generation += 1
            loadingMore = false
            isRefreshing = false
            nextCursor = nil
            pageError = nil
            refreshError = nil
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                rows = []
                phase = .idle
                lastQuery = ""
            }
        }
    }
    private(set) var rows: [MemberRow] = []
    private(set) var phase: LoadPhase<Void> = .idle
    private(set) var nextCursor: String?
    private(set) var pageError: String?
    private(set) var loadingMore = false
    private(set) var isRefreshing = false
    private(set) var refreshError: String?
    private(set) var followError: String?
    private(set) var lastQuery = ""
    private(set) var pendingFollows: Set<UUID> = []
    private var generation = 0
    private let searchMembers: (String, String?) async throws -> Page<MemberRow>
    private let setFollow: (UUID, Bool) async throws -> Bool

    convenience init(services: AppServices) {
        self.init(searchMembers: services.social.searchMembers, setFollow: services.social.setFollow)
    }

    init(searchMembers: @escaping (String, String?) async throws -> Page<MemberRow>,
         setFollow: @escaping (UUID, Bool) async throws -> Bool) {
        self.searchMembers = searchMembers
        self.setFollow = setFollow
    }

    func search(_ text: String) async {
        query = text
        generation += 1
        let current = generation
        loadingMore = false
        pageError = nil
        refreshError = nil
        defer { if current == generation { isRefreshing = false } }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            rows = []
            nextCursor = nil
            phase = .idle
            return
        }
        if rows.isEmpty { phase = .loading } else { isRefreshing = true }
        do {
            let page = try await searchMembers(trimmed, nil)
            try Task.checkCancellation()
            guard current == generation else { return }
            rows = page.items
            nextCursor = page.nextCursor
            lastQuery = trimmed
            pageError = nil
            phase = .loaded(())
        } catch is CancellationError {
            if current == generation { phase = rows.isEmpty ? .idle : .loaded(()) }
        } catch {
            guard current == generation else { return }
            guard !Task.isCancelled else { return }
            if rows.isEmpty {
                phase = .failed(error.roamMessage)
            } else {
                refreshError = error.roamMessage
                phase = .loaded(())
            }
        }
    }

    func loadMore() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cursor = nextCursor, !loadingMore, !isRefreshing, trimmed == lastQuery else { return }
        let current = generation
        loadingMore = true
        defer { if current == generation { loadingMore = false } }
        do {
            let page = try await searchMembers(trimmed, cursor)
            try Task.checkCancellation()
            guard current == generation, trimmed == lastQuery else { return }
            var known = Set(rows.map(\.id))
            rows += page.items.filter { known.insert($0.id).inserted }
            nextCursor = page.nextCursor
            pageError = nil
        } catch is CancellationError {
        } catch {
            guard current == generation, !Task.isCancelled else { return }
            pageError = error.roamMessage
        }
    }

    /// Optimistic follow with rollback; duplicate taps are ignored while in flight.
    func toggleFollow(_ row: MemberRow) async {
        guard !pendingFollows.contains(row.id), let index = rows.firstIndex(where: { $0.id == row.id }) else { return }
        let target = !rows[index].isFollowing
        pendingFollows.insert(row.id)
        followError = nil
        rows[index].isFollowing = target
        defer { pendingFollows.remove(row.id) }
        do {
            let persisted = try await setFollow(row.id, target)
            if let i = rows.firstIndex(where: { $0.id == row.id }) { rows[i].isFollowing = persisted }
        } catch {
            if let i = rows.firstIndex(where: { $0.id == row.id }) { rows[i].isFollowing = !target }
            followError = error.roamMessage
        }
    }

    func clearFollowError() { followError = nil }
}
