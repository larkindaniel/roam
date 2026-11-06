import XCTest
@testable import Roam

/// Settings are server-acknowledged desired state: a change shows in its control at once but applies
/// to the rest of the app only after the save is acknowledged, and a failure restores the old value.
@MainActor
final class M7SettingsStoreTests: XCTestCase {
    final class ScriptedSettings: SettingsService, @unchecked Sendable {
        private let lock = NSLock()
        private var stored = UserSettings.defaults
        private var failures = 0
        private var holding = false
        private var waiting: [CheckedContinuation<Void, Never>] = []
        private(set) var saves: [UserSettings] = []

        init(stored: UserSettings = .defaults, failures: Int = 0) {
            self.stored = stored
            self.failures = failures
        }

        func hold() { lock.withLock { holding = true } }

        func release() {
            let continuations = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
                holding = false
                defer { waiting = [] }
                return waiting
            }
            continuations.forEach { $0.resume() }
        }

        func settings() async throws -> UserSettings { lock.withLock { stored } }

        func update(_ settings: UserSettings) async throws -> UserSettings {
            if lock.withLock({ holding }) {
                await withCheckedContinuation { continuation in lock.withLock { waiting.append(continuation) } }
            }
            return try lock.withLock {
                saves.append(settings)
                if failures > 0 {
                    failures -= 1
                    throw RoamError.timeout
                }
                stored = settings
                return settings
            }
        }
    }

    private func storage() -> AccountStorage {
        AccountStorage(root: FileManager.default.temporaryDirectory.appendingPathComponent("m7-settings-\(UUID().uuidString)"))
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<500 where !condition() { await Task.yield() }
    }

    func testAChangeAppliesOnlyAfterTheServerAcknowledgesIt() async {
        let service = ScriptedSettings()
        let store = SettingsStore(service: service, storage: storage())
        await store.load(userID: UUID())
        service.hold()
        let save = Task { await store.update { $0.distanceUnit = .miles } }
        await waitUntil { store.isSaving }
        XCTAssertEqual(store.displayed.distanceUnit, .miles, "The control shows the new choice while saving")
        XCTAssertEqual(store.applied.distanceUnit, .kilometres, "Distances keep the acknowledged unit until the save is acknowledged")
        service.release()
        await save.value
        XCTAssertEqual(store.applied.distanceUnit, .miles)
        XCTAssertFalse(store.isSaving)
    }

    func testAFailedSaveRestoresThePreviousValueAndRetrySendsTheSameChange() async {
        let service = ScriptedSettings(failures: 1)
        let store = SettingsStore(service: service, storage: storage())
        await store.load(userID: UUID())
        await store.update { $0.hapticsEnabled = false }
        XCTAssertTrue(store.displayed.hapticsEnabled, "The control returns to the previous value")
        XCTAssertTrue(store.applied.hapticsEnabled)
        XCTAssertNotNil(store.saveError)
        XCTAssertEqual(store.failedChange?.hapticsEnabled, false)
        await store.retry()
        XCTAssertFalse(store.applied.hapticsEnabled, "Retry saves the same change")
        XCTAssertNil(store.saveError)
        XCTAssertEqual(service.saves.count, 2)
        XCTAssertEqual(service.saves[0], service.saves[1], "The retry sends the identical desired state")
    }

    func testAcknowledgedSettingsAreCachedPerAccountAndApplyBeforeTheServerAnswers() async {
        let storage = storage()
        let member = UUID(), other = UUID()
        let saved = UserSettings(distanceUnit: .miles, hapticsEnabled: false, notifyFollows: true, notifyLikes: false, notifyComments: true)
        let first = SettingsStore(service: ScriptedSettings(stored: saved), storage: storage)
        await first.load(userID: member)
        XCTAssertEqual(first.applied, saved)

        final class Offline: SettingsService, @unchecked Sendable {
            func settings() async throws -> UserSettings { throw RoamError.offline }
            func update(_ settings: UserSettings) async throws -> UserSettings { throw RoamError.offline }
        }
        let relaunched = SettingsStore(service: Offline(), storage: storage)
        await relaunched.load(userID: member)
        XCTAssertEqual(relaunched.applied, saved, "The last acknowledged settings apply at launch even offline")
        XCTAssertNotNil(relaunched.loadError)
        await relaunched.load(userID: other)
        XCTAssertEqual(relaunched.applied, .defaults, "Another account never sees these settings")
    }

    func testDistancesUseTheChosenUnitRegardlessOfLocale() {
        let us = Locale(identifier: "en_US"), germany = Locale(identifier: "de_DE")
        XCTAssertEqual(DistanceText.format(meters: 2_500, unit: .kilometres, locale: us), "2.5 km")
        XCTAssertEqual(DistanceText.format(meters: 1_609.344, unit: .miles, locale: us), "1.0 mi")
        XCTAssertEqual(DistanceText.format(meters: 2_500, unit: .kilometres, locale: germany), "2,5 km")
        XCTAssertEqual(DistanceText.format(meters: 32_186.88, unit: .miles, locale: germany), "20 mi")
    }
}

