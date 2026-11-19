import XCTest
@testable import SlidePager

final class ScrollRulesTests: XCTestCase {

    // MARK: - pageMustHoldTop

    func testPageMustHoldTopWhileHeaderVisible() {
        XCTAssertTrue(ScrollRules.pageMustHoldTop(outerOffsetY: 0, maxStickyOffset: 200))
        XCTAssertTrue(ScrollRules.pageMustHoldTop(outerOffsetY: 199, maxStickyOffset: 200))
        // At or past the sticky point the page is free.
        XCTAssertFalse(ScrollRules.pageMustHoldTop(outerOffsetY: 200, maxStickyOffset: 200))
        XCTAssertFalse(ScrollRules.pageMustHoldTop(outerOffsetY: 250, maxStickyOffset: 200))
    }

    func testPageMustHoldTopDuringTopBounce() {
        // Negative offset (top rubber-band) still means "header visible".
        XCTAssertTrue(ScrollRules.pageMustHoldTop(outerOffsetY: -20, maxStickyOffset: 200))
    }

    func testPageMustHoldTopWithNoStickyRange() {
        // No header (or header shorter than the top inset): pinned immediately.
        XCTAssertFalse(ScrollRules.pageMustHoldTop(outerOffsetY: 0, maxStickyOffset: 0))
    }

    // MARK: - outerMustHoldSticky

    func testOuterMustHoldStickyWhilePageBelowTop() {
        XCTAssertTrue(ScrollRules.outerMustHoldSticky(
            pageOffsetY: 120, pageTopOffsetY: 0, outerOffsetY: 199, maxStickyOffset: 200
        ))
    }

    func testOuterFreeWhenPageAtTop() {
        XCTAssertFalse(ScrollRules.outerMustHoldSticky(
            pageOffsetY: 0, pageTopOffsetY: 0, outerOffsetY: 199, maxStickyOffset: 200
        ))
        // Page in its own top bounce region also counts as "at top".
        XCTAssertFalse(ScrollRules.outerMustHoldSticky(
            pageOffsetY: -10, pageTopOffsetY: 0, outerOffsetY: 200, maxStickyOffset: 200
        ))
    }

    func testOuterFreeWhenAlreadyAtStickyOffset() {
        XCTAssertFalse(ScrollRules.outerMustHoldSticky(
            pageOffsetY: 120, pageTopOffsetY: 0, outerOffsetY: 200, maxStickyOffset: 200
        ))
    }

    func testPagePanYieldsWhileHeaderVisible() {
        XCTAssertFalse(ScrollRules.pagePanShouldBegin(
            headerVisible: true, velocity: .zero, pageOffsetY: 0, pageTopY: 0
        ))
        XCTAssertFalse(ScrollRules.pagePanShouldBegin(
            headerVisible: true, velocity: CGPoint(x: 2, y: -40), pageOffsetY: 0, pageTopY: 0
        ))
        // A clearly horizontal pan can stay with the page.
        XCTAssertTrue(ScrollRules.pagePanShouldBegin(
            headerVisible: true, velocity: CGPoint(x: 40, y: 2), pageOffsetY: 0, pageTopY: 0
        ))
    }

    func testPagePanYieldsPullDownAtTop() {
        XCTAssertFalse(ScrollRules.pagePanShouldBegin(
            headerVisible: false, velocity: CGPoint(x: 0, y: 30), pageOffsetY: 0, pageTopY: 0
        ))
        XCTAssertTrue(ScrollRules.pagePanShouldBegin(
            headerVisible: false, velocity: CGPoint(x: 0, y: -30), pageOffsetY: 0, pageTopY: 0
        ))
        // Scrolled page keeps a pull-down; the header waits until the page is at top.
        XCTAssertTrue(ScrollRules.pagePanShouldBegin(
            headerVisible: false, velocity: CGPoint(x: 0, y: 30), pageOffsetY: 80, pageTopY: 0
        ))
    }

    func testTransferDragCollapsesHeaderBeforePage() {
        let moved = ScrollRules.transferDrag(
            pageOffsetY: 40, pageStartY: 0, pageTopY: 0, outerStartY: 0, maxStickyOffset: 200
        )
        XCTAssertEqual(moved.outerY, 40, accuracy: 0.01)
        XCTAssertEqual(moved.pageY, 0, accuracy: 0.01)

        let handedOff = ScrollRules.transferDrag(
            pageOffsetY: 250, pageStartY: 0, pageTopY: 0, outerStartY: 0, maxStickyOffset: 200
        )
        XCTAssertEqual(handedOff.outerY, 200, accuracy: 0.01)
        XCTAssertEqual(handedOff.pageY, 50, accuracy: 0.01)
    }

    func testCoastDistanceDecaysInTheFingerDirection() {
        XCTAssertEqual(
            ScrollRules.coastDistance(velocity: 1000, decelerationRate: 0.998, time: 0),
            0
        )
        let opening = ScrollRules.coastDistance(velocity: 800, decelerationRate: 0.998, time: 0.25)
        XCTAssertGreaterThan(opening, 0)
        XCTAssertLessThan(opening, 800 * 0.25)
        let collapsing = ScrollRules.coastDistance(velocity: -800, decelerationRate: 0.998, time: 0.25)
        XCTAssertLessThan(collapsing, 0)
        XCTAssertLessThan(
            abs(ScrollRules.coastSpeed(velocity: 800, decelerationRate: 0.998, time: 0.5)),
            800
        )
    }

