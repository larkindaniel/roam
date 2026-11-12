#if ROAM_FIXTURES
import CryptoKit
import Foundation
import ImageIO

extension FixtureBackend: MemoryService {
    func visit(visitID: UUID) async throws -> Visit {
        let me = try await authenticatedActor()
        if scenario == "gallery-read-failure", injectedContentFaults.insert("visit-read").inserted { throw RoamError.timeout }
        guard let row = visits[visitID], audienceAllows(owner: row.owner, audience: row.audience, viewer: me) else { throw RoamError.notFound }
        return visitModel(row, viewer: me)
    }

    func publicMemories(experienceID: UUID, cursor: String?) async throws -> Page<PublicMemory> {
        try await memoryPage(experienceID: experienceID, friendID: nil, cursor: cursor)
    }

    func friendPlaceMemories(experienceID: UUID, friendID: UUID, cursor: String?) async throws -> Page<PublicMemory> {
        try await memoryPage(experienceID: experienceID, friendID: friendID, cursor: cursor)
    }

    private func memoryPage(experienceID: UUID, friendID: UUID?, cursor: String?) async throws -> Page<PublicMemory> {
        let me = try await authenticatedActor()
        guard experiences[experienceID] != nil else { throw RoamError.notFound }
        if let friendID, !areFriends(me, friendID) { throw RoamError.notFound }
        var rows = visits.values.filter {
            $0.experience == experienceID && (friendID == nil || $0.owner == friendID)
                && audienceAllows(owner: $0.owner, audience: $0.audience, viewer: me)
        }
            .sorted { ($0.createdAt, $0.id.uuidString) > ($1.createdAt, $1.id.uuidString) }
        if let cursor {
            guard let (date, id) = Self.parseCursor(cursor) else { throw RoamError.validation("Refresh these memories and try again.") }
            rows = rows.filter { ($0.createdAt, $0.id.uuidString) < (date, id.uuidString) }
        }
        let page = Array(rows.prefix(Limits.pageSize))
        return Page(items: page.map {
            let visit = visitModel($0, viewer: me)
            let latestPost = activities.values.filter { $0.visit == visit.id }
                .max { ($0.publishedAt, $0.id.uuidString) < ($1.publishedAt, $1.id.uuidString) }
            return PublicMemory(id: visit.id, author: memberSummary($0.owner), experienceID: visit.experienceID,
                                visitDate: visit.visitDate, publicNote: visit.publicNote, media: visit.media,
                                createdAt: visit.createdAt, updatedAt: visit.updatedAt, isOwn: $0.owner == me,
                                activityID: latestPost?.id, companions: visit.companions)
        }, nextCursor: rows.count > Limits.pageSize ? page.last.map { Self.cursor(date: $0.createdAt, id: $0.id) } : nil)
    }

    func updateVisit(visitID: UUID, note: String, date: VisitDate, mediaIDs: [UUID], operationID: UUID) async throws -> Visit {
        let payload = VisitPayload(date: date.date, timeZoneIdentifier: date.timeZoneIdentifier, publicNote: note, mediaIDs: mediaIDs)
        return try await updateVisit(visitID: visitID, payload: payload, operationID: operationID)
    }

