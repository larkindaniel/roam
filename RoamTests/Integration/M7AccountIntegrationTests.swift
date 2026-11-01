import Foundation
import Supabase
import XCTest
@testable import Roam

/// M7 against the real local backend: travel counts from real Visits, per-member settings, and
/// account deletion (recent sign-in, immediate hiding and write stop, session revocation).
/// Every account here is a disposable fictional member created for the test.
final class M7AccountIntegrationTests: BackendTestCase {
    private var year: Int { Calendar.current.component(.year, from: Date()) }

    private func place(_ backend: SupabaseBackend, name: String, locality: String?, region: String?, country: String, countryName: String,
                       latitude: Double, longitude: Double) async throws -> ExperienceSummary {
        try await backend.resolve(PlaceCandidate(provider: .mapkit, providerPlaceID: "I-M7-\(UUID().uuidString)",
            name: "\(name) \(UUID().uuidString.prefix(6))", address: "7 Travel Way", locality: locality, region: region,
            countryCode: country, countryName: countryName, latitude: latitude, longitude: longitude, phone: nil, website: nil,
            providerCategory: nil, timeZoneIdentifier: nil, isLocality: false, suggestedCategory: .culture))
    }

    @discardableResult
    private func log(_ backend: SupabaseBackend, _ experience: ExperienceSummary, date: String?) async throws -> RatingCommitResult {
        let ranking = try await backend.categoryRanking(.culture)
        var insertion = InsertionSession(sentiment: .liked, groups: ranking.groups(for: .liked))
        while !insertion.isComplete { insertion.choose(.preferExisting) }
        return try await backend.commitRating(RatingCommitRequest(operationID: UUID(), intent: .firstLog, experienceID: experience.id,
            category: .culture, sentiment: .liked, baseRevision: ranking.revision, answers: insertion.answers,
            visit: VisitPayload(date: date.flatMap(LocalDate.init(isoString:)), timeZoneIdentifier: nil, publicNote: "", mediaIDs: [], audience: .public)))
    }

    private func expectFailure(_ description: String, _ predicate: (RoamError) -> Bool, _ operation: () async throws -> Void) async {
        do { try await operation(); XCTFail("\(description): unexpectedly succeeded") }
        catch let error as RoamError { XCTAssertTrue(predicate(error), "\(description): unexpected \(error)") }
        catch { XCTFail("\(description): unexpected \(error)") }
    }

