import UIKit
import XCTest
@testable import Roam

/// The fixture backend drives UI journeys, so it must keep the same memory/media rules as the
/// server: acknowledged edits, retained public memories, private staging and owner-only notes.
final class M5FixtureParityTests: XCTestCase {
    private func backend() -> FixtureBackend { FixtureBackend(scenario: "empty", signedInHandle: "maya", latencyMilliseconds: 0) }

    private func place(_ backend: FixtureBackend) async throws -> ExperienceSummary {
        try await backend.resolve(PlaceCandidate(provider: .fixture, providerPlaceID: UUID().uuidString, name: "Memory Gallery", address: "2 Test Street",
                                                locality: "Porto", region: "Porto", countryCode: "PT", countryName: "Portugal", latitude: 41.15, longitude: -8.61,
                                                phone: nil, website: nil, providerCategory: nil, timeZoneIdentifier: "Europe/Lisbon", isLocality: false,
                                                suggestedCategory: .culture))
    }

    @MainActor
    private func photo() throws -> ImageProcessor.Processed {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return try ImageProcessor.prepare(XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 120, height: 90), format: format).image { context in
            UIColor.systemOrange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 120, height: 90))
        }.jpegData(compressionQuality: 0.9)))
    }

    private func log(_ backend: FixtureBackend, _ experience: ExperienceSummary, mediaIDs: [UUID] = [], note: String = "Fixture memory") async throws -> RatingCommitResult {
        let ranking = try await backend.categoryRanking(.culture)
        return try await backend.commitRating(RatingCommitRequest(operationID: UUID(), intent: .firstLog, experienceID: experience.id, category: .culture,
                                                                  sentiment: .liked, baseRevision: ranking.revision, answers: [],
                                                                  visit: VisitPayload(date: LocalDate(isoString: "2026-02-01"), timeZoneIdentifier: "Europe/Lisbon",
                                                                                      publicNote: note, mediaIDs: mediaIDs, audience: .public)))
    }

    func testStagedUploadIsPrivateUntilAttachedThenReadableByOtherMembers() async throws {
        let backend = backend()
        let prepared = try await photo()
        let staged = try await backend.stage(jpegData: prepared.data, width: prepared.width, height: prepared.height, purpose: .visit, uploadAttemptID: UUID())
        _ = try await backend.signIn(email: "theo@roam.test", password: FixtureSeed.password)
        do { _ = try await backend.imageData(path: staged.path); XCTFail("A staged upload was readable by another member") }
        catch { XCTAssertEqual(error as? RoamError, .forbidden) }
        _ = try await backend.signIn(email: "maya@roam.test", password: FixtureSeed.password)
        let experience = try await place(backend)
        _ = try await log(backend, experience, mediaIDs: [staged.id])
        _ = try await backend.signIn(email: "theo@roam.test", password: FixtureSeed.password)
        let bytes = try await backend.imageData(path: staged.path)
        XCTAssertEqual(bytes, prepared.data, "Publication makes the attached photo readable")
    }

    func testSameUploadAttemptIsIdempotentAndChangedBytesConflict() async throws {
        let backend = backend()
        let prepared = try await photo()
        let attempt = UUID()
        let first = try await backend.stage(jpegData: prepared.data, width: prepared.width, height: prepared.height, purpose: .visit, uploadAttemptID: attempt)
        let retried = try await backend.stage(jpegData: prepared.data, width: prepared.width, height: prepared.height, purpose: .visit, uploadAttemptID: attempt)
        XCTAssertEqual(first.id, retried.id)
        var changed = prepared.data
        changed[changed.count / 2] ^= 0x01
        do {
            _ = try await backend.stage(jpegData: changed, width: prepared.width, height: prepared.height, purpose: .visit, uploadAttemptID: attempt)
            XCTFail("One attempt accepted different bytes")
        } catch {
            guard case RoamError.conflict = error else { return XCTFail("Expected a conflict, got \(error)") }
        }
    }

    func testVisitEditKeepsPublicationTimeAndReplaysItsReceipt() async throws {
        let backend = backend()
        let experience = try await place(backend)
        let logged = try await log(backend, experience)
        let visitID = try XCTUnwrap(logged.visitID)
        let before = try await backend.detail(experienceID: experience.id)
        let operation = UUID()
        let edited = try await backend.updateVisit(visitID: visitID, note: "Edited fixture memory", date: .unknown, mediaIDs: [], operationID: operation)
        let replay = try await backend.updateVisit(visitID: visitID, note: "Edited fixture memory", date: .unknown, mediaIDs: [], operationID: operation)
        XCTAssertEqual(replay, edited)
        do {
            _ = try await backend.updateVisit(visitID: visitID, note: "Different", date: .unknown, mediaIDs: [], operationID: operation)
            XCTFail("One operation changed its edit")
        } catch { guard case RoamError.conflict = error else { return XCTFail("Expected a conflict") } }
        let after = try await backend.detail(experienceID: experience.id)
        XCTAssertEqual(after.publicActivity.count, 1)
        XCTAssertEqual(after.publicActivity.first?.publishedAt, before.publicActivity.first?.publishedAt)
        XCTAssertEqual(after.publicActivity.first?.note, "Edited fixture memory")
        XCTAssertNil(after.myVisits.first?.visitDate.date, "An unknown date stays unknown")
    }

    func testPublicMemoryOutlivesRankingRemovalAndLeavesWithItsVisit() async throws {
        let backend = backend()
        let experience = try await place(backend)
        let logged = try await log(backend, experience, note: "Kept memory")
        _ = try await backend.signIn(email: "theo@roam.test", password: FixtureSeed.password)
        var memories = try await backend.publicMemories(experienceID: experience.id, cursor: nil)
        XCTAssertEqual(memories.items.first?.activityID, logged.activityID)
        XCTAssertEqual(memories.items.first?.isOwn, false)
        _ = try await backend.signIn(email: "maya@roam.test", password: FixtureSeed.password)
        try await backend.removeRating(experienceID: experience.id, operationID: UUID())
        _ = try await backend.signIn(email: "theo@roam.test", password: FixtureSeed.password)
        memories = try await backend.publicMemories(experienceID: experience.id, cursor: nil)
        XCTAssertEqual(memories.items.first?.publicNote, "Kept memory", "Removing a ranking keeps the populated memory")
        XCTAssertNil(memories.items.first?.activityID)
        _ = try await backend.signIn(email: "maya@roam.test", password: FixtureSeed.password)
        _ = try await backend.deleteVisit(visitID: try XCTUnwrap(logged.visitID), operationID: UUID(), allowRatingRemoval: false)
        memories = try await backend.publicMemories(experienceID: experience.id, cursor: nil)
        XCTAssertTrue(memories.items.isEmpty, "Deleting the Visit removes its memory")
    }

    func testRemovingAPostKeepsTheRatingAndVisit() async throws {
        let backend = backend()
        let experience = try await place(backend)
        let logged = try await log(backend, experience)
        _ = try await backend.signIn(email: "theo@roam.test", password: FixtureSeed.password)
        do { try await backend.deleteActivity(id: logged.activityID); XCTFail("Another member removed the post") }
        catch { XCTAssertEqual(error as? RoamError, .forbidden) }
        _ = try await backend.signIn(email: "maya@roam.test", password: FixtureSeed.password)
        try await backend.deleteActivity(id: logged.activityID)
        let detail = try await backend.detail(experienceID: experience.id)
        XCTAssertTrue(detail.publicActivity.isEmpty)
        XCTAssertEqual(detail.myRating?.ratingID, logged.ratingID)
        XCTAssertEqual(detail.myVisits.map(\.id), [logged.visitID].compactMap { $0 })
    }

    func testPrivateNoteIsOwnerOnlyAndAbsentFromPublicProjections() async throws {
        let backend = backend()
        let experience = try await place(backend)
        _ = try await log(backend, experience)
        _ = try await backend.savePrivateNote(experienceID: experience.id, text: "fixture-secret-note", operationID: UUID())
        _ = try await backend.signIn(email: "theo@roam.test", password: FixtureSeed.password)
        let note = try await backend.privateNote(experienceID: experience.id)
        XCTAssertNil(note)
        let detail = try await backend.detail(experienceID: experience.id)
        XCTAssertFalse(detail.hasPrivateNote)
        let encoded = String(decoding: try JSONEncoder().encode(detail), as: UTF8.self)
            + String(decoding: try JSONEncoder().encode(try await backend.publicMemories(experienceID: experience.id, cursor: nil).items), as: UTF8.self)
        XCTAssertFalse(encoded.contains("fixture-secret-note"))
    }
}