    func updateVisit(visitID: UUID, payload: VisitPayload, operationID: UUID) async throws -> Visit {
        let me = try await authenticatedActor()
        let key = "\(me)|\(operationID)"
        let date = VisitDate(date: payload.date, timeZoneIdentifier: payload.timeZoneIdentifier)
        let note = payload.publicNote
        let mediaIDs = payload.mediaIDs
        let intent = FixtureVisitEdit(visitID: visitID, payload: payload)
        let digest = try MutationFingerprint.digest(intent)
        if let receipt = receipts[key] {
            guard receipt.hash == digest, let result = receipt.result as? Visit else { throw RoamError.conflict("This save was already used for a different change.") }
            return result
        }
        guard var row = visits[visitID] else { throw RoamError.notFound }
        guard row.owner == me else { throw RoamError.forbidden }
        try validateVisitSocial(payload, owner: me)
        if let issue = Validation.publicNote(note) { throw RoamError.validation(issue.localizedDescription) }
        let zone: TimeZone
        if let identifier = date.timeZoneIdentifier, !identifier.isEmpty {
            guard let known = TimeZone(identifier: identifier) else { throw RoamError.validation("Choose a valid visit time zone.") }
            zone = known
        } else { zone = TimeZone(secondsFromGMT: 0)! }
        if let issue = Validation.visitDate(date.date, today: .today(in: zone)) { throw RoamError.validation(issue.localizedDescription) }
        guard mediaIDs.count <= Limits.photosPerVisit, Set(mediaIDs).count == mediaIDs.count,
              mediaIDs.allSatisfy({ id in
                  guard let asset = media[id], asset.owner == me, asset.purpose == .visit else { return false }
                  return asset.attached ? asset.visit == visitID : asset.createdAt.addingTimeInterval(86_400) > Date()
              }) else { throw RoamError.validation("A photo isn't finished uploading. Remove it or try again.") }
        for removed in row.mediaIDs where !mediaIDs.contains(removed) { media[removed] = nil }
        for (position, id) in mediaIDs.enumerated() {
            media[id]?.attached = true; media[id]?.visit = visitID; media[id]?.position = position
        }
        row.note = note; row.date = date.date; row.timeZone = date.timeZoneIdentifier; row.mediaIDs = mediaIDs; row.updatedAt = Date()
        if let audience = payload.audience { row.audience = audience }
        if let tripID = payload.tripID { row.tripID = tripID }
        else if payload.replaceTrip == true { row.tripID = nil }
        if let companions = payload.companionIDs { row.companionIDs = companions }
        visits[visitID] = row
        let result = visitModel(row)
        receipts[key] = (digest, result)
        if scenario == "memory-write-uncertain", injectedContentFaults.insert("visit-edit").inserted { throw RoamError.timeout }
        return result
    }

    func privateNote(experienceID: UUID) async throws -> PrivateNote? {
        let me = try await authenticatedActor()
        guard experiences[experienceID] != nil else { throw RoamError.notFound }
        return privateNotes[Pair(a: me, b: experienceID)]
    }

    func savePrivateNote(experienceID: UUID, text: String, operationID: UUID) async throws -> PrivateNote {
        let me = try await authenticatedActor()
        let key = "\(me)|\(operationID)"
        let digest = try MutationFingerprint.digest(FixturePrivateEdit(kind: "save_private_note", experienceID: experienceID, text: text))
        if let receipt = receipts[key] {
            guard receipt.hash == digest, let result = receipt.result as? PrivateNote else { throw RoamError.conflict("This save was already used for a different change.") }
            return result
        }
        guard experiences[experienceID] != nil else { throw RoamError.notFound }
        if let issue = Validation.privateNote(text) { throw RoamError.validation(issue.localizedDescription) }
        let result = PrivateNote(experienceID: experienceID, text: text, updatedAt: Date())
        privateNotes[Pair(a: me, b: experienceID)] = result
        receipts[key] = (digest, result)
        if scenario == "private-note-uncertain", injectedContentFaults.insert("private-edit").inserted { throw RoamError.timeout }
        return result
    }

    func deletePrivateNote(experienceID: UUID, operationID: UUID) async throws {
        let me = try await authenticatedActor()
        let key = "\(me)|\(operationID)"
        let digest = try MutationFingerprint.digest(FixturePrivateEdit(kind: "delete_private_note", experienceID: experienceID, text: nil))
        if let receipt = receipts[key] {
            guard receipt.hash == digest, receipt.result is FixturePrivateDelete else { throw RoamError.conflict("This save was already used for a different change.") }
            return
        }
        guard experiences[experienceID] != nil else { throw RoamError.notFound }
        privateNotes[Pair(a: me, b: experienceID)] = nil
        receipts[key] = (digest, FixturePrivateDelete())
    }
}

