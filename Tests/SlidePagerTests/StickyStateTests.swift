import CoreGraphics
import Foundation
import Testing
@testable import SlidePager

/// One `StickyState.resolve` case: raw inputs plus the expected state.
/// `StickyState` itself is not Sendable, and parameterized arguments must be,
/// so the expectation is carried by this Sendable mirror.
struct ResolveCase: Sendable {
    enum Expected: Sendable {
        case expanded
        case partial(CGFloat)
        case collapsed

        var state: StickyState {
            switch self {
            case .expanded: return .expanded
            case .partial(let progress): return .partiallyCollapsed(progress: progress)
            case .collapsed: return .collapsed
            }
        }
    }

    let collapse: CGFloat
    let maxSticky: CGFloat
    let expected: Expected

    init(_ collapse: CGFloat, _ maxSticky: CGFloat, _ expected: Expected) {
        self.collapse = collapse
        self.maxSticky = maxSticky
        self.expected = expected
    }
}

/// Collapse-state resolution, parameterized over representative values and
/// exact epsilon boundaries.
@Suite(.tags(.scrollMath))
struct StickyStateTests {

    @Test("resolve maps collapse onto states", arguments: [
        // Expanded: zero or within epsilon of zero (including top bounce).
        ResolveCase(0, 200, .expanded),
        ResolveCase(0.4, 200, .expanded),
        ResolveCase(0.5, 200, .expanded),       // == epsilon is still expanded
        ResolveCase(-30, 200, .expanded),       // top bounce
        ResolveCase(-40, 200, .expanded),
        // Partial: strict interior, progress == collapse / max.
        ResolveCase(100, 200, .partial(0.5)),
        ResolveCase(150, 200, .partial(0.75)),
        ResolveCase(50, 200, .partial(0.25)),
        ResolveCase(1, 3, .partial(1.0 / 3.0)),
        // Collapsed: within epsilon of the max, overshoot clamps.
        ResolveCase(199.5, 200, .collapsed),
        ResolveCase(200, 200, .collapsed),
        ResolveCase(230, 200, .collapsed),      // bottom rubber-band clamps
        ResolveCase(999, 200, .collapsed),
        // Degenerate range (max <= epsilon) is always collapsed.
        ResolveCase(0, 0, .collapsed),
        ResolveCase(0, 0.4, .collapsed),
        ResolveCase(2, 1, .collapsed),
        ResolveCase(10, 3, .collapsed),
    ])
    func resolveClassification(of testCase: ResolveCase) {
        let resolved = StickyState.resolve(
            collapse: testCase.collapse, maxStickyOffset: testCase.maxSticky
        )
        #expect(resolved == testCase.expected.state)
    }

    @Test("progress is exact for each case", arguments: [
        (ResolveCase.Expected.expanded, CGFloat(0)),
        (.partial(0.3), 0.3),
        (.collapsed, 1),
    ])
    func progressIsExact(expected: ResolveCase.Expected, progress: CGFloat) {
        #expect(expected.state.progress == progress)
    }
}
