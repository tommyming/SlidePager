import UIKit

/// A sticky-header, tabbed, paged container view controller.
///
/// Everything lives inside one vertical `UIScrollView` (the "outer scroll
/// view"):
///
/// ```
/// ┌──────────────────────────┐
/// │  header view             │  scrolls away; collapses fully
/// │  tab bar                 │  pins below the top safe-area inset
/// │  ┌────────────────────┐  │
/// │  │ UIPageViewController│ │  horizontal, scroll style; full height
/// │  └────────────────────┘  │
/// └──────────────────────────┘
/// ```
///
/// Scroll coordination uses the simultaneous-gesture + "who is allowed to
/// scroll" technique: the outer scroll view recognizes pan gestures
/// simultaneously with the pages' scroll views, and `ScrollRules` decides
/// which of the two may move, pinning the other one. A drag that starts on
/// the page view controller is handed to the outer scroll view first — the
/// page controller's pan would otherwise claim it and the header would not
/// collapse. See README for the exact behavior contract.
///
/// The header is completely independent of horizontal page changes: switching
/// pages never moves the header, and the incoming page is synced to the
/// current collapse amount so nothing jumps.
open class SlidePagerViewController: UIViewController {

    // MARK: - Public state
    //
    // These properties are `open` so a client module can read, override, and
    // configure them. Assignment applies the change; call through to `super`
    // when overriding.

    /// The child view controllers, in tab order.
    ///
    /// Assigning replaces the pages and reloads the tab bar. The array must
    /// not be empty. The current index is kept when it is still valid, and
    /// clamped otherwise.
    open var pages: [UIViewController] {
        get { _pages }
        set { configurePages(newValue) }
    }

    /// The index of the currently displayed page.
    ///
    /// Assigning selects that page without animation, the same as
    /// `selectPage(at:animated:)` with `animated: false`. An index outside
    /// `pages` is ignored.
    open var selectedIndex: Int {
        get { _selectedIndex }
        set { configureSelectedIndex(newValue) }
    }

    /// The current sticky state of the header.
    ///
    /// Assigning scrolls the header to that collapse. `.expanded` opens it,
    /// `.collapsed` pins the tab bar, and `.partiallyCollapsed` stops in
    /// between.
    open var stickyState: StickyState {
        get { _stickyState }
        set { configureStickyState(newValue) }
    }

    /// Optional observer for tab, page, and sticky events.
    open weak var delegate: SlidePagerDelegate?

    /// The header view, if one was provided.
    ///
    /// Assigning installs the new view above the tab bar. Pass `nil` to remove
    /// the header.
    open var headerView: UIView? {
        get { _headerView }
        set { setHeaderView(newValue) }
    }

    /// The tab bar view.
    ///
    /// Assigning installs the new bar, reloads titles from `pages`, and keeps
    /// the current selection.
    open var tabBarView: SlidePagerTabBarView {
        get { _tabBar }
        set { setTabBarView(newValue) }
    }

    /// The current header height, resolved from `updateHeaderHeight(_:animated:)`
    /// or the header's fitting size.
    ///
    /// Assigning sets an explicit height without animation, the same as
    /// `updateHeaderHeight(_:animated:)` with `animated: false`.
    open var currentHeaderHeight: CGFloat {
        get { resolvedHeaderHeight }
        set { updateHeaderHeight(newValue, animated: false) }
    }

    // MARK: - Views

    /// The outer, vertical scroll view hosting header + tab bar + pages.
    /// Internal (not public API), but visible to tests.
    let outerScrollView = StickyScrollView()
    private let contentView = UIView()
    private let headerContainer = UIView()
    private let pageHostView = UIView()
    private let pageViewController: UIPageViewController

    private var _pages: [UIViewController]
    private var _selectedIndex: Int = 0
    private var _stickyState: StickyState = .expanded
    /// Set before the first layout so a pre-load `stickyState` assignment is
    /// applied once the header height is known.
    private var requestedStickyState: StickyState?
    private var _headerView: UIView?
    private var _tabBar: SlidePagerTabBarView
    private weak var installedTabBar: UIView?
    private var tabBarEdgeConstraints: [NSLayoutConstraint] = []
    private var pageHostTop: NSLayoutConstraint?

    // MARK: - Layout state

    private var explicitHeaderHeight: CGFloat?
    private var resolvedHeaderHeight: CGFloat = 0
    private var contentViewHeight: NSLayoutConstraint!
    private var headerTop: NSLayoutConstraint!
    private var headerHeight: NSLayoutConstraint!
    private var tabBarHeight: NSLayoutConstraint!
    private var pageHostHeight: NSLayoutConstraint!

    // MARK: - Scroll coordination state

    private var pageObservations: [PageScrollObservation] = []
    private var pagingOffsetObservation: NSKeyValueObservation?
    private var pagingIndicator = PagingIndicatorTracker()
    private var isEnforcingInvariants = false
    private var isRedirectingOverscroll = false
    private var pendingPageOvershoot: CGFloat?
    private let collapsePan = HeaderCollapsePan(target: nil, action: nil)
    private var collapsePanOrigin: (outerY: CGFloat, pageY: CGFloat, translationY: CGFloat)?
    /// Once a drag crosses between the header and the page, this pan is the only
    /// writer of both offsets. Letting either scroll view rubber-band across
    /// that boundary is what stutters.
    private var handoffDriving = false
    private var handoffDidDrive = false
    private var isApplyingHandoff = false
    private var isCoasting = false
    private var coastExtraFingerDown: CGFloat = 0
    private var coastVelocity: CGFloat = 0
    private var coastStartTime: CFTimeInterval = 0
    private var coastLink: CADisplayLink?
    private var lastCoastOuterY: CGFloat = 0
    private var lastCoastPageY: CGFloat = 0
    private var lastDecelOffsetY: CGFloat?
    private var lastDecelTime: CFTimeInterval?
    private lazy var coastBox: CoastBox = {
        let box = CoastBox()
        box.owner = self
        return box
    }()
    private var suspendedPageBounces: (scrollView: UIScrollView, bounces: Bool)?
    private var collapseDrag: CollapseDrag?

