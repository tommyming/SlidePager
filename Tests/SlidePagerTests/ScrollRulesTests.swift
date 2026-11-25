import CoreGraphics
import Foundation
import Testing
@testable import SlidePager

/// The decision table for the nested-scroll coordinator — happy paths.
/// Edge cases live in `ScrollRulesAdditionalTests`.
@Suite(.tags(.scrollMath))
struct ScrollRulesTests {

    // MARK: - pageMustHoldTop

    @Test("pageMustHoldTop pins the page until the sticky point", arguments: [
        (CGFloat(0), CGFloat(200), true),    // header fully visible
        (199, 200, true),                    // one point of header left
        (-20, 200, true),                    // top rubber-band still means header visible
        (200, 200, false),                   // at the sticky point the page is free
        (250, 200, false),                   // past it too
        (0, 0, false),                       // no header (or none past the inset): pinned immediately
    ])
    func pageMustHoldTop(outerY: CGFloat, maxSticky: CGFloat, holds: Bool) {
        #expect(
            ScrollRules.pageMustHoldTop(outerOffsetY: outerY, maxStickyOffset: maxSticky) == holds
        )
    }

    // MARK: - outerMustHoldSticky

    @Test func `Outer must hold sticky while page is below top`() {
        #expect(ScrollRules.outerMustHoldSticky(
            pageOffsetY: 120, pageTopOffsetY: 0, outerOffsetY: 199, maxStickyOffset: 200
        ))
    }

    @Test func `Outer is free when the page is at top`() {
        #expect(!ScrollRules.outerMustHoldSticky(
            pageOffsetY: 0, pageTopOffsetY: 0, outerOffsetY: 199, maxStickyOffset: 200
        ))
        // Page in its own top bounce region also counts as "at top".
        #expect(!ScrollRules.outerMustHoldSticky(
            pageOffsetY: -10, pageTopOffsetY: 0, outerOffsetY: 200, maxStickyOffset: 200
        ))
    }

    @Test func `Outer is free when already at the sticky offset`() {
        #expect(!ScrollRules.outerMustHoldSticky(
            pageOffsetY: 120, pageTopOffsetY: 0, outerOffsetY: 200, maxStickyOffset: 200
        ))
    }

    @Test func `Outer must hold sticky respects page insets`() {
        // A page with a top content inset of 88 rests at -88, not 0.
        #expect(ScrollRules.outerMustHoldSticky(
            pageOffsetY: 0, pageTopOffsetY: -88, outerOffsetY: 150, maxStickyOffset: 200
        ))
        #expect(!ScrollRules.outerMustHoldSticky(
            pageOffsetY: -88, pageTopOffsetY: -88, outerOffsetY: 150, maxStickyOffset: 200
        ))
    }

    // MARK: - pagePanShouldBegin

    @Test func `Page pan yields while the header is visible`() {
        #expect(!ScrollRules.pagePanShouldBegin(
            headerVisible: true, velocity: .zero, pageOffsetY: 0, pageTopY: 0
        ))
        #expect(!ScrollRules.pagePanShouldBegin(
            headerVisible: true, velocity: CGPoint(x: 2, y: -40), pageOffsetY: 0, pageTopY: 0
        ))
        // A clearly horizontal pan can stay with the page.
        #expect(ScrollRules.pagePanShouldBegin(
            headerVisible: true, velocity: CGPoint(x: 40, y: 2), pageOffsetY: 0, pageTopY: 0
        ))
    }

    @Test func `Page pan yields a pull-down at top`() {
        #expect(!ScrollRules.pagePanShouldBegin(
            headerVisible: false, velocity: CGPoint(x: 0, y: 30), pageOffsetY: 0, pageTopY: 0
        ))
        #expect(ScrollRules.pagePanShouldBegin(
            headerVisible: false, velocity: CGPoint(x: 0, y: -30), pageOffsetY: 0, pageTopY: 0
        ))
        // Scrolled page keeps a pull-down; the header waits until the page is at top.
        #expect(ScrollRules.pagePanShouldBegin(
            headerVisible: false, velocity: CGPoint(x: 0, y: 30), pageOffsetY: 80, pageTopY: 0
        ))
    }

    // MARK: - transferDrag

    @Test func `Transfer drag collapses the header before the page`() {
        let moved = ScrollRules.transferDrag(
            pageOffsetY: 40, pageStartY: 0, pageTopY: 0, outerStartY: 0, maxStickyOffset: 200
        )
        #expect(abs(moved.outerY - 40) < 0.01)
        #expect(abs(moved.pageY - 0) < 0.01)

        let handedOff = ScrollRules.transferDrag(
            pageOffsetY: 250, pageStartY: 0, pageTopY: 0, outerStartY: 0, maxStickyOffset: 200
        )
        #expect(abs(handedOff.outerY - 200) < 0.01)
        #expect(abs(handedOff.pageY - 50) < 0.01)
    }

    @Test func `Transfer drag expands the header on pull-down`() {
        let expanded = ScrollRules.transferDrag(
            pageOffsetY: -30, pageStartY: 0, pageTopY: 0, outerStartY: 80, maxStickyOffset: 200
        )
        #expect(abs(expanded.outerY - 50) < 0.01)
        #expect(abs(expanded.pageY - 0) < 0.01)
    }

    // MARK: - coasting

    @Test func `Coast distance decays in the finger direction`() {
        #expect(ScrollRules.coastDistance(velocity: 1000, decelerationRate: 0.998, time: 0) == 0)

        let opening = ScrollRules.coastDistance(velocity: 800, decelerationRate: 0.998, time: 0.25)
        #expect(opening > 0)
        #expect(opening < 800 * 0.25)

        let collapsing = ScrollRules.coastDistance(velocity: -800, decelerationRate: 0.998, time: 0.25)
        #expect(collapsing < 0)

        #expect(abs(ScrollRules.coastSpeed(velocity: 800, decelerationRate: 0.998, time: 0.5)) < 800)
    }

    // MARK: - linkedOffsets

    @Test func `Linked offsets are continuous across the boundary`() {
        // Header collapsing, then the page continues at the same rate.
        let inHeader = ScrollRules.linkedOffsets(
            fingerDown: -40, outerStartY: 0, pageStartY: 0, pageTopY: 0, maxStickyOffset: 200
        )
        #expect(abs(inHeader.outerY - 40) < 0.01)
        #expect(abs(inHeader.pageY - 0) < 0.01)

        let intoPage = ScrollRules.linkedOffsets(
            fingerDown: -250, outerStartY: 0, pageStartY: 0, pageTopY: 0, maxStickyOffset: 200
        )
        #expect(abs(intoPage.outerY - 200) < 0.01)
        #expect(abs(intoPage.pageY - 50) < 0.01)

        // Page scrolling back to its top, then the header opens with no jump.
        let inPage = ScrollRules.linkedOffsets(
            fingerDown: 40, outerStartY: 200, pageStartY: 100, pageTopY: 0, maxStickyOffset: 200
        )
        #expect(abs(inPage.outerY - 200) < 0.01)
        #expect(abs(inPage.pageY - 60) < 0.01)

        let atTop = ScrollRules.linkedOffsets(
            fingerDown: 100, outerStartY: 200, pageStartY: 100, pageTopY: 0, maxStickyOffset: 200
        )
        #expect(abs(atTop.outerY - 200) < 0.01)
        #expect(abs(atTop.pageY - 0) < 0.01)

        let intoHeader = ScrollRules.linkedOffsets(
            fingerDown: 130, outerStartY: 200, pageStartY: 100, pageTopY: 0, maxStickyOffset: 200
        )
        #expect(abs(intoHeader.outerY - 170) < 0.01)
        #expect(abs(intoHeader.pageY - 0) < 0.01)
    }

    // MARK: - pullTowardTop

    @Test func `Pull toward top scrolls the page before expanding the header`() {
        // Still inside the page: header stays collapsed, page moves toward its top.
        let inPage = ScrollRules.pullTowardTop(
            fingerDown: 40, outerStartY: 200, pageStartY: 100, pageTopY: 0, maxStickyOffset: 200
        )
        #expect(inPage != nil)
        #expect(abs(inPage!.outerY - 200) < 0.01)
        #expect(abs(inPage!.pageY - 60) < 0.01)

        // Just reached the top: header has not started expanding.
        let atTop = ScrollRules.pullTowardTop(
            fingerDown: 100, outerStartY: 200, pageStartY: 100, pageTopY: 0, maxStickyOffset: 200
        )
        #expect(atTop != nil)
        #expect(abs(atTop!.outerY - 200) < 0.01)
        #expect(abs(atTop!.pageY - 0) < 0.01)

        // Past the top: the leftover distance restores the header.
        let expanding = ScrollRules.pullTowardTop(
            fingerDown: 130, outerStartY: 200, pageStartY: 100, pageTopY: 0, maxStickyOffset: 200
        )
        #expect(expanding != nil)
        #expect(abs(expanding!.outerY - 170) < 0.01)
        #expect(abs(expanding!.pageY - 0) < 0.01)
    }

    @Test func `Pull toward top does not apply to other drags`() {
        #expect(ScrollRules.pullTowardTop(
            fingerDown: 40, outerStartY: 80, pageStartY: 100, pageTopY: 0, maxStickyOffset: 200
        ) == nil)
        #expect(ScrollRules.pullTowardTop(
            fingerDown: 40, outerStartY: 200, pageStartY: 0, pageTopY: 0, maxStickyOffset: 200
        ) == nil)
        #expect(ScrollRules.pullTowardTop(
            fingerDown: -20, outerStartY: 200, pageStartY: 100, pageTopY: 0, maxStickyOffset: 200
        ) == nil)
    }

    @Test func `page-top takeover keeps the leftover pull on the header`() {
        let outer = ScrollRules.outerOffsetAtPageTopTakeover(
            fingerDown: 58.3, pageStartY: 51.3, pageTopY: 0, maxStickyOffset: 230
        )
        #expect(abs(outer - 223.0) < 0.1)
        let stillInPage = ScrollRules.outerOffsetAtPageTopTakeover(
            fingerDown: 20, pageStartY: 51.3, pageTopY: 0, maxStickyOffset: 230
        )
        #expect(abs(stillInPage - 230) < 0.01)
    }
}
