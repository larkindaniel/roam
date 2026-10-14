import Foundation

/// Input limits shared by client validation and the database constraints (SPEC R02/R10, D11/D13).
enum Limits {
    static let passwordMin = 12
    static let passwordMax = 128
    static let displayNameRange = 1...50
    static let handleRange = 3...20
    static let bioMax = 160
    static let publicNoteMax = 5_000
    static let privateNoteMax = 10_000
    static let commentMax = 2_000
    static let reportTextMax = 1_000
    static let photosPerVisit = 6
    static let photoLongestSide = 2_048
    static let photoMaxBytes = 3 * 1_024 * 1_024
    static let pageSize = 30
    static let searchDebounce: Duration = .milliseconds(300)
    static let draftLifetime: TimeInterval = 30 * 24 * 60 * 60
}

enum ValidationIssue: Error, Hashable, LocalizedError {
    case tooShort(minimum: Int)
    case tooLong(maximum: Int)
    case invalidCharacters
    case required
    case futureDate
    case invalidEmail

    var errorDescription: String? {
        switch self {
        case .tooShort(let minimum): return "Use at least \(minimum) characters."
        case .tooLong(let maximum): return "Use \(maximum) characters or fewer."
        case .invalidCharacters: return "Use lowercase letters, numbers and underscores only."
        case .required: return "This is required."
        case .futureDate: return "A completed visit can't be in the future."
        case .invalidEmail: return "Enter a valid email address."
        }
    }
}

enum Validation {
    static func password(_ value: String) -> ValidationIssue? {
        if value.count < Limits.passwordMin { return .tooShort(minimum: Limits.passwordMin) }
        if value.count > Limits.passwordMax { return .tooLong(maximum: Limits.passwordMax) }
        return nil
    }

    static func email(_ value: String) -> ValidationIssue? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .required }
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."), !parts[1].hasPrefix("."), !parts[1].hasSuffix("."),
              !trimmed.contains(" ") else { return .invalidEmail }
        return nil
    }

    static func displayName(_ value: String) -> ValidationIssue? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .required }
        if trimmed.count > Limits.displayNameRange.upperBound { return .tooLong(maximum: Limits.displayNameRange.upperBound) }
        return nil
    }

    /// Lowercase ASCII letters, digits and underscore, 3–20 characters.
    static func handle(_ value: String) -> ValidationIssue? {
        if value.isEmpty { return .required }
        if value.count < Limits.handleRange.lowerBound { return .tooShort(minimum: Limits.handleRange.lowerBound) }
        if value.count > Limits.handleRange.upperBound { return .tooLong(maximum: Limits.handleRange.upperBound) }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_")
        if !value.allSatisfy({ allowed.contains($0) }) { return .invalidCharacters }
        return nil
    }

    /// Normalizes typed input toward a valid handle without inventing characters.
    static func normalizedHandleInput(_ value: String) -> String {
        String(value.lowercased().filter { !$0.isWhitespace }.prefix(Limits.handleRange.upperBound + 5))
    }

    static func bio(_ value: String) -> ValidationIssue? {
        value.count > Limits.bioMax ? .tooLong(maximum: Limits.bioMax) : nil
    }

    static func publicNote(_ value: String) -> ValidationIssue? {
        value.count > Limits.publicNoteMax ? .tooLong(maximum: Limits.publicNoteMax) : nil
    }

    static func privateNote(_ value: String) -> ValidationIssue? {
        value.count > Limits.privateNoteMax ? .tooLong(maximum: Limits.privateNoteMax) : nil
    }

    static func comment(_ value: String) -> ValidationIssue? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .required }
        if value.count > Limits.commentMax { return .tooLong(maximum: Limits.commentMax) }
        return nil
    }

    static func reportText(_ value: String) -> ValidationIssue? {
        value.count > Limits.reportTextMax ? .tooLong(maximum: Limits.reportTextMax) : nil
    }

    /// Completed visits may be any past date or today in the visit's time zone, never later.
    static func visitDate(_ date: LocalDate?, today: LocalDate) -> ValidationIssue? {
        guard let date else { return nil }
        return date > today ? .futureDate : nil
    }
}
