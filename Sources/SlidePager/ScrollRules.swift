import CoreGraphics

/// The pure decision table for the nested-scroll coordinator.
///
/// Two invariants define the entire system:
///
/// 1. While the header is (even partly) visible, the current page's scroll
///    view sits at its top resting offset — the outer scroll view owns the
///    vertical pan.
/// 2. While the current page is scrolled beyond its top, the outer scroll view
///    sits exactly at the sticky offset (tabs pinned) — the page owns the
///    vertical pan.
///
/// Both pans are recognized together when UIKit allows it (see
/// `StickyScrollView`). When a drag starts inside `UIPageViewController`, the
/// page pan often tracks alone — `transferDrag` then moves the header by the
/// same distance the page tried to scroll.
enum ScrollRules {
    /// Tolerance for floating-point scroll offsets.
    static let epsilon: CGFloat = 0.5

    /// Flicks slower than this (points per second) do not coast.
    static let minimumCoastSpeed: CGFloat = 50

    /// Distance a finger-direction velocity coasts in `time` seconds.
    ///
    /// Matches `UIScrollView`: speed is multiplied by `decelerationRate` every
    /// millisecond. Positive velocity moves the finger down (header expands).
    static func coastDistance(velocity: CGFloat, decelerationRate: CGFloat, time: CGFloat) -> CGFloat {
        guard abs(velocity) > 0, decelerationRate > 0, decelerationRate < 1, time > 0 else { return 0 }
        let lnRate = log(decelerationRate)
        guard lnRate < -0.000_001 else { return velocity * time }
        return velocity * (pow(decelerationRate, 1000 * time) - 1) / (1000 * lnRate)
    }

    /// Remaining finger-direction speed after coasting for `time` seconds.
    static func coastSpeed(velocity: CGFloat, decelerationRate: CGFloat, time: CGFloat) -> CGFloat {
        guard decelerationRate > 0, time >= 0 else { return 0 }
        return velocity * pow(decelerationRate, 1000 * time)
    }

    /// `true` when a pan is clearly horizontal, so it belongs to paging rather
    /// than the sticky header. A zero velocity is not horizontal.
    static func isPredominantlyHorizontal(_ velocity: CGPoint) -> Bool {
        abs(velocity.x) > abs(velocity.y)
    }

    /// Whether a page scroll view's pan may begin.
    ///
    /// While the header is visible, a vertical drag must fail here so the outer
    /// scroll view can collapse it. A downward drag at the top of a page must
    /// also fail so the outer scroll view can expand the header.
    static func pagePanShouldBegin(
        headerVisible: Bool,
        velocity: CGPoint,
        pageOffsetY: CGFloat,
        pageTopY: CGFloat
    ) -> Bool {
        if headerVisible && !isPredominantlyHorizontal(velocity) {
            return false
        }
        let pullingDown = velocity.y > epsilon && !isPredominantlyHorizontal(velocity)
        let atTop = pageOffsetY <= pageTopY + epsilon
        if pullingDown && atTop {
            return false
        }
        return true
    }

    /// Where the outer scroll view and the page should sit after a page pan
    /// has applied `pageOffsetY`, given where both were when the drag began.
    ///
    /// `pageOffsetY - pageStartY` is the finger translation the page pan
    /// applied. That translation collapses the header first, then scrolls the
    /// page; a pull-down gives any remaining distance back to the header.
    static func transferDrag(
        pageOffsetY: CGFloat,
        pageStartY: CGFloat,
        pageTopY: CGFloat,
        outerStartY: CGFloat,
        maxStickyOffset: CGFloat
    ) -> (outerY: CGFloat, pageY: CGFloat) {
        guard maxStickyOffset > epsilon else {
            return (outerStartY, pageOffsetY)
        }
        let translation = pageOffsetY - pageStartY
        if translation >= 0 {
            let desiredOuter = outerStartY + translation
            if desiredOuter <= maxStickyOffset {
                return (desiredOuter, pageStartY)
            }
            return (maxStickyOffset, pageStartY + desiredOuter - maxStickyOffset)
        }
        let pageCanGive = max(0, pageStartY - pageTopY)
        let pull = -translation
        if pull <= pageCanGive {
            return (outerStartY, pageOffsetY)
        }
        let desiredOuter = outerStartY - (pull - pageCanGive)
        if desiredOuter >= 0 {
            return (desiredOuter, pageTopY)
        }
        // Fully expanded: leftover pull is a page bounce.
        return (0, pageTopY + desiredOuter)
    }

