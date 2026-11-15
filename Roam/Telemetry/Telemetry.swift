import Foundation
import UIKit

/// Roam's log: what a tester did, step by step, so a bug report can be replayed and slow spots measured.
///
/// Most of the trail is recorded for you:
/// - every screen with `.screenIdentifier(_:)` logs when it shows (`screen`),
/// - every tap on a button, row or control logs what was tapped (`tap`, see `TapRecorder`),
/// - every push, back, tab change and sheet logs from `AppRouter` (`nav`),
/// - every network request logs its endpoint, status and time (`network`, see `NetworkRecorder`),
/// - crashes, hangs and launches log themselves (`crash`, `lifecycle`).
///
/// Add your own for what those can't see:
/// ```swift
/// Log.action("log.saved", ["score": "\(score)"])          // something happened that matters
/// Log.error("photo.upload", error)                        // something failed
/// let ranked = try await Log.measure("rank.compute") { … } // something that takes time
/// ```
/// Never log what people write (notes, messages, passwords) or anything secret: names of places and ids are fine.
enum Log {
    typealias Props = [String: String]

    static func action(_ name: String, _ props: Props = [:]) { Telemetry.shared.record(.action, name, props: props) }
    static func tap(_ name: String, _ props: Props = [:]) { Telemetry.shared.record(.tap, name, props: props) }
    static func nav(_ name: String, _ props: Props = [:]) { Telemetry.shared.record(.nav, name, props: props) }
    static func lifecycle(_ name: String, _ props: Props = [:]) { Telemetry.shared.record(.lifecycle, name, props: props) }

    static func error(_ name: String, _ error: Error? = nil, _ props: Props = [:]) {
        var props = props
        if let error {
            props["error"] = String(describing: error).prefix(300).description
            props["message"] = error.roamMessage
        }
        Telemetry.shared.record(.error, name, props: props)
    }

    static func timing(_ name: String, ms: Int, _ props: Props = [:]) {
        Telemetry.shared.record(.timing, name, durationMs: ms, props: props)
    }

    /// Starts timing; `end()` logs it. For a whole function: `let span = Log.span("load.feed"); defer { span.end() }`.
    static func span(_ name: String, _ props: Props = [:]) -> LogSpan { LogSpan(name: name, props: props, start: .now) }

    /// Times `work` and logs it as a `timing` event, with `ok: false` if it throws.
    static func measure<T>(_ name: String, _ props: Props = [:], _ work: () async throws -> T) async rethrows -> T {
        let start = ContinuousClock.now
        do {
            let value = try await work()
            timing(name, ms: start.elapsedMilliseconds, props.merging(["ok": "true"]) { $1 })
            return value
        } catch {
            timing(name, ms: start.elapsedMilliseconds, props.merging(["ok": "false", "error": error.roamMessage]) { $1 })
            throw error
        }
    }

    /// The same, for work that isn't async (ranking, geometry, image processing).
    static func measure<T>(_ name: String, _ props: Props = [:], sync work: () throws -> T) rethrows -> T {
        let start = ContinuousClock.now
        do {
            let value = try work()
            timing(name, ms: start.elapsedMilliseconds, props.merging(["ok": "true"]) { $1 })
            return value
        } catch {
            timing(name, ms: start.elapsedMilliseconds, props.merging(["ok": "false", "error": error.roamMessage]) { $1 })
            throw error
        }
    }
}

struct LogSpan {
    let name: String
    let props: Log.Props
    let start: ContinuousClock.Instant
    func end(_ more: Log.Props = [:]) { Log.timing(name, ms: start.elapsedMilliseconds, props.merging(more) { $1 }) }
}

extension ContinuousClock.Instant {
    var elapsedMilliseconds: Int {
        let elapsed = ContinuousClock.now - self
        return Int(elapsed.components.seconds * 1_000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }
}

/// One step in the trail.
struct TelemetryEvent: Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable { case screen, tap, nav, action, network, timing, error, crash, lifecycle }
    var session: UUID
    var seq: Int
    var at: Date
    var kind: Kind
    var name: String
    var screen: String?
    var durationMs: Int?
    var props: [String: String]?
}

/// The phone and app a session ran on: sent once per session, not with every event.
struct TelemetrySession: Codable, Sendable {
    var id: UUID
    var startedAt: Date
    var appVersion: String
    var build: String
    var osVersion: String
    var deviceModel: String
    var locale: String?

    static func current() -> TelemetrySession {
        let info = Bundle.main.infoDictionary
        return TelemetrySession(id: UUID(), startedAt: Date(),
                                appVersion: info?["CFBundleShortVersionString"] as? String ?? "?",
                                build: info?["CFBundleVersion"] as? String ?? "?",
                                osVersion: UIDevice.current.systemVersion,
                                deviceModel: deviceModel(),
                                locale: Locale.current.identifier)
    }

