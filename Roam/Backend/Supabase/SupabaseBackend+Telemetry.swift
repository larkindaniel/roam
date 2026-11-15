import Foundation
import Supabase

extension SupabaseBackend: TelemetryTransport {
    func settings() async throws -> TelemetrySettings {
        try await rpc("telemetry_settings")
    }

    func send(session: TelemetrySession, events: [TelemetryEvent]) async throws {
        let _: Int = try await rpc("log_events", ["p_session": try RPC.json(session), "p_events": try RPC.json(events)])
    }

    func markUnclean(session: UUID) async throws {
        try await rpcVoid("mark_session_unclean", ["p_session_id": RPC.uuid(session)])
    }
}

extension SupabaseBackend: BugReportService {
    func submitBugReport(_ draft: BugReportDraft) async throws -> UUID {
        let snapshot = try await requestSnapshot()
        var attachmentPath: String?
        if let attachment = draft.attachment {
            guard let actor = snapshot.userID else { throw RoamError.notSignedIn }
            let path = "\(actor.uuidString.lowercased())/\(UUID().uuidString.lowercased()).\(attachment.fileExtension)"
            var upload = URLRequest(url: config.supabaseURL.appendingPathComponent("storage/v1/object/bug-reports/\(path)"))
            upload.httpMethod = "POST"
            upload.httpBody = attachment.data
            upload.timeoutInterval = 120
            snapshot.headers.forEach { upload.setValue($0.value, forHTTPHeaderField: $0.key) }
            upload.setValue(attachment.contentType, forHTTPHeaderField: "Content-Type")
            do {
                let (body, response) = try await send(upload)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(status) else {
                    Log.error("bug_report.upload", nil, ["status": "\(status)", "body": String(decoding: body.prefix(200), as: UTF8.self)])
                    throw status == 413 ? RoamError.validation("That recording is too big. Try a shorter one.")
                                        : RoamError.server("Couldn't upload the attachment. Try again.")
                }
            } catch let error as RoamError { throw error } catch { throw Self.map(error) }
            attachmentPath = path
        }
        let report: [String: AnyJSON] = [
            "description": .string(draft.description),
            "screen": RPC.string(draft.screen),
            "sessionId": RPC.uuid(draft.sessionID),
            "lastSeq": RPC.int(draft.lastSeq),
            "attachmentPath": RPC.string(attachmentPath),
            "attachmentKind": RPC.string(draft.attachment?.kind.rawValue),
            "appVersion": .string(draft.device.appVersion),
            "build": .string(draft.device.build),
            "osVersion": .string(draft.device.osVersion),
            "deviceModel": .string(draft.device.deviceModel),
        ]
        let params: RPCParams = ["p_report": .object(report)]
        let id: UUID = try await rpc("submit_bug_report", params)
        // Opening a GitHub issue happens on the server; the report is saved either way.
        guard snapshot.userID != nil else { return id }
        Task.detached(priority: .utility) { [self] in
            var request = URLRequest(url: config.supabaseURL.appendingPathComponent("functions/v1/bug-report-issue"))
            request.httpMethod = "POST"
            snapshot.headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["reportId": id.uuidString.lowercased()])
            _ = try? await send(request)
        }
        return id
    }
}
