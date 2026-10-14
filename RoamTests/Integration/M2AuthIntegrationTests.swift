import Foundation
import Supabase
import UIKit
import XCTest
@testable import Roam

/// M2 against the real local Supabase stack: email auth lifecycle, profile rules and access control.
final class M2AuthIntegrationTests: BackendTestCase {
    func testSignUpRequiresEmailCodeThenCreatesProfile() async throws {
        let backend = makeBackend()
        let email = "signup-\(UUID().uuidString.prefix(8).lowercased())@roam.test"
        let outcome = try await backend.signUp(email: email, password: "integration-pass-123")
        XCTAssertEqual(outcome, .confirmationRequired(email: email), "Local Auth requires email confirmation")
        do {
            _ = try await backend.signIn(email: email, password: "integration-pass-123")
            XCTFail("Unconfirmed email must not sign in")
        } catch {}
        do {
            _ = try await backend.verifySignUp(email: email, code: "000000")
            XCTFail("A wrong code must fail")
        } catch let error as RoamError {
            XCTAssertEqual(error, .validation("That code is invalid or has expired. Request a new one."))
        }
        let code = try await Mailpit.latestCode(to: email)
        let session = try await backend.verifySignUp(email: email, code: code)
        XCTAssertEqual(session.email, email)
        let restored = try await backend.restoreSession()
        XCTAssertEqual(restored?.userID, session.userID, "Session restores from secure storage")
        let noProfile = try await backend.ownProfile()
        XCTAssertNil(noProfile, "New accounts start without a profile")
        let handle = "su\(UUID().uuidString.prefix(6).lowercased())"
        let profile = try await backend.createProfile(displayName: "Sign Up", handle: handle)
        XCTAssertEqual(profile.setupCheckpoint, .profileCreated)
        let availability = try await backend.checkHandle(handle)
        XCTAssertEqual(availability, .available, "Own handle is available to its owner")
    }

    func testShortPasswordRejectedByServerAndClient() async throws {
        let backend = makeBackend()
        do {
            _ = try await backend.signUp(email: "short-\(UUID().uuidString.prefix(6))@roam.test", password: "short")
            XCTFail("Short password accepted")
        } catch let error as RoamError {
            guard case .validation = error else { return XCTFail("Unexpected \(error)") }
        }
    }

    func testFailedSignInMessageDoesNotRevealWhetherAccountExists() async throws {
        let backend = makeBackend()
        var messages: [String] = []
        for email in ["maya@roam.test", "nobody-\(UUID().uuidString.prefix(6))@roam.test"] {
            do {
                _ = try await backend.signIn(email: email, password: "definitely-wrong-password")
                XCTFail("Wrong password accepted")
            } catch {
                messages.append(error.roamMessage)
            }
        }
        XCTAssertEqual(messages[0], messages[1])
        XCTAssertEqual(messages[0], "Email or password is incorrect.")
    }

    func testPasswordRecoveryCodeThenNewPassword() async throws {
        let (backend, email) = try await newMember()
        await backend.signOut()
        let reset = makeBackend()
        try await reset.requestPasswordReset(email: email)
        let code = try await Mailpit.latestCode(to: email, subjectContains: "Reset")
        _ = try await reset.verifyRecovery(email: email, code: code)
        try await reset.updatePassword("a-brand-new-passphrase")
        await reset.signOut()
        let again = makeBackend()
        let session = try await again.signIn(email: email, password: "a-brand-new-passphrase")
        XCTAssertEqual(session.email, email)
        // The used code cannot be replayed.
        do {
            _ = try await makeBackend().verifyRecovery(email: email, code: code)
            XCTFail("Recovery code replay accepted")
        } catch {}
    }

    func testResetRequestForUnknownEmailLooksTheSame() async throws {
        // No error and no account enumeration for an address without an account.
        try await makeBackend().requestPasswordReset(email: "nobody-\(UUID().uuidString.prefix(6))@roam.test")
    }

    func testConcurrentHandleClaimsYieldExactlyOneWinner() async throws {
        let (first, _) = try await newMemberWithoutProfile()
        let (second, _) = try await newMemberWithoutProfile()
        let handle = "race\(UUID().uuidString.prefix(6).lowercased())"
        async let a: Result<OwnProfile, Error> = capture { try await first.createProfile(displayName: "A", handle: handle) }
        async let b: Result<OwnProfile, Error> = capture { try await second.createProfile(displayName: "B", handle: handle) }
        let results = await [a, b]
        XCTAssertEqual(results.filter { if case .success = $0 { return true } else { return false } }.count, 1)
        let failure = results.compactMap { if case .failure(let error) = $0 { return error } else { return nil } }.first
        XCTAssertEqual(failure as? RoamError, .conflict("That handle is taken. Try another."))
    }

