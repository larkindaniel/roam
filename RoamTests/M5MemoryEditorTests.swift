import Foundation
import XCTest
@testable import Roam

/// Memory service double with server-like receipts: a repeated operation returns its original
/// result, and scripted outcomes simulate timeouts and definite rejections.
private actor MemoryTestService: MemoryService {
    var visits: [UUID: Visit]
    var notes: [UUID: PrivateNote] = [:]
    var pages: [String: Page<PublicMemory>] = [:]
    private var updateOutcomes: [RoamError?] = []
    private var noteOutcomes: [RoamError?] = []
    private var pageOutcomes: [RoamError?] = []
    private var receipts: [UUID: Visit] = [:]
    private(set) var updateOperations: [UUID] = []
    private(set) var updatePayloads: [[UUID]] = []
    private(set) var noteOperations: [UUID] = []
    private(set) var pageRequests: [String?] = []

    init(visits: [Visit] = []) { self.visits = Dictionary(uniqueKeysWithValues: visits.map { ($0.id, $0) }) }

    func script(updates: [RoamError?] = [], notes: [RoamError?] = [], pages: [RoamError?] = []) {
        updateOutcomes += updates; noteOutcomes += notes; pageOutcomes += pages
    }
    func setNote(_ note: PrivateNote?, for experience: UUID) { notes[experience] = note }
    func setPage(_ page: Page<PublicMemory>, cursor: String?) { pages[cursor ?? "first"] = page }

    func visit(visitID: UUID) async throws -> Visit {
        guard let visit = visits[visitID] else { throw RoamError.notFound }
        return visit
    }

    func publicMemories(experienceID: UUID, cursor: String?) async throws -> Page<PublicMemory> {
        pageRequests.append(cursor)
        if !pageOutcomes.isEmpty, let error = pageOutcomes.removeFirst() { throw error }
        return pages[cursor ?? "first"] ?? .empty
    }

    func updateVisit(visitID: UUID, note: String, date: VisitDate, mediaIDs: [UUID], operationID: UUID) async throws -> Visit {
        updateOperations.append(operationID)
        updatePayloads.append(mediaIDs)
        if let receipt = receipts[operationID] { return receipt }
        let outcome = updateOutcomes.isEmpty ? nil : updateOutcomes.removeFirst()
        if let outcome, !outcome.isRetryable { throw outcome }
        guard var visit = visits[visitID] else { throw RoamError.notFound }
        visit.publicNote = note
        visit.visitDate = date
        visit.media = mediaIDs.enumerated().compactMap { index, id in
            visits[visitID]?.media.first { $0.id == id }.map { MediaRef(id: $0.id, path: $0.path, width: $0.width, height: $0.height, position: index) }
        }
        visits[visitID] = visit
        receipts[operationID] = visit
        // A retryable outcome models a committed write whose response was lost.
        if let outcome { throw outcome }
        return visit
    }

    func privateNote(experienceID: UUID) async throws -> PrivateNote? { notes[experienceID] }

    func savePrivateNote(experienceID: UUID, text: String, operationID: UUID) async throws -> PrivateNote {
        noteOperations.append(operationID)
        if !noteOutcomes.isEmpty, let error = noteOutcomes.removeFirst() { throw error }
        let note = PrivateNote(experienceID: experienceID, text: text, updatedAt: Date())
        notes[experienceID] = note
        return note
    }

    func deletePrivateNote(experienceID: UUID, operationID: UUID) async throws {
        noteOperations.append(operationID)
        if !noteOutcomes.isEmpty, let error = noteOutcomes.removeFirst() { throw error }
        notes[experienceID] = nil
    }
}

@MainActor
final class M5MemoryEditorTests: XCTestCase {
    private let owner = UUID()
    private let experience = UUID()
    private var storage: AccountStorage!
    private var account: UUID?

    override func setUp() async throws {
        storage = AccountStorage(root: FileManager.default.temporaryDirectory.appendingPathComponent("m5-memory-\(UUID().uuidString)"))
        account = owner
    }

