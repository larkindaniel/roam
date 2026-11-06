import Foundation
import Observation

struct VisitEditPayload: Codable, Hashable {
    let operationID: UUID
    let visitID: UUID
    let note: String
    let date: VisitDate
    let mediaIDs: [UUID]
}

private struct VisitEditDraft: Codable {
    let ownerID: UUID
    let visitID: UUID
    var updatedAt: Date
    var note: String
    var date: VisitDate
    var mediaIDs: [UUID]
    var pending: VisitEditPayload?
}

/// An editor owns local changes; only an acknowledged receipt changes its caller's Visit.
@MainActor
@Observable
final class VisitMemoryEditorModel {
    let original: Visit
    let ownerID: UUID
    var note: String { didSet { if canEdit { persist() } } }
    var date: VisitDate { didSet { if canEdit { persist() } } }
    private(set) var mediaIDs: [UUID]
    private(set) var pending: VisitEditPayload?
    private(set) var saved: Visit?
    private(set) var isSaving = false
    private(set) var error: String?
    private(set) var persistenceError: String?
    private(set) var authError: RoamError?
    /// Set when the server definitively rejected staged photos as expired; the caller re-stages them.
    private(set) var rejectedExpiredMedia = false
    private let memories: any MemoryService
    private let storage: AccountStorage
    private let currentAccount: () -> UUID?
    private let now: () -> Date
    private let destinationTimeZone: String?

    var draftID: String { "visit-edit-\(original.id.uuidString.lowercased())" }
    var canEdit: Bool { !isSaving && pending == nil && saved == nil && currentAccount() == ownerID && original.ownerID == ownerID }
    var isDirty: Bool { note != original.publicNote || date != original.visitDate || mediaIDs != original.media.map(\.id) || pending != nil }
    var zone: TimeZone { (date.timeZoneIdentifier ?? destinationTimeZone).flatMap(TimeZone.init(identifier:)) ?? .current }
    var today: LocalDate { .today(in: zone, now: now()) }

    init(visit: Visit, ownerID: UUID, memories: any MemoryService, storage: AccountStorage,
         currentAccount: @escaping () -> UUID?, now: @escaping () -> Date = Date.init, destinationTimeZone: String? = nil) {
        original = visit; self.ownerID = ownerID; self.memories = memories; self.storage = storage
        self.currentAccount = currentAccount; self.now = now
        self.destinationTimeZone = destinationTimeZone
        let name = "visit-edit-\(visit.id.uuidString.lowercased())"
        storage.purgeExpired(userID: ownerID, prefix: "visit-edit-", lifetime: 30 * 86_400, now: now())
        if let draft = storage.read(VisitEditDraft.self, name: name, userID: ownerID),
           draft.ownerID == ownerID, draft.visitID == visit.id, now().timeIntervalSince(draft.updatedAt) <= 30 * 86_400 {
            note = draft.note; date = draft.date; mediaIDs = draft.mediaIDs; pending = draft.pending
            if pending != nil { error = "Saving wasn't confirmed. Retry checks the same changes." }
        } else {
            note = visit.publicNote; date = visit.visitDate; mediaIDs = visit.media.map(\.id)
            storage.remove(name: name, userID: ownerID)
        }
    }

    func setMediaIDs(_ ids: [UUID]) {
        guard canEdit else { return }
        mediaIDs = ids
        persist()
    }

    func save() async {
        guard !isSaving, saved == nil, currentAccount() == ownerID, original.ownerID == ownerID else {
            error = "Sign in to the account that owns this visit to edit it."; return
        }
        if pending == nil {
            guard Validation.characterCount(note) <= 5_000 else { error = "Public notes can have up to 5,000 characters."; return }
            guard date.date.map({ $0 <= today }) ?? true else { error = "Choose today or an earlier visit date."; return }
            pending = VisitEditPayload(operationID: UUID(), visitID: original.id, note: note, date: date, mediaIDs: mediaIDs)
        }
        persist()
        guard persistenceError == nil, let submitted = pending else { return }
        isSaving = true; error = nil; rejectedExpiredMedia = false
        defer { isSaving = false }
        do {
            let acknowledged = try await memories.updateVisit(visitID: submitted.visitID, note: submitted.note,
                                                               date: submitted.date, mediaIDs: submitted.mediaIDs,
                                                               operationID: submitted.operationID)
            guard currentAccount() == ownerID else { return }
            saved = acknowledged
            pending = nil
            storage.remove(name: draftID, userID: ownerID)
        } catch {
            guard currentAccount() == ownerID else { return }
            self.error = error.roamMessage
            if let error = error as? RoamError {
                if error == .notSignedIn || error == .sessionExpired { authError = error }
                if MemoryMutationRules.definitelyRejected(error) { pending = nil }
                if error == .mediaExpired { rejectedExpiredMedia = true }
            }
            persist()
        }
    }

    func discard() {
        guard !isSaving, pending == nil else { return }
        storage.remove(name: draftID, userID: ownerID)
    }

    private func persist() {
        guard currentAccount() == ownerID, original.ownerID == ownerID, saved == nil else { return }
        let draft = VisitEditDraft(ownerID: ownerID, visitID: original.id, updatedAt: now(), note: note, date: date,
                                   mediaIDs: mediaIDs, pending: pending)
        do { try storage.write(draft, name: draftID, userID: ownerID); persistenceError = nil }
        catch { persistenceError = "Your changes couldn't be kept on this device. Free some storage and retry." }
    }
}