    func testTravelCountsComeFromRealVisitsAndFollowRatingAndVisitRemoval() async throws {
        let (traveller, _) = try await newMember(handlePrefix: "tv")
        let (viewer, _) = try await newMember(handlePrefix: "tw")
        let travellerProfile = try await traveller.ownProfile()
        let me = try XCTUnwrap(travellerProfile?.id)
        let maine = try await place(traveller, name: "Harbour Books", locality: "Portland", region: "Maine", country: "US",
                                    countryName: "United States", latitude: 43.66, longitude: -70.26)
        let oregon = try await place(traveller, name: "Rose Garden", locality: "Portland", region: "Oregon", country: "US",
                                     countryName: "United States", latitude: 45.52, longitude: -122.68)
        let glacier = try await place(traveller, name: "Ice Cap Viewpoint", locality: nil, region: nil, country: "GL",
                                      countryName: "Greenland", latitude: 69.2, longitude: -50.9)
        let thisYear = "\(year)-01-02", lastYear = "\(year - 1)-06-01"
        let maineLog = try await log(traveller, maine, date: thisYear)
        let oregonLog = try await log(traveller, oregon, date: lastYear)
        let glacierLog = try await log(traveller, glacier, date: nil)
        _ = try await traveller.addVisit(AddVisitRequest(operationID: UUID(), experienceID: oregon.id,
            visit: VisitPayload(date: LocalDate(isoString: thisYear), timeZoneIdentifier: nil, publicNote: "", mediaIDs: [], audience: .public)))
        let saved = try await place(traveller, name: "Someday Lake", locality: "Queenstown", region: "Otago", country: "NZ",
                                    countryName: "New Zealand", latitude: -45.03, longitude: 168.66)
        _ = try await traveller.setBookmark(experienceID: saved.id, saved: true)

        let travel = try await traveller.travelProfile(userID: me, year: year)
        XCTAssertEqual(travel.pins.count, 3, "Visits only: the bookmark adds no pin; a revisit adds no second pin")
        XCTAssertEqual(travel.countryCount, 2)
        XCTAssertEqual(travel.cityCount, 2, "Portland, Maine and Portland, Oregon are different cities")
        XCTAssertEqual(travel.placesWithoutCity, 1)
        XCTAssertEqual(travel.newThisYear.count, 1, "Oregon was first visited last year; its revisit doesn't count again")
        XCTAssertEqual(travel.newThisYear.unknownDateCount, 1)
        XCTAssertEqual(travel.pins.first { $0.experienceID == oregon.id }?.visitCount, 2)
        let seen = try await viewer.travelProfile(userID: me, year: year)
        XCTAssertEqual(seen, travel, "Another member sees the same public travel data")
        let header = try await viewer.publicProfile(userID: me)
        XCTAssertEqual(header.countryCount, travel.countryCount)
        XCTAssertEqual(header.cityCount, travel.cityCount)

        // Editing the earliest visit's date recomputes New this year through the real update path.
        _ = try await traveller.updateVisit(visitID: try XCTUnwrap(maineLog.visitID), note: "", date: VisitDate(date: LocalDate(isoString: lastYear),
                                                                                                                 timeZoneIdentifier: nil),
                                            mediaIDs: [], operationID: UUID())
        let afterDateEdit = try await traveller.travelProfile(userID: me, year: year)
        XCTAssertEqual(afterDateEdit.newThisYear.count, 0, "Moving the only first visit out of this year removes it")
        let previous = try await traveller.travelProfile(userID: me, year: year - 1)
        XCTAssertEqual(previous.newThisYear.count, 2, "Both Portlands now first visited last year")

        try await traveller.removeRating(experienceID: oregon.id, operationID: UUID())
        let afterRatingRemoval = try await traveller.travelProfile(userID: me, year: year)
        XCTAssertEqual(afterRatingRemoval.cityCount, 2, "Removing only the Rating keeps travel history")
        _ = try await traveller.deleteVisit(visitID: try XCTUnwrap(glacierLog.visitID), operationID: UUID(), allowRatingRemoval: true)
        let afterLastVisit = try await traveller.travelProfile(userID: me, year: year)
        XCTAssertEqual(afterLastVisit.countryCount, 1, "Greenland's only Visit is gone; the US remains")
        XCTAssertEqual(afterLastVisit.placesWithoutCity, 0, "Deleting the last Visit removes the pin")
        XCTAssertEqual(afterLastVisit.pins.count, 2)
        XCTAssertNotNil(oregonLog.visitID)
    }

    func testSettingsPersistPerMemberAndAreOwnerOnly() async throws {
        let (member, _) = try await newMember(handlePrefix: "st")
        let (other, _) = try await newMember(handlePrefix: "so")
        let defaults = try await member.settings()
        XCTAssertEqual(defaults, .defaults)
        let changed = UserSettings(distanceUnit: .miles, hapticsEnabled: false, notifyFollows: true, notifyLikes: false, notifyComments: true)
        let stored = try await member.update(changed)
        XCTAssertEqual(stored, changed)
        let retried = try await member.update(changed)
        XCTAssertEqual(retried, changed, "A retried save is harmless")
        let relaunched = makeBackend()
        _ = try await relaunched.signIn(email: try XCTUnwrap(member.client.auth.currentUser?.email), password: "integration-pass-123")
        let reloaded = try await relaunched.settings()
        XCTAssertEqual(reloaded, changed, "Settings persist across sessions")
        let otherSettings = try await other.settings()
        XCTAssertEqual(otherSettings, .defaults, "Each member has their own settings")
        let memberProfile = try await member.ownProfile()
        let memberID = try XCTUnwrap(memberProfile?.id)
        let token = try await other.client.auth.session.accessToken
        let (status, body) = try await rest("rest/v1/user_settings?user_id=eq.\(memberID.uuidString.lowercased())", token: token)
        XCTAssertEqual(status, 200)
        XCTAssertEqual(String(decoding: body, as: UTF8.self), "[]", "Another member can't read these settings")
        let (anonymous, _) = try await rest("rest/v1/rpc/my_settings", method: "POST", body: Data("{}".utf8))
        XCTAssertTrue([401, 403].contains(anonymous), "Anonymous callers can't read settings")
    }