/// Travel Profile rows and filters, and fixture parity with `travel_profile`.
final class M7TravelProfileTests: XCTestCase {
    private func pin(_ name: String, _ category: ExperienceCategory?, country: String?, city: String?) -> GlobePin {
        GlobePin(experienceID: UUID(), name: name, category: category, latitude: 0, longitude: 0, countryCode: country,
                 cityKey: city, countryName: country, cityName: city)
    }

    func testFiltersNarrowPinsByCategoryCityOrCountry() {
        let pins = [pin("A", .culture, country: "US", city: "us|maine|portland"), pin("B", .culture, country: "US", city: "us|oregon|portland"),
                    pin("C", .outdoors, country: "GL", city: nil)]
        XCTAssertEqual(pins.filter(TravelFilter.category(.culture).matches).map(\.name), ["A", "B"])
        XCTAssertEqual(pins.filter(TravelFilter.city(key: "us|oregon|portland", name: "Portland").matches).map(\.name), ["B"],
                       "Same-name cities stay distinct")
        XCTAssertEqual(pins.filter(TravelFilter.country(code: "GL", name: "Greenland").matches).map(\.name), ["C"],
                       "A place without a city is still found through its country")
    }

    /// Maya's fixture travels cover the M7 geography cases: two Portlands, a Greenland place with no
    /// city, Singapore (no bundled boundary), a repeated visit, an unknown-date-only place, and
    /// bookmarks and a home city that never count.
    func testFixtureTravelMatchesTheServerRules() async throws {
        let backend = FixtureBackend(scenario: "default", signedInHandle: "maya", latencyMilliseconds: 0)
        let travel = try await backend.travelProfile(userID: FixtureIDs.maya, year: 2026)
        XCTAssertEqual(travel.pins.count, 15, "One pin per visited Experience")
        XCTAssertEqual(Set(travel.pins.map(\.experienceID)).count, travel.pins.count)
        XCTAssertEqual(travel.countryCount, 10)
        XCTAssertEqual(travel.cityCount, 11)
        XCTAssertEqual(travel.cities.filter { $0.name == "Portland" }.compactMap(\.region).sorted(), ["Maine", "Oregon"])
        XCTAssertEqual(travel.placesWithoutCity, 1)
        XCTAssertNil(travel.pins.first { $0.name == "Ice Fjord Overlook" }?.cityKey)
        XCTAssertFalse(travel.pins.contains { $0.name == "Glass Lagoon Baths" }, "A bookmark is not a visit")
        XCTAssertEqual(travel.pins.first { $0.name == "Harbor Lantern Café" }?.visitCount, 2, "Repeat visits keep one pin")
        XCTAssertEqual(travel.pins.first { $0.name == "Harbor Lantern Café" }?.firstVisitDate, LocalDate(isoString: "2026-06-14"))
        XCTAssertEqual(travel.newThisYear.count, 8)
        XCTAssertEqual(travel.newThisYear.unknownDateCount, 1)
        XCTAssertEqual(travel.newThisYear.experienceIDs.count, 8)
        let lastYear = try await backend.travelProfile(userID: FixtureIDs.maya, year: 2025)
        XCTAssertEqual(lastYear.newThisYear.count, 4, "Each year counts its own first visits")
        XCTAssertNotNil(travel.pins.first { $0.countryCode == "SG" })
        XCTAssertNil(CountryGeometry.shared.shape(for: "SG"), "Singapore has no bundled boundary, so its pin stays unshaded")
        XCTAssertNotNil(CountryGeometry.shared.shape(for: "GL"))
    }