    func testLinkedOffsetsAreContinuousAcrossTheBoundary() {
        // Header collapsing, then the page continues at the same rate.
        let inHeader = ScrollRules.linkedOffsets(
            fingerDown: -40, outerStartY: 0, pageStartY: 0, pageTopY: 0, maxStickyOffset: 200
        )
        XCTAssertEqual(inHeader.outerY, 40, accuracy: 0.01)
        XCTAssertEqual(inHeader.pageY, 0, accuracy: 0.01)

        let intoPage = ScrollRules.linkedOffsets(
            fingerDown: -250, outerStartY: 0, pageStartY: 0, pageTopY: 0, maxStickyOffset: 200
        )
        XCTAssertEqual(intoPage.outerY, 200, accuracy: 0.01)
        XCTAssertEqual(intoPage.pageY, 50, accuracy: 0.01)

        // Page scrolling back to its top, then the header opens with no jump.
        let inPage = ScrollRules.linkedOffsets(
            fingerDown: 40, outerStartY: 200, pageStartY: 100, pageTopY: 0, maxStickyOffset: 200
        )
        XCTAssertEqual(inPage.outerY, 200, accuracy: 0.01)
        XCTAssertEqual(inPage.pageY, 60, accuracy: 0.01)

        let atTop = ScrollRules.linkedOffsets(
            fingerDown: 100, outerStartY: 200, pageStartY: 100, pageTopY: 0, maxStickyOffset: 200
        )
        XCTAssertEqual(atTop.outerY, 200, accuracy: 0.01)
        XCTAssertEqual(atTop.pageY, 0, accuracy: 0.01)

        let intoHeader = ScrollRules.linkedOffsets(
            fingerDown: 130, outerStartY: 200, pageStartY: 100, pageTopY: 0, maxStickyOffset: 200
        )
        XCTAssertEqual(intoHeader.outerY, 170, accuracy: 0.01)
        XCTAssertEqual(intoHeader.pageY, 0, accuracy: 0.01)
    }

    func testPullTowardTopScrollsPageBeforeExpandingHeader() {
        // Still inside the page: header stays collapsed, page moves toward its top.
        let inPage = ScrollRules.pullTowardTop(
            fingerDown: 40, outerStartY: 200, pageStartY: 100, pageTopY: 0, maxStickyOffset: 200
        )
        XCTAssertEqual(inPage?.outerY ?? -1, 200, accuracy: 0.01)
        XCTAssertEqual(inPage?.pageY ?? -1, 60, accuracy: 0.01)

        // Just reached the top: header has not started expanding.
        let atTop = ScrollRules.pullTowardTop(
            fingerDown: 100, outerStartY: 200, pageStartY: 100, pageTopY: 0, maxStickyOffset: 200
        )
        XCTAssertEqual(atTop?.outerY ?? -1, 200, accuracy: 0.01)
        XCTAssertEqual(atTop?.pageY ?? -1, 0, accuracy: 0.01)

        // Past the top: the leftover distance restores the header.
        let expanding = ScrollRules.pullTowardTop(
            fingerDown: 130, outerStartY: 200, pageStartY: 100, pageTopY: 0, maxStickyOffset: 200
        )
        XCTAssertEqual(expanding?.outerY ?? -1, 170, accuracy: 0.01)
        XCTAssertEqual(expanding?.pageY ?? -1, 0, accuracy: 0.01)
    }

    func testPullTowardTopDoesNotApplyToOtherDrags() {
        XCTAssertNil(ScrollRules.pullTowardTop(
            fingerDown: 40, outerStartY: 80, pageStartY: 100, pageTopY: 0, maxStickyOffset: 200
        ))
        XCTAssertNil(ScrollRules.pullTowardTop(
            fingerDown: 40, outerStartY: 200, pageStartY: 0, pageTopY: 0, maxStickyOffset: 200
        ))
        XCTAssertNil(ScrollRules.pullTowardTop(
            fingerDown: -20, outerStartY: 200, pageStartY: 100, pageTopY: 0, maxStickyOffset: 200
        ))
    }

    func testTransferDragExpandsHeaderOnPullDown() {
        let expanded = ScrollRules.transferDrag(
            pageOffsetY: -30, pageStartY: 0, pageTopY: 0, outerStartY: 80, maxStickyOffset: 200
        )
        XCTAssertEqual(expanded.outerY, 50, accuracy: 0.01)
        XCTAssertEqual(expanded.pageY, 0, accuracy: 0.01)
    }

    func testOuterMustHoldStickyRespectsPageInsets() {
        // A page with a top content inset of 88 rests at -88, not 0.
        XCTAssertTrue(ScrollRules.outerMustHoldSticky(
            pageOffsetY: 0, pageTopOffsetY: -88, outerOffsetY: 150, maxStickyOffset: 200
        ))
        XCTAssertFalse(ScrollRules.outerMustHoldSticky(
            pageOffsetY: -88, pageTopOffsetY: -88, outerOffsetY: 150, maxStickyOffset: 200
        ))
    }
}
