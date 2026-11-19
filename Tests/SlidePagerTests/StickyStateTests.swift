import XCTest
@testable import SlidePager

final class StickyStateTests: XCTestCase {

    func testExpanded() {
        XCTAssertEqual(StickyState.resolve(collapse: 0, maxStickyOffset: 200), .expanded)
        // Top bounce offset resolves to expanded.
        XCTAssertEqual(StickyState.resolve(collapse: -30, maxStickyOffset: 200), .expanded)
    }

    func testPartiallyCollapsed() {
        XCTAssertEqual(
            StickyState.resolve(collapse: 100, maxStickyOffset: 200),
            .partiallyCollapsed(progress: 0.5)
        )
        XCTAssertEqual(
            StickyState.resolve(collapse: 50, maxStickyOffset: 200),
            .partiallyCollapsed(progress: 0.25)
        )
    }

    func testCollapsed() {
        XCTAssertEqual(StickyState.resolve(collapse: 200, maxStickyOffset: 200), .collapsed)
        // Overshoot (bottom rubber-band of the outer scroll view) is clamped.
        XCTAssertEqual(StickyState.resolve(collapse: 230, maxStickyOffset: 200), .collapsed)
    }

    func testDegenerateRangeIsAlwaysCollapsed() {
        // No header: the tabs are pinned from the start.
        XCTAssertEqual(StickyState.resolve(collapse: 0, maxStickyOffset: 0), .collapsed)
        XCTAssertEqual(StickyState.resolve(collapse: 10, maxStickyOffset: 3), .collapsed)
    }

    func testProgressValues() {
        XCTAssertEqual(StickyState.expanded.progress, 0)
        XCTAssertEqual(StickyState.partiallyCollapsed(progress: 0.3).progress, 0.3)
        XCTAssertEqual(StickyState.collapsed.progress, 1)
    }
}
