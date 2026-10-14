import Foundation

extension SupabaseBackend: RankingService {
    func categoryRanking(_ category: ExperienceCategory) async throws -> CategoryRanking {
        try await rpc("category_ranking", ["p_category": RPC.string(category.rawValue)])
    }

    func commitRating(_ request: RatingCommitRequest) async throws -> RatingCommitResult {
        try await rpc("commit_rating", ["p_request": try RPC.json(request)])
    }

    func addVisit(_ request: AddVisitRequest) async throws -> AddVisitResult {
        try await rpc("add_visit", ["p_request": try RPC.json(request)])
    }

    func removeRating(experienceID: UUID, operationID: UUID) async throws {
        try await rpcVoid("remove_rating", ["p_experience_id": RPC.uuid(experienceID), "p_operation_id": RPC.uuid(operationID)])
    }

    func deleteVisit(visitID: UUID, operationID: UUID, allowRatingRemoval: Bool) async throws -> DeleteVisitResult {
        try await rpc("delete_visit", ["p_visit_id": RPC.uuid(visitID), "p_operation_id": RPC.uuid(operationID),
                                      "p_allow_rating_removal": RPC.bool(allowRatingRemoval)])
    }
}
