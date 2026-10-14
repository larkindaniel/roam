import Foundation
import Observation

enum PhotoDraftStatus: String, Codable, Hashable, Sendable {
    case preparing, uploading, ready, failed, existing
}

struct PhotoDraftAsset: Codable, Hashable, Identifiable, Sendable {
    let localID: UUID
    var id: UUID { localID }
    var status: PhotoDraftStatus
    var error: String?
    var width: Int
    var height: Int
    var staged: StagedMedia?
    var existing: MediaRef?
    var uploadAttemptID: UUID
    var needsNewAttempt = false
}

struct PhotoDraftCheckpoint {
    fileprivate let ownerID: UUID
    fileprivate let draftID: String
    fileprivate let assets: [PhotoDraftAsset]
    fileprivate let bytes: [UUID: Data]
}

private struct PhotoDraftManifest: Codable {
    var schemaVersion = 1
    let ownerID: UUID
    let draftID: String
    var updatedAt: Date
    var assets: [PhotoDraftAsset]
    var retiredStages: [StagedMedia]
}

/// Local bytes survive uncertain uploads and server staging expiry. Only acknowledged,
/// unexpired references enter a Visit payload; publication is owned by the Visit transaction.
@MainActor
@Observable
final class PhotoDraftModel {
    let ownerID: UUID
    let draftID: String
    private(set) var assets: [PhotoDraftAsset] = []
    private(set) var error: String?
    private let storage: AccountStorage
    private let media: any MediaService
    private let currentAccount: () -> UUID?
    private let now: () -> Date
    private var retiredStages: [StagedMedia] = []
    private var operations: [UUID: UUID] = [:]
    private var generation = 0
    private var disposed = false
    private var persistenceError: String?

    var isBusy: Bool { assets.contains { $0.status == .preparing || $0.status == .uploading } }
    var canCommit: Bool {
        !disposed && currentAccount() == ownerID && persistenceError == nil
            && assets.count <= Limits.photosPerVisit && assets.allSatisfy(isReady)
    }

    init(ownerID: UUID, draftID: String, existingMedia: [MediaRef] = [], storage: AccountStorage,
         media: any MediaService, currentAccount: @escaping () -> UUID?, now: @escaping () -> Date = Date.init) {
        self.ownerID = ownerID
        self.draftID = draftID
        self.storage = storage
        self.media = media
        self.currentAccount = currentAccount
        self.now = now
        storage.purgeExpiredPhotoDrafts(userID: ownerID, now: now())
        if let saved = storage.readPhotoDraft(PhotoDraftManifest.self, draftID: draftID, userID: ownerID),
           saved.schemaVersion == 1, saved.ownerID == ownerID, saved.draftID == draftID,
           now().timeIntervalSince(saved.updatedAt) <= Limits.draftLifetime,
           saved.assets.count <= Limits.photosPerVisit,
           Set(saved.assets.map(\.localID)).count == saved.assets.count {
            assets = saved.assets
            retiredStages = saved.retiredStages
            for index in assets.indices where assets[index].existing == nil {
                if assets[index].status == .preparing || assets[index].status == .uploading {
                    assets[index].status = .failed
                    assets[index].error = "This upload was interrupted. Retry checks the same upload."
                }
                if let expiry = assets[index].staged?.expiresAt, expiry <= now() {
                    assets[index].status = .failed
                    assets[index].error = RoamError.mediaExpired.roamMessage
                    assets[index].needsNewAttempt = true
                }
                if thumbnailData(assetID: assets[index].id) == nil {
                    assets[index].status = .failed
                    assets[index].error = "This photo isn't on this device. Remove it and choose it again."
                }
            }
        } else {
            storage.removePhotoDraft(draftID: draftID, userID: ownerID)
            assets = existingMedia.sorted { $0.position < $1.position }.map {
                PhotoDraftAsset(localID: $0.id, status: .existing, error: nil, width: $0.width, height: $0.height,
                                staged: nil, existing: $0, uploadAttemptID: UUID())
            }
        }
        if currentAccount() != ownerID { error = "Sign in to the account that owns this draft to continue." }
        else if assets.count > Limits.photosPerVisit { error = "A visit can have up to six photos." }
    }

    func thumbnailData(assetID: UUID) -> Data? {
        guard currentAccount() == ownerID, !disposed else { return nil }
        return storage.photoData(assetID: assetID, draftID: draftID, userID: ownerID)
    }

    func add(data: Data) async {
        guard editable(), reserveSlot() else { return }
        let id = UUID(), operation = UUID(), epoch = generation
        operations[id] = operation
        assets.append(PhotoDraftAsset(localID: id, status: .preparing, error: nil, width: 0, height: 0,
                                      staged: nil, existing: nil, uploadAttemptID: UUID()))
        guard persist() else { fail(id, message: persistenceError ?? "Your photo couldn't be kept."); return }
        do {
            let prepared = try await Task.detached(priority: .userInitiated) { try ImageProcessor.prepare(data) }.value
            guard valid(id, operation: operation, epoch: epoch), !Task.isCancelled else {
                interrupt(id, operation: operation, epoch: epoch)
                return
            }
            try storage.writePhoto(prepared.data, assetID: id, draftID: draftID, userID: ownerID)
            update(id) { $0.width = prepared.width; $0.height = prepared.height }
            await upload(id, operation: operation, epoch: epoch, prepared: prepared)
        } catch {
            guard valid(id, operation: operation, epoch: epoch) else { return }
            fail(id, message: error.roamMessage)
        }
    }

