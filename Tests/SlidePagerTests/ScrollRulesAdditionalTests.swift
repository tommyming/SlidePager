import CoreGraphics
import Foundation
import Testing
@testable import SlidePager

/// Edge cases beyond the happy paths in `ScrollRulesTests`: invalid inputs,
/// epsilon boundaries, and degenerate geometry.
@Suite(.tags(.scrollMath))
struct ScrollRulesAdditionalTests {

    // MARK: - isPredominantlyHorizontal

    @Test("a pan needs a strict horizontal majority", arguments: [
        CGPoint.zero,
        CGPoint(x: 10, y: 10),
        CGPoint(x: -10, y: 10),
        CGPoint(x: 0, y: 40),
    ])
    func notPredominantlyHorizontal(velocity: CGPoint) {
        #expect(!ScrollRules.isPredominantlyHorizontal(velocity))
    }

    @Test("a clear horizontal majority counts as horizontal", arguments: [
        CGPoint(x: 10, y: 0),
        CGPoint(x: -40, y: 10),
        CGPoint(x: 3, y: -2),
    ])
    func predominantlyHorizontal(velocity: CGPoint) {
        #expect(ScrollRules.isPredominantlyHorizontal(velocity))
    }

    // MARK: - coastDistance / coastSpeed

    @Test("invalid coast inputs cover zero distance", arguments: [
        (CGFloat(0), 0.998, 1),    // zero velocity
        (100, 0, 1),               // deceleration rate 0
        (100, 1, 1),               // no decay at all is rejected
        (100, -0.5, 1),            // negative rate
        (100, 0.998, -1),          // negative time
        (100, 0.998, 0),           // zero time
    ])
    func coastDistanceRejectsInvalidInput(velocity: CGFloat, rate: CGFloat, time: CGFloat) {
        #expect(ScrollRules.coastDistance(velocity: velocity, decelerationRate: rate, time: time) == 0)
    }

    @Test("a deceleration rate within float noise of 1 coasts linearly")
    func coastDistanceNearOneRate() {
        // log(rate) is greater than the -1e-6 guard, so the linear path runs.
        #expect(ScrollRules.coastDistance(velocity: 100, decelerationRate: 0.999_999_9, time: 2) == 200)
    }

    @Test("distance accumulates while speed decays")
    func coastAccumulates() {
        let quarter = abs(ScrollRules.coastDistance(velocity: 900, decelerationRate: 0.998, time: 0.25))
        let half = abs(ScrollRules.coastDistance(velocity: 900, decelerationRate: 0.998, time: 0.5))
        #expect(half > quarter)

        #expect(ScrollRules.coastSpeed(velocity: 900, decelerationRate: 0.998, time: 0) == 900)
        #expect(ScrollRules.coastSpeed(velocity: 900, decelerationRate: 0.998, time: 0.5) < 900)
    }

    @Test("coast speed rejects invalid inputs", arguments: [
        (CGFloat(800), CGFloat(0)),
        (800, -1),
    ])
    func coastSpeedRejectsInvalidInput(velocity: CGFloat, rate: CGFloat) {
        #expect(ScrollRules.coastSpeed(velocity: velocity, decelerationRate: rate, time: 0.25) == 0)
    }

    // MARK: - transferDrag

    @Test("no sticky range passes the page offset straight through")
    func transferDragDegenerate() {
        let moved = ScrollRules.transferDrag(
            pageOffsetY: 33, pageStartY: 10, pageTopY: 0, outerStartY: 77, maxStickyOffset: 0
        )
        #expect(moved.outerY == 77)
        #expect(moved.pageY == 33)
    }

    @Test("a pull that fully opens the header leaves the rest as page bounce")
    func transferDragPullPastFullyOpen() {
        // Pulling down 30 from a header that is 80 collapsed expands to 50.
        let expanding = ScrollRules.transferDrag(
            pageOffsetY: -30, pageStartY: 0, pageTopY: 0, outerStartY: 80, maxStickyOffset: 200
        )
        #expect(expanding.outerY == 50)
        #expect(expanding.pageY == 0)

        // Only 30 of collapse was left; the leftover 30 becomes a page top-bounce.
        let bouncing = ScrollRules.transferDrag(
            pageOffsetY: -40, pageStartY: 0, pageTopY: 0, outerStartY: 30, maxStickyOffset: 200
        )
        #expect(bouncing.outerY == 0)
        #expect(bouncing.pageY == -10)
    }

    // MARK: - linkedOffsets

    @Test("expanding past fully open holds the header at zero")
    func linkedOffsetsFullyOpen() {
        let open = ScrollRules.linkedOffsets(
            fingerDown: 400, outerStartY: 200, pageStartY: 100, pageTopY: 0, maxStickyOffset: 200
        )
        #expect(open.outerY == 0)
        #expect(open.pageY == 0)
    }

    // MARK: - pagePanShouldBegin

    @Test("a pull-down slower than epsilon lets the page pan begin")
    func slowPullDownStillBegins() {
        #expect(ScrollRules.pagePanShouldBegin(
            headerVisible: false, velocity: CGPoint(x: 0, y: 0.3), pageOffsetY: 0, pageTopY: 0
        ))
    }

    @Test("at-top uses the epsilon tolerance")
    func atTopTolerance() {
        // 0.3 past the top still counts as "at top", so the pull-down yields.
        #expect(!ScrollRules.pagePanShouldBegin(
            headerVisible: false, velocity: CGPoint(x: 0, y: 30), pageOffsetY: 0.3, pageTopY: 0
        ))
        // 0.6 past the top is beyond the tolerance, so the page keeps the pan.
        #expect(ScrollRules.pagePanShouldBegin(
            headerVisible: false, velocity: CGPoint(x: 0, y: 30), pageOffsetY: 0.6, pageTopY: 0
        ))
    }

    // MARK: - hold rules

    @Test("pageMustHoldTop flips exactly epsilon before the sticky point", arguments: [
        (CGFloat(199.4), true),
        (199.5, false),
        (199.6, false),
    ])
    func holdTopBoundary(outerY: CGFloat, expected: Bool) {
        #expect(ScrollRules.pageMustHoldTop(outerOffsetY: outerY, maxStickyOffset: 200) == expected)
    }

    @Test("the outer within epsilon of the sticky offset is already holding")
    func outerHoldEpsilon() {
        #expect(!ScrollRules.outerMustHoldSticky(
            pageOffsetY: 120, pageTopOffsetY: 0, outerOffsetY: 200.4, maxStickyOffset: 200
        ))
        #expect(ScrollRules.outerMustHoldSticky(
            pageOffsetY: 120, pageTopOffsetY: 0, outerOffsetY: 199, maxStickyOffset: 200
        ))
        // A page within epsilon of its top is not "below top".
        #expect(!ScrollRules.outerMustHoldSticky(
            pageOffsetY: 0.3, pageTopOffsetY: 0, outerOffsetY: 100, maxStickyOffset: 200
        ))
    }
}
