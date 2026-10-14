import Foundation
import UIKit
import XCTest
@testable import Roam

private func m5Profile(_ id: UUID) -> OwnProfile {
    OwnProfile(id: id, handle: "m\(id.uuidString.prefix(6).lowercased())", displayName: "Member", bio: "", avatarPath: nil,
               homeCity: nil, setupCheckpoint: .complete, hasSeenBeenIntro: true, createdAt: Date())
}

private actor GatedImageMedia: MediaService {
    private var held: [CheckedContinuation<Void, Never>] = []
    private var started: CheckedContinuation<Void, Never>?
    private(set) var reads = 0
    private let data: Data

    init(data: Data) { self.data = data }

    func waitUntilHeld() async {
        guard held.isEmpty else { return }
        await withCheckedContinuation { started = $0 }
    }
    func release() { held.forEach { $0.resume() }; held = [] }

    func stage(jpegData: Data, width: Int, height: Int, purpose: MediaPurpose, uploadAttemptID: UUID) async throws -> StagedMedia {
        throw RoamError.unavailable
    }
    func discardStaged(mediaID: UUID) async throws {}
    func imageData(path: String) async throws -> Data {
        reads += 1
        await withCheckedContinuation { held.append($0); started?.resume(); started = nil }
        return data
    }
}

@MainActor
final class M5SessionCacheTests: XCTestCase {
    private func pixel() throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2), format: format).image { context in
            UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }.jpegData(compressionQuality: 0.9))
    }

    func testClearingTheImageCacheStopsAnInFlightReadFromRepopulatingIt() async throws {
        let media = GatedImageMedia(data: try pixel())
        let store = ImageStore(media: media)
        let path = "visit-media/owner/photo.jpg"
        let loading = Task { await store.image(for: path) }
        await media.waitUntilHeld()
        store.clear()
        await media.release()
        let image = await loading.value
        XCTAssertNil(image, "A read that began for the previous account is dropped")
        XCTAssertNil(store.cached(path), "Cleared caches are not repopulated by old reads")
    }

    func testConcurrentReadsOfOnePhotoShareOneAuthorizedDownload() async throws {
        let media = GatedImageMedia(data: try pixel())
        let store = ImageStore(media: media)
        let path = "visit-media/owner/shared.jpg"
        let first = Task { await store.image(for: path) }
        await media.waitUntilHeld()
        let second = Task { await store.image(for: path) }
        await Task.yield()
        await media.release()
        let images = await (first.value, second.value)
        XCTAssertNotNil(images.0)
        XCTAssertNotNil(images.1)
        let reads = await media.reads
        XCTAssertEqual(reads, 1)
        XCTAssertNotNil(store.cached(path))
    }

    private func fixtureServices() -> AppServices {
        var options = LaunchOptions()
        options.backend = .fixture
        options.fixtureAccount = "maya"
        options.resetLocalState = true
        return AppServices.make(options: options)
    }

    private final class CurrentProfile: @unchecked Sendable { var userID: UUID? }


    func testExpiredSessionKeepsTheOwnersDraftsAndSignOutRemovesThem() async throws {
        let services = fixtureServices()
        let current = CurrentProfile()
        let session = SessionStore(services: services, profileLoader: { current.userID.map(m5Profile) })
        let maya = FixtureIDs.maya
        current.userID = maya
        await session.didAuthenticate(AuthSession(userID: maya, email: "maya@roam.test", providers: [.email]))
        XCTAssertEqual(session.phase, .ready)
        try services.storage.write("unsaved visit note", name: "visit-edit-draft", userID: maya)
        session.markSessionExpired()
        XCTAssertEqual(session.phase, .signedOut)
        XCTAssertTrue(session.sessionExpired)
        XCTAssertEqual(session.expiredUserID, maya)
        XCTAssertEqual(services.storage.read(String.self, name: "visit-edit-draft", userID: maya), "unsaved visit note",
                       "Expiry keeps the owner's draft for after sign-in")
        await session.signOut()
        XCTAssertNil(services.storage.read(String.self, name: "visit-edit-draft", userID: maya), "Sign-out removes that owner's drafts")
    }

    func testRouteIntentSurvivesExpiryOnlyForTheSameAccount() async throws {
        let services = fixtureServices()
        let current = CurrentProfile()
        let session = SessionStore(services: services, profileLoader: { current.userID.map(m5Profile) })
        let maya = FixtureIDs.maya, theo = FixtureIDs.theo
        let route = AppRoute.gallery(experienceID: UUID(), visitID: nil)
        current.userID = maya
        await session.didAuthenticate(AuthSession(userID: maya, email: nil, providers: [.email]))
        session.markSessionExpired(routeIntent: route)
        current.userID = maya
        await session.didAuthenticate(AuthSession(userID: maya, email: nil, providers: [.email]))
        XCTAssertEqual(session.pendingRouteAfterReauth, route, "The same member returns to where they were")
        session.markSessionExpired(routeIntent: route)
        current.userID = theo
        await session.didAuthenticate(AuthSession(userID: theo, email: nil, providers: [.email]))
        XCTAssertNil(session.pendingRouteAfterReauth, "Another account never inherits the expired member's route")
        XCTAssertEqual(session.userID, theo)
    }

    func testAProfileForAnotherAccountIsNeverAdopted() async throws {
        let services = fixtureServices()
        let session = SessionStore(services: services, profileLoader: { m5Profile(FixtureIDs.theo) })
        await session.didAuthenticate(AuthSession(userID: FixtureIDs.maya, email: nil, providers: [.email]))
        XCTAssertNil(session.profile)
        XCTAssertNotEqual(session.phase, .ready, "A mismatched profile response expires the session instead of mixing accounts")
    }
}
