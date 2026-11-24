import CoreGraphics
import Testing
@testable import SlidePager

@Suite(.tags(.scrollMath))
struct PagingIndicatorTrackerTests {
    private let width: CGFloat = 402
    private let resting: CGFloat = 402

    private func move(
        _ tracker: inout PagingIndicatorTracker,
        offset: CGFloat,
        selected: Int,
        fingerDown: Bool = false,
        interacting: Bool = true,
        pageCount: Int = 4
    ) -> PagingIndicatorTracker.Result {
        tracker.consume(
            offsetX: offset,
            oldOffsetX: nil,
            width: width,
            interacting: interacting,
            fingerDown: fingerDown,
            selectedIndex: selected,
            pageCount: pageCount
        )
    }

    @Test func `a forward swipe follows the page it started on`() {
        var tracker = PagingIndicatorTracker()
        _ = move(&tracker, offset: resting, selected: 0, interacting: false)

        let mid = move(&tracker, offset: resting + width * 0.5, selected: 0, fingerDown: true)
        #expect(mid == .follow(from: 0, to: 1, progress: 0.5))

        let almost = move(&tracker, offset: resting + width, selected: 0)
        #expect(almost == .follow(from: 0, to: 1, progress: 1))
    }

    @Test func `selection updating before the recenter does not advance the indicator an extra tab`() {
        var tracker = PagingIndicatorTracker()
        _ = move(&tracker, offset: resting, selected: 0, interacting: false)
        _ = move(&tracker, offset: resting + width * 0.67, selected: 0, fingerDown: true)
        _ = move(&tracker, offset: resting + width, selected: 0)

        // The page controller commits the new page while the scroll view is
        // still one page away from center. That sample must not start a swipe
        // from the page just selected.
        let late = move(&tracker, offset: resting + width, selected: 1)
        #expect(late == .follow(from: 0, to: 1, progress: 1))

        let jump = move(&tracker, offset: resting, selected: 1)
        #expect(jump == .recentered)

        let after = move(&tracker, offset: resting + 20, selected: 1)
        #expect(after == .unchanged)
    }

    @Test func `a reverse swipe does not jump back an extra tab when selection settles early`() {
        var tracker = PagingIndicatorTracker()
        _ = move(&tracker, offset: resting, selected: 2, interacting: false)
        _ = move(&tracker, offset: resting - width, selected: 2, fingerDown: true)

        let late = move(&tracker, offset: resting - width, selected: 1)
        #expect(late == .follow(from: 2, to: 1, progress: 1))

        let jump = move(&tracker, offset: resting, selected: 1)
        #expect(jump == .recentered)
    }

    @Test func `a new finger after recenter starts from the settled page`() {
        var tracker = PagingIndicatorTracker()
        _ = move(&tracker, offset: resting, selected: 0, interacting: false)
        _ = move(&tracker, offset: resting + width, selected: 0, fingerDown: true)
        _ = move(&tracker, offset: resting, selected: 1)

        let next = move(&tracker, offset: resting + width * 0.5, selected: 1, fingerDown: true)
        #expect(next == .follow(from: 1, to: 2, progress: 0.5))
    }

    @Test func `releasing back to the same page is not a recenter jump`() {
        var tracker = PagingIndicatorTracker()
        _ = move(&tracker, offset: resting, selected: 0, interacting: false)
        _ = move(&tracker, offset: resting + width * 0.4, selected: 0, fingerDown: true)
        let back = move(&tracker, offset: resting + width * 0.05, selected: 0)
        guard case .follow(let from, let to, let progress) = back else {
            Issue.record("expected a follow, got \(back)")
            return
        }
        #expect(from == 0)
        #expect(to == 1)
        #expect(abs(progress - 0.05) < 0.001)
    }
}
