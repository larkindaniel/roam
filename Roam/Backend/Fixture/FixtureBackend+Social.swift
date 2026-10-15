#if ROAM_FIXTURES
import Foundation

extension FixtureBackend: SocialService {
    func setFollow(userID: UUID, following: Bool) async throws -> Bool {
        let me = try await authenticatedActor()
        guard userID != me else { throw RoamError.validation("You can't follow yourself.") }
        guard isVisibleMember(userID, to: me) else { throw RoamError.notFound }
        let key = Pair(a: me, b: userID)
        if following {
            if follows[key] == nil {
                follows[key] = Date()
                notify(recipient: userID, actor: me, type: .follow, activity: nil, comment: nil, eventKey: "follow:\(me):\(userID)", now: Date())
            }
        } else {
            follows[key] = nil
            notifications = notifications.filter { $0.value.eventKey != "follow:\(me):\(userID)" }
        }
        return follows[key] != nil
    }

    private func memberRows(_ ids: [UUID], viewer: UUID, query: String, cursor: String?) -> Page<MemberRow> {
        let needle = GeographyKey.normalize(query)
        let visible = ids.filter { isVisibleMember($0, to: viewer) || $0 == viewer }
            .map(memberSummary)
            .filter { needle.isEmpty || GeographyKey.normalize($0.handle).contains(needle) || GeographyKey.normalize($0.displayName).contains(needle) }
            .sorted { $0.handle < $1.handle }
        let after = cursor.map { c in visible.filter { $0.handle > c } } ?? visible
        let slice = Array(after.prefix(Limits.pageSize))
        let next = after.count > Limits.pageSize ? slice.last?.handle : nil
        return Page(items: slice.map { member in
            MemberRow(member: member, isFollowing: follows[Pair(a: viewer, b: member.id)] != nil,
                      followsViewer: follows[Pair(a: member.id, b: viewer)] != nil, isSelf: member.id == viewer)
        }, nextCursor: next)
    }

    func followers(of userID: UUID, query: String, cursor: String?) async throws -> Page<MemberRow> {
        let me = try await authenticatedActor()
        guard userID == me || isVisibleMember(userID, to: me) else { throw RoamError.notFound }
        return memberRows(follows.keys.filter { $0.b == userID }.map(\.a), viewer: me, query: query, cursor: cursor)
    }

    func following(of userID: UUID, query: String, cursor: String?) async throws -> Page<MemberRow> {
        let me = try await authenticatedActor()
        guard userID == me || isVisibleMember(userID, to: me) else { throw RoamError.notFound }
        return memberRows(follows.keys.filter { $0.a == userID }.map(\.b), viewer: me, query: query, cursor: cursor)
    }

    func searchMembers(query: String, cursor: String?) async throws -> Page<MemberRow> {
        let me = try await authenticatedActor()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .empty }
        return memberRows(members.keys.filter { $0 != me }, viewer: me, query: trimmed, cursor: cursor)
    }

    func setMute(userID: UUID, muted: Bool) async throws {
        let me = try await authenticatedActor()
        guard userID != me else { return }
        if muted { mutes.insert(Pair(a: me, b: userID)) } else { mutes.remove(Pair(a: me, b: userID)) }
    }

    func setBlock(userID: UUID, blocked: Bool) async throws {
        let me = try await authenticatedActor()
        guard userID != me else { return }
        if blocked {
            blocks.insert(Pair(a: me, b: userID))
            follows[Pair(a: me, b: userID)] = nil
            follows[Pair(a: userID, b: me)] = nil
        } else {
            blocks.remove(Pair(a: me, b: userID))
        }
    }

    func blockedMembers() async throws -> [MemberSummary] {
        let me = try await authenticatedActor()
        return blocks.filter { $0.a == me }.map { memberSummary($0.b) }.sorted { $0.handle < $1.handle }
    }

    func mutedMembers() async throws -> [MemberSummary] {
        let me = try await authenticatedActor()
        return mutes.filter { $0.a == me }.map { memberSummary($0.b) }.sorted { $0.handle < $1.handle }
    }

    func report(target: ReportTarget, reason: ReportReason, text: String?, operationID: UUID) async throws -> ReportReceipt {
        let me = try await authenticatedActor()
        if let text, let issue = Validation.reportText(text) { throw RoamError.validation(issue.localizedDescription) }
        if let existing = reports[operationID] { return existing.receipt }
        let receipt = ReportReceipt(id: operationID, targetKind: target.kind, reason: reason, status: "received", createdAt: Date())
        reports[operationID] = (me, receipt, target.targetID, text)
        return receipt
    }

    func myReports() async throws -> [ReportReceipt] {
        let me = try requireProfile()
        return reports.values.filter { $0.reporter == me }.map(\.receipt).sorted { $0.createdAt > $1.createdAt }
    }
}