    private func visit(owner: UUID? = nil, media: [MediaRef] = []) -> Visit {
        Visit(id: UUID(), experienceID: experience, ownerID: owner ?? self.owner,
              visitDate: VisitDate(date: LocalDate(isoString: "2026-05-01"), timeZoneIdentifier: "Europe/Lisbon"),
              publicNote: "Original note", media: media, createdAt: Date(), updatedAt: Date())
    }

    private func media(_ positions: [Int]) -> [MediaRef] {
        positions.map { MediaRef(id: UUID(), path: "visit-media/o/\(UUID().uuidString).jpg", width: 4, height: 3, position: $0) }
    }

    private func editor(_ visit: Visit, service: MemoryTestService) -> VisitMemoryEditorModel {
        VisitMemoryEditorModel(visit: visit, ownerID: owner, memories: service, storage: storage, currentAccount: { [unowned self] in self.account })
    }

    // MARK: Visit memory editor

    func testEditorChangesStayLocalUntilDoneAndSurviveRestartUntilDiscarded() async throws {
        let original = visit()
        let service = MemoryTestService(visits: [original])
        let model = editor(original, service: service)
        model.note = "Draft note"
        XCTAssertEqual(editor(original, service: service).note, "Draft note", "An interrupted edit survives a restart")
        let calls = await service.updateOperations
        XCTAssertTrue(calls.isEmpty, "Typing never publishes on its own")
        model.discard()
        XCTAssertEqual(editor(original, service: service).note, "Original note", "Cancel discards the local draft")
    }

    func testUncertainSaveKeepsTheExactPendingEditAndRetriesTheSameOperation() async throws {
        let original = visit()
        let service = MemoryTestService(visits: [original])
        await service.script(updates: [.timeout])
        let model = editor(original, service: service)
        model.note = "Edited once"
        await model.save()
        XCTAssertNil(model.saved)
        XCTAssertNotNil(model.pending)
        XCTAssertFalse(model.canEdit, "An unconfirmed save freezes the submitted edit")
        let restored = editor(original, service: service)
        XCTAssertEqual(restored.pending, model.pending, "The exact pending request survives a restart")
        await restored.save()
        XCTAssertEqual(restored.saved?.publicNote, "Edited once")
        let operations = await service.updateOperations
        XCTAssertEqual(operations.count, 2)
        XCTAssertEqual(Set(operations).count, 1, "Retry reuses the original operation so it cannot double-apply")
        XCTAssertEqual(editor(original, service: service).note, "Original note", "An acknowledged edit clears its draft")
    }

    func testDefiniteRejectionKeepsTheEditAndFlagsExpiredPhotos() async throws {
        let original = visit()
        let service = MemoryTestService(visits: [original])
        await service.script(updates: [.mediaExpired])
        let model = editor(original, service: service)
        model.note = "Keep me"
        await model.save()
        XCTAssertNil(model.pending, "A definite rejection allows a fresh attempt")
        XCTAssertTrue(model.rejectedExpiredMedia)
        XCTAssertEqual(model.note, "Keep me")
        XCTAssertEqual(model.error, RoamError.mediaExpired.errorDescription)
    }

    func testLocalValidationRejectsFutureDatesAndLongNotesWithoutCallingTheServer() async throws {
        let original = visit()
        let service = MemoryTestService(visits: [original])
        let model = editor(original, service: service)
        model.date = VisitDate(date: model.today.adding(days: 1), timeZoneIdentifier: model.zone.identifier)
        await model.save()
        XCTAssertEqual(model.error, "Choose today or an earlier visit date.")
        model.date = .unknown
        model.note = String(repeating: "é", count: 5_001)
        await model.save()
        XCTAssertEqual(model.error, "Public notes can have up to 5,000 characters.")
        let calls = await service.updateOperations
        XCTAssertTrue(calls.isEmpty)
    }

    func testAnotherSignedInAccountCannotSaveTheOwnersEdit() async throws {
        let original = visit()
        let service = MemoryTestService(visits: [original])
        let model = editor(original, service: service)
        model.note = "Owner draft"
        account = UUID()
        await model.save()
        XCTAssertNil(model.saved)
        let calls = await service.updateOperations
        XCTAssertTrue(calls.isEmpty)
    }

    // MARK: Private note

