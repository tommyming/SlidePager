import ObjectiveC
import UIKit

/// The outer, vertical scroll view that hosts the header, tab bar, and pages.
///
/// Two hooks make a drag that starts inside `UIPageViewController` collapse
/// the header:
///
/// - `gestureRecognizerShouldBegin(_:)` ignores predominantly horizontal pans
///   so page swipes stay with the page view controller. It does *not* defer to
///   `UIScrollView`'s implementation: that returns false when the touch is
///   inside a descendant scroll view, which is exactly this drag.
/// - Failure requirements against other pans are refused. `UIScrollViewPanGestureRecognizer`
///   otherwise forces the outer pan to wait for the page controller's pan,
///   and that pan never fails for a vertical drag — so the header never moves.
///   `StickyPanBypass` does the same for the private pan subclass, which
///   ignores the delegate.
final class StickyScrollView: UIScrollView, UIGestureRecognizerDelegate {
    override init(frame: CGRect) {
        super.init(frame: frame)
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        alwaysBounceVertical = true
        isDirectionalLockEnabled = true
        // Don't hold touches while deciding to scroll. The page controller's
        // own scroll view already delays them; delaying again drops the
        // vertical drag that should collapse the header.
        delaysContentTouches = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGestureRecognizer else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        let velocity = panGestureRecognizer.velocity(in: self)
        if ScrollRules.isPredominantlyHorizontal(velocity) { return false }
        // A scrolled page must pan like a normal scroll view. Starting the
        // outer pan here moves the page under the finger and the content jumps.
        if let allowsVerticalPan, !allowsVerticalPan(velocity) { return false }
        return true
    }

    /// Return false when a vertical pan should be left to the current page.
    var allowsVerticalPan: ((CGPoint) -> Bool)?

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard gestureRecognizer === panGestureRecognizer else { return false }
        return otherGestureRecognizer is UIPanGestureRecognizer
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }
}

/// A vertical pan attached to the page area. It drives header collapse when a
/// drag starts on `UIPageViewController` and the outer scroll view's own pan
/// does not get the touch.
///
/// Recognizes alongside the page controller's pan. A clearly horizontal
/// translation cancels it so paging is left alone.
final class HeaderCollapsePan: UIPanGestureRecognizer, UIGestureRecognizerDelegate {
    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        delegate = self
        name = StickyPanBypass.collapsePanName
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        !ScrollRules.isPredominantlyHorizontal(velocity(in: view))
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    func cancelForPaging() {
        state = .cancelled
    }
}

/// Stops `UIScrollView`'s private pan subclass from installing a failure
/// requirement between the outer sticky pan and a page / page-controller pan.
///
/// The delegate methods above are not enough: the pan subclass implements
/// `shouldRequireFailureOfGestureRecognizer:` itself, and a YES from a
/// subclass is guaranteed to create the requirement even when both delegates
/// return NO. The hook calls through for every other pair of recognizers.
/// Box stored on a page or paging scroll view. The scroll view must stay the
/// delegate of its own pan (UIKit asserts otherwise), so the yield decision
/// is consulted from a hooked `gestureRecognizerShouldBegin` instead.
final class PanBeginPolicy: NSObject {
    let shouldBegin: (UIPanGestureRecognizer) -> Bool
    init(_ shouldBegin: @escaping (UIPanGestureRecognizer) -> Bool) {
        self.shouldBegin = shouldBegin
    }
}

enum StickyPanBypass {
    static let collapsePanName = "SlidePager.headerCollapse"
    @MainActor private static var failureHookInstalled = false
    @MainActor private static var hookedShouldBegin = Set<ObjectIdentifier>()
    // Address is the associated-object key. The stored 0 is never written.
    // The gesture hook reads it synchronously, so it cannot hop to the main actor.
    nonisolated(unsafe) private static var policyKey: UInt8 = 0
    private typealias FailureIMP = @convention(c) (Any, Selector, UIGestureRecognizer) -> Bool
    private typealias ShouldBeginIMP = @convention(c) (Any, Selector, UIGestureRecognizer) -> Bool