extension FixtureBackend: FeedService {
    func feed(cursor: String?) async throws -> Page<ActivityItem> {
        let me = try await authenticatedActor()
        let followed = Set(follows.keys.filter { $0.a == me }.map(\.b))
        let rows = activities.values.filter { row in
            row.author == me || (followed.contains(row.author) && !mutes.contains(Pair(a: me, b: row.author)) && isVisibleMember(row.author, to: me))
        }
        return page(of: rows, cursor: cursor, viewer: me)
    }

    func profileActivity(userID: UUID, cursor: String?) async throws -> Page<ActivityItem> {
        let me = try await authenticatedActor()
        guard userID == me || isVisibleMember(userID, to: me) else { throw RoamError.notFound }
        return page(of: activities.values.filter { $0.author == userID }, cursor: cursor, viewer: me)
    }

    func activity(id: UUID) async throws -> ActivityItem {
        let me = try await authenticatedActor()
        guard let row = activities[id], canSeeActivity(row, viewer: me), let item = activityItem(row, viewer: me) else { throw RoamError.unavailable }
        return item
    }

    func setLike(activityID: UUID, liked: Bool) async throws -> Bool {
        let me = try await authenticatedActor()
        guard let row = activities[activityID], canSeeActivity(row, viewer: me) else { throw RoamError.unavailable }
        let key = Pair(a: me, b: activityID)
        let eventKey = "like:\(me):\(activityID)"
        if liked {
            if likes[key] == nil {
                likes[key] = Date()
                notify(recipient: row.author, actor: me, type: .like, activity: activityID, comment: nil, eventKey: eventKey, now: Date())
            }
        } else {
            likes[key] = nil
            notifications = notifications.filter { $0.value.eventKey != eventKey }
        }
        return likes[key] != nil
    }

    func comments(activityID: UUID, cursor: String?) async throws -> Page<Comment> {
        let me = try await authenticatedActor()
        guard let row = activities[activityID], canSeeActivity(row, viewer: me) else { throw RoamError.unavailable }
        let all = comments.values.filter { $0.activity == activityID && isVisibleMember($0.author, to: me) || ($0.activity == activityID && $0.author == me) }
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
        var remaining = all
        if let (date, id) = Self.parseCursor(cursor) {
            remaining = all.filter { ($0.createdAt, $0.id.uuidString) > (date, id.uuidString) }
        }
        let slice = Array(remaining.prefix(Limits.pageSize))
        let next = remaining.count > Limits.pageSize ? slice.last.map { Self.cursor(date: $0.createdAt, id: $0.id) } : nil
        return Page(items: slice.map { Comment(id: $0.id, activityID: $0.activity, author: memberSummary($0.author), body: $0.body,
                                               createdAt: $0.createdAt, isOwn: $0.author == me) }, nextCursor: next)
    }