    /// Picker failures remain chosen failed assets until explicitly removed.
    func addFailure(message: String) {
        guard editable(), reserveSlot() else { return }
        assets.append(PhotoDraftAsset(localID: UUID(), status: .failed, error: message, width: 0, height: 0,
                                      staged: nil, existing: nil, uploadAttemptID: UUID()))
        _ = persist()
    }

    func retry(assetID: UUID) async {
        guard editable(), let index = assets.firstIndex(where: { $0.id == assetID }), assets[index].existing == nil else { return }
        guard assets[index].status != .uploading, assets[index].status != .preparing else { return }
        if assets[index].status == .ready, isReady(assets[index]) { return }
        if let expiry = assets[index].staged?.expiresAt, expiry <= now() { assets[index].needsNewAttempt = true }
        if assets[index].needsNewAttempt {
            if let staged = assets[index].staged { retiredStages.append(staged) }
            assets[index].uploadAttemptID = UUID()
            assets[index].staged = nil
            assets[index].needsNewAttempt = false
        }
        let operation = UUID(), epoch = generation
        operations[assetID] = operation
        do {
            guard let bytes = thumbnailData(assetID: assetID) else { throw ImageProcessor.Failure.unreadable }
            let prepared = try ImageProcessor.preparedJPEG(bytes)
            await upload(assetID, operation: operation, epoch: epoch, prepared: prepared)
        } catch { fail(assetID, message: error.roamMessage) }
    }

    private func upload(_ id: UUID, operation: UUID, epoch: Int, prepared: ImageProcessor.Processed) async {
        guard valid(id, operation: operation, epoch: epoch), let asset = assets.first(where: { $0.id == id }) else { return }
        update(id) { $0.status = .uploading; $0.error = nil; $0.width = prepared.width; $0.height = prepared.height }
        guard persist() else { fail(id, message: persistenceError ?? "Your photo couldn't be kept."); return }
        do {
            var staged = try await media.stage(jpegData: prepared.data, width: prepared.width, height: prepared.height,
                                               purpose: .visit, uploadAttemptID: asset.uploadAttemptID)
            guard valid(id, operation: operation, epoch: epoch) else {
                // A removed/canceled photo never rejoins the draft. Foreign accounts cannot clean it.
                if currentAccount() == ownerID { try? await media.discardStaged(mediaID: staged.id) }
                return
            }
            if staged.expiresAt == nil { staged.expiresAt = now().addingTimeInterval(24 * 60 * 60) }
            update(id) {
                $0.staged = staged
                $0.status = .ready
                $0.error = nil
            }
            operations[id] = nil
            error = nil
            _ = persist()
        } catch {
            guard valid(id, operation: operation, epoch: epoch) else { return }
            if error as? RoamError == .mediaExpired { update(id) { $0.needsNewAttempt = true } }
            fail(id, message: error.roamMessage)
        }
    }

    func remove(assetID: UUID) async {
        guard editable(), let asset = assets.first(where: { $0.id == assetID }) else { return }
        operations[assetID] = nil
        assets.removeAll { $0.id == assetID }
        if let staged = asset.staged { retiredStages.append(staged) }
        storage.removePhoto(assetID: assetID, draftID: draftID, userID: ownerID)
        error = nil
        _ = persist()
        // Staged removal is deferred until discard/expiry so editor Cancel can restore it.
        // Existing attached assets are changed only by the acknowledged Visit mutation.
    }

