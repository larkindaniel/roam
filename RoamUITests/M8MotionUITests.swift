import XCTest

/// M8 Reduce Motion: the debug component catalogue reports the system setting the app received.
/// Runs with `TEST_RUNNER_ROAM_EXPECT_REDUCE_MOTION=1` after Reduce Motion is switched on for the
/// simulator; otherwise it expects the setting off. Roam's only app-defined motion (skeleton pulse
/// and map camera moves) is gated on this setting.
final class M8MotionUITests: RoamUITestCase {
    func testTheAppReceivesTheReduceMotionSetting() {
        let expected = ProcessInfo.processInfo.environment["ROAM_EXPECT_REDUCE_MOTION"] == "1"
        launch(extra: ["-roam-component-catalog"])
        let status = waitFor(element("catalog-reduce-motion"), timeout: 10)
        XCTAssertEqual(status.label, expected ? "Reduce Motion: on" : "Reduce Motion: off")
        if expected { capture("m8-16-reduce-motion-on") }
    }
}
