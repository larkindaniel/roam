import XCTest
@testable import Roam

@MainActor
final class AppRouterTests: XCTestCase {
    func testEachTabKeepsItsOwnStack() {
        let router = AppRouter(initialTab: .friends)
        let id = UUID()
        router.push(.globe(id), on: .myPlaces)
        router.push(.notifications, on: .friends)
        router.selectedTab = .forYou
        XCTAssertEqual(router.path(for: .myPlaces), [.globe(id)])
        XCTAssertEqual(router.path(for: .friends), [.notifications])
        XCTAssertTrue(router.path(for: .forYou).isEmpty)
        router.popToRoot(.friends)
        XCTAssertTrue(router.path(for: .friends).isEmpty)
        XCTAssertEqual(router.path(for: .myPlaces), [.globe(id)], "Popping one tab never affects another")
    }

    func testFindPeopleRoutesToMembersSegment() {
        let router = AppRouter(initialTab: .friends)
        router.showFindPeople()
        XCTAssertEqual(router.searchSegmentRequest, .members)
        XCTAssertEqual(router.path(for: .friends), [.search], "Search opens within the current tab")
    }

    func testResetAfterSetupLandsInYourLists() {
        let router = AppRouter(initialTab: .friends)
        router.push(.notifications)
        router.reset(initialTab: .myPlaces)
        XCTAssertEqual(router.selectedTab, .myPlaces)
        XCTAssertTrue(router.path(for: .friends).isEmpty)
    }
}

final class AccountStorageTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testAccountsAreIsolatedAndClearedIndependently() throws {
        let storage = AccountStorage(root: root)
        let maya = UUID()
        let theo = UUID()
        try storage.write("maya draft", name: "draft-1", userID: maya)
        try storage.write("theo draft", name: "draft-1", userID: theo)
        XCTAssertEqual(storage.read(String.self, name: "draft-1", userID: maya), "maya draft")
        XCTAssertEqual(storage.read(String.self, name: "draft-1", userID: theo), "theo draft")
        storage.clearAccount(maya)
        XCTAssertNil(storage.read(String.self, name: "draft-1", userID: maya))
        XCTAssertEqual(storage.read(String.self, name: "draft-1", userID: theo), "theo draft")
    }

    func testExpiredDraftsArePurged() throws {
        let storage = AccountStorage(root: root)
        let user = UUID()
        try storage.write("old", name: "draft-old", userID: user)
        try storage.write("new", name: "draft-new", userID: user)
        let oldURL = storage.directory(for: user).appendingPathComponent("draft-old.json")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-31 * 86_400)], ofItemAtPath: oldURL.path)
        storage.purgeExpired(userID: user, prefix: "draft-", lifetime: Limits.draftLifetime)
        XCTAssertEqual(storage.names(userID: user, prefix: "draft-"), ["draft-new"])
    }
}

final class LaunchOptionsTests: XCTestCase {
    func testFixtureFlagsParseInDebug() {
        let options = LaunchOptions.current(arguments: ["Roam", "-roam-backend", "fixture", "-roam-fixture-account", "maya",
                                                        "-roam-initial-tab", "explore", "-roam-location", "denied"])
        XCTAssertEqual(options.backend, .fixture)
        XCTAssertEqual(options.fixtureAccount, "maya")
        XCTAssertNil(options.initialTab)
        XCTAssertEqual(options.initialRoute, "explore")
        XCTAssertEqual(options.simulateLocation, "denied")
    }

    func testConfiguredLaunchUsesRealBackend() {
        XCTAssertEqual(LaunchOptions.current(arguments: ["Roam"], hasBackendConfiguration: true).backend, .supabase)
    }

    func testExplicitRealBackendWinsWithoutConfiguration() {
        let options = LaunchOptions.current(arguments: ["Roam", "-roam-backend", "supabase"], hasBackendConfiguration: false)
        XCTAssertEqual(options.backend, .supabase)
        XCTAssertNil(options.fixtureAccount)
    }

    #if targetEnvironment(simulator)
    func testUnconfiguredSimulatorOpensDemo() {
        let options = LaunchOptions.current(arguments: ["Roam"], hasBackendConfiguration: false)
        XCTAssertEqual(options.backend, .fixture)
        XCTAssertEqual(options.fixtureAccount, "maya")
        XCTAssertEqual(options.fixtureScenario, "social-activities")
    }
    #endif

    func testExplicitFixtureModeCanStillStartSignedOut() {
        let options = LaunchOptions.current(arguments: ["Roam", "-roam-backend", "fixture"], hasBackendConfiguration: false)
        XCTAssertEqual(options.backend, .fixture)
        XCTAssertNil(options.fixtureAccount)
    }
}

final class AppConfigTests: XCTestCase {
    func testBundleConfigContainsOnlyPublicClientValues() throws {
        let info = Bundle(for: AppServices.self).infoDictionary ?? [:]
        let key = info["RoamSupabasePublishableKey"] as? String ?? ""
        XCTAssertFalse(key.hasPrefix("sb_secret_"), "A secret key must never ship in the app")
        if key.hasPrefix("eyJ"), let payload = key.split(separator: ".").dropFirst().first {
            var base64 = String(payload).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            while base64.count % 4 != 0 { base64 += "=" }
            let json = String(data: Data(base64Encoded: base64) ?? Data(), encoding: .utf8) ?? ""
            XCTAssertFalse(json.contains("service_role"), "Service-role JWTs must never ship in the app")
        }
        let allValues = info.values.compactMap { $0 as? String }.joined(separator: " ")
        XCTAssertFalse(allValues.contains("service_role"))
    }
}
