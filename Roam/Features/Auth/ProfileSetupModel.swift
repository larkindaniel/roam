import Foundation
import Observation
import UIKit

/// Progressive setup (S01). Server checkpoints make it resumable after interruption; typed name
/// and handle are kept in an account-scoped local draft until the profile exists.
@MainActor
@Observable
final class ProfileSetupModel {
    /// Name, handle and photo make the profile; then what you like, your home city and friends. Setup never logs places.
    enum Step: Int, CaseIterable {
        case name, handle, photo, preferences, home, friends
    }

    enum HandleState: Equatable {
        case idle
        case checking
        case available
        case unavailable(String)
    }

    struct Draft: Codable {
        var displayName: String
        var handle: String
    }

    var step: Step
    var displayName: String
    var handle: String
    var handleState: HandleState = .idle
    var avatarImage: UIImage?
    var avatarPath: String?
    var avatarBusy = false
    /// Your home cities (as many as you like); the profile's own home city, if any, starts the list.
    var homeCities: [Destination] = []
    var suggestions: LoadPhase<[MemberRow]> = .idle
    var following: Set<UUID> = []
    var pendingFollows: Set<UUID> = []
    /// Your answers to the preference questions (each optional).
    var taste = TasteProfile.empty
    var busy = false
    var error: String?
    private(set) var profile: OwnProfile?

    private let services: AppServices
    private let auth: AuthSession

    init(services: AppServices, auth: AuthSession, profile: OwnProfile?, prefillName: String?) {
        self.services = services
        self.auth = auth
        self.profile = profile
        let draft = services.storage.read(Draft.self, name: "setup-draft", userID: auth.userID)
        displayName = profile?.displayName ?? draft?.displayName ?? prefillName ?? ""
        handle = profile?.handle ?? draft?.handle ?? ""
        avatarPath = profile?.avatarPath
        homeCities = profile?.homeCity.map { [$0] } ?? []
        switch profile?.setupCheckpoint {
        // A name typed before, or one Apple gave on first sign-in, skips straight to the handle (back still edits it).
        case .none:
            let hasName = draft?.displayName.isEmpty == false || prefillName?.trimmingCharacters(in: .whitespaces).isEmpty == false
            step = hasName ? .handle : .name
        case .profileCreated?: step = .photo
        case .optionalDetails?: step = .preferences
        case .complete?: step = .friends
        }
        if profile == nil, handle.isEmpty, !displayName.isEmpty { handle = Self.suggestedHandle(from: displayName) }
    }

    var progress: Double { Double(step.rawValue + 1) / Double(Step.allCases.count) }

    func saveDraft() {
        guard profile == nil else { return }
        try? services.storage.write(Draft(displayName: displayName, handle: handle), name: "setup-draft", userID: auth.userID)
    }

    var nameIssue: ValidationIssue? { Validation.displayName(displayName) }

    /// Their name in lowercase letters and numbers only, as long as a handle may be.
    static func suggestedHandle(from name: String) -> String {
        let base = name.lowercased().filter { $0.isLetter || $0.isNumber }
        return String(base.unicodeScalars.filter { $0.isASCII }.map(Character.init).prefix(Limits.handleRange.upperBound))
    }

    func continueFromName() {
        guard nameIssue == nil else { return }
        if handle.isEmpty { handle = Self.suggestedHandle(from: displayName) }
        saveDraft()
        step = .handle
    }

    /// Debounced availability check; it never reserves the handle.
    func checkHandle() async {
        let candidate = handle
        if let issue = Validation.handle(candidate) {
            handleState = .unavailable(issue.localizedDescription)
            return
        }
        handleState = .checking
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled, candidate == handle else { return }
        do {
            switch try await services.profiles.checkHandle(candidate) {
            case .available: handleState = .available
            case .taken: handleState = .unavailable("@\(candidate) is taken. Try another.")
            case .invalid(let issue): handleState = .unavailable(issue.localizedDescription)
            }
        } catch {
            handleState = .idle
        }
    }

    /// Creates the profile. A handle lost to a race keeps every typed value on screen.
    func createProfile() async {
        guard Validation.handle(handle) == nil, nameIssue == nil else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            profile = try await services.profiles.createProfile(displayName: displayName, handle: handle)
            services.storage.remove(name: "setup-draft", userID: auth.userID)
            step = .photo
        } catch RoamError.conflict(let message) {
            handleState = .unavailable(message)
            saveDraft()
        } catch {
            self.error = error.roamMessage
            saveDraft()
        }
    }

    func uploadAvatar(_ data: Data) async {
        avatarBusy = true
        error = nil
        defer { avatarBusy = false }
        do {
            let processed = try ImageProcessor.prepare(data, maxPixel: 1_024)
            let staged = try await services.media.stage(jpegData: processed.data, width: processed.width, height: processed.height, purpose: .avatar)
            guard let current = profile else { return }
            profile = try await services.profiles.updateProfile(ProfileUpdate(displayName: current.displayName, handle: current.handle,
                                                                              bio: current.bio, homeCity: current.homeCity,
                                                                              avatarPath: staged.path))
            avatarPath = staged.path
            if let image = UIImage(data: processed.data) {
                avatarImage = image
                services.images.store(image, for: staged.path)
            }
        } catch {
            self.error = error.roamMessage
        }
    }

    /// After the photo come your preferences.
    func finishPhotoStep() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            profile = try await services.profiles.setSetupCheckpoint(.optionalDetails)
            step = .preferences
        } catch {
            self.error = error.roamMessage
        }
    }

    func loadTaste() async {
        if let saved = try? await services.plans.taste() { taste = saved }
    }

    /// Saves whichever questions were answered (none is fine), then on to your home city.
    func savePreferences() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            if taste != .empty { taste = try await services.plans.saveTaste(taste) }
            step = .home
        } catch {
            self.error = error.roamMessage
        }
    }

    /// Makes each chosen city a home (optional), then on to friends.
    func saveHome() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            for city in homeCities { _ = try await services.plans.setHomeCity(city, present: true) }
            step = .friends
        } catch {
            self.error = error.roamMessage
        }
    }

    func addHome(_ city: Destination) {
        if !homeCities.contains(where: { $0.id == city.id }) { homeCities.append(city) }
    }

    func removeHome(_ city: Destination) { homeCities.removeAll { $0.id == city.id } }

    /// One step back (the profile, once made, isn't undone: back from the photo goes nowhere).
    var canGoBack: Bool { step == .handle || step.rawValue > Step.photo.rawValue }

    func goBack() {
        guard canGoBack, let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    func loadSuggestions() async {
        suggestions = .loading
        do {
            suggestions = .loaded(try await services.profiles.suggestedMembers(limit: 8))
        } catch {
            suggestions = .failed(error.roamMessage)
        }
    }

    /// Explicit, member-initiated requests only — nothing is preselected.
    func toggleFollow(_ member: MemberSummary) async {
        guard !pendingFollows.contains(member.id) else { return }
        let action: FriendAction = following.contains(member.id) ? .cancel : .request
        pendingFollows.insert(member.id)
        defer { pendingFollows.remove(member.id) }
        do {
            let persisted = try await services.social.friendAction(userID: member.id, action: action)
            if persisted == .none { following.remove(member.id) } else { following.insert(member.id) }
        } catch {
            self.error = error.roamMessage
        }
    }

    func finish() async -> OwnProfile? {
        busy = true
        error = nil
        defer { busy = false }
        do {
            let completed = try await services.profiles.setSetupCheckpoint(.complete)
            profile = completed
            return completed
        } catch {
            self.error = error.roamMessage
            return nil
        }
    }
}