    func postComment(activityID: UUID, body: String, operationID: UUID) async throws -> Comment {
        let me = try await authenticatedActor()
        if let issue = Validation.comment(body) { throw RoamError.validation(issue.localizedDescription) }
        guard let row = activities[activityID], canSeeActivity(row, viewer: me) else { throw RoamError.unavailable }
        if let existing = comments.values.first(where: { $0.author == me && $0.operationID == operationID }) {
            guard existing.activity == activityID, existing.body == body else {
                throw RoamError.conflict("This save was already used for a different change.")
            }
            return Comment(id: existing.id, activityID: existing.activity, author: memberSummary(me), body: existing.body, createdAt: existing.createdAt, isOwn: true)
        }
        let id = UUID()
        let now = Date()
        comments[id] = CommentRow(id: id, activity: activityID, author: me, body: body, createdAt: now, operationID: operationID)
        notify(recipient: row.author, actor: me, type: .comment, activity: activityID, comment: id, eventKey: "comment:\(id)", now: now)
        // The comment is stored but the response is lost once; the retry must not duplicate it.
        if scenario == "comment-uncertain", injectedContentFaults.insert("comment-post").inserted { throw RoamError.timeout }
        return Comment(id: id, activityID: activityID, author: memberSummary(me), body: body, createdAt: now, isOwn: true)
    }

    func deleteComment(id: UUID) async throws {
        let me = try await authenticatedActor()
        guard let comment = comments[id] else { return }
        guard comment.author == me else { throw RoamError.forbidden }
        comments[id] = nil
        notifications = notifications.filter { $0.value.comment != id }
    }

    func deleteActivity(id: UUID) async throws {
        let me = try await authenticatedActor()
        guard let row = activities[id] else { return }
        guard row.author == me else { throw RoamError.forbidden }
        deleteActivityCascade(id)
    }
}

extension FixtureBackend: NotificationService {
    private func visibleNotifications(for me: UUID) -> [NotificationRow] {
        notifications.values.filter { $0.recipient == me && isVisibleMember($0.actor, to: me) }
            .sorted { ($0.createdAt, $0.id.uuidString) > ($1.createdAt, $1.id.uuidString) }
    }

    func notifications(cursor: String?) async throws -> Page<AppNotification> {
        let me = try await authenticatedActor()
        var rows = visibleNotifications(for: me)
        if let (date, id) = Self.parseCursor(cursor) {
            rows = rows.filter { ($0.createdAt, $0.id.uuidString) < (date, id.uuidString) }
        }
        let slice = Array(rows.prefix(Limits.pageSize))
        let next = rows.count > Limits.pageSize ? slice.last.map { Self.cursor(date: $0.createdAt, id: $0.id) } : nil
        return Page(items: slice.map { row in
            let activity = row.activity.flatMap { activities[$0] }
            return AppNotification(id: row.id, type: row.type, actor: memberSummary(row.actor), activityID: row.activity,
                                   experienceName: activity.map { placeName($0.experience) },
                                   commentPreview: row.comment.flatMap { comments[$0]?.body },
                                   createdAt: row.createdAt, readAt: row.readAt,
                                   targetAvailable: row.type == .follow ? isVisibleMember(row.actor, to: me) : activity != nil)
        }, nextCursor: next)
    }

    func unreadCount() async throws -> Int {
        let me = try requireProfile()
        return visibleNotifications(for: me).filter { $0.readAt == nil }.count
    }

    func markRead(id: UUID) async throws {
        let me = try requireProfile()
        guard notifications[id]?.recipient == me else { return }
        if notifications[id]?.readAt == nil { notifications[id]?.readAt = Date() }
    }

    func markAllRead() async throws {
        let me = try await authenticatedActor()
        for (id, row) in notifications where row.recipient == me && row.readAt == nil { notifications[id]?.readAt = Date() }
    }
}

extension FixtureBackend: SettingsService {
    func settings() async throws -> UserSettings {
        await pause()
        return settingsByUser[try requireProfile()] ?? .defaults
    }

    func update(_ settings: UserSettings) async throws -> UserSettings {
        let me = try await authenticatedActor()
        if scenario == "settings-save-failure", injectedContentFaults.insert("settings").inserted { throw RoamError.timeout }
        settingsByUser[me] = settings
        return settings
    }
}

