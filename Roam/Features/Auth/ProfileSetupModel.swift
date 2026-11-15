import Foundation
import Observation
import UIKit

/// Setup (S01). Name, handle, photo, preferences and home cities stay on the phone, and any step can be revisited, until
/// Add friends: searching people needs a profile, so it's made (hidden from everyone) when you continue from home.
/// Friend requests wait until "Start using Roam", which completes setup and makes the profile findable.
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
    /// The chosen photo, ready to upload when the profile is made.
    private var pendingAvatar: ImageProcessor.Processed?
    /// Homes already saved to the server, so going back and changing them saves only the difference.
    private var savedHomes: [Destination] = []
    /// Your home cities (as many as you like); the profile's own home city, if any, starts the list.
    var homeCities: [Destination] = []
    var suggestions: LoadPhase<[MemberRow]> = .idle
    var following: Set<UUID> = []
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
        case .optionalDetails?: step = .friends
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

    /// On to the photo; nothing is saved yet (the handle's only been checked).
    func continueFromHandle() {
        guard Validation.handle(handle) == nil, handleState == .available || profile?.handle == handle else { return }
        saveDraft()
        step = .photo
    }

    /// Keeps the chosen photo on the phone until the profile is made.
    func pickAvatar(_ data: Data) {
        do {
            let processed = try ImageProcessor.prepare(data, maxPixel: 1_024)
            pendingAvatar = processed
            avatarImage = UIImage(data: processed.data)
            error = nil
        } catch {
            self.error = error.roamMessage
        }
    }

    var hasPhoto: Bool { avatarImage != nil || avatarPath != nil }

    func finishPhotoStep() { step = .preferences }

    func loadTaste() async {
        if let saved = try? await services.plans.taste() { taste = saved }
    }

    func savePreferences() { step = .home }

    /// Continuing from home makes the profile (or brings it up to date after going back): name and handle, photo,
    /// preferences and homes. It stays hidden from everyone until setup finishes. A handle lost to someone else in the
    /// meantime goes back to the handle step with everything kept.
    func saveHome() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            if let current = profile {
                if current.displayName != displayName || current.handle != handle {
                    profile = try await services.profiles.updateProfile(ProfileUpdate(displayName: displayName, handle: handle,
                                                                                      bio: current.bio, homeCity: current.homeCity,
                                                                                      avatarPath: current.avatarPath))
                }
            } else {
                profile = try await services.profiles.createProfile(displayName: displayName, handle: handle)
                services.storage.remove(name: "setup-draft", userID: auth.userID)
            }
            if let photo = pendingAvatar, let current = profile {
                let staged = try await services.media.stage(jpegData: photo.data, width: photo.width, height: photo.height, purpose: .avatar)
                profile = try await services.profiles.updateProfile(ProfileUpdate(displayName: current.displayName, handle: current.handle,
                                                                                  bio: current.bio, homeCity: current.homeCity,
                                                                                  avatarPath: staged.path))
                avatarPath = staged.path
                if let image = UIImage(data: photo.data) { services.images.store(image, for: staged.path) }
                pendingAvatar = nil
            }
            if taste != .empty { taste = try await services.plans.saveTaste(taste) }
            for city in savedHomes where !homeCities.contains(where: { $0.id == city.id }) {
                _ = try await services.plans.setHomeCity(city, present: false)
            }
            for city in homeCities where !savedHomes.contains(where: { $0.id == city.id }) {
                _ = try await services.plans.setHomeCity(city, present: true)
            }
            savedHomes = homeCities
            if profile?.setupCheckpoint != .optionalDetails {
                profile = try await services.profiles.setSetupCheckpoint(.optionalDetails)
            }
            step = .friends
        } catch RoamError.conflict(let message) {
            handleState = .unavailable(message)
            step = .handle
        } catch {
            self.error = error.roamMessage
        }
    }

    func addHome(_ city: Destination) {
        if !homeCities.contains(where: { $0.id == city.id }) { homeCities.append(city) }
    }

    func removeHome(_ city: Destination) { homeCities.removeAll { $0.id == city.id } }

    /// Every step but the first can go back.
    var canGoBack: Bool { step != .name }

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

    /// Who to ask, chosen by you (nothing preselected); the requests go when setup finishes.
    func toggleFollow(_ member: MemberSummary) {
        if following.contains(member.id) { following.remove(member.id) } else { following.insert(member.id) }
    }

    /// "Start using Roam": sends the friend requests, then completes setup, which makes the profile findable.
    func finish() async -> OwnProfile? {
        busy = true
        error = nil
        defer { busy = false }
        do {
            for id in following {
                _ = try await services.social.friendAction(userID: id, action: .request)
                following.remove(id)
            }
            let completed = try await services.profiles.setSetupCheckpoint(.complete)
            profile = completed
            return completed
        } catch {
            self.error = error.roamMessage
            return nil
        }
    }
}