    func testFixtureTravelRejectsBlockedViewersLikeTheServer() async throws {
        let backend = FixtureBackend(scenario: "default", signedInHandle: "maya", latencyMilliseconds: 0)
        try await backend.setBlock(userID: FixtureIDs.theo, blocked: true)
        do {
            _ = try await backend.travelProfile(userID: FixtureIDs.theo, year: 2026)
            XCTFail("A blocked member's travels were readable")
        } catch {
            XCTAssertEqual(error as? RoamError, .notFound)
        }
    }
}

/// S17 share text: public values only, the sharer's own labelled score, and a real Apple Maps link.
final class M7ShareTextTests: XCTestCase {
    private func summary(followingScore: Score? = Score(tenths: 91)) -> ExperienceSummary {
        ExperienceSummary(id: UUID(), placeID: UUID(), name: "Harbor Lantern Café", category: .foodDrink, locality: "Lisbon", region: "Lisboa",
                          countryCode: "PT", countryName: "Portugal", latitude: 38.7072, longitude: -9.1366, providerPlaceID: nil,
                          followingScore: followingScore, followingCount: 2,
                          viewer: .none)
    }

    func testExperienceTextHasNameCategoryAreaAndAppleMapsLink() throws {
        let text = ShareText.experience(summary(), ownRating: nil)
        XCTAssertTrue(text.hasPrefix("Harbor Lantern Café\nFood & Drink · Lisbon, Portugal\n"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("score"), "Without your own rating no score is shared, not even Following")
        let link = try XCTUnwrap(text.split(separator: "\n").last.flatMap { URLComponents(string: String($0)) })
        XCTAssertEqual(link.scheme, "https")
        XCTAssertEqual(link.host, "maps.apple.com")
        XCTAssertEqual(link.queryItems?.first { $0.name == "q" }?.value, "Harbor Lantern Café")
        XCTAssertEqual(link.queryItems?.first { $0.name == "ll" }?.value, "38.707200,-9.136600")
    }

    func testOnlyTheSharersOwnCurrentScoreIsIncludedAndLabelled() {
        let mine = MyRating(ratingID: UUID(), category: .foodDrink, sentiment: .liked, score: Score(tenths: 84), rank: 2, groupSize: 1,
                            categoryCount: 4, firstRatedAt: Date())
        let text = ShareText.experience(summary(), ownRating: mine)
        let scoreLines = text.split(separator: "\n").filter { $0.localizedCaseInsensitiveContains("score") }
        XCTAssertEqual(scoreLines, ["My Roam score: 8.4/10 in Food & Drink"], "Only your own labelled score; never the Following 9.1")
    }

    func testProfileTextIsPlainPublicValuesWithoutALink() {
        let text = ShareText.profile(displayName: "Maya Chen", handle: "mayaroams", countryCount: 1, cityCount: 11)
        XCTAssertEqual(text, "Maya Chen (@mayaroams) on Roam\nVisited 1 country · 11 cities")
        XCTAssertFalse(text.contains("http"), "Roam has no hosted profile pages to link to")
    }
}

/// Account deletion asks for a recent sign-in, confirms, and reports the server's state honestly.
@MainActor
final class M7DeleteAccountModelTests: XCTestCase {
    private func model(_ backend: FixtureBackend, providers: [AuthProviderKind] = [.email]) -> DeleteAccountModel {
        DeleteAccountModel(auth: backend, account: backend, providers: providers)
    }

