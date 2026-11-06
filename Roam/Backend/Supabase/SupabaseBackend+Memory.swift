import Foundation

extension SupabaseBackend: MemoryService {
    func visit(visitID: UUID) async throws -> Visit {
        try await rpc("visit", ["p_visit_id": RPC.uuid(visitID)])
    }

    func publicMemories(experienceID: UUID, cursor: String?) async throws -> Page<PublicMemory> {
        struct Wire: Decodable { let items: [PublicMemory]; let nextCursor: String? }
        let page: Wire = try await rpc("public_memories", ["p_experience_id": RPC.uuid(experienceID), "p_cursor": RPC.string(cursor)])
        return Page(items: page.items, nextCursor: page.nextCursor)
    }

    func updateVisit(visitID: UUID, note: String, date: VisitDate, mediaIDs: [UUID], operationID: UUID) async throws -> Visit {
        let payload = VisitPayload(date: date.date, timeZoneIdentifier: date.timeZoneIdentifier, publicNote: note, mediaIDs: mediaIDs)
        return try await rpc("update_visit", ["p_visit_id": RPC.uuid(visitID), "p_payload": try RPC.json(payload), "p_operation_id": RPC.uuid(operationID)])
    }

    func privateNote(experienceID: UUID) async throws -> PrivateNote? {
        try await rpc("my_private_note", ["p_experience_id": RPC.uuid(experienceID)])
    }

    func savePrivateNote(experienceID: UUID, text: String, operationID: UUID) async throws -> PrivateNote {
        try await rpc("save_private_note", ["p_experience_id": RPC.uuid(experienceID), "p_text": RPC.string(text), "p_operation_id": RPC.uuid(operationID)])
    }

    func deletePrivateNote(experienceID: UUID, operationID: UUID) async throws {
        try await rpcVoid("delete_private_note", ["p_experience_id": RPC.uuid(experienceID), "p_operation_id": RPC.uuid(operationID)])
    }
}

extension SupabaseBackend {
    /// Removes only the post; its Rating and Visit stay. Repeating it is harmless.
    func deleteActivity(id: UUID) async throws {
        let _: Bool = try await rpc("delete_activity", ["p_activity_id": RPC.uuid(id)])
    }
}
