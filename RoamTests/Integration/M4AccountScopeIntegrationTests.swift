import Foundation
import XCTest
@testable import Roam

private actor AccountSwitchTransportGate {
    private var enabled = false
    private var release: CheckedContinuation<Void, Never>?
    let arrived: XCTestExpectation
    init(arrived: XCTestExpectation) { self.arrived = arrived }
    func enable() { enabled = true }
    func resume() { release?.resume(); release = nil }
    func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        if enabled {
            enabled = false
            await withCheckedContinuation { continuation in
                release = continuation
                arrived.fulfill()
            }
        }
        return try await URLSession.shared.data(for: request)
    }
}

final class M4AccountScopeIntegrationTests: BackendTestCase {
    func testInFlightMutationKeepsOriginalActorAcrossSignOutAndAccountSwitch() async throws {
        let (original, originalEmail) = try await newMember(handlePrefix: "sa")
        let (_, otherEmail) = try await newMember(handlePrefix: "sb")
        let candidate = PlaceCandidate(provider: .mapkit, providerPlaceID: "M4-ACTOR-\(UUID())", name: "Actor-bound Café", address: "1 Test Street",
                                       locality: "Lisbon", region: "Lisboa", countryCode: "PT", countryName: "Portugal", latitude: 38.7, longitude: -9.1,
                                       phone: nil, website: nil, providerCategory: nil, timeZoneIdentifier: "Europe/Lisbon", isLocality: false, suggestedCategory: .foodDrink)
        let experience = try await original.resolve(candidate)
        let arrived = expectation(description: "RPC request built with original session")
        let gate = AccountSwitchTransportGate(arrived: arrived)
        let switchingClient = SupabaseBackend(config: config, authStorage: InMemoryAuthStorage(), rpcFetch: { try await gate.fetch($0) })
        _ = try await switchingClient.signIn(email: originalEmail, password: "integration-pass-123")
        await gate.enable()
        let save = Task { try await switchingClient.setBookmark(experienceID: experience.id, saved: true) }
        await fulfillment(of: [arrived], timeout: 5)
        await switchingClient.signOut()
        _ = try await switchingClient.signIn(email: otherEmail, password: "integration-pass-123")
        await gate.resume()
        let saved = try await save.value
        XCTAssertTrue(saved)
        let originalLibrary = try await original.library()
        let otherLibrary = try await switchingClient.library()
        XCTAssertTrue(originalLibrary.bookmarked.contains(experience.id), "An already-started request retains its original JWT actor")
        XCTAssertFalse(otherLibrary.bookmarked.contains(experience.id), "An account switch must not transfer pending intent to the new member")
    }
}
