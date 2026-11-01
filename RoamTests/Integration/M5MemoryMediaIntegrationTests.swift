import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import Roam

/// M5 public-API journeys against the real local backend: Storage uploads, the live prepare-media
/// Edge inspector, RLS-checked reads and the memory RPCs. Each test owns new fictional accounts.
final class M5MemoryMediaIntegrationTests: BackendTestCase {
    @MainActor
    private func photo(hue: CGFloat = 0.45, width: CGFloat = 96, height: CGFloat = 72) throws -> ImageProcessor.Processed {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return try ImageProcessor.prepare(XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor(hue: hue, saturation: 0.7, brightness: 0.8, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }.jpegData(compressionQuality: 0.9)))
    }

    private func stage(_ backend: SupabaseBackend, _ photo: ImageProcessor.Processed, attempt: UUID = UUID()) async throws -> StagedMedia {
        try await backend.stage(jpegData: photo.data, width: photo.width, height: photo.height, purpose: .visit, uploadAttemptID: attempt)
    }

    private func place(_ backend: SupabaseBackend) async throws -> ExperienceSummary {
        try await backend.resolve(PlaceCandidate(provider: .mapkit, providerPlaceID: "I-M5-\(UUID().uuidString)",
            name: "Memory Place \(UUID().uuidString.prefix(6))", address: "5 Memory Lane, Porto", locality: "Porto", region: "Porto",
            countryCode: "PT", countryName: "Portugal", latitude: 41.15, longitude: -8.61, phone: nil, website: nil,
            providerCategory: nil, timeZoneIdentifier: "Europe/Lisbon", isLocality: false, suggestedCategory: .culture))
    }

    private func log(_ backend: SupabaseBackend, _ experience: ExperienceSummary, note: String = "Integration memory",
                     mediaIDs: [UUID] = []) async throws -> RatingCommitResult {
        let ranking = try await backend.categoryRanking(.culture)
        return try await backend.commitRating(RatingCommitRequest(operationID: UUID(), intent: .firstLog, experienceID: experience.id,
            category: .culture, sentiment: .liked, baseRevision: ranking.revision, answers: [],
            visit: VisitPayload(date: LocalDate(isoString: "2026-03-04"), timeZoneIdentifier: "Europe/Lisbon", publicNote: note, mediaIDs: mediaIDs, audience: .public)))
    }

    private func expectFailure(_ description: String, _ predicate: (RoamError) -> Bool, _ operation: () async throws -> Void) async {
        do {
            try await operation()
            XCTFail("\(description): unexpectedly succeeded")
        } catch let error as RoamError {
            XCTAssertTrue(predicate(error), "\(description): unexpected \(error)")
        } catch {
            XCTFail("\(description): unexpected \(error)")
        }
    }

    private func isValidation(_ error: RoamError) -> Bool { if case .validation = error { return true }; return false }

    func testInspectedUploadStaysPrivateUntilPublicationThenFollowsVisitVisibility() async throws {
        let (owner, _) = try await newMember(handlePrefix: "mo")
        let (viewer, _) = try await newMember(handlePrefix: "mv")
        let prepared = try await photo()
        let staged = try await stage(owner, prepared)
        XCTAssertEqual(staged.width, prepared.width, "The server measured the real pixels")
        XCTAssertNotNil(staged.expiresAt, "Staged uploads report their 24-hour expiry")
        let ownCopy = try await owner.imageData(path: staged.path)
        XCTAssertEqual(ownCopy, prepared.data, "The owner can preview their staged upload")
        await expectFailure("staged read by another member", { _ in true }) { _ = try await viewer.imageData(path: staged.path) }
        let experience = try await place(owner)
        _ = try await log(owner, experience, mediaIDs: [staged.id])
        let published = try await viewer.imageData(path: staged.path)
        XCTAssertEqual(published, prepared.data, "Publication grants an authorized read of the exact uploaded bytes")
        let memories = try await viewer.publicMemories(experienceID: experience.id, cursor: nil)
        XCTAssertEqual(memories.items.first?.media.map(\.id), [staged.id])
    }

    func testLiveInspectorRejectsMetadataTruncatedNonJPEGAndOversizedUploads() async throws {
        let (owner, _) = try await newMember(handlePrefix: "mi")
        let prepared = try await photo()
        let exifJPEG = try await MainActor.run {
            try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { context in
                UIColor.systemPink.setFill(); context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
            }.jpegData(compressionQuality: 0.9))
        }
        await expectFailure("APP1/EXIF upload", isValidation) {
            _ = try await owner.stage(jpegData: exifJPEG, width: 40, height: 30, purpose: .visit, uploadAttemptID: UUID())
        }
        await expectFailure("truncated upload", isValidation) {
            _ = try await owner.stage(jpegData: prepared.data.prefix(prepared.data.count / 2), width: prepared.width, height: prepared.height,
                                      purpose: .visit, uploadAttemptID: UUID())
        }
        let png = try await MainActor.run { try XCTUnwrap(UIImage(data: prepared.data)?.pngData()) }
        await expectFailure("PNG bytes declared as JPEG", isValidation) {
            _ = try await owner.stage(jpegData: png, width: prepared.width, height: prepared.height, purpose: .visit, uploadAttemptID: UUID())
        }
        let wide = try await MainActor.run { () throws -> Data in
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 2_049, height: 8), format: format).image { context in
                UIColor.systemGreen.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2_049, height: 8))
            }.cgImage)
            let output = NSMutableData()
            let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            return try ImageProcessor.stripMetadataSegments(output as Data)
        }
        await expectFailure("2,049-pixel upload", isValidation) {
            _ = try await owner.stage(jpegData: wide, width: 2_049, height: 8, purpose: .visit, uploadAttemptID: UUID())
        }
        await expectFailure("over 3 MB upload", isValidation) {
            _ = try await owner.stage(jpegData: Data(repeating: 0xff, count: Limits.photoMaxBytes + 1), width: 10, height: 10,
                                      purpose: .visit, uploadAttemptID: UUID())
        }
    }

    func testSameAttemptRetryIsIdempotentAndDifferentBytesConflict() async throws {
        let (owner, _) = try await newMember(handlePrefix: "ma")
        let attempt = UUID()
        let first = try await stage(owner, try await photo(hue: 0.1), attempt: attempt)
        let retried = try await stage(owner, try await photo(hue: 0.1), attempt: attempt)
        XCTAssertEqual(retried.id, first.id, "An uncertain upload retries into the same media")
        let different = try await photo(hue: 0.9)
        await expectFailure("different bytes under one attempt", { if case .conflict = $0 { return true }; return false }) {
            _ = try await self.stage(owner, different, attempt: attempt)
        }
    }

    func testDiscardedUploadCannotAttachOrBeRevived() async throws {
        let (owner, _) = try await newMember(handlePrefix: "md")
        let prepared = try await photo()
        let attempt = UUID()
        let staged = try await stage(owner, prepared, attempt: attempt)
        try await owner.discardStaged(mediaID: staged.id)
        let experience = try await place(owner)
        await expectFailure("attach a discarded upload", isValidation) { _ = try await self.log(owner, experience, mediaIDs: [staged.id]) }
        await expectFailure("revive a discarded attempt", { $0 == .mediaExpired }) { _ = try await self.stage(owner, prepared, attempt: attempt) }
        let library = try await owner.library()
        XCTAssertFalse(library.visited.contains(experience.id), "Rejected attachment wrote no Visit")
    }

    func testEditingAMemoryUpdatesThePostInPlaceAndRetriesSafely() async throws {
        let (owner, _) = try await newMember(handlePrefix: "me")
        let (viewer, _) = try await newMember(handlePrefix: "mw")
        let experience = try await place(owner)
        let logged = try await log(owner, experience, note: "Before edit")
        let visitID = try XCTUnwrap(logged.visitID)
        let before = try await viewer.detail(experienceID: experience.id)
        let added = try await stage(owner, try await photo(hue: 0.3))
        let operation = UUID()
        let date = VisitDate(date: LocalDate(isoString: "2026-03-01"), timeZoneIdentifier: "Pacific/Kiritimati")
        let edited = try await owner.updateVisit(visitID: visitID, note: "After edit", date: date, mediaIDs: [added.id], operationID: operation)
        XCTAssertEqual(edited.visitDate.date?.isoString, "2026-03-01", "The calendar date is stored as entered")
        let replay = try await owner.updateVisit(visitID: visitID, note: "After edit", date: date, mediaIDs: [added.id], operationID: operation)
        XCTAssertEqual(replay, edited)
        await expectFailure("one operation with a different edit", { if case .conflict = $0 { return true }; return false }) {
            _ = try await owner.updateVisit(visitID: visitID, note: "Changed", date: date, mediaIDs: [], operationID: operation)
        }
        await expectFailure("another member editing", { $0 == .forbidden }) {
            _ = try await viewer.updateVisit(visitID: visitID, note: "Hijack", date: .unknown, mediaIDs: [], operationID: UUID())
        }
        let after = try await viewer.detail(experienceID: experience.id)
        XCTAssertEqual(after.publicActivity.count, 1, "An edit publishes nothing new")
        XCTAssertEqual(after.publicActivity.first?.publishedAt, before.publicActivity.first?.publishedAt)
        XCTAssertEqual(after.publicActivity.first?.note, "After edit")
        XCTAssertEqual(after.publicActivity.first?.media.map(\.id), [added.id])
    }

    func testPrivateNoteNeverReachesAnotherMemberOrAnyPublicPayload() async throws {
        let (owner, _) = try await newMember(handlePrefix: "mp")
        let (viewer, _) = try await newMember(handlePrefix: "mq")
        let experience = try await place(owner)
        _ = try await log(owner, experience)
        let secret = "integration-private-\(UUID().uuidString.prefix(8))"
        _ = try await owner.savePrivateNote(experienceID: experience.id, text: secret, operationID: UUID())
        let ownNote = try await owner.privateNote(experienceID: experience.id)
        XCTAssertEqual(ownNote?.text, secret)
        let foreign = try await viewer.privateNote(experienceID: experience.id)
        XCTAssertNil(foreign)
        let viewerToken = try await viewer.client.auth.session.accessToken
        let (status, rows) = try await rest("rest/v1/private_notes?select=body", token: viewerToken)
        XCTAssertEqual(status, 200)
        XCTAssertFalse(String(decoding: rows, as: UTF8.self).contains(secret), "Direct table reads are owner-only")
        for function in ["experience_detail", "public_memories"] {
            let body = try JSONSerialization.data(withJSONObject: ["p_experience_id": experience.id.uuidString.lowercased()])
            let (code, data) = try await rest("rest/v1/rpc/\(function)", token: viewerToken, method: "POST", body: body)
            XCTAssertEqual(code, 200)
            XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(secret), "\(function) never serializes the private note")
        }
        try await owner.deletePrivateNote(experienceID: experience.id, operationID: UUID())
        let deleted = try await owner.privateNote(experienceID: experience.id)
        XCTAssertNil(deleted)
    }

    func testRemovingTheRankingKeepsPhotosAndDeletingTheVisitRevokesThem() async throws {
        let (owner, _) = try await newMember(handlePrefix: "mr")
        let (viewer, _) = try await newMember(handlePrefix: "ms")
        let prepared = try await photo(hue: 0.6)
        let staged = try await stage(owner, prepared)
        let experience = try await place(owner)
        let logged = try await log(owner, experience, note: "Retained with photo", mediaIDs: [staged.id])
        try await owner.removeRating(experienceID: experience.id, operationID: UUID())
        let retained = try await viewer.publicMemories(experienceID: experience.id, cursor: nil)
        let memory = try XCTUnwrap(retained.items.first { $0.id == logged.visitID })
        XCTAssertEqual(memory.publicNote, "Retained with photo")
        XCTAssertNil(memory.activityID, "The rating post is gone")
        let stillReadable = try await viewer.imageData(path: staged.path)
        XCTAssertEqual(stillReadable, prepared.data, "Retained memories keep authorized photo access")
        _ = try await owner.deleteVisit(visitID: try XCTUnwrap(logged.visitID), operationID: UUID(), allowRatingRemoval: false)
        let afterDeletion = try await viewer.publicMemories(experienceID: experience.id, cursor: nil)
        XCTAssertFalse(afterDeletion.items.contains { $0.id == logged.visitID })
        await expectFailure("reading a deleted Visit's photo", { _ in true }) { _ = try await viewer.imageData(path: staged.path) }
    }

    func testRemovingAPostKeepsTheRatingAndVisit() async throws {
        let (owner, _) = try await newMember(handlePrefix: "mx")
        let (viewer, _) = try await newMember(handlePrefix: "my")
        let experience = try await place(owner)
        let logged = try await log(owner, experience)
        await expectFailure("another member removing the post", { $0 == .forbidden }) { try await viewer.deleteActivity(id: logged.activityID) }
        try await owner.deleteActivity(id: logged.activityID)
        try await owner.deleteActivity(id: logged.activityID)
        let detail = try await owner.detail(experienceID: experience.id)
        XCTAssertTrue(detail.publicActivity.isEmpty)
        XCTAssertEqual(detail.myRating?.ratingID, logged.ratingID)
        XCTAssertEqual(detail.myVisits.map(\.id), [try XCTUnwrap(logged.visitID)])
        let revisit = try await owner.addVisit(AddVisitRequest(operationID: UUID(), experienceID: experience.id,
            visit: VisitPayload(date: nil, timeZoneIdentifier: nil, publicNote: "Again", mediaIDs: [], audience: .public)))
        let republished = try await viewer.detail(experienceID: experience.id)
        XCTAssertEqual(republished.publicActivity.map(\.id), [revisit.activityID], "A later completion still publishes automatically")
    }
}
