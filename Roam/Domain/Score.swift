import Foundation

/// A Roam score stored exactly in tenths (0...100) so client and server rounding agree.
struct Score: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    let tenths: Int

    init(tenths: Int) {
        precondition((0...100).contains(tenths), "Score out of range: \(tenths)")
        self.tenths = tenths
    }

    /// Parses a decimal such as 8.4 coming from the database (numeric(3,1)).
    init?(decimal: Decimal) {
        guard !decimal.isNaN, decimal >= 0, decimal <= 10 else { return nil }
        var value = decimal * 10
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        let intValue = NSDecimalNumber(decimal: rounded).intValue
        guard (0...100).contains(intValue) else { return nil }
        self.tenths = intValue
    }

    var decimalValue: Decimal { Decimal(tenths) / 10 }

    /// Always one decimal place: "8.4", "10.0", "0.0".
    var formatted: String { "\(tenths / 10).\(tenths % 10)" }

    var description: String { formatted }

    /// Colour band used for badges; text/icons always accompany colour.
    var band: Sentiment {
        if tenths >= Sentiment.liked.boundsInTenths.low { return .liked }
        if tenths >= Sentiment.fine.boundsInTenths.low { return .fine }
        return .disliked
    }

    static func < (lhs: Score, rhs: Score) -> Bool { lhs.tenths < rhs.tenths }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let decimal = try? container.decode(Decimal.self), let score = Score(decimal: decimal) {
            self = score
            return
        }
        if let string = try? container.decode(String.self), let decimal = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")), let score = Score(decimal: decimal) {
            self = score
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid score")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(decimalValue)
    }
}

/// Exact score arithmetic for formula `roam-category-v1`.
enum ScoreMath {
    static let formulaVersion = "roam-category-v1"

    /// Half-up rounding of a non-negative rational number to an integer.
    static func roundHalfUp(numerator: Int, denominator: Int) -> Int {
        precondition(denominator > 0 && numerator >= 0)
        return (2 * numerator + denominator) / (2 * denominator)
    }

    /// Score for the tie group at `groupIndex` (0 = best) among `groupCount` groups of one sentiment.
    /// One group uses the band midpoint; otherwise groups are evenly spaced from high to low.
    static func score(groupIndex: Int, groupCount: Int, sentiment: Sentiment) -> Score {
        precondition(groupCount >= 1 && (0..<groupCount).contains(groupIndex))
        let (low, high) = sentiment.boundsInTenths
        if groupCount == 1 {
            return Score(tenths: roundHalfUp(numerator: high + low, denominator: 2))
        }
        let numerator = high * (groupCount - 1) - groupIndex * (high - low)
        return Score(tenths: roundHalfUp(numerator: numerator, denominator: groupCount - 1))
    }

    /// Mean of current scores rounded half-up to one decimal (Following score).
    static func mean(of scores: [Score]) -> Score? {
        guard !scores.isEmpty else { return nil }
        let sum = scores.reduce(0) { $0 + $1.tenths }
        return Score(tenths: roundHalfUp(numerator: sum, denominator: scores.count))
    }
}