    @MainActor
    static func install(for pan: UIPanGestureRecognizer) {
        guard !failureHookInstalled else { return }
        failureHookInstalled = true
        let cls: AnyClass = type(of: pan)
        hookFailure(cls, NSSelectorFromString("shouldRequireFailureOfGestureRecognizer:"))
        hookFailure(cls, NSSelectorFromString("shouldBeRequiredToFailByGestureRecognizer:"))
    }

    /// `shouldBegin` returning false keeps that scroll view's pan from claiming
    /// a vertical drag. The scroll view remains its pan's delegate.
    @MainActor
    static func setPolicy(on scrollView: UIScrollView, _ shouldBegin: @escaping (UIPanGestureRecognizer) -> Bool) {
        objc_setAssociatedObject(
            scrollView,
            &policyKey,
            PanBeginPolicy(shouldBegin),
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        hookShouldBegin(UIScrollView.self)
        hookShouldBeginIfOverridden(type(of: scrollView))
    }

    @MainActor
    private static func hookShouldBegin(_ cls: AnyClass) {
        let sel = #selector(UIGestureRecognizerDelegate.gestureRecognizerShouldBegin(_:))
        guard let method = class_getInstanceMethod(cls, sel) else { return }
        replaceShouldBegin(method, selector: sel, owner: ObjectIdentifier(cls))
    }

    /// Hooks `cls` only when it implements `gestureRecognizerShouldBegin` itself.
    /// Inherited implementations are already covered by the `UIScrollView` hook.
    @MainActor
    private static func hookShouldBeginIfOverridden(_ cls: AnyClass) {
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(cls, &count) else { return }
        defer { free(methods) }
        let sel = #selector(UIGestureRecognizerDelegate.gestureRecognizerShouldBegin(_:))
        for index in 0..<Int(count) where method_getName(methods[index]) == sel {
            replaceShouldBegin(methods[index], selector: sel, owner: ObjectIdentifier(cls))
            return
        }
    }

    @MainActor
    private static func replaceShouldBegin(_ method: Method, selector: Selector, owner: ObjectIdentifier) {
        guard hookedShouldBegin.insert(owner).inserted else { return }
        let original = unsafeBitCast(method_getImplementation(method), to: ShouldBeginIMP.self)
        let block: @convention(block) (Any, UIGestureRecognizer) -> Bool = { object, gesture in
            if let scrollView = object as? UIScrollView,
               gesture === scrollView.panGestureRecognizer,
               let policy = objc_getAssociatedObject(scrollView, &policyKey) as? PanBeginPolicy,
               let pan = gesture as? UIPanGestureRecognizer,
               !policy.shouldBegin(pan) {
                return false
            }
            return original(object, selector, gesture)
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    private static func hookFailure(_ cls: AnyClass, _ selector: Selector) {
        guard let method = class_getInstanceMethod(cls, selector) else { return }
        let original = unsafeBitCast(method_getImplementation(method), to: FailureIMP.self)
        let block: @convention(block) (Any, UIGestureRecognizer) -> Bool = { object, other in
            let gesture = object as! UIGestureRecognizer
            if shouldYield(gesture, other) { return false }
            return original(object, selector, other)
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    /// `true` when one recognizer is the outer sticky pan and the other is a
    /// pan, so neither should be required to fail before the header can move.
    private static func shouldYield(_ a: UIGestureRecognizer, _ b: UIGestureRecognizer) -> Bool {
        // Gesture hooks run synchronously on the main thread.
        MainActor.assumeIsolated {
            if a.name == collapsePanName || b.name == collapsePanName { return true }
            let aOuter = a.view is StickyScrollView
            let bOuter = b.view is StickyScrollView
            guard aOuter != bOuter else { return false }
            let inner = aOuter ? b : a
            return inner is UIPanGestureRecognizer
        }
    }
}