private struct FixtureVisitEdit: Encodable {
    let kind = "update_visit"
    let visitID: UUID
    let payload: VisitPayload
}
private struct FixturePrivateEdit: Encodable { let kind: String; let experienceID: UUID; let text: String? }
private struct FixturePrivateDelete {}
private struct FixtureUploadIntent: Encodable { let width: Int; let height: Int; let purpose: MediaPurpose; let digest: String }

extension FixtureBackend: MediaService {
    func stage(jpegData: Data, width: Int, height: Int, purpose: MediaPurpose, uploadAttemptID: UUID) async throws -> StagedMedia {
        let me = try await authenticatedActor()
        let key = "\(me)|\(uploadAttemptID)"
        let digest = try MutationFingerprint.digest(FixtureUploadIntent(width: width, height: height, purpose: purpose,
                                                  digest: SHA256.hash(data: jpegData).map { String(format: "%02x", $0) }.joined()))
        if let previous = uploadAttempts[key] {
            guard previous.hash == digest else { throw RoamError.conflict("This photo upload was already used for different content.") }
            guard let row = media[previous.mediaID], row.attached || row.createdAt.addingTimeInterval(86_400) > Date() else { throw RoamError.mediaExpired }
            return StagedMedia(id: row.id, path: row.path, width: row.width, height: row.height,
                               expiresAt: row.attached ? nil : row.createdAt.addingTimeInterval(86_400))
        }
        guard !jpegData.isEmpty, jpegData.count <= Limits.photoMaxBytes, width > 0, height > 0,
              max(width, height) <= Limits.photoLongestSide,
              let source = CGImageSourceCreateWithData(jpegData as CFData, nil), CGImageSourceGetStatus(source).rawValue == 0,
              CGImageSourceGetType(source) as String? == "public.jpeg",
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              properties[kCGImagePropertyPixelWidth as String] as? Int == width,
              properties[kCGImagePropertyPixelHeight as String] as? Int == height,
              properties[kCGImagePropertyGPSDictionary as String] == nil,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { throw RoamError.validation("Choose a finished JPEG within the photo limits.") }
        mediaUploadCallCount += 1
        if scenario == "media-partial-failure", mediaUploadCallCount == 2 { throw RoamError.timeout }
        let id = UUID(), now = Date()
        let path = "fixture/\(me.uuidString.lowercased())/\(uploadAttemptID.uuidString.lowercased()).jpg"
        media[id] = MediaRow(id: id, owner: me, visit: nil, purpose: purpose, path: path, width: width, height: height, position: 0,
                             attached: false, createdAt: now, data: jpegData, seedHue: 0.5)
        uploadAttempts[key] = (digest, id)
        return StagedMedia(id: id, path: path, width: width, height: height, expiresAt: now.addingTimeInterval(86_400))
    }

    func discardStaged(mediaID: UUID) async throws {
        let me = try await authenticatedActor()
        guard let row = media[mediaID] else { return }
        guard row.owner == me else { throw RoamError.forbidden }
        if !row.attached { media[mediaID] = nil }
    }

    func imageData(path: String) async throws -> Data {
        let me = try await authenticatedActor()
        guard let row = media.values.first(where: { $0.path == path }) else { throw RoamError.notFound }
        guard row.owner == me || (row.attached && isVisibleMember(row.owner, to: me)) else { throw RoamError.forbidden }
        if scenario == "media-read-failure", injectedContentFaults.insert("image-read").inserted { throw RoamError.timeout }
        if let data = row.data { return data }
        let data = FixtureArtwork.photo(hue: row.seedHue, seed: row.id.hashValue)
        media[row.id]?.data = data
        return data
    }
}
#endif