    private struct CollapseDrag {
        weak var scrollView: UIScrollView?
        var pageStart: CGFloat
        var outerStart: CGFloat
    }

    // MARK: - Init

    /// Creates a pager.
    ///
    /// - Parameters:
    ///   - header: An optional header view shown above the tab bar.
    ///   - headerHeight: The header's height. Pass `nil` to derive it from the
    ///     header's autolayout fitting size.
    ///   - tabBar: A tab bar view conforming to `SlidePagerTabBar`.
    ///   - pages: The child view controllers, in tab order. Pages conforming to
    ///     `SlidePagerPage` get nested-scroll coordination; each page's `title`
    ///     is used as its tab title.
    public init<TabBar: UIView>(
        header: UIView? = nil,
        headerHeight: CGFloat? = nil,
        tabBar: TabBar,
        pages: [UIViewController]
    ) where TabBar: SlidePagerTabBar {
        precondition(!pages.isEmpty, "SlidePagerViewController requires at least one page")

        self._headerView = header
        self.explicitHeaderHeight = headerHeight
        self._tabBar = tabBar
        self._pages = pages
        self.pageViewController = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal
        )
        super.init(nibName: nil, bundle: nil)
    }

    /// Creates a pager without a header (the tab bar pins immediately).
    public convenience init<TabBar: UIView>(
        tabBar: TabBar,
        pages: [UIViewController]
    ) where TabBar: SlidePagerTabBar {
        self.init(header: nil, headerHeight: nil, tabBar: tabBar, pages: pages)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        // UIKit releases this controller on the main thread. The display link
        // is not Sendable, so deinit cannot touch it without that assumption.
        MainActor.assumeIsolated {
            coastLink?.invalidate()
        }
    }

    // MARK: - View lifecycle

    open override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        configureOuterScrollView()
        configureHeader()
        configureTabBar()
        configurePageViewController()
        outerScrollView.delegate = self
        outerScrollView.allowsVerticalPan = { [weak self] velocity in
            guard let self else { return true }
            let collapsed = self.outerScrollView.contentOffset.y >= self.maxStickyOffset - ScrollRules.epsilon
            guard collapsed else { return true }
            // Header is collapsed. The page scrolls on its own unless it is
            // already at the top and the finger is pulling the header back open.
            guard let page = self.currentPageScrollView else { return true }
            let atTop = page.contentOffset.y <= self.topRestingOffset(of: page) + ScrollRules.epsilon
            let pullingDown = velocity.y > ScrollRules.epsilon
            return atTop && pullingDown
        }

        let initialIndex = pages.indices.contains(selectedIndex) ? selectedIndex : 0
        let first = pages[initialIndex]
        pageViewController.setViewControllers([first], direction: .forward, animated: false)
        attachObserversIfPossible(for: first)
        settleCurrentPage(to: initialIndex, animated: false, notify: false)
    }

    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        installPanCoordination()
        applyStickyGeometry(preservingCollapse: true)
        if requestedStickyState != nil {
            applyRequestedStickyStateIfNeeded()
        } else {
            enforceScrollInvariants()
        }
    }

    open override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        // Safe-area changes (Stage Manager, foldables, nav bar visibility)
        // must re-run the sticky geometry from the new insets.
        view.setNeedsLayout()
    }

    // MARK: - Public methods

    /// Programmatically switches to the page at `index`.
    public func selectPage(at index: Int, animated: Bool) {
        transitionToPage(at: index, animated: animated, source: .programmatic)
    }

    /// Replaces the header height, optionally animating. Pass `nil` to re-derive
    /// the height from the header's autolayout fitting size.
    ///
    /// If the header was fully collapsed it stays fully collapsed; otherwise the
    /// current collapse amount is preserved (clamped to the new range).
    public func updateHeaderHeight(_ height: CGFloat?, animated: Bool) {
        explicitHeaderHeight = height
        guard isViewLoaded, view.bounds.width > 0 else { return }
        if animated {
            UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
                self.applyStickyGeometry(preservingCollapse: true)
                self.contentView.layoutIfNeeded()
            }
        } else {
            applyStickyGeometry(preservingCollapse: true)
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }
        enforceScrollInvariants()
    }

    // MARK: - External configuration

    private func configurePages(_ newPages: [UIViewController]) {
        precondition(!newPages.isEmpty, "SlidePagerViewController requires at least one page")
        if pagesAreIdentical(_pages, newPages) { return }
        _pages = newPages
        let index = pages.indices.contains(_selectedIndex) ? _selectedIndex : newPages.count - 1
        guard isViewLoaded else {
            _selectedIndex = index
            return
        }
        _tabBar.reloadTabs(titles: tabTitles(for: newPages))
        let page = newPages[index]
        let displayed = pageViewController.viewControllers?.first
        pageViewController.setViewControllers([page], direction: .forward, animated: false)
        pageObservations.removeAll()
        let indexChanged = index != _selectedIndex
        settleCurrentPage(to: index, animated: false, notify: indexChanged)
        if !indexChanged, displayed !== page {
            _tabBar.setSelectedIndex(index, animated: false)
            delegate?.slidePager(self, didTransitionToPageAt: index)
        }
    }

    private func configureSelectedIndex(_ index: Int) {
        guard pages.indices.contains(index) else { return }
        guard isViewLoaded else {
            _selectedIndex = index
            return
        }
        transitionToPage(at: index, animated: false, source: .programmatic)
    }

    private func configureStickyState(_ state: StickyState) {
        let geometryReady = isViewLoaded && view.bounds.width > 0
        guard geometryReady else {
            let changed = _stickyState != state
            _stickyState = state
            requestedStickyState = state
            if changed {
                delegate?.slidePager(self, didChangeStickyState: state)
            }
            return
        }
        requestedStickyState = nil
        applyStickyOffset(for: state)
    }

    private func applyRequestedStickyStateIfNeeded() {
        guard let state = requestedStickyState else { return }
        requestedStickyState = nil
        configureStickyState(state)
    }

    private func applyStickyOffset(for state: StickyState) {
        let target: CGFloat
        switch state {
        case .expanded:
            target = 0
        case .collapsed:
            target = maxStickyOffset
        case .partiallyCollapsed(let progress):
            let clamped = min(max(progress, 0), 1)
            target = maxStickyOffset * clamped
        }
        if abs(outerScrollView.contentOffset.y - target) > ScrollRules.epsilon {
            outerScrollView.setContentOffset(CGPoint(x: 0, y: target), animated: false)
        }
        enforceScrollInvariants()
    }

    private func setHeaderView(_ header: UIView?) {
        guard _headerView !== header else { return }
        _headerView = header
        guard headerContainer.superview != nil else { return }
        installHeaderView()
        applyStickyGeometry(preservingCollapse: true)
        enforceScrollInvariants()
    }

    private func setTabBarView(_ tabBar: SlidePagerTabBarView) {
        guard _tabBar !== tabBar else { return }
        _tabBar = tabBar
        guard isViewLoaded else { return }
        installTabBar(tabBar)
        applyStickyGeometry(preservingCollapse: true)
        enforceScrollInvariants()
    }

    private func pagesAreIdentical(_ lhs: [UIViewController], _ rhs: [UIViewController]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0 === $1 }
    }

    private func tabTitles(for pages: [UIViewController]) -> [String] {
        pages.enumerated().map { index, page in
            page.title ?? "Tab \(index + 1)"
        }
    }

    // MARK: - Configuration

    private func configureOuterScrollView() {
        outerScrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(outerScrollView)
        NSLayoutConstraint.activate([
            outerScrollView.topAnchor.constraint(equalTo: view.topAnchor),
            outerScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            outerScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            outerScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        contentView.translatesAutoresizingMaskIntoConstraints = false
        outerScrollView.addSubview(contentView)
        contentViewHeight = contentView.heightAnchor.constraint(equalToConstant: 0)
        // Top + bottom pins are what give the scroll view a content size.
        // Height alone does not; without the bottom pin a drag on the page
        // controller has nothing to scroll, so the header never collapses.
        NSLayoutConstraint.activate([
            contentView.widthAnchor.constraint(equalTo: outerScrollView.frameLayoutGuide.widthAnchor),
            contentView.topAnchor.constraint(equalTo: outerScrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: outerScrollView.contentLayoutGuide.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: outerScrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: outerScrollView.contentLayoutGuide.trailingAnchor),
            contentViewHeight,
        ])
    }

    private func configureHeader() {
        headerContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(headerContainer)
        headerTop = headerContainer.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 0)
        headerHeight = headerContainer.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            headerTop,
            headerHeight,
            headerContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            headerContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])

        installHeaderView()
    }

    private func installHeaderView() {
        for subview in headerContainer.subviews {
            subview.removeFromSuperview()
        }
        guard let header = _headerView else { return }
        header.translatesAutoresizingMaskIntoConstraints = false
        headerContainer.addSubview(header)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: headerContainer.topAnchor),
            header.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor),
            header.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor),
        ])
    }

    private func configureTabBar() {
        installTabBar(_tabBar)
    }

    private func installTabBar(_ tabBar: SlidePagerTabBarView) {
        NSLayoutConstraint.deactivate(tabBarEdgeConstraints)
        tabBarEdgeConstraints = []
        if let installed = installedTabBar, installed !== tabBar {
            installed.removeFromSuperview()
        }
        installedTabBar = tabBar
        _tabBar = tabBar
        if tabBar.superview !== contentView {
            tabBar.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(tabBar)
        }
        tabBarHeight?.isActive = false
        tabBarHeight = tabBar.heightAnchor.constraint(equalToConstant: max(1, tabBar.preferredHeight))
        tabBarEdgeConstraints = [
            tabBar.topAnchor.constraint(equalTo: headerContainer.bottomAnchor),
            tabBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tabBarHeight,
        ]
        NSLayoutConstraint.activate(tabBarEdgeConstraints)
        tabBar.onSelection = { [weak self] index in
            self?.tabBarDidSelect(index)
        }
        tabBar.reloadTabs(titles: tabTitles(for: pages))
        guard pageHostView.superview != nil else { return }
        tabBar.setSelectedIndex(selectedIndex, animated: false)
        pageHostTop?.isActive = false
        pageHostTop = pageHostView.topAnchor.constraint(equalTo: tabBar.bottomAnchor)
        pageHostTop?.isActive = true
    }

    private func configurePageViewController() {
        let pager = pageViewController
        pager.view.translatesAutoresizingMaskIntoConstraints = false

        pageHostView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(pageHostView)
        pageHostHeight = pageHostView.heightAnchor.constraint(equalToConstant: 0)
        let pageHostTop = pageHostView.topAnchor.constraint(equalTo: _tabBar.bottomAnchor)
        self.pageHostTop = pageHostTop
        NSLayoutConstraint.activate([
            pageHostTop,
            pageHostView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            pageHostView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            pageHostHeight,
        ])

        addChild(pager)
        pageHostView.addSubview(pager.view)
        NSLayoutConstraint.activate([
            pager.view.topAnchor.constraint(equalTo: pageHostView.topAnchor),
            pager.view.bottomAnchor.constraint(equalTo: pageHostView.bottomAnchor),
            pager.view.leadingAnchor.constraint(equalTo: pageHostView.leadingAnchor),
            pager.view.trailingAnchor.constraint(equalTo: pageHostView.trailingAnchor),
        ])
        pager.didMove(toParent: self)
        pager.dataSource = self
        pager.delegate = self
        collapsePan.addTarget(self, action: #selector(collapsePanChanged(_:)))
        pageHostView.addGestureRecognizer(collapsePan)
        installPanCoordination()
    }

    /// Drives header movement from a drag that starts on the page view controller.
    ///
    /// A pull back up a scrolled page stays on that page until the page reaches
    /// its top. Further movement in the same drag expands the header to full size.
    @objc private func collapsePanChanged(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            stopCoast(endingPan: false)
            // Translation is read in this view, not the page host. The page
            // host moves as the header collapses, so a translation in that
            // view stays near zero and the header never moves.
            let outerY = outerScrollView.contentOffset.y
            let pageY = currentPageScrollView?.contentOffset.y ?? 0
            collapsePanOrigin = (outerY: outerY, pageY: pageY, translationY: pan.translation(in: view).y)
            let top = currentPageScrollView.map { topRestingOffset(of: $0) } ?? 0
            let headerVisible = outerY < maxStickyOffset - ScrollRules.epsilon
            let pageAtTop = pageY <= top + ScrollRules.epsilon
            // Drive from the first pixel when the header is in the gesture.
            // A scrolled page keeps its own scroll view until it actually hits the top.
            handoffDriving = headerVisible || pageAtTop
            if handoffDriving {
                handoffDidDrive = true
                suspendPageBounces()
            }
        case .changed:
            guard collapsePanOrigin != nil else { return }
            let translation = pan.translation(in: view)
            if abs(translation.x) > abs(translation.y), abs(translation.x) > 8 {
                (pan as? HeaderCollapsePan)?.cancelForPaging()
                endCollapsePan()
                return
            }
            if !handoffDriving {
                if !takeOverIfPageReachedTop() { return }
            }
            applyLinkedOffsets()
        case .ended:
            let velocityY = pan.velocity(in: view).y
            if handoffDriving, abs(velocityY) >= ScrollRules.minimumCoastSpeed {
                startCoast(fingerVelocity: velocityY)
            } else {
                endCollapsePan()
            }
        case .cancelled, .failed:
            stopCoast()
        default:
            break
        }
    }

    /// Header is collapsed and the page is away from its top, so a drag should
    /// scroll the page exactly as a normal scroll view would.
    private var pageShouldScrollNormally: Bool {
        guard outerScrollView.contentOffset.y >= maxStickyOffset - ScrollRules.epsilon else { return false }
        guard let page = currentPageScrollView else { return false }
        return page.contentOffset.y > topRestingOffset(of: page) + ScrollRules.epsilon
    }

    /// `true` when a pull-down has brought a scrolled page to its top, and this
    /// pan should take over so the header continues at the same finger speed.
    private func takeOverIfPageReachedTop() -> Bool {
        guard let origin = collapsePanOrigin, let page = currentPageScrollView else { return false }
        let top = topRestingOffset(of: page)
        let startedCollapsed = origin.outerY >= maxStickyOffset - ScrollRules.epsilon
        let startedScrolled = origin.pageY > top + ScrollRules.epsilon
        guard startedCollapsed, startedScrolled else { return false }
        guard page.contentOffset.y <= top + ScrollRules.epsilon else { return false }
        let fingerDown = collapsePan.translation(in: view).y - origin.translationY
        guard fingerDown > ScrollRules.epsilon else { return false }
        // Restart the translation here so the header picks up with no jump
        // and no rubber-band pause.
        handoffDriving = true
        handoffDidDrive = true
        collapsePanOrigin = (
            outerY: maxStickyOffset,
            pageY: top,
            translationY: collapsePan.translation(in: view).y
        )
        suspendPageBounces()
        applyLinkedOffsets()
        return true
    }

    private func suspendPageBounces() {
        guard suspendedPageBounces == nil, let page = currentPageScrollView else { return }
        suspendedPageBounces = (page, page.bounces)
        page.bounces = false
    }

    private func endCollapsePan() {
        if let suspended = suspendedPageBounces {
            suspended.scrollView.bounces = suspended.bounces
            suspendedPageBounces = nil
        }
        handoffDriving = false
        isCoasting = false
        coastExtraFingerDown = 0
        collapsePanOrigin = nil
    }

    /// Continues a header drag after the finger lifts, with the same decay
    /// `UIScrollView` uses. Positive velocity moves the finger down (header opens).
    private func startCoast(fingerVelocity: CGFloat) {
        guard abs(fingerVelocity) >= ScrollRules.minimumCoastSpeed, collapsePanOrigin != nil else {
            endCollapsePan()
            return
        }
        stopCoast(endingPan: false)
        handoffDriving = true
        handoffDidDrive = true
        isCoasting = true
        coastVelocity = fingerVelocity
        coastExtraFingerDown = 0
        coastStartTime = CACurrentMediaTime()
        lastCoastOuterY = outerScrollView.contentOffset.y
        lastCoastPageY = currentPageScrollView?.contentOffset.y ?? 0
        let link = CADisplayLink(target: coastBox, selector: #selector(CoastBox.tick(_:)))
        link.add(to: .main, forMode: .common)
        coastLink = link
    }

    fileprivate func coastTick(_ link: CADisplayLink) {
        guard isCoasting, collapsePanOrigin != nil else {
            stopCoast()
            return
        }
        let time = CGFloat(max(0, link.timestamp - coastStartTime))
        let rate = outerScrollView.decelerationRate.rawValue
        coastExtraFingerDown = ScrollRules.coastDistance(
            velocity: coastVelocity,
            decelerationRate: rate,
            time: time
        )
        let beforeOuter = outerScrollView.contentOffset.y
        let beforePage = currentPageScrollView?.contentOffset.y ?? beforeOuter
        applyLinkedOffsets()
        let speed = abs(ScrollRules.coastSpeed(velocity: coastVelocity, decelerationRate: rate, time: time))
        let outerStuck = abs(outerScrollView.contentOffset.y - beforeOuter) < ScrollRules.epsilon
        let pageStuck = abs((currentPageScrollView?.contentOffset.y ?? beforePage) - beforePage) < ScrollRules.epsilon
        if speed < ScrollRules.minimumCoastSpeed || (time > 0.05 && outerStuck && pageStuck) {
            stopCoast()
        }
    }

    private func stopCoast(endingPan: Bool = true) {
        coastLink?.invalidate()
        coastLink = nil
        isCoasting = false
        coastExtraFingerDown = 0
        if endingPan {
            endCollapsePan()
        }
    }

    /// A page flick that reaches the top keeps going, opening the header.
    private func continueHeaderCoastIfPageReachedTop(_ page: UIScrollView) {
        guard !isCoasting, !handoffDriving, page.isDecelerating else { return }
        let top = topRestingOffset(of: page)
        guard page.contentOffset.y <= top + ScrollRules.epsilon else {
            lastDecelOffsetY = page.contentOffset.y
            lastDecelTime = CACurrentMediaTime()
            return
        }
        guard outerScrollView.contentOffset.y >= maxStickyOffset - ScrollRules.epsilon else { return }
        let now = CACurrentMediaTime()
        guard let lastOffset = lastDecelOffsetY, let lastTime = lastDecelTime, now - lastTime > 0.001 else {
            lastDecelOffsetY = page.contentOffset.y
            lastDecelTime = now
            return
        }
        let offsetVelocity = (page.contentOffset.y - lastOffset) / (now - lastTime)
        lastDecelOffsetY = page.contentOffset.y
        lastDecelTime = now
        // Offset falling means the finger was moving down.
        let fingerVelocity = -offsetVelocity
        guard fingerVelocity >= ScrollRules.minimumCoastSpeed else { return }
        isCoasting = true
        page.setContentOffset(CGPoint(x: page.contentOffset.x, y: top), animated: false)
        collapsePanOrigin = (outerY: maxStickyOffset, pageY: top, translationY: collapsePan.translation(in: view).y)
        suspendPageBounces()
        startCoast(fingerVelocity: fingerVelocity)
    }

    /// Writes both offsets from the finger. Called on every move and again
    /// after either scroll view writes, so a rubber-band cannot flash through.
    private func applyLinkedOffsets() {
        guard !isApplyingHandoff, let origin = collapsePanOrigin else { return }
        isApplyingHandoff = true
        defer { isApplyingHandoff = false }
        let top = currentPageScrollView.map { topRestingOffset(of: $0) } ?? 0
        let fingerDown = collapsePan.translation(in: view).y - origin.translationY + coastExtraFingerDown
        var linked = ScrollRules.linkedOffsets(
            fingerDown: fingerDown,
            outerStartY: origin.outerY,
            pageStartY: origin.pageY,
            pageTopY: top,
            maxStickyOffset: maxStickyOffset
        )
        if let page = currentPageScrollView {
            let maxPage = max(
                top,
                page.contentSize.height - page.bounds.height + page.adjustedContentInset.bottom
            )
            linked.pageY = min(max(top, linked.pageY), max(top, maxPage))
        }
        if abs(linked.outerY - outerScrollView.contentOffset.y) > ScrollRules.epsilon {
            pin(outerScrollView, toY: linked.outerY)
        }
        if let page = currentPageScrollView,
           abs(linked.pageY - page.contentOffset.y) > ScrollRules.epsilon {
            pin(page, toY: linked.pageY)
        }
    }

    // MARK: - Sticky geometry

    /// The geometry contract (see README):
    ///
    /// - `headerTop` = top safe-area inset (edge-to-edge under nav bars).
    /// - The page host is as tall as the *fully collapsed* visible area, so the
    ///   maximum outer offset is exactly `headerHeight`: the full collapse
    ///   point at which the tab bar sits below the top safe-area inset.
    ///
    /// content height = topInset + headerHeight + tabBarHeight + pageHostHeight
    /// max offset     = headerHeight
    private func applyStickyGeometry(preservingCollapse: Bool) {
        guard view.bounds.width > 0 else { return }
        let width = view.bounds.width
        let topInset = view.safeAreaInsets.top
        let newHeaderHeight = resolveHeaderHeight(width: width)
        let tabHeight = _tabBar.preferredHeight
        let pageHostSize = max(0, view.bounds.height - topInset - tabHeight)

        let oldMax = resolvedHeaderHeight
        let offsetBefore = outerScrollView.contentOffset.y

        headerTop.constant = topInset
        headerHeight.constant = newHeaderHeight
        tabBarHeight.constant = tabHeight
        pageHostHeight.constant = pageHostSize
        contentViewHeight.constant = topInset + newHeaderHeight + tabHeight + pageHostSize

        resolvedHeaderHeight = newHeaderHeight

        // Keep the pinned state stable when the header height changes.
        // A zero previous range is not "pinned" — that is the first layout,
        // and treating it as pinned collapses the header before the user drags.
        if preservingCollapse, abs(oldMax - newHeaderHeight) > ScrollRules.epsilon {
            let target: CGFloat
            let wasPinned = oldMax > ScrollRules.epsilon && offsetBefore >= oldMax - ScrollRules.epsilon
            if wasPinned {
                target = newHeaderHeight
            } else {
                target = min(max(0, offsetBefore), newHeaderHeight)
            }
            if abs(target - offsetBefore) > ScrollRules.epsilon {
                outerScrollView.setContentOffset(CGPoint(x: 0, y: target), animated: false)
            }
        }
    }

    private func resolveHeaderHeight(width: CGFloat) -> CGFloat {
        if let explicit = explicitHeaderHeight { return max(0, explicit) }
        guard let header = _headerView else { return 0 }
        // Hysteresis so fitting-size jitter cannot cause a layout loop.
        let fitting = header.systemLayoutSizeFitting(
            CGSize(width: width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        if abs(fitting - resolvedHeaderHeight) <= ScrollRules.epsilon {
            return resolvedHeaderHeight
        }
        return max(0, fitting)
    }

    private var maxStickyOffset: CGFloat { max(0, resolvedHeaderHeight) }

    // MARK: - Page transitions

    private enum TransitionSource { case tabBar, programmatic }

    private func tabBarDidSelect(_ index: Int) {
        transitionToPage(at: index, animated: true, source: .tabBar)
    }

    private func transitionToPage(at index: Int, animated: Bool, source: TransitionSource) {
        guard pages.indices.contains(index), index != selectedIndex else { return }
        if source == .tabBar {
            delegate?.slidePager(self, didSelectTabAt: index)
        }
        let page = pages[index]
        let direction: UIPageViewController.NavigationDirection = index > selectedIndex ? .forward : .reverse
        if animated {
            pageViewController.setViewControllers([page], direction: direction, animated: true)
            // Completion is handled by the page view controller delegate.
        } else {
            pageViewController.setViewControllers([page], direction: direction, animated: false)
            settleCurrentPage(to: index, animated: false, notify: true)
        }
    }

    private func settleCurrentPage(to index: Int, animated: Bool, notify: Bool) {
        guard pages.indices.contains(index) else { return }
        let changed = index != _selectedIndex
        _selectedIndex = index
        pendingPageOvershoot = nil
        attachObserversIfPossible(for: pages[index])
        if notify, changed {
            _tabBar.setSelectedIndex(index, animated: animated)
            delegate?.slidePager(self, didTransitionToPageAt: index)
        }
        // Sync the incoming page to the effective collapse amount so the
        // header/tabs never jump on a page switch.
        enforceScrollInvariants()
    }

    // MARK: - Scroll coordination

    private var currentPageScrollView: UIScrollView? {
        guard pages.indices.contains(selectedIndex) else { return nil }
        let page = pages[selectedIndex]
        guard page.isViewLoaded, let scrollable = page as? SlidePagerPage else { return nil }
        return scrollable.pageScrollView
    }

    private func attachObserversIfPossible(for page: UIViewController) {
        guard page.isViewLoaded, let scrollable = page as? SlidePagerPage else { return }
        guard let scrollView = scrollable.pageScrollView else { return }
        attachObservers(for: scrollView)
    }

    private func attachObservers(for scrollView: UIScrollView) {
        pageObservations.removeAll { $0.scrollView == nil }
        guard !pageObservations.contains(where: { $0.scrollView === scrollView }) else { return }
        let observation = scrollView.observe(\.contentOffset, options: [.old, .new]) { [weak self] scrollView, change in
            // contentOffset KVO fires synchronously on the main thread while scrolling.
            MainActor.assumeIsolated {
                self?.pageScrollViewDidChange(scrollView, oldOffset: change.oldValue)
            }
        }
        pageObservations.append(PageScrollObservation(scrollView: scrollView, observation: observation))
        installPagePanRelay(on: scrollView)
    }

    private func pageScrollViewDidChange(_ scrollView: UIScrollView, oldOffset: CGPoint?) {
        guard isViewLoaded, !isEnforcingInvariants, !isApplyingHandoff else { return }
        if scrollView === currentPageScrollView, !handoffDriving, !isCoasting {
            continueHeaderCoastIfPageReachedTop(scrollView)
            _ = takeOverIfPageReachedTop()
        }
        if handoffDriving {
            applyLinkedOffsets()
            updateStickyState(
                collapse: min(max(0, outerScrollView.contentOffset.y), maxStickyOffset),
                maxStickyOffset: maxStickyOffset
            )
            return
        }
        isEnforcingInvariants = true
        defer { isEnforcingInvariants = false }
        if scrollView === currentPageScrollView {
            absorbPageDrag(scrollView, oldOffset: oldOffset)
        }
        applyInvariants()
    }

    /// Applies the two `ScrollRules` invariants to whatever just moved.
    private func enforceScrollInvariants() {
        guard isViewLoaded, !isEnforcingInvariants else { return }
        isEnforcingInvariants = true
        defer { isEnforcingInvariants = false }
        applyInvariants()
    }

    private func applyInvariants() {
        // The driven handoff already wrote both offsets. Pinning here would
        // fight that write and stutter at the boundary.
        if handoffDriving {
            updateStickyState(
                collapse: min(max(0, outerScrollView.contentOffset.y), maxStickyOffset),
                maxStickyOffset: maxStickyOffset
            )
            return
        }
        let maxSticky = maxStickyOffset
        let outerY = outerScrollView.contentOffset.y

        // Invariant 1: while the header is visible, every mounted page sits at
        // its top resting offset — the outer scroll view owns vertical pans.
        // A page that is still tracking below its top is scrolling normally;
        // snapping it here is the "content jumps up immediately" bug.
        let headerVisible = ScrollRules.pageMustHoldTop(outerOffsetY: outerY, maxStickyOffset: maxSticky)
        if headerVisible {
            for observation in pageObservations {
                guard let scrollView = observation.scrollView else { continue }
                let top = topRestingOffset(of: scrollView)
                if (scrollView.isTracking || scrollView.isDragging),
                   scrollView.contentOffset.y > top + ScrollRules.epsilon {
                    continue
                }
                pinToTopIfNeeded(scrollView)
            }
        }

        // Invariant 2: while the current page is scrolled beyond its top, the
        // outer scroll view sits exactly at the sticky offset — the page owns
        // vertical pans and the tab bar stays pinned.
        if let current = currentPageScrollView {
            let top = topRestingOffset(of: current)
            if ScrollRules.outerMustHoldSticky(
                pageOffsetY: current.contentOffset.y,
                pageTopOffsetY: top,
                outerOffsetY: outerY,
                maxStickyOffset: maxSticky
            ) {
                pin(outerScrollView, toY: maxSticky)
            }
        }

        updateStickyState(
            collapse: min(max(0, outerY), maxSticky),
            maxStickyOffset: maxSticky
        )
    }

    /// The content offset at which a page's scroll view shows its very top,
    /// respecting whatever content insets the page uses.
    private func topRestingOffset(of scrollView: UIScrollView) -> CGFloat {
        -scrollView.adjustedContentInset.top
    }

    private func pinToTopIfNeeded(_ scrollView: UIScrollView) {
        let top = topRestingOffset(of: scrollView)
        if abs(scrollView.contentOffset.y - top) > ScrollRules.epsilon {
            pin(scrollView, toY: top)
        }
    }

    private func pin(_ scrollView: UIScrollView, toY y: CGFloat) {
        var offset = scrollView.contentOffset
        offset.y = y
        scrollView.setContentOffset(offset, animated: false)
    }

    private func updateStickyState(collapse: CGFloat, maxStickyOffset: CGFloat) {
        let state = StickyState.resolve(collapse: collapse, maxStickyOffset: maxStickyOffset)
        guard state != _stickyState else { return }
        _stickyState = state
        delegate?.slidePager(self, didChangeStickyState: state)
    }
}

// MARK: - UIPageViewController data source & delegate

extension SlidePagerViewController: UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    public func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let index = pages.firstIndex(of: viewController), index > 0 else { return nil }
        let page = pages[index - 1]
        attachObserversIfPossible(for: page)
        return page
    }

    public func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let index = pages.firstIndex(of: viewController), index < pages.count - 1 else { return nil }
        let page = pages[index + 1]
        attachObserversIfPossible(for: page)
        return page
    }

    public func pageViewController(
        _ pageViewController: UIPageViewController,
        willTransitionTo pendingViewControllers: [UIViewController]
    ) {
        // Observing the incoming page during the interactive swipe keeps it
        // pinned to the effective collapse amount mid-gesture.
        for page in pendingViewControllers {
            attachObserversIfPossible(for: page)
        }
    }

    public func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard completed,
              let current = pageViewController.viewControllers?.first,
              let index = pages.firstIndex(of: current)
        else { return }
        settleCurrentPage(to: index, animated: false, notify: true)
    }
}