    func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        guard editable(), destination >= 0, destination <= assets.count, offsets.allSatisfy({ assets.indices.contains($0) }) else { return }
        let moving = offsets.map { assets[$0] }
        let remaining = assets.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        let insertion = destination - offsets.filter { $0 < destination }.count
        assets = Array(remaining[..<insertion]) + moving + Array(remaining[insertion...])
        _ = persist()
    }

    func attachmentIDs() throws -> [UUID] {
        guard editable(), persistenceError == nil else { throw RoamError.validation(error ?? "Your draft couldn't be kept.") }
        for index in assets.indices where assets[index].status == .ready && !isReady(assets[index]) {
            assets[index].status = .failed
            assets[index].error = RoamError.mediaExpired.roamMessage
            assets[index].needsNewAttempt = true
        }
        guard assets.count <= Limits.photosPerVisit, assets.allSatisfy(isReady) else {
            error = "Finish uploading each photo, or remove failed photos before saving."
            _ = persist()
            throw RoamError.validation(error!)
        }
        return assets.compactMap { $0.existing?.id ?? $0.staged?.id }
    }

    /// The server definitively rejected staged media as expired. Keep the local bytes and require a
    /// fresh upload attempt for every staged photo; already-saved photos are unaffected.
    func expireStagedUploads() {
        guard editable() else { return }
        for index in assets.indices where assets[index].existing == nil && assets[index].staged != nil {
            assets[index].status = .failed
            assets[index].error = RoamError.mediaExpired.roamMessage
            assets[index].needsNewAttempt = true
        }
        error = RoamError.mediaExpired.roamMessage
        _ = persist()
    }

    func checkpoint() -> PhotoDraftCheckpoint {
        let bytes = Dictionary(uniqueKeysWithValues: assets.compactMap { asset in
            thumbnailData(assetID: asset.id).map { (asset.id, $0) }
        })
        return PhotoDraftCheckpoint(ownerID: ownerID, draftID: draftID, assets: assets, bytes: bytes)
    }

    func restore(_ checkpoint: PhotoDraftCheckpoint) async {
        guard editable(), checkpoint.ownerID == ownerID, checkpoint.draftID == draftID else { return }
        generation += 1
        operations.removeAll()
        let old = assets
        for asset in old where !checkpoint.assets.contains(where: { $0.id == asset.id }) {
            if let staged = asset.staged { retiredStages.append(staged) }
            storage.removePhoto(assetID: asset.id, draftID: draftID, userID: ownerID)
        }
        assets = checkpoint.assets
        for index in assets.indices {
            if let bytes = checkpoint.bytes[assets[index].id] {
                do { try storage.writePhoto(bytes, assetID: assets[index].id, draftID: draftID, userID: ownerID) }
                catch { assets[index].status = .failed; assets[index].error = error.roamMessage }
            }
            if assets[index].status == .preparing || assets[index].status == .uploading {
                assets[index].status = .failed
                assets[index].needsNewAttempt = true
                assets[index].error = "This upload was canceled. Retry to upload the kept photo."
            }
        }
        let activeStages = Set(assets.compactMap { $0.staged?.id })
        retiredStages.removeAll { activeStages.contains($0.id) }
        error = nil
        _ = persist()
    }

    func discard() async {
        guard currentAccount() == ownerID, !disposed else { return }
        generation += 1
        disposed = true
        operations.removeAll()
        let staged = assets.compactMap(\.staged) + retiredStages
        assets = []
        retiredStages = []
        storage.removePhotoDraft(draftID: draftID, userID: ownerID)
        var removed = Set<UUID>()
        for asset in staged where removed.insert(asset.id).inserted {
            guard currentAccount() == ownerID else { return }
            try? await media.discardStaged(mediaID: asset.id)
        }
    }

    /// The Visit transaction already owns attachment/deletion; this performs local cleanup only.
    func committed() {
        guard currentAccount() == ownerID, !disposed else { return }
        generation += 1
        disposed = true
        operations.removeAll()
        storage.removePhotoDraft(draftID: draftID, userID: ownerID)
    }

    private func isReady(_ asset: PhotoDraftAsset) -> Bool {
        if asset.status == .existing { return asset.existing != nil }
        guard asset.status == .ready, let staged = asset.staged,
              staged.expiresAt.map({ $0 > now() }) ?? true else { return false }
        return storage.photoData(assetID: asset.id, draftID: draftID, userID: ownerID) != nil
    }

    private func editable() -> Bool {
        guard !disposed, currentAccount() == ownerID else {
            error = "Sign in to the account that owns this draft to continue."
            return false
        }
        return true
    }

    private func reserveSlot() -> Bool {
        guard assets.count < Limits.photosPerVisit else { error = "A visit can have up to six photos."; return false }
        return true
    }

    private func valid(_ id: UUID, operation: UUID, epoch: Int) -> Bool {
        !disposed && currentAccount() == ownerID && generation == epoch && operations[id] == operation && assets.contains { $0.id == id }
    }

    private func update(_ id: UUID, _ change: (inout PhotoDraftAsset) -> Void) {
        guard let index = assets.firstIndex(where: { $0.id == id }) else { return }
        change(&assets[index])
    }

    private func interrupt(_ id: UUID, operation: UUID, epoch: Int) {
        guard valid(id, operation: operation, epoch: epoch) else { return }
        fail(id, message: "Preparing this photo was interrupted. Remove it and choose it again.")
    }

    /// A per-photo failure is shown on that photo; `error` is kept for draft-wide problems.
    private func fail(_ id: UUID, message: String) {
        operations[id] = nil
        update(id) { $0.status = .failed; $0.error = message }
        _ = persist()
    }

    @discardableResult private func persist() -> Bool {
        guard !disposed, currentAccount() == ownerID else { return false }
        do {
            try storage.writePhotoDraft(PhotoDraftManifest(ownerID: ownerID, draftID: draftID, updatedAt: now(), assets: assets,
                                                           retiredStages: retiredStages), draftID: draftID, userID: ownerID)
            persistenceError = nil
            return true
        } catch {
            persistenceError = "Your photos couldn't be kept on this device. Free some storage and retry before saving."
            self.error = persistenceError
            return false
        }
    }
}