extension FixtureBackend: TravelService {
    /// Mirrors `travel_profile`: Visits only, one pin per Experience, canonical city keys, and New
    /// this year by each Experience's earliest known visit date.
    func travelProfile(userID: UUID, year: Int) async throws -> TravelProfile {
        let me = try await authenticatedActor()
        guard userID == me || isVisibleMember(userID, to: me) else { throw RoamError.notFound }
        guard (1900...2999).contains(year) else { throw RoamError.validation("Choose a calendar year.") }
        let ownerVisits = visits.values.filter { $0.owner == userID }
        let byExperience = Dictionary(grouping: ownerVisits, by: \.experience)
        var pins: [GlobePin] = []
        var categoryCounts: [ExperienceCategory?: Int] = [:]
        var cityCounts: [String: CityCount] = [:]
        var countryCounts: [String: CountryCount] = [:]
        var withoutCity = 0
        var thisYear: [GlobePin] = []
        var unknownOnly = 0
        for (experienceID, rows) in byExperience {
            guard let experience = experiences[experienceID], let place = places[experience.placeID] else { continue }
            let c = place.candidate
            let rating = ratings.values.first { $0.owner == userID && $0.experience == experienceID }
            let category = rating?.category ?? experience.category
            let cityKey = GeographyKey.cityKey(countryCode: c.countryCode, region: c.region, locality: c.locality)
            let firstKnown = rows.compactMap(\.date).min()
            let pin = GlobePin(experienceID: experienceID, name: c.name, category: category, latitude: c.latitude, longitude: c.longitude,
                               countryCode: c.countryCode, cityKey: cityKey, countryName: c.countryName,
                               cityName: cityKey == nil ? nil : c.locality, firstVisitDate: firstKnown, visitCount: rows.count)
            pins.append(pin)
            categoryCounts[category, default: 0] += 1
            if let code = c.countryCode {
                countryCounts[code, default: CountryCount(countryCode: code, name: c.countryName ?? code, count: 0)].count += 1
            }
            if let cityKey, let code = c.countryCode {
                cityCounts[cityKey, default: CityCount(cityKey: cityKey, name: c.locality ?? "", region: c.region, countryCode: code,
                                                       countryName: c.countryName, count: 0)].count += 1
            } else {
                withoutCity += 1
            }
            if let firstKnown {
                if firstKnown.year == year { thisYear.append(pin) }
            } else {
                unknownOnly += 1
            }
        }
        let newest = thisYear.sorted { ($0.firstVisitDate!, $1.name) > ($1.firstVisitDate!, $0.name) }
        return TravelProfile(
            pins: pins.sorted { ($0.name, $0.experienceID.uuidString) < ($1.name, $1.experienceID.uuidString) },
            countryCount: countryCounts.count, cityCount: cityCounts.count,
            categories: categoryCounts.map { CategoryCount(category: $0.key, count: $0.value) }.sorted { ($0.count, $1.id) > ($1.count, $0.id) },
            cities: cityCounts.values.sorted { ($0.count, $1.name, $1.cityKey) > ($1.count, $0.name, $0.cityKey) },
            countries: countryCounts.values.sorted { ($0.count, $1.name) > ($1.count, $0.name) },
            placesWithoutCity: withoutCity,
            newThisYear: NewThisYear(year: year, count: newest.count, unknownDateCount: unknownOnly, experienceIDs: newest.map(\.experienceID)))
    }
}

extension FixtureBackend: AccountService {
    /// Mirrors `request_account_deletion`: a sign-in within 10 minutes, then the account is hidden
    /// and write-disabled at once. The fixture has no deletion worker, so the status stays pending.
    func requestDeletion() async throws -> AccountDeletionStatus {
        let me = try await authenticatedActor()
        guard let signedInAt = authenticatedAt[me], Date().timeIntervalSince(signedInAt) <= 600 else {
            throw RoamError.reauthenticationRequired
        }
        if scenario == "deletion-failure", injectedContentFaults.insert("deletion").inserted { throw RoamError.timeout }
        members[me]?.deleted = true
        let status = AccountDeletionStatus(state: .pending, appleRevocation: "not_applicable", storageCleanup: "pending", updatedAt: Date())
        deletionStatus[me] = status
        return status
    }

    func deletionStatus() async throws -> AccountDeletionStatus? {
        guard let id = currentUserID else { throw RoamError.notSignedIn }
        return deletionStatus[id]
    }
}
#endif
