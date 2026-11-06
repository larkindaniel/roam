import Foundation
import Supabase
import XCTest
@testable import Roam

/// Real local-backend integration mode. Requires the local Supabase stack, the fixture accounts
/// (scripts/fixtures/setup.py) and TEST_RUNNER_ROAM_BACKEND_TESTS=1; otherwise the tests skip.
class BackendTestCase: XCTestCase {
    static let fixturePassword = "roam-fixture-pass"
    static let maya = UUID(uuidString: "00000010-0000-4000-8000-000000000001")!
    static let theo = UUID(uuidString: "00000010-0000-4000-8000-000000000002")!
    static let priya = UUID(uuidString: "00000010-0000-4000-8000-000000000003")!
    static let jonas = UUID(uuidString: "00000010-0000-4000-8000-000000000004")!

    var config: AppConfig!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ROAM_BACKEND_TESTS"] == "1",
                          "Real-backend tests need TEST_RUNNER_ROAM_BACKEND_TESTS=1 and the local stack")
        config = try XCTUnwrap(AppConfig.fromBundle(Bundle(for: AppServices.self)), "Run scripts/configure-local.sh before building")
    }

    /// One member asks and the other accepts, as the app does.
    func befriend(_ first: SupabaseBackend, _ second: SupabaseBackend) async throws {
        let firstProfile = try await first.ownProfile()
        let secondProfile = try await second.ownProfile()
        let firstID = try XCTUnwrap(firstProfile?.id)
        let secondID = try XCTUnwrap(secondProfile?.id)
        _ = try await first.friendAction(userID: secondID, action: .request)
        _ = try await second.friendAction(userID: firstID, action: .accept)
    }

    func makeBackend() -> SupabaseBackend {
        SupabaseBackend(config: config, authStorage: InMemoryAuthStorage())
    }

    func signedIn(_ email: String, password: String = BackendTestCase.fixturePassword) async throws -> SupabaseBackend {
        let backend = makeBackend()
        _ = try await backend.signIn(email: email, password: password)
        return backend
    }

    /// A brand-new confirmed member with a profile, created through the public sign-up path.
    func newMember(handlePrefix: String = "t") async throws -> (SupabaseBackend, String) {
        let backend = makeBackend()
        let email = "test-\(UUID().uuidString.prefix(8).lowercased())@roam.test"
        _ = try await backend.signUp(email: email, password: "integration-pass-123")
        let code = try await Mailpit.latestCode(to: email)
        _ = try await backend.verifySignUp(email: email, code: code)
        let handle = "\(handlePrefix)\(UUID().uuidString.prefix(8).lowercased())".replacingOccurrences(of: "-", with: "")
        _ = try await backend.createProfile(displayName: "Test \(handle)", handle: String(handle.prefix(20)))
        return (backend, email)
    }

    /// Raw REST call with an arbitrary bearer (or none), to prove access rules below the app's services.
    func rest(_ path: String, token: String? = nil, method: String = "GET", body: Data? = nil) async throws -> (Int, Data) {
        let parts = path.split(separator: "?", maxSplits: 1).map(String.init)
        var components = URLComponents(url: config.supabaseURL.appendingPathComponent(parts[0]), resolvingAgainstBaseURL: false)!
        if parts.count > 1 { components.percentEncodedQuery = parts[1] }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }
}

final class InMemoryAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private var values: [String: Data] = [:]
    private let lock = NSLock()

    func store(key: String, value: Data) throws {
        lock.lock(); defer { lock.unlock() }
        values[key] = value
    }

    func retrieve(key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }

    func remove(key: String) throws {
        lock.lock(); defer { lock.unlock() }
        values[key] = nil
    }
}

/// Reads codes from the local Supabase mail viewer (Mailpit). Local only.
enum Mailpit {
    static var baseURL: URL {
        URL(string: ProcessInfo.processInfo.environment["ROAM_MAILPIT_URL"] ?? "http://127.0.0.1:54324")!
    }

    static func latestCode(to email: String, subjectContains: String? = nil, timeout: TimeInterval = 15) async throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            var components = URLComponents(url: baseURL.appendingPathComponent("api/v1/search"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "query", value: "to:\"\(email)\"")]
            let (data, _) = try await URLSession.shared.data(from: components.url!)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let messages = json["messages"] as? [[String: Any]] {
                let matching = messages.filter { subjectContains == nil || (($0["Subject"] as? String) ?? "").contains(subjectContains!) }
                if let id = matching.first?["ID"] as? String {
                    let (messageData, _) = try await URLSession.shared.data(from: baseURL.appendingPathComponent("api/v1/message/\(id)"))
                    let message = try JSONSerialization.jsonObject(with: messageData) as? [String: Any]
                    let text = (message?["Text"] as? String ?? "") + (message?["HTML"] as? String ?? "")
                    if let range = text.range(of: #"\b\d{6}\b"#, options: .regularExpression) {
                        return String(text[range])
                    }
                }
            }
            try await Task.sleep(for: .milliseconds(400))
        }
        throw RoamError.timeout
    }
}