    func testPrivateNoteLoadsSavesAndDeletesWithAcknowledgement() async throws {
        let service = MemoryTestService()
        await service.setNote(PrivateNote(experienceID: experience, text: "Locker 12", updatedAt: Date()), for: experience)
        let model = PrivateNoteEditorModel(experienceID: experience, ownerID: owner, memories: service, storage: storage, currentAccount: { [unowned self] in self.account })
        await model.load()
        XCTAssertEqual(model.text, "Locker 12")
        XCTAssertTrue(model.hasSavedNote)
        model.text = "Locker 14"
        await model.save()
        XCTAssertTrue(model.didSave)
        let saved = await service.notes[experience]?.text
        XCTAssertEqual(saved, "Locker 14")
        let deleting = PrivateNoteEditorModel(experienceID: experience, ownerID: owner, memories: service, storage: storage, currentAccount: { [unowned self] in self.account })
        await deleting.load()
        await deleting.save(delete: true)
        XCTAssertTrue(deleting.didSave)
        let remaining = await service.notes[experience]
        XCTAssertNil(remaining)
    }

    func testUnconfirmedPrivateNoteSaveSurvivesRestartAndRetriesTheSameOperation() async throws {
        let service = MemoryTestService()
        await service.script(notes: [.timeout])
        let model = PrivateNoteEditorModel(experienceID: experience, ownerID: owner, memories: service, storage: storage, currentAccount: { [unowned self] in self.account })
        await model.load()
        model.text = "Gate code 4411"
        await model.save()
        XCTAssertFalse(model.didSave)
        XCTAssertNotNil(model.pendingID)
        let restored = PrivateNoteEditorModel(experienceID: experience, ownerID: owner, memories: service, storage: storage, currentAccount: { [unowned self] in self.account })
        XCTAssertEqual(restored.pendingID, model.pendingID)
        await restored.load()
        XCTAssertEqual(restored.text, "Gate code 4411", "The restored draft wins over the server's older note")
        await restored.save()
        XCTAssertTrue(restored.didSave)
        let operations = await service.noteOperations
        XCTAssertEqual(Set(operations).count, 1)
    }

    func testPrivateNoteDraftsBelongOnlyToTheirOwner() async throws {
        let service = MemoryTestService()
        let model = PrivateNoteEditorModel(experienceID: experience, ownerID: owner, memories: service, storage: storage, currentAccount: { [unowned self] in self.account })
        await model.load()
        model.text = "Only mine"
        let other = UUID()
        account = other
        let foreign = PrivateNoteEditorModel(experienceID: experience, ownerID: other, memories: service, storage: storage, currentAccount: { [unowned self] in self.account })
        await foreign.load()
        XCTAssertEqual(foreign.text, "", "Another account never sees this account's private draft")
    }

    // MARK: Gallery

    func testVisitGalleryOrdersPhotosAndRemovesOwnPhotoThroughAnAcknowledgedEdit() async throws {
        let refs = media([2, 0, 1])
        let original = visit(media: refs)
        let service = MemoryTestService(visits: [original])
        let gallery = VisitGalleryModel(experienceID: experience, visitID: original.id, ownerID: owner, memories: service,
                                        storage: storage, currentAccount: { [unowned self] in self.account })
        await gallery.load()
        XCTAssertEqual(gallery.photos.map(\.id), [refs[1].id, refs[2].id, refs[0].id])
        await gallery.remove(try XCTUnwrap(gallery.photos.first))
        let payloads = await service.updatePayloads
        XCTAssertEqual(payloads.last, [refs[2].id, refs[0].id], "Removal keeps the other photos in order")
        XCTAssertEqual(gallery.photos.map(\.id), [refs[2].id, refs[0].id])
        XCTAssertEqual(gallery.removedPhotoID, refs[1].id)
        let stored = await service.visits[original.id]
        XCTAssertEqual(stored?.publicNote, "Original note", "Removing a photo keeps the note and date")
    }

