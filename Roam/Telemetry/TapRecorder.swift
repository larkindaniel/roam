import SwiftUI
import UIKit

extension View {
    /// Names a button for UI tests (its accessibility identifier) and for the beta's event trail: each tap logs a
    /// `tap` event under this name. Use it on every button, link and toggle in place of `.accessibilityIdentifier`.
    func tapID(_ id: String) -> some View {
        accessibilityIdentifier(id)
            .simultaneousGesture(TapGesture().onEnded { TapRecorder.named(id) })
    }
}

/// Logs every tap in the app as a `tap` event. It watches touches on the window (never stopping or delaying them):
/// - a button with `.tapID(_:)` logs under that name,
/// - a system control (the back button, toolbar and keyboard buttons) logs under its UIKit accessibility name,
/// - anything else logs as `unnamed` with where on the screen it was, which with the screen, the navigation and the
///   network calls around it is usually enough to tell what it was.
/// Text typed into fields is never read.
final class TapRecorder: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private var start: CGPoint?
    private var began = ContinuousClock.now
    /// The last tap's point and time, picked up by a named tap that lands at the same moment.
    nonisolated(unsafe) private static var lastTouch: (point: CGPoint, at: ContinuousClock.Instant)?
    nonisolated(unsafe) private static var lastNamedAt: ContinuousClock.Instant?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    /// A `.tapID` button was tapped.
    static func named(_ id: String) {
        var props: [String: String] = [:]
        if let touch = lastTouch, touch.at.elapsedMilliseconds < 600 {
            props = ["x": "\(Int(touch.point.x))", "y": "\(Int(touch.point.y))"]
        }
        lastNamedAt = .now
        Log.tap(id, props)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touches.count == 1, let window = view as? UIWindow, let touch = touches.first else { state = .failed; return }
        start = touch.location(in: window)
        began = .now
        Self.lastTouch = (touch.location(in: window), .now)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let start, let window = view, let touch = touches.first else { return }
        let point = touch.location(in: window)
        if hypot(point.x - start.x, point.y - start.y) > 12 { self.start = nil; state = .failed }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        defer { state = .failed }
        guard let start, let window = view as? UIWindow else { return }
        let began = began
        let system = Self.uikitName(at: start, in: window)
        // A named button reports itself right after this; only log here if none does.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if let named = Self.lastNamedAt, named >= began { return }
            var props = ["x": "\(Int(start.x))", "y": "\(Int(start.y))"]
            if let label = system?.label, system?.identifier != nil { props["label"] = label }
            Log.tap(system?.identifier ?? system?.label ?? "unnamed", props)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        start = nil
        state = .failed
    }

    override func reset() { start = nil }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    /// The UIKit view under the point and its accessibility name, walking up to the first that has one. SwiftUI's own
    /// views don't answer here (their names only exist while VoiceOver or a UI test is running), UIKit's always do.
    private static func uikitName(at point: CGPoint, in window: UIWindow) -> (identifier: String?, label: String?)? {
        var view = window.hitTest(point, with: nil)
        var steps = 0
        while let current = view, steps < 8 {
            let identifier = current.accessibilityIdentifier.flatMap { $0.isEmpty ? nil : $0 }
            let label = current.accessibilityLabel.flatMap { $0.isEmpty ? nil : String($0.prefix(80)) }
            if identifier != nil || label != nil { return (identifier, label) }
            view = current.superview
            steps += 1
        }
        return nil
    }
}

/// Puts a `TapRecorder` on the window this view lands in. Placed once, behind the root view.
struct TapRecorderInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> InstallerView { InstallerView() }
    func updateUIView(_ uiView: InstallerView, context: Context) {}

    final class InstallerView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            isUserInteractionEnabled = false
            guard let window, !(window.gestureRecognizers ?? []).contains(where: { $0 is TapRecorder }) else { return }
            window.addGestureRecognizer(TapRecorder(target: nil, action: nil))
        }
    }
}
