import Foundation
import Observation

struct GalleryPhoto: Identifiable, Hashable {
    let media: MediaRef
    let visitID: UUID
    let ownerID: UUID
    let authorName: String
    let date: VisitDate
    let isOwn: Bool
    var id: UUID { media.id }
}

private struct GalleryRemovalDraft: Codable {
    let ownerID: UUID
    let experienceID: UUID
    let photoID: UUID
    let updatedAt: Date
    let payload: VisitEditPayload
}

@MainActor
@Observable
final class VisitGalleryModel {
    let experienceID: UUID
    let visitID: UUID?
    let ownerID: UUID
    private(set) var photos: [GalleryPhoto] = []
    private(set) var isLoading = false
    private(set) var loadingMore = false
    private(set) var isRemoving = false
    private(set) var error: String?
    private(set) var pageError: String?
    private(set) var nextCursor: String?
    private(set) var pendingRemoval: VisitEditPayload?
    private(set) var removedPhotoID: UUID?
    private(set) var authError: RoamError?
    private var pendingPhotoID: UUID?
    private var generation = 0
    private let memories: any MemoryService
    private let storage: AccountStorage
    private let currentAccount: () -> UUID?
    private let now: () -> Date
    var draftID: String { "gallery-remove-\(experienceID.uuidString.lowercased())" }

    init(experienceID: UUID, visitID: UUID? = nil, ownerID: UUID, memories: any MemoryService,
         storage: AccountStorage, currentAccount: @escaping () -> UUID?, now: @escaping () -> Date = Date.init) {
        self.experienceID = experienceID; self.visitID = visitID; self.ownerID = ownerID
        self.memories = memories; self.storage = storage; self.currentAccount = currentAccount; self.now = now
        let name = "gallery-remove-\(experienceID.uuidString.lowercased())"
        if let draft = storage.read(GalleryRemovalDraft.self, name: name, userID: ownerID),
           draft.ownerID == ownerID, draft.experienceID == experienceID, now().timeIntervalSince(draft.updatedAt) <= 30 * 86_400 {
            pendingRemoval = draft.payload; pendingPhotoID = draft.photoID
            error = "Photo removal wasn't confirmed. Retry checks the original change."
        }
    }

    func load() async {
        guard currentAccount() == ownerID else { clear(); return }
        generation += 1
        let token = generation
        isLoading = true
        defer { if token == generation { isLoading = false } }
        do {
            let loaded: [GalleryPhoto]
            var cursor: String?
            if let visitID {
                let visit = try await memories.visit(visitID: visitID)
                guard visit.experienceID == experienceID else { throw RoamError.notFound }
                loaded = visit.media.sorted { $0.position < $1.position }.map {
                    GalleryPhoto(media: $0, visitID: visit.id, ownerID: visit.ownerID,
                                 authorName: visit.ownerID == ownerID ? "Your visit" : "Traveller's visit",
                                 date: visit.visitDate, isOwn: visit.ownerID == ownerID)
                }
            } else {
                let page = try await memories.publicMemories(experienceID: experienceID, cursor: nil)
                loaded = page.items.flatMap(photos(for:))
                cursor = page.nextCursor
            }
            guard token == generation, currentAccount() == ownerID, !Task.isCancelled else { return }
            photos = unique(loaded)
            nextCursor = cursor
            pageError = nil
            if pendingRemoval == nil { error = nil }
        } catch {
            guard token == generation, currentAccount() == ownerID else { return }
            record(error)
            if MemoryMutationRules.definitelyRejected(error as? RoamError ?? .server("")) ||
                (error as? RoamError) == .sessionExpired || (error as? RoamError) == .notSignedIn {
                photos = []; nextCursor = nil
            }
        }
    }

    func loadMore() async {
        guard !loadingMore, !isLoading, let cursor = nextCursor, visitID == nil, currentAccount() == ownerID else { return }
        let token = generation
        loadingMore = true
        defer { if token == generation { loadingMore = false } }
        do {
            let page = try await memories.publicMemories(experienceID: experienceID, cursor: cursor)
            guard token == generation, nextCursor == cursor, currentAccount() == ownerID, !Task.isCancelled else { return }
            photos = unique(photos + page.items.flatMap(photos(for:)))
            nextCursor = page.nextCursor; pageError = nil
        } catch {
            guard token == generation, currentAccount() == ownerID else { return }
            pageError = error.roamMessage
            if let error = error as? RoamError, error == .forbidden || error == .notFound || error == .sessionExpired || error == .notSignedIn {
                photos = []; nextCursor = nil; record(error)
            }
        }
    }

    func remove(_ photo: GalleryPhoto) async {
        guard !isRemoving, pendingRemoval == nil, photo.isOwn, photo.ownerID == ownerID, currentAccount() == ownerID else { return }
        isRemoving = true
        do {
            let visit = try await memories.visit(visitID: photo.visitID)
            guard currentAccount() == ownerID, visit.ownerID == ownerID, visit.experienceID == experienceID else { throw RoamError.forbidden }
            pendingRemoval = VisitEditPayload(operationID: UUID(), visitID: visit.id, note: visit.publicNote, date: visit.visitDate,
                                              mediaIDs: visit.media.sorted { $0.position < $1.position }.filter { $0.id != photo.id }.map(\.id))
            pendingPhotoID = photo.id
            isRemoving = false
            await retryRemoval()
        } catch {
            isRemoving = false
            if currentAccount() == ownerID { record(error) }
        }
    }

    func retryRemoval() async {
        guard !isRemoving, let pending = pendingRemoval, let photoID = pendingPhotoID, currentAccount() == ownerID else { return }
        do {
            let draft = GalleryRemovalDraft(ownerID: ownerID, experienceID: experienceID, photoID: photoID, updatedAt: now(), payload: pending)
            try storage.write(draft, name: draftID, userID: ownerID)
        } catch { self.error = "The pending photo removal couldn't be kept on this device. Free some storage and retry."; return }
        isRemoving = true; error = nil
        defer { isRemoving = false }
        do {
            _ = try await memories.updateVisit(visitID: pending.visitID, note: pending.note, date: pending.date,
                                               mediaIDs: pending.mediaIDs, operationID: pending.operationID)
            guard currentAccount() == ownerID else { return }
            removedPhotoID = photoID
            pendingRemoval = nil; pendingPhotoID = nil
            storage.remove(name: draftID, userID: ownerID)
            await load()
        } catch {
            guard currentAccount() == ownerID else { return }
            record(error)
            if let error = error as? RoamError, MemoryMutationRules.definitelyRejected(error) {
                pendingRemoval = nil; pendingPhotoID = nil
                storage.remove(name: draftID, userID: ownerID)
            }
        }
    }

    func clear() {
        generation += 1; photos = []; nextCursor = nil; isLoading = false; loadingMore = false
    }

    private func photos(for memory: PublicMemory) -> [GalleryPhoto] {
        memory.media.sorted { $0.position < $1.position }.map {
            GalleryPhoto(media: $0, visitID: memory.id, ownerID: memory.author.id, authorName: memory.author.displayName,
                         date: memory.visitDate, isOwn: memory.isOwn && memory.author.id == ownerID)
        }
    }
    private func unique(_ items: [GalleryPhoto]) -> [GalleryPhoto] {
        var ids = Set<UUID>()
        return items.filter { ids.insert($0.id).inserted }
    }
    private func record(_ error: Error) {
        self.error = error.roamMessage
        if let error = error as? RoamError, error == .sessionExpired || error == .notSignedIn { authError = error }
    }
}