// MARK: - Tab indicator follows the page swipe

extension SlidePagerViewController {
    private func observePagingScroll() {
        guard pagingOffsetObservation == nil, let paging = pagingScrollView() else { return }
        pagingOffsetObservation = paging.observe(\.contentOffset, options: [.old, .new]) { [weak self] scrollView, change in
            MainActor.assumeIsolated {
                self?.pagingScrollViewDidScroll(scrollView, oldOffsetX: change.oldValue?.x)
            }
        }
    }

    /// Slides the tab indicator with the page controller's scroll view, and
    /// settles the selection when that scroll view comes to rest. Relying only
    /// on `didFinishAnimating` leaves the indicator on the previous page.
    private func pagingScrollViewDidScroll(_ scrollView: UIScrollView, oldOffsetX: CGFloat?) {
        let width = scrollView.bounds.width
        guard width > 1 else { return }
        let interacting = scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating
        switch pagingIndicator.consume(
            offsetX: scrollView.contentOffset.x,
            oldOffsetX: oldOffsetX,
            width: width,
            interacting: interacting,
            fingerDown: scrollView.isTracking || scrollView.isDragging,
            selectedIndex: selectedIndex,
            pageCount: pages.count
        ) {
        case .resting:
            syncSelectionFromVisiblePage()
        case .recentered:
            // The page controller jumped back to the settled page. Pin the
            // indicator there — a late progress sample must not leave it on
            // the following tab.
            pinIndicatorToVisiblePage()
        case .follow(let from, let to, let progress):
            _tabBar.setTransitionProgress(from: from, to: to, progress: progress)
        case .unchanged:
            break
        }
    }

