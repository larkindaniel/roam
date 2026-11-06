import Foundation
import UIKit
import XCTest
@testable import Roam

/// Server staging double: records every upload attempt and discard; can fail, expire or hold a call.
private actor PhotoTestMedia: MediaService {
    private var outcomes: [RoamError?] = []
    private(set) var attempts: [UUID] = []
    private(set) var discarded: [UUID] = []
    private var byAttempt: [UUID: StagedMedia] = [:]
    private var holdNext = false
    private var held: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private let lifetime: TimeInterval
    private let clock: TestClock

    init(clock: TestClock, lifetime: TimeInterval = 24 * 60 * 60) {
        self.clock = clock
        self.lifetime = lifetime
    }

    func failNext(_ errors: RoamError?...) { outcomes += errors }
    func holdNextUpload() { holdNext = true }
    func waitUntilHeld() async {
        guard held == nil else { return }
        await withCheckedContinuation { started = $0 }
    }
    func release() { held?.resume(); held = nil }

    func stage(jpegData: Data, width: Int, height: Int, purpose: MediaPurpose, uploadAttemptID: UUID) async throws -> StagedMedia {
        attempts.append(uploadAttemptID)
        if holdNext {
            holdNext = false
            await withCheckedContinuation { held = $0; started?.resume(); started = nil }
        }
        if !outcomes.isEmpty, let error = outcomes.removeFirst() { throw error }
        if let existing = byAttempt[uploadAttemptID] { return existing }
        let now = await clock.now
        let staged = StagedMedia(id: UUID(), path: "visit-media/owner/\(uploadAttemptID.uuidString.lowercased()).jpg",
                                 width: width, height: height, expiresAt: now.addingTimeInterval(lifetime))
        byAttempt[uploadAttemptID] = staged
        return staged
    }

    func discardStaged(mediaID: UUID) async throws { discarded.append(mediaID) }
    func imageData(path: String) async throws -> Data { throw RoamError.notFound }
}

@MainActor
final class TestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_790_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@MainActor
final class M5PhotoDraftTests: XCTestCase {
    private let owner = UUID()
    private var storage: AccountStorage!
    private var clock: TestClock!
    private var account: UUID?

    override func setUp() async throws {
        storage = AccountStorage(root: FileManager.default.temporaryDirectory.appendingPathComponent("m5-photo-\(UUID().uuidString)"))
        clock = TestClock()
        account = owner
    }

    private func makeModel(_ media: PhotoTestMedia, draftID: String = "draft", existing: [MediaRef] = []) -> PhotoDraftModel {
        PhotoDraftModel(ownerID: owner, draftID: draftID, existingMedia: existing, storage: storage, media: media,
                        currentAccount: { [unowned self] in self.account }, now: { [unowned self] in self.clock.now })
    }

    static func sampleJPEG(width: CGFloat = 240, height: CGFloat = 160, hue: CGFloat = 0.5) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor(hue: hue, saturation: 0.6, brightness: 0.8, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
    }

    func testReadyUploadSurvivesRestartWithItsLocalBytes() async throws {
        let media = PhotoTestMedia(clock: clock)
        let model = makeModel(media)
        await model.add(data: try Self.sampleJPEG())
        XCTAssertEqual(model.assets.map(\.status), [.ready])
        XCTAssertTrue(model.canCommit)
        let ids = try model.attachmentIDs()
        let restored = makeModel(media)
        XCTAssertEqual(restored.assets.map(\.status), [.ready])
        XCTAssertEqual(try restored.attachmentIDs(), ids, "A restored draft attaches the same acknowledged upload")
        let bytes = try XCTUnwrap(restored.thumbnailData(assetID: restored.assets[0].id))
        XCTAssertNil(ImageProcessor.properties(of: bytes)["{GPS}"], "Locally kept bytes are the stripped upload")
    }