    /// One continuous position for a drag that crosses the header/page boundary.
    ///
    /// `fingerDown` is how far the finger has moved down since the drag's origin.
    /// The header consumes movement until it is fully collapsed; the page consumes
    /// the rest. The mapping is 1:1 with the finger, so the handoff does not
    /// stutter the way a rubber-band transfer does.
    static func linkedOffsets(
        fingerDown: CGFloat,
        outerStartY: CGFloat,
        pageStartY: CGFloat,
        pageTopY: CGFloat,
        maxStickyOffset: CGFloat
    ) -> (outerY: CGFloat, pageY: CGFloat) {
        let pageTravel = max(0, pageStartY - pageTopY)
        let combined = outerStartY + pageTravel - fingerDown
        if combined <= 0 {
            return (0, pageTopY)
        }
        if combined <= maxStickyOffset {
            return (combined, pageTopY)
        }
        return (maxStickyOffset, pageTopY + combined - maxStickyOffset)
    }

    /// A pull that started with the header collapsed and the page scrolled.
    ///
    /// The page keeps the drag until it reaches its top. Only the distance past
    /// that top expands the header. Returns nil for any other drag (header
    /// already visible, page already at top, or the finger is not pulling
    /// toward the top).
    static func pullTowardTop(
        fingerDown: CGFloat,
        outerStartY: CGFloat,
        pageStartY: CGFloat,
        pageTopY: CGFloat,
        maxStickyOffset: CGFloat
    ) -> (outerY: CGFloat, pageY: CGFloat)? {
        guard outerStartY >= maxStickyOffset - epsilon else { return nil }
        let pageCanGive = max(0, pageStartY - pageTopY)
        guard pageCanGive > epsilon, fingerDown > epsilon else { return nil }
        if fingerDown <= pageCanGive {
            return (maxStickyOffset, pageStartY - fingerDown)
        }
        let expand = fingerDown - pageCanGive
        return (max(0, outerStartY - expand), pageTopY)
    }

    /// Header offset when a pull-down first reaches the page top.
    ///
    /// The distance already past the top must move the header immediately.
    /// Dropping it makes the next pull-down hitch for a frame.
    static func outerOffsetAtPageTopTakeover(
        fingerDown: CGFloat,
        pageStartY: CGFloat,
        pageTopY: CGFloat,
        maxStickyOffset: CGFloat
    ) -> CGFloat {
        let pageCanGive = max(0, pageStartY - pageTopY)
        let leftover = max(0, fingerDown - pageCanGive)
        return max(0, maxStickyOffset - leftover)
    }

    /// `true` when the page must be held at its top resting offset because the
    /// header is still (at least partly) visible.
    ///
    /// The outer scroll view is allowed to rubber-band past the sticky offset
    /// (native bounce); while it is *below* the sticky offset the header is
    /// visible and the page is pinned.
    static func pageMustHoldTop(outerOffsetY: CGFloat, maxStickyOffset: CGFloat) -> Bool {
        outerOffsetY < maxStickyOffset - epsilon
    }

    /// `true` when the outer scroll view must be held at the sticky offset
    /// because the current page is scrolled beyond its top.
    static func outerMustHoldSticky(
        pageOffsetY: CGFloat,
        pageTopOffsetY: CGFloat,
        outerOffsetY: CGFloat,
        maxStickyOffset: CGFloat
    ) -> Bool {
        let pageBelowTop = pageOffsetY > pageTopOffsetY + epsilon
        return pageBelowTop && abs(outerOffsetY - maxStickyOffset) > epsilon
    }
}