    /// Moves the indicator onto the page the page controller is showing.
    ///
    /// Called when that controller recenters its scroll view. `selectedIndex`
    /// may already match, but the indicator can still be on the wrong tab.
    private func pinIndicatorToVisiblePage() {
        guard let current = pageViewController.viewControllers?.first,
              let index = pages.firstIndex(of: current)
        else { return }
        if index != _selectedIndex {
            settleCurrentPage(to: index, animated: false, notify: true)
        } else {
            _tabBar.setSelectedIndex(index, animated: false)
        }
    }

    private func syncSelectionFromVisiblePage() {
        guard let current = pageViewController.viewControllers?.first,
              let index = pages.firstIndex(of: current)
        else { return }
        // Leave the indicator where the swipe put it until the page controller
        // actually reports a new page. Snapping back here is what makes the
        // indicator miss the page the user landed on.
        guard index != selectedIndex else { return }
        settleCurrentPage(to: index, animated: false, notify: true)
    }
}

// MARK: - Outer scroll view delegate

extension SlidePagerViewController: UIScrollViewDelegate {
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard scrollView === outerScrollView else { return }
        stopCoast()
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === outerScrollView, !isApplyingHandoff else { return }
        if handoffDriving {
            applyLinkedOffsets()
            updateStickyState(
                collapse: min(max(0, outerScrollView.contentOffset.y), maxStickyOffset),
                maxStickyOffset: maxStickyOffset
            )
            return
        }
        redirectOuterOverscrollToPage()
        enforceScrollInvariants()
    }

    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        enforceScrollInvariants()
    }

    public func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        guard scrollView === outerScrollView else { return }
        // A driven handoff already placed the page on the finger. Animating an
        // extra overshoot from here is the hitch at the end of the transfer.
        if handoffDriving || handoffDidDrive || isCoasting {
            // Freeze the outer scroll view so its own deceleration does not
            // fight the header coast.
            targetContentOffset.pointee = scrollView.contentOffset
            pendingPageOvershoot = nil
            return
        }
        // When a collapse gesture carries past the sticky point, stop the outer
        // scroll view exactly at it and hand the leftover distance to the
        // current page, so scrolling does not stop dead when the tab bar pins.
        let maxSticky = maxStickyOffset
        let overshoot = targetContentOffset.pointee.y - maxSticky
        guard overshoot > ScrollRules.epsilon else { return }
        targetContentOffset.pointee.y = maxSticky
        pendingPageOvershoot = overshoot
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView === outerScrollView else { return }
        if !decelerate { applyPendingOvershoot() }
    }

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === outerScrollView else { return }
        applyPendingOvershoot()
    }

    private func applyPendingOvershoot() {
        guard let overshoot = pendingPageOvershoot else { return }
        pendingPageOvershoot = nil
        guard let page = currentPageScrollView, page.isScrollEnabled else { return }
        let top = topRestingOffset(of: page)
        let maxY = max(
            top,
            page.contentSize.height - page.bounds.height + page.adjustedContentInset.bottom
        )
        guard maxY > top + ScrollRules.epsilon else { return }
        // The page may already show the distance dragged past the sticky point.
        // Overshoot is the extra coast beyond that, not a replacement for it.
        let base = max(top, page.contentOffset.y)
        let target = min(base + overshoot, maxY)
        page.setContentOffset(CGPoint(x: page.contentOffset.x, y: target), animated: true)
    }

    /// While the finger is down and the outer pan has carried past the sticky
    /// point, keep the tab bar pinned and give the leftover distance to the
    /// page. The page's own pan has usually already failed (the header was
    /// visible when the drag began), so it will not pick the gesture up itself.
    private func redirectOuterOverscrollToPage() {
        guard !isRedirectingOverscroll, outerScrollView.isTracking else { return }
        let maxSticky = maxStickyOffset
        let y = outerScrollView.contentOffset.y
        guard y > maxSticky + ScrollRules.epsilon else { return }
        guard let page = currentPageScrollView, !page.isTracking, !page.isDragging else { return }
        let top = topRestingOffset(of: page)
        let maxPage = max(
            top,
            page.contentSize.height - page.bounds.height + page.adjustedContentInset.bottom
        )
        guard maxPage > top + ScrollRules.epsilon else { return }
        let excess = min(y - maxSticky, maxPage - top)
        isRedirectingOverscroll = true
        pin(outerScrollView, toY: maxSticky)
        pin(page, toY: top + excess)
        isRedirectingOverscroll = false
    }
}

