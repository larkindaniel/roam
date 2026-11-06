import XCTest
@testable import Roam

@MainActor
final class AppRouterTests: XCTestCase {
    func testEachTabKeepsItsOwnStack() {
        let router = AppRouter(initialTab: .feed)
        let id = UUID()
        router.push(.globe(id), on: .profile)
        router.push(.notifications, on: .feed)
        router.selectedTab = .search
        XCTAssertEqual(router.path(for: .profile), [.globe(id)])
        XCTAssertEqual(router.path(for: .feed), [.notifications])
        XCTAssertTrue(router.path(for: .search).isEmpty)
        router.popToRoot(.feed)
        XCTAssertTrue(router.path(for: .feed).isEmpty)
        XCTAssertEqual(router.path(for: .profile), [.globe(id)], "Popping one tab never affects another")
    }

    func testFindPeopleRoutesToMembersSegment() {
        let router = AppRouter(initialTab: .feed)
        router.showFindPeople()
        XCTAssertEqual(router.selectedTab, .search)
        XCTAssertEqual(router.searchSegmentRequest, .members)
    }

    func testResetAfterSetupLandsInYourLists() {
        let router = AppRouter(initialTab: .feed)
        router.push(.notifications)
        router.reset(initialTab: .lists)
        XCTAssertEqual(router.selectedTab, .lists)
        XCTAssertTrue(router.path(for: .feed).isEmpty)
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
        XCTAssertEqual(options.initialTab, .explore)
        XCTAssertEqual(options.simulateLocation, "denied")
    }

    func testDefaultIsRealBackend() {
        XCTAssertEqual(LaunchOptions.current(arguments: ["Roam"]).backend, .supabase)
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