    private static func deviceModel() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated + " (Simulator)" }
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

/// What the server says to record (one row in `telemetry_settings`), cached for the next launch.
struct TelemetrySettings: Codable, Sendable, Equatable {
    var eventsEnabled = true
    var bugReportsEnabled = true
    var mutedKinds: [String] = []
}

/// Where the trail goes: the backend's `log_events`, or nowhere (fixtures, UI tests).
protocol TelemetryTransport: Sendable {
    func settings() async throws -> TelemetrySettings
    func send(session: TelemetrySession, events: [TelemetryEvent]) async throws
    func markUnclean(session: UUID) async throws
}

/// Records the trail, keeps it on disk until it's uploaded (so a crash doesn't lose it), and uploads it in batches.
/// Thread-safe: log from anywhere.
final class Telemetry: @unchecked Sendable {
    static let shared = Telemetry()

    let session = TelemetrySession.current()
    /// The settings in force (last server answer, or defaults).
    private(set) var settings: TelemetrySettings
    private(set) var currentScreen: String?
    private(set) var lastTapAt: ContinuousClock.Instant?

    private let lock = NSLock()
    private var seq = 0
    private var pending: [TelemetryEvent] = []
    /// The last events of this session, for a bug report's summary.
    private var recent: [TelemetryEvent] = []
    private var transport: (any TelemetryTransport)?
    private var recording = false
    private var uploading = false
    private let io = DispatchQueue(label: "roam.telemetry.io")
    private let directory: URL
    private var handle: FileHandle?
    private static let settingsKey = "roam.telemetry.settings"
    private static let batchSize = 200
    private static let pendingCap = 2_000

