import Foundation

/// Public client configuration from Info.plist (populated by Config/*.xcconfig).
/// Contains only the API URL and publishable key; RLS protects everything behind them.
struct AppConfig: Equatable, Sendable {
    let supabaseURL: URL
    let publishableKey: String

    static func fromBundle(_ bundle: Bundle = .main) -> AppConfig? {
        guard let urlString = bundle.object(forInfoDictionaryKey: "RoamSupabaseURL") as? String,
              let url = URL(string: urlString), url.scheme != nil,
              let key = bundle.object(forInfoDictionaryKey: "RoamSupabasePublishableKey") as? String,
              !key.isEmpty, !key.hasPrefix("<"), !key.hasPrefix("$(")
        else { return nil }
        return AppConfig(supabaseURL: url, publishableKey: key)
    }

    static let authCallbackURL = URL(string: "roam://auth-callback")!
}

/// Debug launch options. Release builds ignore every fixture flag and always use the real backend.
struct LaunchOptions: Equatable, Sendable {
    enum Backend: String, Sendable {
        case supabase
        case fixture
    }

    var backend: Backend = .supabase
    /// Fixture handle to start signed in as (`maya`, `theo`, ...); nil starts signed out.
    var fixtureAccount: String?
    /// Named fixture data variant: `default`, `empty`, `new-account`.
    var fixtureScenario: String = "default"
    /// Artificial fixture latency in milliseconds, to exercise loading states.
    var fixtureLatencyMilliseconds: Int = 0
    var resetLocalState = false
    var uiTesting = false
    var showComponentCatalog = false
    var initialTab: AppTab?
    var simulateLocation: String?
    /// Debug-only route pushed after launch (`globe`), for direct visual inspection.
    var initialRoute: String?

    static func current(arguments: [String] = ProcessInfo.processInfo.arguments) -> LaunchOptions {
        var options = LaunchOptions()
        #if ROAM_FIXTURES
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        if let backend = value(after: "-roam-backend").flatMap(Backend.init(rawValue:)) { options.backend = backend }
        options.fixtureAccount = value(after: "-roam-fixture-account")
        if let scenario = value(after: "-roam-fixture-scenario") { options.fixtureScenario = scenario }
        if let latency = value(after: "-roam-fixture-latency").flatMap(Int.init) { options.fixtureLatencyMilliseconds = latency }
        options.resetLocalState = arguments.contains("-roam-reset-state")
        options.uiTesting = arguments.contains("-roam-ui-testing")
        options.showComponentCatalog = arguments.contains("-roam-component-catalog")
        let startingPoint = value(after: "-roam-initial-tab")
        options.initialTab = startingPoint.flatMap(AppTab.init(rawValue:))
        options.simulateLocation = value(after: "-roam-location")
        options.initialRoute = value(after: "-roam-initial-route")
        // Search, Explore and Profile are screens within For You, so a test can start on one directly.
        if let startingPoint, ["search", "explore", "profile"].contains(startingPoint) { options.initialRoute = startingPoint }
        #endif
        return options
    }
}