private struct PrivateNoteDraft: Codable {
    let ownerID: UUID
    let experienceID: UUID
    var updatedAt: Date
    var text: String
    var pendingID: UUID?
    var pendingText: String?
    var deleting: Bool
}

@MainActor
@Observable
final class PrivateNoteEditorModel {
    let experienceID: UUID
    let ownerID: UUID
    var text = "" { didSet { if loaded && canEdit { persist() } } }
    private(set) var loaded = false
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var didSave = false
    private(set) var error: String?
    private(set) var persistenceError: String?
    private(set) var authError: RoamError?
    private(set) var pendingID: UUID?
    private(set) var deleting = false
    /// Whether the server holds a note, so Delete is offered only for something that exists.
    private(set) var hasSavedNote = false
    private var pendingText: String?
    private var hasRestoredDraft = false
    private var generation = 0
    private let memories: any MemoryService
    private let storage: AccountStorage
    private let currentAccount: () -> UUID?
    private let now: () -> Date
    var draftID: String { "private-note-draft-\(experienceID.uuidString.lowercased())" }
    var canEdit: Bool { !isSaving && pendingID == nil && !didSave && currentAccount() == ownerID }

    init(experienceID: UUID, ownerID: UUID, memories: any MemoryService, storage: AccountStorage,
         currentAccount: @escaping () -> UUID?, now: @escaping () -> Date = Date.init) {
        self.experienceID = experienceID; self.ownerID = ownerID; self.memories = memories
        self.storage = storage; self.currentAccount = currentAccount; self.now = now
        storage.purgeExpired(userID: ownerID, prefix: "private-note-draft-", lifetime: 30 * 86_400, now: now())
        let name = "private-note-draft-\(experienceID.uuidString.lowercased())"
        if let draft = storage.read(PrivateNoteDraft.self, name: name, userID: ownerID),
           draft.ownerID == ownerID, draft.experienceID == experienceID, now().timeIntervalSince(draft.updatedAt) <= 30 * 86_400 {
            text = draft.text; pendingID = draft.pendingID; pendingText = draft.pendingText; deleting = draft.deleting
            hasRestoredDraft = true
            if pendingID != nil { error = "Saving wasn't confirmed. Retry checks the same private-note change." }
        }
    }

    func load() async {
        guard !isLoading, !isSaving, currentAccount() == ownerID else { return }
        generation += 1
        let token = generation
        isLoading = true
        defer { if token == generation { isLoading = false } }
        do {
            let note = try await memories.privateNote(experienceID: experienceID)
            guard token == generation, currentAccount() == ownerID, !Task.isCancelled else { return }
            if !hasRestoredDraft && !loaded { text = note?.text ?? "" }
            hasSavedNote = note != nil
            loaded = true
            if pendingID == nil { error = nil }
        } catch {
            guard token == generation, currentAccount() == ownerID else { return }
            self.error = error.roamMessage
            if let error = error as? RoamError, error == .sessionExpired || error == .notSignedIn { authError = error }
            if hasRestoredDraft { loaded = true }
        }
    }

    func save(delete: Bool = false) async {
        guard !isSaving, loaded, !didSave, currentAccount() == ownerID else { return }
        if pendingID == nil {
            guard delete || Validation.characterCount(text) <= 10_000 else { error = "Private notes can have up to 10,000 characters."; return }
            pendingID = UUID(); pendingText = text; deleting = delete
        }
        persist()
        guard persistenceError == nil, let operation = pendingID, let submitted = pendingText else { return }
        isSaving = true; error = nil
        defer { isSaving = false }
        do {
            if deleting { try await memories.deletePrivateNote(experienceID: experienceID, operationID: operation) }
            else { _ = try await memories.savePrivateNote(experienceID: experienceID, text: submitted, operationID: operation) }
            guard currentAccount() == ownerID else { return }
            didSave = true
            pendingID = nil
            storage.remove(name: draftID, userID: ownerID)
        } catch {
            guard currentAccount() == ownerID else { return }
            self.error = error.roamMessage
            if let error = error as? RoamError {
                if error == .notSignedIn || error == .sessionExpired { authError = error }
                if MemoryMutationRules.definitelyRejected(error) { pendingID = nil; pendingText = nil; deleting = false }
            }
            persist()
        }
    }

    func discard() {
        guard !isSaving, pendingID == nil else { return }
        generation += 1
        storage.remove(name: draftID, userID: ownerID)
    }

    private func persist() {
        guard currentAccount() == ownerID, !didSave else { return }
        let draft = PrivateNoteDraft(ownerID: ownerID, experienceID: experienceID, updatedAt: now(), text: text,
                                     pendingID: pendingID, pendingText: pendingText, deleting: deleting)
        do { try storage.write(draft, name: draftID, userID: ownerID); persistenceError = nil }
        catch { persistenceError = "Your private changes couldn't be kept on this device. Free some storage and retry." }
    }
}

enum MemoryMutationRules {
    static func definitelyRejected(_ error: RoamError) -> Bool {
        switch error {
        case .validation, .conflict, .notFound, .forbidden, .mediaExpired: return true
        default: return false
        }
    }
}
