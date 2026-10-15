import Foundation
import Observation
import SwiftUI

/// The signed-in member's preferences (S26). The server is the source of truth; the last
/// acknowledged values are cached per account so units and haptics apply from launch.
///
/// A change shows in its control at once (`displayed`) but applies to the rest of the app only
/// after the server acknowledges it (`applied`). A failed save restores the previous value and
/// keeps the attempted one for Retry.
@MainActor
@Observable
final class SettingsStore {
    private(set) var applied: UserSettings = .defaults
    private(set) var pending: UserSettings?
    private(set) var hasLoaded = false
    private(set) var loadError: String?
    private(set) var saveError: String?
    private(set) var failedChange: UserSettings?

    private let service: any SettingsService
    private let storage: AccountStorage
    private var userID: UUID?
    private var generation = 0
    static let cacheName = "settings"

    init(service: any SettingsService, storage: AccountStorage) {
        self.service = service
        self.storage = storage
    }

    /// What the settings controls show: the value being saved, else the acknowledged one.
    var displayed: UserSettings { pending ?? applied }
    var isSaving: Bool { pending != nil }

    /// Applies the cached values for this account, then refreshes from the server.
    func load(userID: UUID) async {
        if self.userID != userID {
            reset()
            self.userID = userID
            if let cached = storage.read(UserSettings.self, name: Self.cacheName, userID: userID) { applied = cached }
        }
        let token = generation
        do {
            let fresh = try await service.settings()
            guard token == generation, self.userID == userID else { return }
            accept(fresh)
            hasLoaded = true
            loadError = nil
        } catch {
            guard token == generation, self.userID == userID else { return }
            loadError = error.roamMessage
        }
    }

    /// Saves one change on top of what the controls show. Only one save runs at a time.
    func update(_ change: (inout UserSettings) -> Void) async {
        guard pending == nil, userID != nil else { return }
        var desired = displayed
        change(&desired)
        guard desired != applied else { return }
        await save(desired)
    }

    func retry() async {
        guard let failedChange, pending == nil else { return }
        await save(failedChange)
    }

    func dismissError() {
        saveError = nil
        failedChange = nil
    }

    func reset() {
        generation += 1
        applied = .defaults
        pending = nil
        hasLoaded = false
        loadError = nil
        saveError = nil
        failedChange = nil
        userID = nil
    }

    private func save(_ desired: UserSettings) async {
        let token = generation
        let owner = userID
        pending = desired
        saveError = nil
        failedChange = nil
        do {
            let stored = try await service.update(desired)
            guard token == generation, owner == userID else { return }
            pending = nil
            accept(stored)
        } catch {
            guard token == generation, owner == userID else { return }
            pending = nil
            failedChange = desired
            saveError = error.roamMessage
        }
    }

    private func accept(_ value: UserSettings) {
        applied = value
        if let userID { try? storage.write(value, name: Self.cacheName, userID: userID) }
    }
}

// MARK: - Applying preferences

extension EnvironmentValues {
    /// Acknowledged distance unit for every distance shown in the app.
    @Entry var roamDistanceUnit: DistanceUnit = .kilometres
    /// Acknowledged haptics preference; every Roam haptic checks it.
    @Entry var roamHapticsEnabled: Bool = true
}

enum DistanceText {
    /// "1.2 km" or "0.7 mi" in the member's chosen unit, independent of the device locale.
    static func format(meters: Double, unit: DistanceUnit, locale: Locale = .current) -> String {
        let value = unit == .kilometres ? meters / 1_000 : meters / 1_609.344
        let digits = value < 10 ? 1 : 0
        let number = value.formatted(.number.precision(.fractionLength(digits)).locale(locale))
        return "\(number) \(unit.rawValue)"
    }
}

private struct RoamHaptic<Trigger: Equatable>: ViewModifier {
    let feedback: SensoryFeedback
    let trigger: Trigger
    @Environment(\.roamHapticsEnabled) private var enabled

    func body(content: Content) -> some View {
        content.sensoryFeedback(feedback, trigger: trigger) { _, _ in enabled }
    }
}

extension View {
    /// Plays `feedback` when `trigger` changes, unless the member turned haptics off.
    func roamHaptic<Trigger: Equatable>(_ feedback: SensoryFeedback, trigger: Trigger) -> some View {
        modifier(RoamHaptic(feedback: feedback, trigger: trigger))
    }
}