    func testFailedUploadBlocksSaveUntilRetryReusesTheSameAttempt() async throws {
        let media = PhotoTestMedia(clock: clock)
        await media.failNext(.timeout)
        let model = makeModel(media)
        await model.add(data: try Self.sampleJPEG())
        XCTAssertEqual(model.assets.map(\.status), [.failed])
        XCTAssertFalse(model.canCommit)
        XCTAssertThrowsError(try model.attachmentIDs(), "A failed photo can never be reported as saved")
        await model.retry(assetID: model.assets[0].id)
        XCTAssertEqual(model.assets.map(\.status), [.ready])
        let attempts = await media.attempts
        XCTAssertEqual(attempts.count, 2)
        XCTAssertEqual(Set(attempts).count, 1, "An uncertain upload retries its own immutable attempt path")
    }

    func testInterruptedUploadRestoresAsFailedAndRetriesTheSameAttempt() async throws {
        let media = PhotoTestMedia(clock: clock)
        await media.holdNextUpload()
        let model = makeModel(media)
        let data = try Self.sampleJPEG()
        let adding = Task { await model.add(data: data) }
        await media.waitUntilHeld()
        let restored = makeModel(media)
        XCTAssertEqual(restored.assets.map(\.status), [.failed], "A process restart never shows an unfinished upload as ready")
        XCTAssertNotNil(restored.assets[0].error)
        await media.release()
        await adding.value
        await restored.retry(assetID: restored.assets[0].id)
        XCTAssertEqual(restored.assets.map(\.status), [.ready])
        let attempts = await media.attempts
        XCTAssertEqual(Set(attempts).count, 1, "Retry checks the interrupted attempt instead of creating a duplicate")
    }

    func testExpiredStageNeedsAFreshAttemptAndBothStagesAreDiscarded() async throws {
        let media = PhotoTestMedia(clock: clock)
        let model = makeModel(media)
        await model.add(data: try Self.sampleJPEG())
        let first = try XCTUnwrap(model.assets.first?.staged)
        clock.advance(24 * 60 * 60 + 1)
        XCTAssertFalse(model.canCommit)
        XCTAssertThrowsError(try model.attachmentIDs())
        XCTAssertEqual(model.assets.first?.status, .failed)
        XCTAssertEqual(model.assets.first?.needsNewAttempt, true)
        await model.retry(assetID: model.assets[0].id)
        let second = try XCTUnwrap(model.assets.first?.staged)
        XCTAssertNotEqual(first.id, second.id)
        let attempts = await media.attempts
        XCTAssertEqual(Set(attempts).count, 2, "An expired path is never revived; a new attempt is uploaded")
        await model.discard()
        let discarded = await media.discarded
        XCTAssertEqual(Set(discarded), [first.id, second.id], "Retired and current staged uploads are both discarded")
        XCTAssertTrue(makeModel(media).assets.isEmpty)
    }

    func testServerExpiryRejectionRequiresNewAttemptsWithoutLosingSavedPhotos() async throws {
        let media = PhotoTestMedia(clock: clock)
        let existing = MediaRef(id: UUID(), path: "visit-media/owner/kept.jpg", width: 10, height: 10, position: 0)
        let model = makeModel(media, existing: [existing])
        await model.add(data: try Self.sampleJPEG())
        model.expireStagedUploads()
        XCTAssertEqual(model.assets.map(\.status), [.existing, .failed])
        XCTAssertEqual(model.assets.last?.needsNewAttempt, true)
        await model.retry(assetID: model.assets[1].id)
        XCTAssertEqual(try model.attachmentIDs().first, existing.id)
        XCTAssertEqual(try model.attachmentIDs().count, 2)
    }

    func testSixPhotoLimitAndPickerFailuresStayVisibleUntilRemoved() async throws {
        let media = PhotoTestMedia(clock: clock)
        let model = makeModel(media)
        for index in 0..<5 { await model.add(data: try Self.sampleJPEG(hue: CGFloat(index) / 10)) }
        model.addFailure(message: "This selected photo couldn't be read.")
        XCTAssertEqual(model.assets.count, 6)
        await model.add(data: try Self.sampleJPEG())
        XCTAssertEqual(model.assets.count, 6, "A seventh photo is refused")
        XCTAssertEqual(model.error, "A visit can have up to six photos.")
        XCTAssertFalse(model.canCommit, "A failed picker item cannot silently disappear from the draft")
        await model.remove(assetID: try XCTUnwrap(model.assets.first { $0.status == .failed }).id)
        XCTAssertTrue(model.canCommit)
        XCTAssertEqual(try model.attachmentIDs().count, 5)
    }

