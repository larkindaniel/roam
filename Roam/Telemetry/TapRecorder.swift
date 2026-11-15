import SwiftUI
import UIKit

extension View {
    /// Names a button for UI tests (its accessibility identifier) and for the beta's event trail: each tap logs a
    /// `tap` event under this name. Use it on every button, link and toggle in place of `.accessibilityIdentifier`.
    ///
    /// It adds no gesture (one would steal taps from buttons inside a List or Form): an invisible marker behind the
    /// button says where it is, and the tap recorder names a tap by the marker under the finger.
    func tapID(_ id: String) -> some View {
        accessibilityIdentifier(id)
            .background(TapMarker(id: id).allowsHitTesting(false))
    }
}

/// An invisible UIKit view behind a named button, so a tap on the window can be matched to the button's name.
struct TapMarker: UIViewRepresentable {
    let id: String

    func makeUIView(context: Context) -> MarkerView {
        let view = MarkerView()
        view.markerID = id
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: MarkerView, context: Context) { view.markerID = id }

    final class MarkerView: UIView {
        var markerID = ""
        /// Every marker on screen (weakly held), for the recorder to search.
        nonisolated(unsafe) static let all = NSHashTable<MarkerView>.weakObjects()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { Self.all.add(self) } else { Self.all.remove(self) }
        }

        /// Showing: in a window, and no view above it hidden or see-through (tabs not on screen are faded out).
        var isShowing: Bool {
            guard window != nil else { return false }
            var view: UIView? = self
            while let current = view {
                if current.isHidden || current.alpha < 0.01 || current.layer.opacity < 0.01 { return false }
                view = current.superview
            }
            return true
        }
    }

    /// The smallest showing marker under the point, on the same layer as the view the touch hit (so a sheet's buttons
    /// win over the page under it).
    static func name(at point: CGPoint, in window: UIWindow, hit: UIView?) -> String? {
        let layer = hit.flatMap(Self.presentationRoot)
        var best: (id: String, area: CGFloat)?
        for marker in MarkerView.all.allObjects where marker.window === window && !marker.markerID.isEmpty {
            let frame = marker.convert(marker.bounds, to: window)
            guard frame.contains(point), marker.isShowing else { continue }
            if let layer, let markerLayer = Self.presentationRoot(marker), markerLayer !== layer { continue }
            let area = frame.width * frame.height
            if best == nil || area < best!.area { best = (marker.markerID, area) }
        }
        return best?.id
    }

    /// The view of the view controller a view belongs to that's presented on its own (the app, or a sheet).
    private static func presentationRoot(_ view: UIView) -> UIView? {
        var responder: UIResponder? = view
        var root: UIView?
        while let current = responder {
            if let controller = current as? UIViewController {
                root = controller.view
                if controller.presentingViewController != nil || controller.parent == nil { return root }
            }
            responder = current.next
        }
        return root
    }
}

/// Logs every tap in the app as a `tap` event. It watches touches on the window (never stopping or delaying them):
/// - a button with `.tapID(_:)` logs under that name (found by its marker, see `TapMarker`),
/// - a slider or tappable view that calls `TapRecorder.named` logs under its name,
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

    /// Something named was tapped that has no marker: a slider stop, a view with onTapGesture.
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
        let touchedAt = Date()
        // A .tapID button: named by its marker, straight away.
        if let id = TapMarker.name(at: start, in: window, hit: window.hitTest(start, with: nil)) {
            Self.lastNamedAt = .now
            Log.tap(id, ["x": "\(Int(start.x))", "y": "\(Int(start.y))"], at: touchedAt)
            return
        }
        let system = Self.uikitName(at: start, in: window)
        // iOS's own controls (back, toolbar buttons, the keyboard, map pins) can't be .tapID buttons: log them now, so
        // they come before what they cause.
        // Toolbar items can hold a .tapID button, so they wait for its name like everything else.
        if let system, system.known != "system.toolbar-button",
           system.identifier != nil || system.label != nil || system.known != nil {
            var props = ["x": "\(Int(start.x))", "y": "\(Int(start.y))"]
            if let label = system.label, system.identifier != nil { props["label"] = label }
            if let kind = system.kind { props["view"] = kind }
            Log.tap(system.identifier ?? system.label ?? system.known ?? "unnamed", props)
            return
        }
        // A named button reports itself right after this; only log here if none does.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if let named = Self.lastNamedAt, named >= began { return }
            var props = ["x": "\(Int(start.x))", "y": "\(Int(start.y))"]
            if let label = system?.label, system?.identifier != nil { props["label"] = label }
            if let kind = system?.kind { props["view"] = kind }
            // Logged a moment later, but with the time it happened.
            Log.tap(system?.identifier ?? system?.label ?? system?.known ?? "unnamed", props, at: touchedAt)
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
    /// What was tapped, from UIKit: its accessibility name if it has one, else a name for iOS's own controls we know
    /// (the back button, map pins, the keyboard), and the view's type so an unknown one can still be looked up.
    private static func uikitName(at point: CGPoint, in window: UIWindow) -> (identifier: String?, label: String?, known: String?, kind: String?)? {
        guard let hit = window.hitTest(point, with: nil) else { return nil }
        var view: UIView? = hit
        var steps = 0
        var classes: [String] = []
        while let current = view, steps < 10 {
            let type = String(describing: Swift.type(of: current))
            classes.append(type)
            let identifier = current.accessibilityIdentifier.flatMap { $0.isEmpty ? nil : $0 }
            let label = current.accessibilityLabel.flatMap { $0.isEmpty ? nil : String($0.prefix(80)) }
            if identifier != nil || label != nil { return (identifier, label, nil, type) }
            view = current.superview
            steps += 1
        }
        let chain = classes.joined(separator: " ")
        let known: String?
        switch true {
        case chain.contains("BackButton") || chain.contains("_UIButtonBarButton") && point.x < 90: known = "system.back"
        case chain.contains("BarButton") || chain.contains("ButtonBar") || chain.contains("BarItem"): known = "system.toolbar-button"
        case chain.contains("Annotation") || chain.contains("Marker"): known = "map.pin"
        case chain.contains("MKMapView") || chain.contains("MKMap"): known = "map"
        case chain.contains("AlertControllerAction") || chain.contains("ActionSheet"): known = "system.alert-action"
case chain.contains("TextView") || chain.contains("TextField") || chain.contains("TextInput"): known = "text-field"
        case chain.contains("NavigationBar"): known = "system.navigation-bar"
        default: known = nil
        }
        return (nil, nil, known, classes.first)
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
