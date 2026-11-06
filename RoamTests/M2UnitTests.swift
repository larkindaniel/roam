import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import Roam

final class AppleNonceTests: XCTestCase {
    func testSha256MatchesKnownVector() {
        XCTAssertEqual(AuthFlowModel.sha256("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testNoncesAreLongAndUnique() {
        let nonces = (0..<50).map { _ in AuthFlowModel.randomNonce() }
        XCTAssertTrue(nonces.allSatisfy { $0.count == 32 })
        XCTAssertEqual(Set(nonces).count, 50)
    }
}

final class ImageProcessorTests: XCTestCase {
    /// A JPEG with GPS metadata and a 90° EXIF orientation.
    private func photoWithLocation(width: Int, height: Int) throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return format
        }()).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 3))
        }
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 38.7, kCGImagePropertyGPSLatitudeRef: "N",
                                            kCGImagePropertyGPSLongitude: 9.1, kCGImagePropertyGPSLongitudeRef: "W"],
        ]
        CGImageDestinationAddImage(destination, try XCTUnwrap(image.cgImage), properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    func testStripsLocationAndAppliesOrientationWithinLimits() throws {
        let source = try photoWithLocation(width: 4000, height: 3000)
        XCTAssertNotNil(ImageProcessor.properties(of: source)[kCGImagePropertyGPSDictionary as String], "Fixture has GPS")
        let processed = try ImageProcessor.prepare(source)
        let properties = ImageProcessor.properties(of: processed.data)
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary as String], "Location metadata must be stripped")
        XCTAssertLessThanOrEqual(max(processed.width, processed.height), 2_048)
        XCTAssertLessThanOrEqual(processed.data.count, Limits.photoMaxBytes)
        XCTAssertGreaterThan(processed.height, processed.width, "Orientation 6 (rotated) is baked into upright pixels")
        let orientation = properties[kCGImagePropertyOrientation as String] as? Int
        XCTAssertTrue(orientation == nil || orientation == 1)
    }

    func testRejectsUnreadableData() {
        XCTAssertThrowsError(try ImageProcessor.prepare(Data("not an image".utf8))) { error in
            XCTAssertEqual(error as? ImageProcessor.Failure, .unreadable)
        }
    }
}

@MainActor
final class ProfileSetupModelTests: XCTestCase {
    private func services(scenario: String = "new-account", account: String = "newcomer") -> AppServices {
        var options = LaunchOptions()
        options.backend = .fixture
        options.fixtureAccount = account
        options.fixtureScenario = scenario
        options.resetLocalState = true
        return AppServices.make(options: options)
    }

    func testNewAccountStartsAtNameAndPrefillsAppleName() {
        let services = services()
        let auth = AuthSession(userID: FixtureIDs.newcomer, email: "newcomer@roam.test", providers: [.apple])
        let model = ProfileSetupModel(services: services, auth: auth, profile: nil, prefillName: "Avery Stone")
        XCTAssertEqual(model.step, .name)
        XCTAssertEqual(model.displayName, "Avery Stone")
    }

    func testTakenHandleKeepsEnteredDataAndResumesFromDraft() async throws {
        let services = services()
        let auth = AuthSession(userID: FixtureIDs.newcomer, email: "newcomer@roam.test", providers: [.email])
        let model = ProfileSetupModel(services: services, auth: auth, profile: nil, prefillName: nil)
        model.displayName = "Avery Stone"
        model.continueFromName()
        model.handle = "mayaroams"
        await model.createProfile()
        XCTAssertEqual(model.step, .handle, "Stays on the handle step")
        XCTAssertEqual(model.displayName, "Avery Stone")
        XCTAssertEqual(model.handle, "mayaroams", "Entered data is not lost on conflict")
        if case .unavailable = model.handleState {} else { XCTFail("Shows the conflict") }
        // A fresh model (app relaunch) resumes from the local draft at the handle step.
        let resumed = ProfileSetupModel(services: services, auth: auth, profile: nil, prefillName: nil)
        XCTAssertEqual(resumed.step, .handle)
        XCTAssertEqual(resumed.displayName, "Avery Stone")
        model.handle = "avery_stone"
        await model.createProfile()
        XCTAssertEqual(model.step, .photo)
        XCTAssertNil(services.storage.read(ProfileSetupModel.Draft.self, name: "setup-draft", userID: FixtureIDs.newcomer), "Draft cleared once the profile exists")
    }

    func testServerCheckpointResumesAfterInterruption() async throws {
        let services = services()
        let auth = AuthSession(userID: FixtureIDs.newcomer, email: "newcomer@roam.test", providers: [.email])
        let created = try await services.profiles.createProfile(displayName: "Avery", handle: "avery_resume")
        XCTAssertEqual(ProfileSetupModel(services: services, auth: auth, profile: created, prefillName: nil).step, .photo)
        let optional = try await services.profiles.setSetupCheckpoint(.optionalDetails)
        XCTAssertEqual(ProfileSetupModel(services: services, auth: auth, profile: optional, prefillName: nil).step, .people)
    }

    func testSuggestionsNeverPreselectFollows() async throws {
        let services = services()
        _ = try await services.profiles.createProfile(displayName: "Avery", handle: "avery_people")
        let auth = AuthSession(userID: FixtureIDs.newcomer, email: "newcomer@roam.test", providers: [.email])
        let model = ProfileSetupModel(services: services, auth: auth, profile: nil, prefillName: nil)
        await model.loadSuggestions()
        XCTAssertFalse(model.suggestions.value?.isEmpty ?? true)
        XCTAssertTrue(model.following.isEmpty)
        XCTAssertTrue(model.suggestions.value?.allSatisfy { $0.friendState != .friends } ?? false)
    }
}

@MainActor
final class SessionStoreTests: XCTestCase {
    func testSignOutClearsAccountScopedData() async throws {
        var options = LaunchOptions()
        options.backend = .fixture
        options.fixtureAccount = "maya"
        options.resetLocalState = true
        let services = AppServices.make(options: options)
        let session = SessionStore(services: services)
        await session.bootstrap()
        XCTAssertEqual(session.phase, .ready)
        let userID = try XCTUnwrap(session.userID)
        try services.storage.write("draft", name: "draft-x", userID: userID)
        await session.signOut()
        XCTAssertEqual(session.phase, .signedOut)
        XCTAssertNil(services.storage.read(String.self, name: "draft-x", userID: userID))
        XCTAssertNil(session.profile)
    }
}
