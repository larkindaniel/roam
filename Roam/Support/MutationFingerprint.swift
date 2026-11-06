import CryptoKit
import Foundation

/// Stable across process launches; server receipts compute their own canonical intent digest.
enum MutationFingerprint {
    static func digest<T: Encodable>(_ intent: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return SHA256.hash(data: try encoder.encode(intent)).map { String(format: "%02x", $0) }.joined()
    }
}
