import CoreGraphics

/// Decides how the tab indicator should move while `UIPageViewController` scrolls.
///
/// The page controller reports the new page — and the container updates
/// `selectedIndex` — while its scroll view is still sitting a full page away
/// from the resting offset. A later sample of that same offset must not be
/// read as a new swipe that starts at the page just selected. After the
/// controller jumps the scroll view back to center, further samples are
/// ignored until the gesture ends.
struct PagingIndicatorTracker: Equatable {
    private(set) var restingOffsetX: CGFloat?
    private var lastProgress: CGFloat = 0
    private var originIndex: Int?
    private var suppressFollow = false

    enum Result: Equatable {
        /// The scroll view is at rest. Sync the selection from the visible page.
        case resting
        /// The page controller recentered. Pin the indicator to the landed page.
        case recentered
        /// Slide the indicator from `from` toward `to`. `progress` is 0...1.
        case follow(from: Int, to: Int, progress: CGFloat)
        /// Interacting, but the indicator should stay where it is.
        case unchanged
    }

    mutating func consume(
        offsetX: CGFloat,
        oldOffsetX: CGFloat?,
        width: CGFloat,
        interacting: Bool,
        fingerDown: Bool,
        selectedIndex: Int,
        pageCount: Int
    ) -> Result {
        guard width > 1, pageCount > 0 else { return .unchanged }
        if !interacting {
            restingOffsetX = offsetX
            lastProgress = 0
            originIndex = nil
            suppressFollow = false
            return .resting
        }
        // A new finger starts a new gesture, even if the previous recenter
        // has not yet been followed by a resting sample.
        if fingerDown {
            suppressFollow = false
        }
        // Capture the page this gesture started on only while following it.
        // A sample after the recenter must not adopt the page just selected.
        if !suppressFollow, originIndex == nil {
            originIndex = selectedIndex
        }
        if restingOffsetX == nil {
            restingOffsetX = oldOffsetX ?? offsetX
        }
        let resting = restingOffsetX ?? width
        let progress = (offsetX - resting) / width
        // The page controller jumps the scroll view back to center when a
        // swipe completes. That is not the user dragging back.
        if abs(progress) < 0.05, abs(progress - lastProgress) > 0.5 {
            lastProgress = 0
            originIndex = nil
            suppressFollow = true
            return .recentered
        }
        guard !suppressFollow else { return .unchanged }
        lastProgress = progress
        guard abs(progress) > 0.001 else { return .unchanged }
        let from = originIndex ?? selectedIndex
        let forward = progress > 0
        let to = forward ? min(pageCount - 1, from + 1) : max(0, from - 1)
        guard to != from, pagesContain(from, to, pageCount: pageCount) else { return .unchanged }
        return .follow(from: from, to: to, progress: min(1, abs(progress)))
    }

    private func pagesContain(_ from: Int, _ to: Int, pageCount: Int) -> Bool {
        (0..<pageCount).contains(from) && (0..<pageCount).contains(to)
    }
}