    func testDeletionHidesTheAccountStopsWritesAndRevokesSessions() async throws {
        let (leaver, email) = try await newMember(handlePrefix: "dl")
        let (follower, _) = try await newMember(handlePrefix: "df")
        let leaverProfile = try await leaver.ownProfile()
        let leaverID = try XCTUnwrap(leaverProfile?.id)
        let experience = try await place(leaver, name: "Farewell Hall", locality: "Lisbon", region: "Lisboa", country: "PT",
                                         countryName: "Portugal", latitude: 38.71, longitude: -9.14)
        try await log(leaver, experience, date: "2026-03-03")
        try await befriend(follower, leaver)
        let before = try await follower.feed(cursor: nil)
        XCTAssertEqual(before.items.count, 1)

        // A different device signs in too; its refresh token must stop working.
        let otherDevice = makeBackend()
        _ = try await otherDevice.signIn(email: email, password: "integration-pass-123")

        let status = try await leaver.requestDeletion()
        XCTAssertEqual(status.state, .pending)
        XCTAssertEqual(status.appleRevocation, "not_applicable")
        let readBack = try await leaver.deletionStatus()
        XCTAssertEqual(readBack?.state, .pending)

        await expectFailure("hidden profile", { $0 == .notFound }) { _ = try await follower.publicProfile(userID: leaverID) }
        let after = try await follower.feed(cursor: nil)
        XCTAssertTrue(after.items.isEmpty, "Posts leave followers' feeds at once")
        await expectFailure("writes stop", { $0 == .forbidden }) { _ = try await leaver.setBookmark(experienceID: experience.id, saved: true) }
        await expectFailure("no new profile", { $0 == .forbidden }) { _ = try await leaver.createProfile(displayName: "Again", handle: "again_\(Int.random(in: 1000...9999))") }
        do {
            _ = try await otherDevice.client.auth.refreshSession()
            XCTFail("A revoked session refreshed")
        } catch {
            // Expected: every session and refresh token was revoked with the request.
        }
    }

    /// The server's ten-minute rule reads the token's `amr` sign-in time. A refresh must not renew
    /// it, and reauthenticating must. (pgTAP checks the refusal itself with an old `amr`.)
    func testRefreshKeepsTheSignInTimeAndReauthenticationRenewsIt() async throws {
        let (member, _) = try await newMember(handlePrefix: "dr")
        let first = try await member.client.auth.session
        let signedInAt = try amrTime(first.accessToken)
        try await Task.sleep(for: .milliseconds(1_200))
        let refreshed = try await member.client.auth.refreshSession()
        XCTAssertNotEqual(refreshed.accessToken, first.accessToken)
        XCTAssertEqual(try amrTime(refreshed.accessToken), signedInAt, "Refreshing doesn't count as signing in again")
        try await member.reauthenticate(password: "integration-pass-123")
        let renewed = try await member.client.auth.session
        XCTAssertGreaterThan(try amrTime(renewed.accessToken), signedInAt, "Reauthenticating renews the sign-in time")
    }

    private func amrTime(_ jwt: String) throws -> Int {
        let segment = try XCTUnwrap(jwt.split(separator: ".").dropFirst().first).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padded = segment + String(repeating: "=", count: (4 - segment.count % 4) % 4)
        let payload = try XCTUnwrap(Data(base64Encoded: padded))
        let claims = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        let amr = try XCTUnwrap(claims["amr"] as? [[String: Any]])
        return try XCTUnwrap(amr.compactMap { ($0["timestamp"] as? NSNumber)?.intValue }.max())
    }
}
