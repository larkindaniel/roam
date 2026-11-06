import XCTest

/// M1: design-system components at default and accessibility Dynamic Type sizes.
final class M1ComponentUITests: RoamUITestCase {
    func testComponentCatalogDefaultSize() {
        launch(extra: ["-roam-component-catalog"])
        waitFor(element("component-catalog"))
        capture("m1-10-components-default")
        app.swipeUp()
        capture("m1-11-components-default-lower")
    }

    func testComponentCatalogLargeDynamicType() {
        launch(extra: ["-roam-component-catalog", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        waitFor(element("component-catalog"))
        capture("m1-12-components-ax-large")
        app.swipeUp()
        capture("m1-13-components-ax-large-lower")
        // Row actions stay separately reachable at large text sizes.
        let save = app.buttons["save-Cedar Ridge Trail"]
        for _ in 0..<6 where !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.isHittable, "Save stays a separate, reachable action at accessibility sizes")
        capture("m1-14-components-ax-large-row-actions")
    }
}
