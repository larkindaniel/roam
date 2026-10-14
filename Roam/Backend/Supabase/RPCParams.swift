import Foundation
import Supabase

/// Builds RPC argument objects with explicit `p_` keys and Postgres-friendly encodings.
typealias RPCParams = [String: AnyJSON]

enum RPC {
    static func uuid(_ value: UUID?) -> AnyJSON { value.map { .string($0.uuidString.lowercased()) } ?? .null }
    static func string(_ value: String?) -> AnyJSON { value.map(AnyJSON.string) ?? .null }
    static func int(_ value: Int?) -> AnyJSON { value.map(AnyJSON.integer) ?? .null }
    static func bool(_ value: Bool) -> AnyJSON { .bool(value) }
    static func date(_ value: LocalDate?) -> AnyJSON { value.map { .string($0.isoString) } ?? .null }
    static func uuids(_ values: [UUID]) -> AnyJSON { .array(values.map { .string($0.uuidString.lowercased()) }) }

    /// Encodes any value with Roam's JSON conventions and re-reads it as `AnyJSON`.
    static func json<T: Encodable>(_ value: T?) throws -> AnyJSON {
        guard let value else { return .null }
        let data = try RoamJSON.encoder.encode(value)
        return try JSONDecoder().decode(AnyJSON.self, from: data)
    }
}

/// `bucket/objectPath` storage paths returned by the API.
struct StoragePath: Hashable, Sendable {
    let bucket: String
    let object: String

    init?(_ raw: String) {
        guard let slash = raw.firstIndex(of: "/") else { return nil }
        bucket = String(raw[..<slash])
        object = String(raw[raw.index(after: slash)...])
        guard ["avatars", "visit-media"].contains(bucket), !object.isEmpty else { return nil }
    }
}
