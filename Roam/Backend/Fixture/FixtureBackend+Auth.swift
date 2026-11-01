#if ROAM_FIXTURES
import Foundation

extension FixtureBackend: AuthService {
    static let confirmationCode = "123456"
    static let recoveryCode = "654321"

    private func session(for id: UUID) -> AuthSession {
        let member = members[id]
        return AuthSession(userID: id, email: member?.email, providers: member?.providers ?? [.email])
    }

    func restoreSession() async throws -> AuthSession? {
        await pause()
        guard let id = currentUserID, members[id]?.deleted == false else { return nil }
        return session(for: id)
    }

    nonisolated func sessionChanges() -> AsyncStream<AuthSession?> {
        sessionBroadcaster.stream()
    }

    func signUp(email: String, password: String) async throws -> SignUpOutcome {
        await pause()
        if let issue = Validation.email(email) { throw RoamError.validation(issue.localizedDescription) }
        if let issue = Validation.password(password) { throw RoamError.validation(issue.localizedDescription) }
        let normalized = email.lowercased()
        // Like the server, don't reveal whether the address already has an account.
        if !members.values.contains(where: { $0.email == normalized }) {
            let id = UUID()
            members[id] = Member(id: id, handle: nil, displayName: nil, bio: "", email: normalized, password: password, avatarPath: nil,
                                 homeCity: nil, setupCheckpoint: nil, hasSeenBeenIntro: false, createdAt: Date(),
                                 emailConfirmed: false, providers: [.email])
        }
        pendingCodes["signup:\(normalized)"] = Self.confirmationCode
        return .confirmationRequired(email: normalized)
    }

    func verifySignUp(email: String, code: String) async throws -> AuthSession {
        await pause()
        let normalized = email.lowercased()
        guard pendingCodes["signup:\(normalized)"] == code,
              let id = members.values.first(where: { $0.email == normalized })?.id else {
            throw RoamError.validation("That code is invalid or has expired. Request a new one.")
        }
        pendingCodes["signup:\(normalized)"] = nil
        members[id]?.emailConfirmed = true
        currentUserID = id
        authenticatedAt[id] = Date()
        let session = session(for: id)
        sessionBroadcaster.send(session)
        return session
    }

    func resendConfirmation(email: String) async throws {
        await pause()
        pendingCodes["signup:\(email.lowercased())"] = Self.confirmationCode
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        await pause()
        guard let member = members.values.first(where: { $0.email == email.lowercased() && !$0.deleted }),
              member.password == password, member.emailConfirmed else {
            throw RoamError.validation("Email or password is incorrect.")
        }
        currentUserID = member.id
        authenticatedAt[member.id] = Date()
        let session = session(for: member.id)
        sessionBroadcaster.send(session)
        return session
    }

    func signInWithApple(idToken: String, rawNonce: String) async throws -> AuthSession {
        // Fixture mode never fabricates an Apple identity; the real provider is required.
        throw RoamError.server("Sign in with Apple needs the real Apple provider. It isn't available in fixture mode.")
    }

    func requestPasswordReset(email: String) async throws {
        await pause()
        pendingCodes["recovery:\(email.lowercased())"] = Self.recoveryCode
    }

    func verifyRecovery(email: String, code: String) async throws -> AuthSession {
        await pause()
        let normalized = email.lowercased()
        guard pendingCodes["recovery:\(normalized)"] == code,
              let id = members.values.first(where: { $0.email == normalized && !$0.deleted })?.id else {
            throw RoamError.validation("That code is invalid or has expired. Request a new one.")
        }
        pendingCodes["recovery:\(normalized)"] = nil
        currentUserID = id
        recoveryUserID = id
        authenticatedAt[id] = Date()
        return session(for: id)
    }

    func handleCallback(_ url: URL) async throws -> AuthCallbackResult {
        throw RoamError.validation("This link has expired. Request a new one from the app.")
    }

    func updatePassword(_ newPassword: String) async throws {
        await pause()
        let id = try requireUser()
        if let issue = Validation.password(newPassword) { throw RoamError.validation(issue.localizedDescription) }
        members[id]?.password = newPassword
        recoveryUserID = nil
        sessionBroadcaster.send(session(for: id))
    }

    func reauthenticate(password: String) async throws {
        await pause()
        let id = try requireUser()
        guard members[id]?.password == password else { throw RoamError.validation("That password is incorrect.") }
        authenticatedAt[id] = Date()
    }

    func signOut() async {
        currentUserID = nil
        recoveryUserID = nil
        sessionBroadcaster.send(nil)
    }
}

extension FixtureBackend: ProfileService {
    private func ownProfileModel(_ id: UUID) -> OwnProfile? {
        guard let member = members[id], let handle = member.handle, let name = member.displayName, let checkpoint = member.setupCheckpoint else { return nil }
        return OwnProfile(id: id, handle: handle, displayName: name, bio: member.bio, avatarPath: member.avatarPath, homeCity: member.homeCity,
                          setupCheckpoint: checkpoint, hasSeenBeenIntro: member.hasSeenBeenIntro, createdAt: member.createdAt)
    }

    func ownProfile() async throws -> OwnProfile? {
        await pause()
        return ownProfileModel(try requireUser())
    }

