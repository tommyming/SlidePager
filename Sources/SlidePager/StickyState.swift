import CoreGraphics
import Foundation

/// The collapse state of the header.
public enum StickyState: Equatable {
    /// The header is fully visible (`progress == 0`).
    case expanded
    /// The header is somewhere between fully visible and pinned
    /// (`progress` in `0...1`).
    case partiallyCollapsed(progress: CGFloat)
    /// The header is fully collapsed and the tab bar is pinned.
    case collapsed

    /// `0` when expanded, `1` when collapsed.
    public var progress: CGFloat {
        switch self {
        case .expanded: return 0
        case .partiallyCollapsed(let progress): return progress
        case .collapsed: return 1
        }
    }

    /// Resolves raw scroll geometry into a sticky state.
    static func resolve(collapse: CGFloat, maxStickyOffset: CGFloat) -> StickyState {
        guard maxStickyOffset > ScrollRules.epsilon else { return .collapsed }
        let clamped = min(max(0, collapse), maxStickyOffset)
        if clamped <= ScrollRules.epsilon { return .expanded }
        if clamped >= maxStickyOffset - ScrollRules.epsilon { return .collapsed }
        return .partiallyCollapsed(progress: clamped / maxStickyOffset)
    }
}