    private init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("telemetry", isDirectory: true)
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let saved = try? JSONDecoder().decode(TelemetrySettings.self, from: data) {
            settings = saved
        } else {
            settings = TelemetrySettings()
        }
    }

    var bugReportsEnabled: Bool { lock.withLock { settings.bugReportsEnabled } }

    /// The sequence number of the latest event, so a bug report can say "everything up to here".
    var lastSeq: Int { lock.withLock { seq } }

    /// The last `count` events, oldest first.
    func recentEvents(_ count: Int = 40) -> [TelemetryEvent] { lock.withLock { Array(recent.suffix(count)) } }

    /// Starts recording. With no transport (fixtures, UI tests) nothing is written to disk or sent.
    func start(transport: (any TelemetryTransport)?) {
        lock.withLock {
            self.transport = transport
            recording = transport != nil
        }
        guard transport != nil else { return }
        io.sync { openSessionFile() }
        CrashRecorder.shared.start()
        let previousUnclean = CrashRecorder.shared.previousSessionEndedUncleanly
        Log.lifecycle("app.launch", ["session": session.id.uuidString,
                                     "previous_unclean": previousUnclean.map(\.uuidString) ?? "none"])
        if let previousUnclean {
            record(.crash, "unclean_exit", props: ["previous_session": previousUnclean.uuidString,
                                                   "why": "The last session ended while the app was open: a crash, a hang the system killed, or running out of memory."])
        }
        Task.detached(priority: .utility) { [self] in
            await refreshSettings()
            if let previousUnclean { try? await transport?.markUnclean(session: previousUnclean) }
            await uploadEarlierSessions()
            await uploadLoop()
        }
    }

    // MARK: Recording

    func record(_ kind: TelemetryEvent.Kind, _ name: String, screen: String? = nil, durationMs: Int? = nil,
                props: [String: String] = [:]) {
        let event: TelemetryEvent? = lock.withLock {
            if kind == .screen { currentScreen = name }
            if kind == .tap { lastTapAt = .now }
            seq += 1
            let trimmed = props.isEmpty ? nil : props.mapValues { String($0.prefix(500)) }
            let event = TelemetryEvent(session: session.id, seq: seq, at: Date(), kind: kind, name: String(name.prefix(120)),
                                       screen: screen ?? currentScreen, durationMs: durationMs, props: trimmed)
            recent.append(event)
            if recent.count > 300 { recent.removeFirst(recent.count - 300) }
            guard recording, settings.eventsEnabled, !settings.mutedKinds.contains(kind.rawValue) else { return nil }
            pending.append(event)
            if pending.count > Self.pendingCap { pending.removeFirst(pending.count - Self.pendingCap) }
            return event
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["ROAM_LOG_CONSOLE"] != nil {
            print("[roam] \(kind.rawValue) \(name) \(props)")
        }
        #endif
        guard let event else { return }
        io.async { [self] in append(event) }
    }

    // MARK: Disk

    private var eventsFile: URL { directory.appendingPathComponent("\(session.id.uuidString).events.jsonl") }

    private func openSessionFile() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let info = directory.appendingPathComponent("\(session.id.uuidString).session.json")
        try? RoamJSON.encoder.encode(session).write(to: info, options: .atomic)
        FileManager.default.createFile(atPath: eventsFile.path, contents: nil)
        handle = try? FileHandle(forWritingTo: eventsFile)
    }

    private func append(_ event: TelemetryEvent) {
        guard let handle, var line = try? RoamJSON.encoder.encode(event) else { return }
        line.append(0x0A)
        try? handle.seekToEnd()
        try? handle.write(contentsOf: line)
    }

    /// Rewrites this session's file with just what's still to send.
    private func rewrite(_ events: [TelemetryEvent]) {
        var data = Data()
        for event in events {
            guard let line = try? RoamJSON.encoder.encode(event) else { continue }
            data.append(line)
            data.append(0x0A)
        }
        try? handle?.truncate(atOffset: 0)
        try? handle?.seek(toOffset: 0)
        try? handle?.write(contentsOf: data)
    }

    // MARK: Upload

    private func refreshSettings() async {
        guard let transport = lock.withLock({ transport }),
              let fresh = try? await transport.settings() else { return }
        lock.withLock {
            settings = fresh
            if !fresh.eventsEnabled { pending.removeAll() }
            pending.removeAll { fresh.mutedKinds.contains($0.kind.rawValue) }
        }
        if let data = try? JSONEncoder().encode(fresh) { UserDefaults.standard.set(data, forKey: Self.settingsKey) }
    }

    private func uploadLoop() async {
        while true {
            try? await Task.sleep(for: .seconds(15))
            await flush()
        }
    }

    /// Sends what's waiting, in batches. Safe to call often; only one upload runs at a time.
    func flush() async {
        guard let transport = lock.withLock({ () -> (any TelemetryTransport)? in
            guard !uploading, !pending.isEmpty else { return nil }
            uploading = true
            return transport
        }) else { return }
        defer { lock.withLock { uploading = false } }
        while let batch = lock.withLock({ pending.isEmpty ? nil : Array(pending.prefix(Self.batchSize)) }) {
            do {
                try await transport.send(session: session, events: batch)
            } catch {
                return
            }
            let lastSent = batch.last?.seq ?? 0
            let remaining = lock.withLock { () -> [TelemetryEvent] in
                pending.removeAll { $0.seq <= lastSent }
                return pending
            }
            io.async { [self] in rewrite(remaining) }
        }
    }

    /// Earlier sessions' leftovers (the app was killed or offline before they went), then their files are removed.
    private func uploadEarlierSessions() async {
        guard let transport = lock.withLock({ transport }) else { return }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for info in files where info.lastPathComponent.hasSuffix(".session.json") {
            let id = info.lastPathComponent.replacingOccurrences(of: ".session.json", with: "")
            guard id != session.id.uuidString else { continue }
            let eventsURL = directory.appendingPathComponent("\(id).events.jsonl")
            guard let data = try? Data(contentsOf: info), let earlier = try? RoamJSON.decoder.decode(TelemetrySession.self, from: data) else {
                try? FileManager.default.removeItem(at: info)
                try? FileManager.default.removeItem(at: eventsURL)
                continue
            }
            let lines = (try? String(contentsOf: eventsURL, encoding: .utf8))?.split(separator: "\n") ?? []
            let events = lines.compactMap { try? RoamJSON.decoder.decode(TelemetryEvent.self, from: Data($0.utf8)) }
            var sent = true
            for start in stride(from: 0, to: events.count, by: Self.batchSize) {
                let batch = Array(events[start..<min(start + Self.batchSize, events.count)])
                do { try await transport.send(session: earlier, events: batch) } catch { sent = false; break }
            }
            // Old leftovers that can't be sent after a week aren't worth keeping.
            let stale = earlier.startedAt < Date().addingTimeInterval(-7 * 86_400)
            if sent || stale {
                try? FileManager.default.removeItem(at: info)
                try? FileManager.default.removeItem(at: eventsURL)
            }
        }
    }

    // MARK: App lifecycle

    /// Going to the background: say so, and send what's waiting while iOS gives us time.
    @MainActor func didEnterBackground() {
        Log.lifecycle("app.background")
        CrashRecorder.shared.markBackgrounded()
        let application = UIApplication.shared
        var task = UIBackgroundTaskIdentifier.invalid
        task = application.beginBackgroundTask(withName: "roam.telemetry") {
            application.endBackgroundTask(task)
        }
        Task {
            await flush()
            application.endBackgroundTask(task)
        }
    }

    @MainActor func didBecomeActive() {
        CrashRecorder.shared.markForeground(session: session.id)
        Log.lifecycle("app.foreground")
    }
}
