import Foundation

/// JSON coding shared by the Supabase backend. RPCs return camelCase JSON that matches the
/// Swift models directly; timestamps are ISO 8601 with up to microsecond precision.
enum RoamJSON {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = parseDate(string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
            }
            return date
        }
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatDate(date))
        }
        return encoder
    }()

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let whole: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Accepts `2026-10-14T01:34:48.601868+00:00`, `...Z`, without fractions, and Postgres'
    /// space separator. Fractions beyond milliseconds are truncated before parsing.
    static func parseDate(_ raw: String) -> Date? {
        var string = raw.replacingOccurrences(of: " ", with: "T")
        if let dot = string.firstIndex(of: ".") {
            let afterDot = string.index(after: dot)
            let digitsEnd = string[afterDot...].firstIndex { !$0.isNumber } ?? string.endIndex
            let digits = string[afterDot..<digitsEnd]
            if digits.count > 3 {
                string.replaceSubrange(afterDot..<digitsEnd, with: digits.prefix(3))
            }
        }
        if string.hasSuffix("+00") { string += ":00" }
        return fractional.date(from: string) ?? whole.date(from: string)
    }

    static func formatDate(_ date: Date) -> String { fractional.string(from: date) }
}