    func testUncertainPhotoRemovalSurvivesRestartAndRetriesTheSameOperation() async throws {
        let refs = media([0, 1])
        let original = visit(media: refs)
        let service = MemoryTestService(visits: [original])
        await service.script(updates: [.timeout])
        let gallery = VisitGalleryModel(experienceID: experience, visitID: original.id, ownerID: owner, memories: service,
                                        storage: storage, currentAccount: { [unowned self] in self.account })
        await gallery.load()
        await gallery.remove(try XCTUnwrap(gallery.photos.first))
        XCTAssertNotNil(gallery.pendingRemoval)
        let restored = VisitGalleryModel(experienceID: experience, visitID: original.id, ownerID: owner, memories: service,
                                         storage: storage, currentAccount: { [unowned self] in self.account })
        XCTAssertEqual(restored.pendingRemoval, gallery.pendingRemoval)
        await restored.retryRemoval()
        XCTAssertNil(restored.pendingRemoval)
        let operations = await service.updateOperations
        XCTAssertEqual(Set(operations).count, 1, "The retried removal is the same operation")
    }

    func testOtherMembersPhotosCannotBeRemoved() async throws {
        let original = visit(owner: UUID(), media: media([0]))
        let service = MemoryTestService(visits: [original])
        let gallery = VisitGalleryModel(experienceID: experience, visitID: original.id, ownerID: owner, memories: service,
                                        storage: storage, currentAccount: { [unowned self] in self.account })
        await gallery.load()
        XCTAssertEqual(gallery.photos.first?.isOwn, false)
        await gallery.remove(try XCTUnwrap(gallery.photos.first))
        let calls = await service.updateOperations
        XCTAssertTrue(calls.isEmpty)
    }

    func testExperienceGalleryPaginatesWithoutDuplicatesAndKeepsPhotosOnPageFailure() async throws {
        let service = MemoryTestService()
        let author = MemberSummary(id: UUID(), handle: "theowanders", displayName: "Theo Park", avatarPath: nil)
        let shared = media([0])
        func memory(_ refs: [MediaRef]) -> PublicMemory {
            PublicMemory(id: UUID(), author: author, experienceID: experience, visitDate: .unknown, publicNote: "", media: refs,
                         createdAt: Date(), updatedAt: Date(), isOwn: false)
        }
        await service.setPage(Page(items: [memory(shared + media([1]))], nextCursor: "c1"), cursor: nil)
        await service.setPage(Page(items: [memory(shared), memory(media([0]))], nextCursor: nil), cursor: "c1")
        let gallery = VisitGalleryModel(experienceID: experience, ownerID: owner, memories: service, storage: storage,
                                        currentAccount: { [unowned self] in self.account })
        await gallery.load()
        XCTAssertEqual(gallery.photos.count, 2)
        await service.script(pages: [.timeout])
        await gallery.loadMore()
        XCTAssertEqual(gallery.photos.count, 2, "A failed page keeps the photos already shown")
        XCTAssertNotNil(gallery.pageError)
        await gallery.loadMore()
        XCTAssertEqual(gallery.photos.count, 3, "Paging deduplicates the same photo")
        XCTAssertNil(gallery.nextCursor)
    }

    // MARK: Public memories

    func testPublicMemoriesRefreshFailureKeepsTheAcknowledgedPage() async throws {
        let service = MemoryTestService()
        let author = MemberSummary(id: UUID(), handle: "lenaeats", displayName: "Lena Ortiz", avatarPath: nil)
        let item = PublicMemory(id: UUID(), author: author, experienceID: experience, visitDate: .unknown, publicNote: "Great view",
                                media: [], createdAt: Date(), updatedAt: Date(), isOwn: false)
        await service.setPage(Page(items: [item], nextCursor: "next"), cursor: nil)
        await service.setPage(Page(items: [item], nextCursor: nil), cursor: "next")
        let model = PublicMemoriesModel(experienceID: experience, service: service)
        await model.load()
        XCTAssertEqual(model.memories.map(\.id), [item.id])
        await service.script(pages: [.offline])
        await model.load()
        XCTAssertEqual(model.memories.map(\.id), [item.id], "Refresh failure never blanks acknowledged memories")
        XCTAssertEqual(model.error, RoamError.offline.errorDescription)
        await model.loadMore()
        XCTAssertEqual(model.memories.count, 1, "A repeated memory is not appended twice")
        XCTAssertNil(model.nextCursor)
    }
}
