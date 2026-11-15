import Foundation

/// Times every request the backend makes (database calls, auth, photos, edge functions) from URLSession's own
/// measurements, and logs each as a `network` event: which endpoint, status, size and how long it took. Ids in paths
/// are dropped from the name so the same call groups together in `latency_last_7_days`.
final class NetworkRecorder: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = NetworkRecorder()

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let request = task.originalRequest, let url = request.url, let name = Self.name(for: url, method: request.httpMethod) else { return }
        let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        let transaction = metrics.transactionMetrics.last
        var props: [String: String] = [
            "status": "\(status)",
            "ok": (200..<300).contains(status) ? "true" : "false",
            "method": request.httpMethod ?? "GET",
            "bytes": "\(task.countOfBytesReceived)",
        ]
        if metrics.redirectCount > 0 { props["redirects"] = "\(metrics.redirectCount)" }
        if let transaction, transaction.isReusedConnection == false, let start = transaction.connectStartDate, let end = transaction.connectEndDate {
            props["connect_ms"] = "\(Int(end.timeIntervalSince(start) * 1_000))"
        }
        if let error = task.error as? URLError { props["error"] = "\(error.code.rawValue)" }
        Telemetry.shared.record(.network, name, durationMs: Int(metrics.taskInterval.duration * 1_000), props: props)
    }

    /// `rpc.feed_page`, `auth.token`, `storage.object`, `fn.prepare-media`; nil for what isn't worth logging (the log
    /// upload itself).
    static func name(for url: URL, method: String?) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { return url.host ?? "request" }
        switch parts[0] {
        case "rest":
            if parts.count >= 4, parts[2] == "rpc" {
                let function = parts[3]
                if function == "log_events" || function == "telemetry_settings" { return nil }
                return "rpc.\(function)"
            }
            return "rest.\(parts.count > 2 ? parts[2] : "?")"
        case "auth": return "auth.\(parts.count > 2 ? parts[2] : "?")"
        case "storage":
            // storage/v1/object/[authenticated/]bucket/... → storage.get.visit-media
            let rest = Array(parts.dropFirst(3))
            let bucket = rest.first == "authenticated" || rest.first == "sign" || rest.first == "public" ? rest.dropFirst().first : rest.first
            return "storage.\((method ?? "GET").lowercased()).\(bucket ?? "?")"
        case "functions": return "fn.\(parts.count > 2 ? parts[2] : "?")"
        default: return "\(url.host ?? "web")"
        }
    }
}