    func testDeletionNeedsARecentPasswordThenHidesTheAccount() async throws {
        let backend = FixtureBackend(scenario: "default", signedInHandle: "maya", latencyMilliseconds: 0)
        let flow = model(backend)
        XCTAssertTrue(flow.canUsePassword)
        XCTAssertFalse(flow.canUseApple, "Only the account's providers are offered")
        flow.begin()
        flow.password = "wrong-password"
        await flow.confirmPassword()
        XCTAssertEqual(flow.step, .reauthenticate)
        XCTAssertEqual(flow.error, "That password is incorrect.")
        flow.password = FixtureSeed.password
        await flow.confirmPassword()
        XCTAssertEqual(flow.step, .confirm)
        XCTAssertTrue(flow.password.isEmpty, "The password isn't kept")
        await flow.delete()
        guard case .requested(let status) = flow.step else { return XCTFail("Deletion wasn't requested: \(flow.step)") }
        XCTAssertEqual(status.state, .pending)
        let lines = DeleteAccountModel.statusLines(status).joined(separator: " ")
        XCTAssertTrue(lines.contains("still in progress"), "A pending job is never reported as finished")
        XCTAssertFalse(lines.contains("have been deleted"))
        // The account is hidden and write-disabled at once.
        _ = try await backend.signIn(email: "theo@roam.test", password: FixtureSeed.password)
        do { _ = try await backend.publicProfile(userID: FixtureIDs.maya); XCTFail("A deleted profile stayed visible") }
        catch { XCTAssertEqual(error as? RoamError, .notFound) }
    }

    func testAStaleSignInIsSentBackToReauthenticate() async throws {
        let backend = FixtureBackend(scenario: "default", signedInHandle: "maya", latencyMilliseconds: 0)
        let flow = model(backend)
        flow.begin()
        flow.password = FixtureSeed.password
        await flow.confirmPassword()
        await backend.ageAuthentication(by: 11 * 60)
        await flow.delete()
        XCTAssertEqual(flow.step, .reauthenticate)
        XCTAssertEqual(flow.error, RoamError.reauthenticationRequired.roamMessage)
    }

    func testAFailedRequestSaysTheAccountWasNotDeleted() async throws {
        let backend = FixtureBackend(scenario: "deletion-failure", signedInHandle: "maya", latencyMilliseconds: 0)
        let flow = model(backend)
        flow.begin()
        flow.password = FixtureSeed.password
        await flow.confirmPassword()
        await flow.delete()
        XCTAssertEqual(flow.step, .confirm)
        XCTAssertTrue(flow.error?.hasPrefix("Your account wasn't deleted.") == true)
        await flow.delete()
        guard case .requested = flow.step else { return XCTFail("Retry didn't request deletion") }
    }

    func testAppleStatusesAreReportedWithoutClaimingRevocation() {
        let status = AccountDeletionStatus(state: .completed, appleRevocation: "not_configured", storageCleanup: "completed", updatedAt: Date())
        let lines = DeleteAccountModel.statusLines(status)
        XCTAssertEqual(lines.first, "Your account and its data have been deleted.")
        XCTAssertTrue(lines.contains { $0.hasPrefix("Roam couldn't revoke Sign in with Apple automatically.") })
        let email = AccountDeletionStatus(state: .pending, appleRevocation: "not_applicable", storageCleanup: "pending", updatedAt: Date())
        XCTAssertFalse(DeleteAccountModel.statusLines(email).contains { $0.contains("Apple") })
    }
}

/// Profile edits validate locally, survive a restart as an account-scoped draft, keep every field
/// when a save fails and send nothing on Cancel.
@MainActor
final class M7EditProfileModelTests: XCTestCase {
    private func services(_ backend: FixtureBackend) -> AppServices {
        var options = LaunchOptions()
        options.backend = .fixture
        return AppServices(options: options, isFixture: true, isConfigured: true, backend: backend,
                           places: FixturePlaceProvider(catalog: backend.catalog, latencyMilliseconds: 0),
                           storage: AccountStorage(root: FileManager.default.temporaryDirectory.appendingPathComponent("m7-edit-\(UUID().uuidString)")),
                           healthCheck: nil)
    }

