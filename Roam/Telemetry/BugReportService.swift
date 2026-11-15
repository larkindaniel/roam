import Foundation

/// A tester's bug report, ready to send: what they wrote, an optional screenshot or recording, and where it came from.
struct BugReportDraft: Sendable {
    struct Attachment: Sendable {
        enum Kind: String, Sendable { case screenshot, recording }
        var kind: Kind
        var data: Data
        var contentType: String
        var fileExtension: String
    }

    var description: String
    var screen: String?
    var attachment: Attachment?
    var sessionID: UUID
    var lastSeq: Int
    var device: TelemetrySession
}

protocol BugReportService: Sendable {
    /// Uploads the attachment, saves the report and asks the server to open a GitHub issue for it.
    func submitBugReport(_ draft: BugReportDraft) async throws -> UUID
}

/// Fixture mode: reports go nowhere, after a moment.
struct FixtureBugReports: BugReportService {
    func submitBugReport(_ draft: BugReportDraft) async throws -> UUID {
        try await Task.sleep(for: .milliseconds(300))
        return UUID()
    }
}
