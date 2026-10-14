import Foundation

/// Per-account local storage for non-sensitive drafts and caches. Each account has its own
/// directory, so data never mixes between accounts; signing out or deleting the account clears it.
/// Credentials and tokens never go here (sessions live in the Keychain via the auth client).
final class AccountStorage: @unchecked Sendable {
    private let root: URL
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(RoamJSON.formatDate(date))
        }
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = RoamJSON.parseDate(string) else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid stored date") }
            return date
        }
        return decoder
    }()

    init(root: URL? = nil) {
        let base = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Roam", isDirectory: true)
        self.root = base.appendingPathComponent("Accounts", isDirectory: true)
    }

    func directory(for userID: UUID) -> URL {
        root.appendingPathComponent(userID.uuidString.lowercased(), isDirectory: true)
    }

    private func url(_ name: String, userID: UUID) -> URL {
        directory(for: userID).appendingPathComponent("\(name).json")
    }

    func write<T: Encodable>(_ value: T, name: String, userID: UUID) throws {
        let directory = directory(for: userID)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(value)
        try data.write(to: url(name, userID: userID), options: [.atomic, .completeFileProtection])
    }

    func read<T: Decodable>(_ type: T.Type, name: String, userID: UUID) -> T? {
        guard let data = try? Data(contentsOf: url(name, userID: userID)) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    func remove(name: String, userID: UUID) {
        try? fileManager.removeItem(at: url(name, userID: userID))
    }

    func names(userID: UUID, prefix: String) -> [String] {
        let items = (try? fileManager.contentsOfDirectory(atPath: directory(for: userID).path)) ?? []
        return items.filter { $0.hasPrefix(prefix) && $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
    }

    func clearAccount(_ userID: UUID) {
        try? fileManager.removeItem(at: directory(for: userID))
    }

    func clearAll() {
        try? fileManager.removeItem(at: root)
    }

    /// Deletes files untouched for longer than `lifetime` (30-day draft expiry).
    func purgeExpired(userID: UUID, prefix: String, lifetime: TimeInterval, now: Date = Date()) {
        let directory = directory(for: userID)
        for name in names(userID: userID, prefix: prefix) {
            let fileURL = directory.appendingPathComponent("\(name).json")
            let modified = (try? fileManager.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date) ?? now
            if now.timeIntervalSince(modified) > lifetime { try? fileManager.removeItem(at: fileURL) }
        }
    }
}