    func testPublicProfileVisibleToOtherMemberButPrivateDataIsNot() async throws {
        let theo = try await signedIn("theo@roam.test")
        let maya = try await theo.publicProfile(userID: Self.maya)
        XCTAssertEqual(maya.member.handle, "mayaroams")
        XCTAssertEqual(maya.relationship.isFollowing, true)
        let token = try await theo.client.auth.session.accessToken
        let (_, notes) = try await rest("rest/v1/private_notes", token: token)
        let theoNotes = try JSONSerialization.jsonObject(with: notes) as? [[String: Any]] ?? []
        XCTAssertTrue(theoNotes.allSatisfy { ($0["owner_id"] as? String) == Self.theo.uuidString.lowercased() }, "Only own private notes")
        let (_, settings) = try await rest("rest/v1/user_settings?user_id=eq.\(Self.maya.uuidString.lowercased())", token: token)
        XCTAssertEqual(String(data: settings, encoding: .utf8), "[]", "Another member's settings are invisible")
        let (status, _) = try await rest("rest/v1/profiles?select=setup_checkpoint", token: token)
        XCTAssertTrue([401, 403].contains(status), "Owner-only profile columns are not selectable (got \(status))")
    }

    func testAnonymousCallerReadsNothing() async throws {
        let (profilesStatus, _) = try await rest("rest/v1/profiles")
        XCTAssertEqual(profilesStatus, 401)
        let (rpcStatus, _) = try await rest("rest/v1/rpc/public_profile", method: "POST",
                                            body: Data(#"{"p_user_id":"00000010-0000-4000-8000-000000000001"}"#.utf8))
        XCTAssertEqual(rpcStatus, 401)
    }

    func testForeignWritesAreRejected() async throws {
        let theo = try await signedIn("theo@roam.test")
        let token = try await theo.client.auth.session.accessToken
        let (status, _) = try await rest("rest/v1/profiles?id=eq.\(Self.maya.uuidString.lowercased())", token: token, method: "PATCH",
                                         body: Data(#"{"bio":"hacked"}"#.utf8))
        XCTAssertTrue([401, 403].contains(status), "Direct profile writes are denied (got \(status))")
        let (insertStatus, _) = try await rest("rest/v1/follows", token: token, method: "POST",
                                               body: Data(#"{"follower_id":"00000010-0000-4000-8000-000000000001","followee_id":"00000010-0000-4000-8000-000000000003"}"#.utf8))
        XCTAssertTrue([401, 403].contains(insertStatus), "Cannot write rows on another member's behalf")
    }

    func testInvalidAppleTokenFailsClosed() async throws {
        let backend = makeBackend()
        do {
            _ = try await backend.signInWithApple(idToken: "not-a-real.apple.token", rawNonce: AuthFlowModel.randomNonce())
            XCTFail("An invalid Apple identity token must not create a session")
        } catch {}
        let restored = try await backend.restoreSession()
        XCTAssertNil(restored)
    }

    func testAvatarUploadIsOwnerScopedAndBlockStopsReads() async throws {
        let (owner, _) = try await newMember(handlePrefix: "av")
        // The app's real upload preparation: M5 server inspection rejects raw UIKit JPEG metadata.
        let photo = try ImageProcessor.prepare(XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }.jpegData(compressionQuality: 0.8)))
        let jpeg = photo.data
        let staged = try await owner.stage(jpegData: jpeg, width: photo.width, height: photo.height, purpose: .avatar)
        let ownProfile = try await owner.ownProfile()
        let current = try XCTUnwrap(ownProfile)
        let updated = try await owner.updateProfile(ProfileUpdate(displayName: current.displayName, handle: current.handle, bio: "",
                                                                  homeCity: nil, avatarPath: staged.path))
        XCTAssertEqual(updated.avatarPath, staged.path)
        let viewer = try await signedIn("priya@roam.test")
        let data = try await viewer.imageData(path: staged.path)
        XCTAssertFalse(data.isEmpty, "Another member can read a current avatar")
        // Uploading into someone else's folder is denied by storage policy.
        let otherFolder = "\(updated.id.uuidString.lowercased())/sneaky.jpg"
        do {
            _ = try await viewer.client.storage.from("avatars").upload(otherFolder, data: jpeg, options: FileOptions(contentType: "image/jpeg"))
            XCTFail("Upload into another member's folder accepted")
        } catch {}
    }

    func testExpiredOrForgedRecoveryLinkFailsSafely() async throws {
        let backend = makeBackend()
        let forged = URL(string: "roam://auth-callback/recovery?code=forged-code-value")!
        do {
            _ = try await backend.handleCallback(forged)
            XCTFail("A forged recovery callback must not create a session")
        } catch let error as RoamError {
            XCTAssertNotEqual(error, .notSignedIn)
        }
        let restored = try await backend.restoreSession()
        XCTAssertNil(restored)
    }

    // MARK: helpers

    private func newMemberWithoutProfile() async throws -> (SupabaseBackend, String) {
        let backend = makeBackend()
        let email = "race-\(UUID().uuidString.prefix(8).lowercased())@roam.test"
        _ = try await backend.signUp(email: email, password: "integration-pass-123")
        _ = try await backend.verifySignUp(email: email, code: try await Mailpit.latestCode(to: email))
        return (backend, email)
    }

    private func capture<T>(_ work: () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }
}
