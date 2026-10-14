import Foundation
import Observation

/// The viewer's bookmarks and rated experiences, shared by every surface so Save/Log state stays
/// synchronized. Bookmarks update optimistically and roll back on failure.
@MainActor
@Observable
final class LibraryStore {
    private(set) var library: UserLibrary = .empty
    private(set) var pending: [UUID: Bool] = [:]
    private(set) var lastError: String?
    /// Bumped after any acknowledged write so open screens can refresh derived data.
    private(set) var revision = 0

    private let lists: any ListService
    private var accountGeneration = 0

    init(services: AppServices) {
        self.lists = services.lists
    }

    init(lists: any ListService) { self.lists = lists }

    func refresh() async {
        let generation = accountGeneration
        let requestedRevision = revision
        if let latest = try? await lists.library(), generation == accountGeneration, requestedRevision == revision {
            // A snapshot begun before an acknowledged write must not undo that write locally.
            library = latest
            revision += 1
        }
    }

    func reset() {
        accountGeneration += 1
        lastError = nil
        library = .empty
        pending = [:]
        revision += 1
    }

    func isBookmarked(_ id: UUID) -> Bool { pending[id] ?? library.bookmarked.contains(id) }

    func ratedCategory(_ id: UUID) -> ExperienceCategory? { library.rated[id] }

    func saveState(for id: UUID) -> SaveActionState {
        if library.rated[id] != nil { return .alreadyBeen }
        if let target = pending[id] { return .pending(target: target) }
        return library.bookmarked.contains(id) ? .saved : .notSaved
    }

    /// Desired-state bookmark write with optimistic update and rollback. Duplicate taps while a
    /// write is in flight are ignored.
    @discardableResult
    func setBookmark(_ experienceID: UUID, saved: Bool) async -> Bool {
        guard pending[experienceID] == nil else { return false }
        let generation = accountGeneration
        let previous = library.bookmarked.contains(experienceID)
        pending[experienceID] = saved
        lastError = nil
        do {
            let persisted = try await lists.setBookmark(experienceID: experienceID, saved: saved)
            guard generation == accountGeneration else { return false }
            if persisted { library.bookmarked.insert(experienceID) } else { library.bookmarked.remove(experienceID) }
            pending[experienceID] = nil
            revision += 1
            return true
        } catch {
            guard generation == accountGeneration else { return false }
            if previous { library.bookmarked.insert(experienceID) } else { library.bookmarked.remove(experienceID) }
            pending[experienceID] = nil
            lastError = error.roamMessage
            if case RoamError.alreadyRated = error { await refresh() }
            return false
        }
    }

    func applyRated(_ experienceID: UUID, category: ExperienceCategory) {
        library.rated[experienceID] = category
        library.bookmarked.remove(experienceID)
        library.visited.insert(experienceID)
        revision += 1
    }

    func applyRatingRemoved(_ experienceID: UUID) {
        library.rated[experienceID] = nil
        revision += 1
    }

    func noteChanged() { revision += 1 }

    func clearError() { lastError = nil }
}
