import UIKit

/// A page whose primary scroll view participates in the sticky-header scroll
/// coordination.
///
/// Conform child view controllers that contain a `UITableView`,
/// `UICollectionView`, `UIScrollView`, or any `UIScrollView` subclass. The
/// container never replaces the scroll view's `UIScrollViewDelegate` or content
/// insets. It observes `contentOffset`, writes offsets back when the page is
/// not allowed to scroll, and coordinates pan ownership so a vertical drag on
/// the page collapses the header first.
///
/// Pages without scrollable content can simply omit conformance; the container
/// still allows the header to collapse from anywhere on those pages.
public protocol SlidePagerPage: UIViewController {
    /// The scroll view that should coordinate with the sticky header.
    ///
    /// Return `nil` while your scroll view does not exist yet; the container
    /// re-queries this property whenever the page becomes current.
    var pageScrollView: UIScrollView? { get }
}

/// The behavior contract the built-in tab bar — and any custom tab bar — must
/// provide. Tab bars are UIKit views, so every requirement runs on the main actor.
@MainActor
public protocol SlidePagerTabBar: AnyObject {
    /// The height the container should reserve for the tab bar.
    var preferredHeight: CGFloat { get }

    /// Called when the user taps a tab. The index is guaranteed valid.
    var onSelection: ((Int) -> Void)? { get set }

    /// Rebuilds the tab bar for the given titles.
    /// The container calls this once when it is configured.
    func reloadTabs(titles: [String])

    /// Moves the selection to `index`, optionally animating the indicator.
    func setSelectedIndex(_ index: Int, animated: Bool)

    /// Moves the indicator between two tabs while the user is swiping pages.
    ///
    /// `progress` is `0` at `from` and `1` at `to`. The default does nothing, so
    /// a custom tab bar can ignore interactive swipes and only implement
    /// `setSelectedIndex`.
    func setTransitionProgress(from: Int, to: Int, progress: CGFloat)
}

public extension SlidePagerTabBar {
    func setTransitionProgress(from: Int, to: Int, progress: CGFloat) {}
}

/// A concrete view that satisfies `SlidePagerTabBar`.
public typealias SlidePagerTabBarView = UIView & SlidePagerTabBar

/// Observes tab selections, page transitions, and sticky-header state.
/// Callbacks are delivered on the main actor, from the pager's view controller.
@MainActor
public protocol SlidePagerDelegate: AnyObject {
    /// The user tapped a tab.
    func slidePager(_ pager: SlidePagerViewController, didSelectTabAt index: Int)

    /// A page transition (swipe, tab tap, or programmatic call) settled on a
    /// new page.
    func slidePager(_ pager: SlidePagerViewController, didTransitionToPageAt index: Int)

    /// The sticky state changed. Fires continuously while the header collapses
    /// or expands, which makes it convenient for parallax effects.
    func slidePager(_ pager: SlidePagerViewController, didChangeStickyState state: StickyState)
}

public extension SlidePagerDelegate {
    func slidePager(_ pager: SlidePagerViewController, didSelectTabAt index: Int) {}
    func slidePager(_ pager: SlidePagerViewController, didTransitionToPageAt index: Int) {}
    func slidePager(_ pager: SlidePagerViewController, didChangeStickyState state: StickyState) {}
}
