import UIKit
import Testing
@testable import SlidePager

/// The gesture hooks that make nested-scroll coordination possible.
@MainActor
@Suite(.tags(.uiKitHeadless))
struct StickyScrollViewTests {

    @Test("configuration matches the coordination contract")
    func configuration() {
        let scrollView = StickyScrollView()
        #expect(!scrollView.showsVerticalScrollIndicator)
        #expect(!scrollView.showsHorizontalScrollIndicator)
        #expect(scrollView.contentInsetAdjustmentBehavior == .never)
        #expect(scrollView.alwaysBounceVertical)
        #expect(scrollView.isDirectionalLockEnabled)
        #expect(!scrollView.delaysContentTouches)
    }

    @Test("a pan with no policy may begin")
    func panBeginsWithoutPolicy() {
        let scrollView = StickyScrollView()
        // Zero velocity (no touch) is not horizontal, so it passes the guard.
        #expect(scrollView.gestureRecognizerShouldBegin(scrollView.panGestureRecognizer))
    }

    @Test("the vertical-pan policy is consulted")
    func policyIsConsulted() {
        let scrollView = StickyScrollView()
        var consulted = false
        scrollView.allowsVerticalPan = { _ in
            consulted = true
            return false
        }
        #expect(!scrollView.gestureRecognizerShouldBegin(scrollView.panGestureRecognizer))
        #expect(consulted)

        scrollView.allowsVerticalPan = { _ in true }
        #expect(scrollView.gestureRecognizerShouldBegin(scrollView.panGestureRecognizer))
    }

    @Test("recognizes simultaneously with pans only")
    func simultaneousRecognition() {
        let scrollView = StickyScrollView()
        let pan = scrollView.panGestureRecognizer

        #expect(scrollView.gestureRecognizer(pan, shouldRecognizeSimultaneouslyWith: UIPanGestureRecognizer()))
        #expect(!scrollView.gestureRecognizer(pan, shouldRecognizeSimultaneouslyWith: UITapGestureRecognizer()))
        // Only the outer pan is allowed a say; other recognizers get no relay.
        #expect(!scrollView.gestureRecognizer(
            UITapGestureRecognizer(), shouldRecognizeSimultaneouslyWith: pan
        ))
    }

    @Test("never requires other recognizers to fail")
    func noFailureRequirements() {
        let scrollView = StickyScrollView()
        let pan = scrollView.panGestureRecognizer
        let other = UIPanGestureRecognizer()

        #expect(!scrollView.gestureRecognizer(pan, shouldRequireFailureOf: other))
        #expect(!scrollView.gestureRecognizer(pan, shouldBeRequiredToFailBy: other))
    }

    @Test("the collapse pan is simultaneous and vertically biased")
    func collapsePanBehavior() {
        let view = UIView()
        let pan = HeaderCollapsePan(target: nil, action: nil)
        view.addGestureRecognizer(pan)

        #expect(pan.name == StickyPanBypass.collapsePanName)
        // Zero velocity (no touch yet) is not horizontal, so it may begin.
        #expect(pan.gestureRecognizerShouldBegin(pan))
        #expect(pan.gestureRecognizer(pan, shouldRecognizeSimultaneouslyWith: UIPanGestureRecognizer()))
    }
}
