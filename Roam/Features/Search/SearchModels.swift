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

    var query = ""
    private(set) var phase: Phase = .idle
    private(set) var hits: [SearchHit] = []
    private(set) var isRefreshing = false
    private(set) var lastQuery = ""
    private var generation = 0
    private let services: AppServices

    init(services: AppServices) {
        self.services = services
    }

    func search(_ text: String, near destination: Destination?) async {
        generation += 1
        let current = generation
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            hits = []
            phase = .idle
            isRefreshing = false
            return
        }
        if hits.isEmpty { phase = .loading } else { isRefreshing = true }
        do {
            let candidates = try await services.places.searchPlaces(query: trimmed, around: destination)
            try Task.checkCancellation()
            let matches = (try? await services.experiences.matches(for: candidates)) ?? [:]
            guard current == generation else { return }
            hits = candidates.map { SearchHit(candidate: $0, experience: matches[$0.id]) }
            lastQuery = trimmed
            phase = hits.isEmpty ? .noResults : .results
        } catch is CancellationError {
        } catch {
            guard current == generation else { return }
            phase = .failed(error.roamMessage)
        }
        if current == generation { isRefreshing = false }
    }

    /// Resolves a hit into its one Roam experience (first save/log/open only).
    func resolve(_ hit: SearchHit) async throws -> ExperienceSummary {
        if let experience = hit.experience { return experience }
        let summary = try await services.experiences.resolve(hit.candidate)
        if let index = hits.firstIndex(where: { $0.id == hit.id }) { hits[index].experience = summary }
        return summary
    }
}

/// Member search with stable, cursor-paginated results.
@MainActor
@Observable
final class MemberSearchModel {
    var query = ""
    private(set) var rows: [MemberRow] = []
    private(set) var phase: LoadPhase<Void> = .idle
    private(set) var nextCursor: String?
    private(set) var pageError: String?
    private(set) var loadingMore = false
    private(set) var pendingFollows: Set<UUID> = []
    private var generation = 0
    private let services: AppServices

    init(services: AppServices) {
        self.services = services
    }

    func search(_ text: String) async {
        generation += 1
        let current = generation
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            rows = []
            nextCursor = nil
            phase = .idle
            return
        }
        if rows.isEmpty { phase = .loading }
        do {
            let page = try await services.social.searchMembers(query: trimmed, cursor: nil)
            guard current == generation else { return }
            rows = page.items
            nextCursor = page.nextCursor
            pageError = nil
            phase = .loaded(())
        } catch is CancellationError {
        } catch {
            guard current == generation else { return }
            phase = .failed(error.roamMessage)
        }
    }

    func loadMore() async {
        guard let cursor = nextCursor, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let page = try await services.social.searchMembers(query: query, cursor: cursor)
            let known = Set(rows.map(\.id))
            rows += page.items.filter { !known.contains($0.id) }
            nextCursor = page.nextCursor
            pageError = nil
        } catch {
            pageError = error.roamMessage
        }
    }

    /// Optimistic follow with rollback; duplicate taps are ignored while in flight.
    func toggleFollow(_ row: MemberRow) async {
        guard !pendingFollows.contains(row.id), let index = rows.firstIndex(of: row) else { return }
        let target = !row.isFollowing
        pendingFollows.insert(row.id)
        rows[index].isFollowing = target
        defer { pendingFollows.remove(row.id) }
        do {
            let persisted = try await services.social.setFollow(userID: row.id, following: target)
            if let i = rows.firstIndex(where: { $0.id == row.id }) { rows[i].isFollowing = persisted }
        } catch {
            if let i = rows.firstIndex(where: { $0.id == row.id }) { rows[i].isFollowing = !target }
            pageError = error.roamMessage
        }
    }
}