    func checkHandle(_ handle: String) async throws -> HandleAvailability {
        await pause()
        let me = try requireUser()
        if let issue = Validation.handle(handle) { return .invalid(issue) }
        return members.values.contains(where: { $0.handle == handle && $0.id != me }) ? .taken : .available
    }

    func createProfile(displayName: String, handle: String) async throws -> OwnProfile {
        await pause()
        let me = try requireUser()
        if let issue = Validation.displayName(displayName) { throw RoamError.validation(issue.localizedDescription) }
        if let issue = Validation.handle(handle) { throw RoamError.validation(issue.localizedDescription) }
        if members.values.contains(where: { $0.handle == handle && $0.id != me }) {
            throw RoamError.conflict("That handle was just taken. Try another.")
        }
        if let existing = ownProfileModel(me) { return existing }
        members[me]?.handle = handle
        members[me]?.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        members[me]?.setupCheckpoint = .profileCreated
        settingsByUser[me] = settingsByUser[me] ?? .defaults
        return ownProfileModel(me)!
    }

    func updateProfile(_ update: ProfileUpdate) async throws -> OwnProfile {
        let me = try await authenticatedActor()
        if let issue = Validation.displayName(update.displayName) { throw RoamError.validation(issue.localizedDescription) }
        if let issue = Validation.handle(update.handle) { throw RoamError.validation(issue.localizedDescription) }
        if let issue = Validation.bio(update.bio) { throw RoamError.validation(issue.localizedDescription) }
        if members.values.contains(where: { $0.handle == update.handle && $0.id != me }) {
            throw RoamError.conflict("That handle is taken. Your other changes are still here.")
        }
        if let path = update.avatarPath {
            guard let asset = media.values.first(where: { $0.path == path && $0.owner == me && $0.purpose == .avatar }),
                  asset.attached || asset.createdAt.addingTimeInterval(86_400) > Date() else { throw RoamError.forbidden }
        }
        members[me]?.displayName = update.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        members[me]?.handle = update.handle
        members[me]?.bio = update.bio
        members[me]?.homeCity = update.homeCity
        if let path = update.avatarPath, let assetID = media.values.first(where: { $0.path == path && $0.owner == me })?.id { media[assetID]?.attached = true }
        members[me]?.avatarPath = update.avatarPath
        return ownProfileModel(me)!
    }

    func setSetupCheckpoint(_ checkpoint: SetupCheckpoint) async throws -> OwnProfile {
        await pause()
        let me = try requireProfile()
        if let current = members[me]?.setupCheckpoint, current < checkpoint { members[me]?.setupCheckpoint = checkpoint }
        return ownProfileModel(me)!
    }

    func markBeenIntroSeen() async throws {
        let me = try requireProfile()
        members[me]?.hasSeenBeenIntro = true
    }

    func publicProfile(userID: UUID) async throws -> PublicProfile {
        await pause()
        let me = try requireProfile()
        guard let member = members[userID], let handle = member.handle, !member.deleted, !isBlockedEitherWay(me, userID) || me == userID else {
            throw RoamError.notFound
        }
        let visited = Set(visits.values.filter { $0.owner == userID }.map(\.experience))
        let geography = visited.compactMap { experiences[$0].flatMap { places[$0.placeID]?.candidate } }
        let countryCount = Set(geography.compactMap(\.countryCode)).count
        let cityCount = Set(geography.compactMap { GeographyKey.cityKey(countryCode: $0.countryCode, region: $0.region, locality: $0.locality) }).count
        let relationship = me == userID ? Relationship.selfRelationship : Relationship(
            isSelf: false, friendState: friendState(viewer: me, member: userID),
            isMuted: mutes.contains(Pair(a: me, b: userID)), isBlocked: blocks.contains(Pair(a: me, b: userID)))
        return PublicProfile(
            member: MemberSummary(id: userID, handle: handle, displayName: member.displayName ?? handle, avatarPath: member.avatarPath),
            bio: member.bio, homeCityName: member.homeCity?.displayName, joinedAt: member.createdAt,
            followerCount: follows.keys.filter { $0.b == userID && isVisibleMember($0.a, to: me) }.count,
            followingCount: follows.keys.filter { $0.a == userID && isVisibleMember($0.b, to: me) }.count,
            rankedCount: ratings.values.filter { $0.owner == userID }.count,
            wantCount: bookmarks.keys.filter { $0.a == userID }.count,
            countryCount: countryCount, cityCount: cityCount, relationship: relationship)
    }

    func suggestedMembers(limit: Int) async throws -> [MemberRow] {
        await pause()
        let me = try requireProfile()
        // Deterministic: members with the most public ratings, excluding self, blocked and already-followed.
        let candidates = members.values.filter { $0.id != me && $0.handle != nil && !$0.deleted && !isBlockedEitherWay(me, $0.id)
            && follows[Pair(a: me, b: $0.id)] == nil }
        let ranked = candidates.sorted { lhs, rhs in
            let l = ratings.values.filter { $0.owner == lhs.id }.count
            let r = ratings.values.filter { $0.owner == rhs.id }.count
            return l != r ? l > r : (lhs.handle ?? "") < (rhs.handle ?? "")
        }
        return ranked.prefix(limit).map { member in
            MemberRow(member: memberSummary(member.id), friendState: friendState(viewer: me, member: member.id), isSelf: false)
        }
    }
}
#endif