// MARK: - Pan coordination

extension SlidePagerViewController {
    /// UIPageViewController's internal scroll view claims vertical pans and
    /// never scrolls them, which stops the header from collapsing. Yield those
    /// pans, and yield page pans while the header still owns vertical movement.
    private func installPanCoordination() {
        installPagingPanRelay()
        observePagingScroll()
        if let current = currentPageScrollView {
            installPagePanRelay(on: current)
        }
        for observation in pageObservations {
            if let scrollView = observation.scrollView {
                installPagePanRelay(on: scrollView)
            }
        }
    }

    private func pagingScrollView() -> UIScrollView? {
        pageViewController.view.subviews.compactMap { $0 as? UIScrollView }.first
    }

    private func installPagingPanRelay() {
        guard let paging = pagingScrollView() else { return }
        let pan = paging.panGestureRecognizer
        // The scroll view must remain its pan's delegate. A policy consulted
        // from gestureRecognizerShouldBegin yields vertical drags instead.
        StickyPanBypass.setPolicy(on: paging) { pan in
            let velocity = pan.velocity(in: pan.view)
            let clearlyVertical = abs(velocity.y) > abs(velocity.x) && abs(velocity.y) > ScrollRules.epsilon
            return !clearlyVertical
        }
        StickyPanBypass.install(for: pan)
        paging.isDirectionalLockEnabled = true
        paging.delaysContentTouches = false
        if #available(iOS 17.4, *) {
            paging.bouncesVertically = false
        }
    }

    private func installPagePanRelay(on scrollView: UIScrollView) {
        if scrollView === outerScrollView || scrollView === pagingScrollView() { return }
        StickyPanBypass.setPolicy(on: scrollView) { [weak self] pan in
            guard let self, let page = pan.view as? UIScrollView else { return true }
            return ScrollRules.pagePanShouldBegin(
                headerVisible: ScrollRules.pageMustHoldTop(
                    outerOffsetY: self.outerScrollView.contentOffset.y,
                    maxStickyOffset: self.maxStickyOffset
                ),
                velocity: pan.velocity(in: page),
                pageOffsetY: page.contentOffset.y,
                pageTopY: self.topRestingOffset(of: page)
            )
        }
        StickyPanBypass.install(for: scrollView.panGestureRecognizer)
    }

    /// The page pan is tracking and the outer pan is not. Move the header by
    /// the distance the page tried to scroll, then pin the page back.
    private func absorbPageDrag(_ scrollView: UIScrollView, oldOffset: CGPoint?) {
        let tracking = scrollView.isTracking || scrollView.isDragging
        if !tracking {
            if collapseDrag?.scrollView === scrollView {
                collapseDrag = nil
            }
            return
        }
        guard !outerScrollView.isTracking && !outerScrollView.isDragging else { return }
        // Normal in-range page scrolling must not be rewritten into a header move.
        if pageShouldScrollNormally { return }
        // The page-area pan owns this drag and writes both offsets itself.
        if collapsePan.state == .began || collapsePan.state == .changed { return }
        if collapseDrag?.scrollView !== scrollView {
            collapseDrag = CollapseDrag(
                scrollView: scrollView,
                pageStart: oldOffset?.y ?? scrollView.contentOffset.y,
                outerStart: outerScrollView.contentOffset.y
            )
        }
        guard let drag = collapseDrag else { return }
        let transferred = ScrollRules.transferDrag(
            pageOffsetY: scrollView.contentOffset.y,
            pageStartY: drag.pageStart,
            pageTopY: topRestingOffset(of: scrollView),
            outerStartY: drag.outerStart,
            maxStickyOffset: maxStickyOffset
        )
        if abs(transferred.outerY - outerScrollView.contentOffset.y) > ScrollRules.epsilon {
            pin(outerScrollView, toY: transferred.outerY)
        }
        if abs(transferred.pageY - scrollView.contentOffset.y) > ScrollRules.epsilon {
            pin(scrollView, toY: transferred.pageY)
        }
    }
}

// MARK: - KVO box

/// Display-link target that does not retain the pager.
/// The link is added to the main run loop, so `tick` is already on the main actor.
@MainActor
private final class CoastBox: NSObject {
    weak var owner: SlidePagerViewController?

    @objc func tick(_ link: CADisplayLink) {
        owner?.coastTick(link)
    }
}

private final class PageScrollObservation {
    weak var scrollView: UIScrollView?
    let observation: NSKeyValueObservation

    init(scrollView: UIScrollView, observation: NSKeyValueObservation) {
        self.scrollView = scrollView
        self.observation = observation
    }
}
