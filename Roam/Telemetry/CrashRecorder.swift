import Foundation
import MetricKit

/// Crashes, two ways:
/// - **Unclean exits, straight away.** A marker file says "open in the foreground"; going to the background removes it.
///   If the next launch finds it, the last session ended while the app was open: a crash, a hang iOS killed, or
///   running out of memory. That session's trail is still on disk, so it uploads with everything up to the end.
/// - **The details, from iOS.** MetricKit hands over crash and hang reports with call stacks, usually on the next
///   launch (sometimes up to a day later). They're logged as `crash` events with the stack in `props`.
///
/// TestFlight's own crash reports (App Store Connect → TestFlight → Crashes) are symbolicated and worth a look too.
final class CrashRecorder: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = CrashRecorder()

    /// The session that was open when the app last ended without going to the background, if any.
    private(set) var previousSessionEndedUncleanly: UUID?
    private var started = false
    private let marker = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("telemetry/foreground.marker")

    func start() {
        guard !started else { return }
        started = true
        if let text = try? String(contentsOf: marker, encoding: .utf8), let id = UUID(uuidString: text) {
            previousSessionEndedUncleanly = id
        }
        try? FileManager.default.removeItem(at: marker)
        MXMetricManager.shared.add(self)
        NSSetUncaughtExceptionHandler { exception in
            // Objective-C exceptions only (Swift traps show up as unclean exits and MetricKit reports).
            Telemetry.shared.record(.crash, "exception", props: [
                "name": exception.name.rawValue,
                "reason": exception.reason ?? "",
                "stack": exception.callStackSymbols.prefix(40).joined(separator: "\n"),
            ])
        }
    }

    func markForeground(session: UUID) {
        try? FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? session.uuidString.write(to: marker, atomically: true, encoding: .utf8)
    }

    func markBackgrounded() {
        try? FileManager.default.removeItem(at: marker)
    }

    // MARK: MetricKit

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            for crash in payload.crashDiagnostics ?? [] {
                var props = Self.common(crash.metaData, stack: crash.callStackTree)
                props["exception_type"] = crash.exceptionType.map { "\($0)" } ?? ""
                props["exception_code"] = crash.exceptionCode.map { "\($0)" } ?? ""
                props["signal"] = crash.signal.map { "\($0)" } ?? ""
                props["termination_reason"] = crash.terminationReason ?? ""
                props["reported_for"] = payload.timeStampEnd.formatted(.iso8601)
                Telemetry.shared.record(.crash, "crash", props: props)
            }
            for hang in payload.hangDiagnostics ?? [] {
                var props = Self.common(hang.metaData, stack: hang.callStackTree)
                props["hang_duration_s"] = String(format: "%.1f", hang.hangDuration.converted(to: .seconds).value)
                Telemetry.shared.record(.crash, "hang", props: props)
            }
        }
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        // Daily summaries: how long launches take and how often the app hangs, from iOS itself.
        for payload in payloads {
            var props: [String: String] = ["app_version": payload.latestApplicationVersion]
            if let launch = payload.applicationLaunchMetrics {
                props["launch_first_draw_histogram"] = Self.describe(launch.histogrammedTimeToFirstDraw)
            }
            if let responsiveness = payload.applicationResponsivenessMetrics {
                props["hang_time_histogram"] = Self.describe(responsiveness.histogrammedApplicationHangTime)
            }
            Telemetry.shared.record(.lifecycle, "metrickit.daily", props: props)
        }
    }

    private static func common(_ meta: MXMetaData, stack: MXCallStackTree) -> [String: String] {
        [
            "app_build": meta.applicationBuildVersion,
            "os": meta.osVersion,
            "device": meta.deviceType,
            // The raw tree: symbolicate against the build's dSYM (see docs/telemetry.md).
            "stack": String(decoding: stack.jsonRepresentation(), as: UTF8.self).prefix(12_000).description,
        ]
    }

    private static func describe<Unit>(_ histogram: MXHistogram<Unit>) -> String {
        histogram.bucketEnumerator.compactMap { $0 as? MXHistogramBucket<Unit> }
            .map { "\($0.bucketStart.value)-\($0.bucketEnd.value)\($0.bucketEnd.unit.symbol):\($0.bucketCount)" }
            .joined(separator: " ")
    }
}
