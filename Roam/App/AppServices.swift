import Foundation
import Observation

/// Dependency container injected into SwiftUI. Debug launch options can select the fixture
/// backend; Release builds always use the real backend and MapKit.
@MainActor
@Observable
final class AppServices {
    let options: LaunchOptions
    let isFixture: Bool
    let isConfigured: Bool
    let auth: any AuthService
    let profiles: any ProfileService
    let places: any PlaceSearchProviding
    let experiences: any ExperienceService
    let lists: any ListService
    let ranking: any RankingService
    let memories: any MemoryService
    let media: any MediaService
    let social: any SocialService
    let feed: any FeedService
    let notifications: any NotificationService
    let settings: any SettingsService
    let travel: any TravelService
    let account: any AccountService
    let storage: AccountStorage
    let location: LocationService
    let images: ImageStore
    private let healthCheck: (@Sendable () async -> Bool)?

    init<Backend>(options: LaunchOptions, isFixture: Bool, isConfigured: Bool, backend: Backend, places: any PlaceSearchProviding,
                  storage: AccountStorage, healthCheck: (@Sendable () async -> Bool)?)
    where Backend: AuthService & ProfileService & ExperienceService & ListService & RankingService & MemoryService & MediaService
        & SocialService & FeedService & NotificationService & SettingsService & TravelService & AccountService {
        self.options = options
        self.isFixture = isFixture
        self.isConfigured = isConfigured
        self.auth = backend
        self.profiles = backend
        self.places = places
        self.experiences = backend
        self.lists = backend
        self.ranking = backend
        self.memories = backend
        self.media = backend
        self.social = backend
        self.feed = backend
        self.notifications = backend
        self.settings = backend
        self.travel = backend
        self.account = backend
        self.storage = storage
        self.location = LocationService(simulated: options.simulateLocation)
        self.images = ImageStore(media: backend)
        self.healthCheck = healthCheck
    }

    func backendIsHealthy() async -> Bool {
        await healthCheck?() ?? true
    }

    static func make(options: LaunchOptions = .current()) -> AppServices {
        let storage = AccountStorage()
        if options.resetLocalState { storage.clearAll() }
        #if ROAM_FIXTURES
        if options.backend == .fixture {
            let backend = FixtureBackend(scenario: options.fixtureScenario, signedInHandle: options.fixtureAccount,
                                         latencyMilliseconds: options.fixtureLatencyMilliseconds)
            let delays = options.fixtureScenario == "search-race" ? ["har": 1_200] : [:]
            let places = FixturePlaceProvider(catalog: backend.catalog, latencyMilliseconds: options.fixtureLatencyMilliseconds, queryDelays: delays)
            return AppServices(options: options, isFixture: true, isConfigured: true, backend: backend, places: places,
                               storage: storage, healthCheck: nil)
        }
        #endif
        let config = AppConfig.fromBundle()
        let backend = SupabaseBackend(config: config ?? AppConfig(supabaseURL: URL(string: "http://127.0.0.1:54321")!, publishableKey: "unconfigured"))
        return AppServices(options: options, isFixture: false, isConfigured: config != nil, backend: backend,
                           places: MapKitPlaceSearchProvider(), storage: storage,
                           healthCheck: { await backend.health() })
    }
}
