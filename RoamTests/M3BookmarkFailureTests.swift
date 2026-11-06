import XCTest
@testable import Roam

private actor ControlledListService: ListService {
    var ids = Set<UUID>()
    var failNext = false
    var delay: Duration = .zero
    func fail() { failNext = true }
    func wait(_ delay: Duration) { self.delay = delay }
    func library() async throws -> UserLibrary { UserLibrary(bookmarked: ids, rated: [:], visited: []) }
    func setBookmark(experienceID: UUID, saved: Bool) async throws -> Bool {
        if delay > .zero { try await Task.sleep(for: delay) }
        if failNext { failNext = false; throw RoamError.offline }
        if saved { ids.insert(experienceID) } else { ids.remove(experienceID) }
        return saved
    }
    func been(ownerID: UUID) async throws -> [ListEntry] { [] }
    func want(ownerID: UUID) async throws -> [ListEntry] { [] }
    func sharedWants(with otherUserID: UUID) async throws -> [ListEntry] { [] }
}

/// Captures a server snapshot, then holds its response until the test acknowledges a mutation.
private actor GatedBookmarkSnapshotService: ListService {
    private var ids = Set<UUID>()
    private var snapshotRequested = false
    private var snapshotWaiter: CheckedContinuation<Void, Never>?
    private var requestWaiter: CheckedContinuation<Void, Never>?

    func library() async throws -> UserLibrary {
        let snapshot = UserLibrary(bookmarked: ids, rated: [:], visited: [])
        await withCheckedContinuation { continuation in
            snapshotWaiter = continuation
            snapshotRequested = true
            requestWaiter?.resume()
            requestWaiter = nil
        }
        return snapshot
    }

    func waitForSnapshotRequest() async {
        guard !snapshotRequested else { return }
        await withCheckedContinuation { requestWaiter = $0 }
    }

    func releaseSnapshot() {
        snapshotWaiter?.resume()
        snapshotWaiter = nil
    }

    func setBookmark(experienceID: UUID, saved: Bool) async throws -> Bool {
        if saved { ids.insert(experienceID) } else { ids.remove(experienceID) }
        return saved
    }
    func been(ownerID: UUID) async throws -> [ListEntry] { [] }
    func want(ownerID: UUID) async throws -> [ListEntry] { [] }
    func sharedWants(with otherUserID: UUID) async throws -> [ListEntry] { [] }
}

@MainActor
final class M3BookmarkFailureTests: XCTestCase {
    func testLateSameAccountSnapshotCannotUndoAcknowledgedSaveOrRemoval() async {
        for desired in [true, false] {
            let service = GatedBookmarkSnapshotService()
            let library = LibraryStore(lists: service)
            let id = UUID()
            if !desired {
                let seeded = await library.setBookmark(id, saved: true)
                XCTAssertTrue(seeded)
            }
            let refresh = Task { await library.refresh() }
            await service.waitForSnapshotRequest()
            let acknowledged = await library.setBookmark(id, saved: desired)
            XCTAssertTrue(acknowledged)
            XCTAssertEqual(library.isBookmarked(id), desired)
            let acknowledgedRevision = library.revision
            await service.releaseSnapshot()
            await refresh.value
            XCTAssertEqual(library.isBookmarked(id), desired, "An older snapshot cannot reverse acknowledged desired state \(desired)")
            XCTAssertEqual(library.revision, acknowledgedRevision, "Rejected stale snapshots do not trigger derived-list refreshes")
            XCTAssertTrue(library.pending.isEmpty)
        }
    }

    func testNetworkFailureRollsBackThenSameDesiredStateRetries() async {
        let service = ControlledListService()
        let library = LibraryStore(lists: service)
        let id = UUID()
        await service.fail()
        let failed = await library.setBookmark(id, saved: true)
        XCTAssertFalse(failed)
        XCTAssertFalse(library.isBookmarked(id))
        XCTAssertNotNil(library.lastError)
        let retried = await library.setBookmark(id, saved: true)
        XCTAssertTrue(retried)
        XCTAssertTrue(library.isBookmarked(id))
        XCTAssertNil(library.lastError)
        await service.fail()
        let failedRemoval = await library.setBookmark(id, saved: false)
        XCTAssertFalse(failedRemoval)
        XCTAssertTrue(library.isBookmarked(id), "Failed removal retains acknowledged save")
    }

    func testAccountResetCannotBeOverwrittenByOldPendingWrite() async {
        let service = ControlledListService()
        await service.wait(.milliseconds(40))
        let library = LibraryStore(lists: service)
        let id = UUID()
        let write = Task { await library.setBookmark(id, saved: true) }
        await Task.yield()
        XCTAssertTrue(library.isBookmarked(id))
        library.reset()
        let acknowledgedInOldAccount = await write.value
        XCTAssertFalse(acknowledgedInOldAccount)
        XCTAssertFalse(library.isBookmarked(id))
        XCTAssertTrue(library.pending.isEmpty)
        XCTAssertNil(library.lastError)
    }
}
