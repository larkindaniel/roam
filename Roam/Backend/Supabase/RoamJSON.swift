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

    private static let whole: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Preserve server microseconds: tie representatives use oldest timestamp before UUID.
    static func parseDate(_ raw: String) -> Date? {
        var string = raw.replacingOccurrences(of: " ", with: "T")
        if string.hasSuffix("+00") { string += ":00" }
        if let dot = string.firstIndex(of: ".") {
            let afterDot = string.index(after: dot)
            let digitsEnd = string[afterDot...].firstIndex { !$0.isNumber } ?? string.endIndex
            let digits = string[afterDot..<digitsEnd]
            guard !digits.isEmpty, let fraction = Double("0." + digits) else { return nil }
            string.removeSubrange(dot..<digitsEnd)
            guard let base = whole.date(from: string) else { return nil }
            return base.addingTimeInterval(fraction)
        }
        return whole.date(from: string)
    }

    static func formatDate(_ date: Date) -> String {
        var seconds = floor(date.timeIntervalSince1970)
        var micros = Int(((date.timeIntervalSince1970 - seconds) * 1_000_000).rounded())
        if micros == 1_000_000 { seconds += 1; micros = 0 }
        let base = whole.string(from: Date(timeIntervalSince1970: seconds))
        return String(base.dropLast()) + String(format: ".%06dZ", micros)
    }

}