    func testCancelRestoresTheCheckpointAndRetiresUploadsMadeInTheEditor() async throws {
        let media = PhotoTestMedia(clock: clock)
        let model = makeModel(media)
        await model.add(data: try Self.sampleJPEG(hue: 0.1))
        await model.add(data: try Self.sampleJPEG(hue: 0.2))
        let before = model.assets
        let checkpoint = model.checkpoint()
        await model.add(data: try Self.sampleJPEG(hue: 0.3))
        let added = try XCTUnwrap(model.assets.last?.staged)
        model.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        await model.remove(assetID: before[0].id)
        await model.restore(checkpoint)
        XCTAssertEqual(model.assets.map(\.id), before.map(\.id), "Cancel restores order and removed photos")
        XCTAssertNotNil(model.thumbnailData(assetID: before[0].id), "A removed photo's local bytes come back on Cancel")
        await model.discard()
        let discarded = await media.discarded
        XCTAssertTrue(discarded.contains(added.id), "An upload made only in the cancelled editor is discarded")
    }

    func testCommittedDraftClearsLocalBytesButNeverDiscardsAttachedMedia() async throws {
        let media = PhotoTestMedia(clock: clock)
        let model = makeModel(media)
        await model.add(data: try Self.sampleJPEG())
        let assetID = model.assets[0].id
        model.committed()
        XCTAssertNil(storage.photoData(assetID: assetID, draftID: "draft", userID: owner))
        let discarded = await media.discarded
        XCTAssertTrue(discarded.isEmpty, "The Visit transaction owns attached media")
        XCTAssertTrue(makeModel(media).assets.isEmpty)
    }

    func testAnotherAccountCannotReadOrChangeTheDraft() async throws {
        let media = PhotoTestMedia(clock: clock)
        let model = makeModel(media)
        await model.add(data: try Self.sampleJPEG())
        let assetID = model.assets[0].id
        account = UUID()
        XCTAssertNil(model.thumbnailData(assetID: assetID))
        XCTAssertFalse(model.canCommit)
        await model.add(data: try Self.sampleJPEG())
        XCTAssertEqual(model.assets.count, 1)
        XCTAssertThrowsError(try model.attachmentIDs())
        await model.discard()
        account = owner
        XCTAssertEqual(makeModel(media).assets.count, 1, "A different signed-in account cannot discard the owner's draft")
    }

    func testDraftExpiresAfterThirtyDays() async throws {
        let media = PhotoTestMedia(clock: clock)
        let model = makeModel(media)
        await model.add(data: try Self.sampleJPEG())
        let assetID = model.assets[0].id
        clock.advance(Limits.draftLifetime + 60)
        XCTAssertTrue(makeModel(media).assets.isEmpty)
        XCTAssertNil(storage.photoData(assetID: assetID, draftID: "draft", userID: owner), "Expired bytes are deleted with their manifest")
    }

    func testSavedPhotosStayExistingAndReorderingIsADraftChange() async throws {
        let media = PhotoTestMedia(clock: clock)
        let refs = [MediaRef(id: UUID(), path: "visit-media/o/a.jpg", width: 4, height: 3, position: 1),
                    MediaRef(id: UUID(), path: "visit-media/o/b.jpg", width: 4, height: 3, position: 0)]
        let model = makeModel(media, existing: refs)
        XCTAssertEqual(model.assets.map(\.status), [.existing, .existing])
        XCTAssertEqual(try model.attachmentIDs(), [refs[1].id, refs[0].id], "Saved photos keep their stored order")
        model.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        XCTAssertEqual(try model.attachmentIDs(), [refs[0].id, refs[1].id])
        await model.remove(assetID: refs[0].id)
        let discarded = await media.discarded
        XCTAssertTrue(discarded.isEmpty, "Removing a saved photo changes only the draft until the Visit edit is acknowledged")
    }
}