    func testUnsavedEditsSurviveARestartAndCancelDiscardsThemWithoutAWrite() async throws {
        let backend = FixtureBackend(scenario: "default", signedInHandle: "maya", latencyMilliseconds: 0)
        let services = services(backend)
        let loaded = try await backend.ownProfile()
        let profile = try XCTUnwrap(loaded)
        let editor = EditProfileModel(services: services, profile: profile)
        XCTAssertFalse(editor.canSave, "Nothing to save before a change")
        editor.draft.bio = "Night trains and day hikes."
        let restored = EditProfileModel(services: services, profile: profile)
        XCTAssertTrue(restored.restoredDraft)
        XCTAssertEqual(restored.draft.bio, "Night trains and day hikes.")
        restored.discard()
        let fresh = EditProfileModel(services: services, profile: profile)
        XCTAssertFalse(fresh.restoredDraft)
        XCTAssertEqual(fresh.draft, fresh.original)
        let stored = try await backend.ownProfile()
        XCTAssertEqual(stored?.bio, profile.bio, "Cancel sent nothing")
    }

    func testValidationBlocksSaveAndALostHandleKeepsEveryField() async throws {
        let backend = FixtureBackend(scenario: "default", signedInHandle: "maya", latencyMilliseconds: 0)
        let services = services(backend)
        let loaded = try await backend.ownProfile()
        let profile = try XCTUnwrap(loaded)
        let editor = EditProfileModel(services: services, profile: profile)
        editor.draft.displayName = "   "
        XCTAssertEqual(editor.nameIssue, ValidationIssue.required.localizedDescription)
        XCTAssertFalse(editor.canSave)
        editor.draft.displayName = "Maya C."
        editor.draft.bio = String(repeating: "a", count: Limits.bioMax + 1)
        XCTAssertNotNil(editor.bioIssue)
        XCTAssertFalse(editor.canSave)
        editor.draft.bio = "  Harbours and late jazz.\n"
        editor.draft.handle = "theowanders"
        await editor.checkHandle()
        XCTAssertEqual(editor.handleIssue, "@theowanders is taken. Try another.")
        XCTAssertFalse(editor.canSave)
        editor.draft.handle = "maya_travels"
        await editor.checkHandle()
        XCTAssertTrue(editor.canSave)
        // Another member takes the handle between the check and the save.
        _ = try await backend.signIn(email: "theo@roam.test", password: FixtureSeed.password)
        _ = try await backend.updateProfile(ProfileUpdate(displayName: "Theo Park", handle: "maya_travels", bio: "", homeCity: nil, avatarPath: nil))
        _ = try await backend.signIn(email: "maya@roam.test", password: FixtureSeed.password)
        let lost = await editor.save()
        XCTAssertNil(lost)
        XCTAssertEqual(editor.draft.displayName, "Maya C.", "A failed save keeps every field")
        XCTAssertEqual(editor.draft.bio, "  Harbours and late jazz.\n", "The draft keeps exactly what was typed")
        XCTAssertNotNil(editor.handleIssue)
        XCTAssertTrue(EditProfileModel(services: services, profile: profile).restoredDraft, "The draft is still on disk")
        editor.draft.handle = "maya_roams_on"
        await editor.checkHandle()
        let saved = await editor.save()
        XCTAssertEqual(saved?.handle, "maya_roams_on")
        XCTAssertEqual(saved?.displayName, "Maya C.")
        XCTAssertEqual(saved?.bio, "Harbours and late jazz.", "Surrounding whitespace is trimmed on save")
        XCTAssertFalse(EditProfileModel(services: services, profile: try XCTUnwrap(saved)).restoredDraft, "A saved edit leaves no draft")
    }
}
