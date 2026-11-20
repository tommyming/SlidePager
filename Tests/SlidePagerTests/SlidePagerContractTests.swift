import UIKit
import Testing
@testable import SlidePager

// MARK: - Helpers

/// A page with a table view, primed with scrollable content.
@MainActor
private final class ContractListPage: UIViewController, SlidePagerPage {
    let tableView = UITableView()
    var pageScrollView: UIScrollView? { tableView }

    init(title: String? = nil) {
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        tableView.contentSize = CGSize(width: 390, height: 4000)
    }
}

/// A page that conforms to `SlidePagerPage` but has no scroll view yet.
@MainActor
private final class ContractStaticPage: UIViewController, SlidePagerPage {
    var pageScrollView: UIScrollView? { nil }
}

/// Records every call the container makes to its tab bar.
@MainActor
private final class RecordingTabBar: UIView, SlidePagerTabBar {
    var preferredHeight: CGFloat { 46 }
    var onSelection: ((Int) -> Void)?

    private(set) var reloadCalls: [[String]] = []
    private(set) var selectionCalls: [(index: Int, animated: Bool)] = []
    private(set) var transitionCalls: [(from: Int, to: Int, progress: CGFloat)] = []

    func reloadTabs(titles: [String]) { reloadCalls.append(titles) }
    func setSelectedIndex(_ index: Int, animated: Bool) { selectionCalls.append((index, animated)) }
    func setTransitionProgress(from: Int, to: Int, progress: CGFloat) {
        transitionCalls.append((from, to, progress))
    }
}

@MainActor
private final class ContractRecorder: SlidePagerDelegate {
    var selections: [Int] = []
    var transitions: [Int] = []
    var states: [StickyState] = []

    func slidePager(_ pager: SlidePagerViewController, didSelectTabAt index: Int) {
        selections.append(index)
    }

    func slidePager(_ pager: SlidePagerViewController, didTransitionToPageAt index: Int) {
        transitions.append(index)
    }

    func slidePager(_ pager: SlidePagerViewController, didChangeStickyState state: StickyState) {
        states.append(state)
    }
}

// MARK: - Tests

/// The behavior contract documented in the README, verified end to end.
@MainActor
@Suite(.tags(.uiKitHeadless))
struct SlidePagerContractTests {

    private func makePager(
        header: UIView? = UIView(),
        headerHeight: CGFloat? = 200
    ) -> (pager: SlidePagerViewController, tabBar: RecordingTabBar, pages: [ContractListPage]) {
        let tabBar = RecordingTabBar()
        let pages = [
            ContractListPage(title: "Feed"),
            ContractListPage(title: "Grid"),
            ContractListPage(title: "About"),
        ]
        let pager = SlidePagerViewController(
            header: header, headerHeight: headerHeight, tabBar: tabBar, pages: pages
        )
        return (pager, tabBar, pages)
    }

    /// Loads the pager with a concrete size, since unit-test views have no window.
    private func load(_ pager: SlidePagerViewController) {
        pager.loadViewIfNeeded()
        pager.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        pager.view.layoutIfNeeded()
    }

    private func close(_ a: CGFloat, _ b: CGFloat, epsilon: CGFloat = 0.6) -> Bool {
        abs(a - b) <= epsilon
    }

    /// Pumps the main run loop (which drives UIKit animations) until the
    /// condition holds, or the timeout elapses.
    private func waitUntil(
        _ condition: () -> Bool,
        timeout: TimeInterval = 3
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }

    // MARK: - Tab titles

    @Test("the tab bar receives one title per page on load")
    func reloadTabsReceivesPageTitles() {
        let made = makePager()
        load(made.pager)
        #expect(made.tabBar.reloadCalls == [["Feed", "Grid", "About"]])
    }

    @Test("pages without titles fall back to Tab N")
    func nilTitlesFallBack() {
        let tabBar = RecordingTabBar()
        let pager = SlidePagerViewController(
            header: UIView(), headerHeight: 200, tabBar: tabBar,
            pages: [ContractListPage(), ContractListPage()]
        )
        load(pager)
        #expect(tabBar.reloadCalls == [["Tab 1", "Tab 2"]])
    }

    @Test("the initial settle does not push a selection to the tab bar")
    func initialSelectionIsSilent() {
        let made = makePager()
        load(made.pager)
        #expect(made.pager.selectedIndex == 0)
        #expect(made.tabBar.selectionCalls.isEmpty)
        #expect(made.tabBar.transitionCalls.isEmpty)
    }

    // MARK: - Selection

    @Test("programmatic selection syncs the tab bar and notifies the delegate")
    func programmaticSelectionSyncsTabBar() {
        let made = makePager()
        load(made.pager)
        let recorder = ContractRecorder()
        made.pager.delegate = recorder

        made.pager.selectPage(at: 2, animated: false)

        #expect(made.pager.selectedIndex == 2)
        #expect(made.tabBar.selectionCalls.count == 1)
        #expect(made.tabBar.selectionCalls.first?.index == 2)
        #expect(made.tabBar.selectionCalls.first?.animated == false)
        #expect(recorder.transitions == [2])
        #expect(recorder.selections.isEmpty, "a programmatic change is not a tab tap")
    }

    @Test("out-of-range selection is ignored", arguments: [-1, 3, 99])
    func invalidSelectionIgnored(index: Int) {
        let made = makePager()
        load(made.pager)
        let recorder = ContractRecorder()
        made.pager.delegate = recorder

        made.pager.selectPage(at: index, animated: false)

        #expect(made.pager.selectedIndex == 0)
        #expect(recorder.transitions.isEmpty)
    }

    @Test("a tab tap reports the selection and settles the new page")
    func tabTapFlow() {
        let made = makePager()
        load(made.pager)
        let recorder = ContractRecorder()
        made.pager.delegate = recorder

        made.tabBar.onSelection?(1)

        #expect(recorder.selections == [1])
        #expect(waitUntil { made.pager.selectedIndex == 1 }, "the animated transition should settle")
        #expect(recorder.transitions == [1])
        #expect(made.tabBar.selectionCalls.contains { $0.index == 1 })
    }

    @Test("tapping the visible tab does nothing")
    func sameTabTapIsNoOp() {
        let made = makePager()
        load(made.pager)
        let recorder = ContractRecorder()
        made.pager.delegate = recorder

        made.tabBar.onSelection?(0)

        #expect(recorder.selections.isEmpty)
        #expect(recorder.transitions.isEmpty)
        #expect(made.pager.selectedIndex == 0)
    }

    // MARK: - Scroll state across page switches

    @Test("a collapsed pager preserves each page's scroll offset across tab switches")
    func pageOffsetsSurviveTabSwitches() {
        let made = makePager()
        load(made.pager)
        let recorder = ContractRecorder()
        made.pager.delegate = recorder

        made.pager.outerScrollView.setContentOffset(CGPoint(x: 0, y: 200), animated: false)
        #expect(made.pager.stickyState == .collapsed)

        // Pre-scroll page 1 before it is ever shown.
        let grid = made.pages[1]
        grid.loadViewIfNeeded()
        grid.tableView.contentOffset = CGPoint(x: 0, y: 120)

        made.pager.selectPage(at: 1, animated: false)
        #expect(close(grid.tableView.contentOffset.y, 120))
        made.pager.selectPage(at: 0, animated: false)
        #expect(close(grid.tableView.contentOffset.y, 120), "offset must survive while collapsed")
        made.pager.selectPage(at: 1, animated: false)
        #expect(close(grid.tableView.contentOffset.y, 120))

        // The header itself never moved.
        #expect(close(made.pager.outerScrollView.contentOffset.y, 200))
        #expect(recorder.transitions == [1, 0, 1])
    }

    @Test("an expanded pager pins the incoming page to its top")
    func incomingPageSyncsToCollapse() {
        let made = makePager()
        load(made.pager)

        let grid = made.pages[1]
        grid.loadViewIfNeeded()
        grid.tableView.contentOffset = CGPoint(x: 0, y: 80)

        made.pager.selectPage(at: 1, animated: false)

        #expect(close(grid.tableView.contentOffset.y, 0), "incoming page syncs to the collapse amount")
        #expect(close(made.pager.outerScrollView.contentOffset.y, 0), "a page switch must not move the header")
    }

    // MARK: - Sticky state reporting

    @Test("partial collapse reports one continuous progress state")
    func partialCollapseStates() {
        let made = makePager()
        load(made.pager)
        let recorder = ContractRecorder()
        made.pager.delegate = recorder

        made.pager.outerScrollView.setContentOffset(CGPoint(x: 0, y: 100), animated: false)

        #expect(made.pager.stickyState == .partiallyCollapsed(progress: 0.5))
        #expect(recorder.states == [.partiallyCollapsed(progress: 0.5)])
    }

    @Test("a partly collapsed header does not snap after layout")
    func partialStaysAfterLayout() {
        let made = makePager()
        load(made.pager)
        made.pager.outerScrollView.setContentOffset(CGPoint(x: 0, y: 100), animated: false)

        made.pager.view.setNeedsLayout()
        made.pager.view.layoutIfNeeded()

        #expect(close(made.pager.outerScrollView.contentOffset.y, 100))
        #expect(made.pager.stickyState == .partiallyCollapsed(progress: 0.5))
    }

    // MARK: - Header height changes

    @Test("a partially collapsed header keeps its collapse when the header resizes")
    func headerResizePreservesPartialCollapse() {
        let made = makePager()
        load(made.pager)
        made.pager.outerScrollView.setContentOffset(CGPoint(x: 0, y: 100), animated: false)

        // Growing keeps the absolute collapse distance.
        made.pager.updateHeaderHeight(150, animated: false)
        #expect(made.pager.currentHeaderHeight == 150)
        #expect(close(made.pager.outerScrollView.contentOffset.y, 100))
        #expect(made.pager.stickyState == .partiallyCollapsed(progress: 100.0 / 150.0))

        // Shrinking past the current collapse clamps to fully collapsed.
        made.pager.updateHeaderHeight(80, animated: false)
        #expect(made.pager.currentHeaderHeight == 80)
        #expect(close(made.pager.outerScrollView.contentOffset.y, 80))
        #expect(made.pager.stickyState == .collapsed)
    }

    @Test("a nil height is derived from the header fitting size")
    func fittingSizeHeader() throws {
        let header = UIView()
        header.heightAnchor.constraint(equalToConstant: 123).isActive = true
        let tabBar = RecordingTabBar()
        let pager = SlidePagerViewController(
            header: header, headerHeight: nil, tabBar: tabBar, pages: [ContractListPage()]
        )
        load(pager)

        #expect(pager.currentHeaderHeight == 123)
        #expect(try #require(pager.headerView) === header)
    }

    @Test("updateHeaderHeight(nil) re-derives the fitting size")
    func rederiveAfterExplicit() {
        let header = UIView()
        header.heightAnchor.constraint(equalToConstant: 123).isActive = true
        let tabBar = RecordingTabBar()
        let pager = SlidePagerViewController(
            header: header, headerHeight: 200, tabBar: tabBar, pages: [ContractListPage()]
        )
        load(pager)
        #expect(pager.currentHeaderHeight == 200)

        pager.updateHeaderHeight(nil, animated: false)
        #expect(pager.currentHeaderHeight == 123)
    }

    // MARK: - Safe area

    /// A host that reports a fixed 100pt top safe-area inset, so the pager's
    /// safe-area layout can be exercised without a real scene.
    private final class FixedInsetHostView: UIView {
        override var safeAreaInsets: UIEdgeInsets {
            UIEdgeInsets(top: 100, left: 0, bottom: 0, right: 0)
        }
    }

    @Test("the header starts below the top safe-area inset")
    func safeAreaInsetLaysOutBelowTopInset() throws {
        let made = makePager()
        load(made.pager)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let host = FixedInsetHostView(frame: window.bounds)
        window.addSubview(host)
        made.pager.view.frame = host.bounds
        made.pager.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(made.pager.view)

        // Safe-area propagation itself triggers another layout pass
        // (viewSafeAreaInsetsDidChange), so pump a few cycles.
        for _ in 0..<3 {
            window.setNeedsLayout()
            window.layoutIfNeeded()
        }

        let header = try #require(made.pager.headerView)
        let container = try #require(header.superview)
        try #require(
            made.pager.view.safeAreaInsets.top == 100,
            "the host's insets must reach the pager's view"
        )
        let frameInOuter = made.pager.outerScrollView.convert(header.frame, from: container)
        #expect(close(frameInOuter.minY, 100))

        // The sticky stop is still the header height itself.
        made.pager.outerScrollView.setContentOffset(CGPoint(x: 0, y: 200), animated: false)
        #expect(made.pager.stickyState == .collapsed)

        made.pager.view.removeFromSuperview()
    }

    // MARK: - Pages without scroll views

    @Test("pages without a scroll view still collapse the header")
    func plainPagesCollapse() {
        let tabBar = RecordingTabBar()
        let pager = SlidePagerViewController(
            tabBar: tabBar,
            pages: [ContractStaticPage(), UIViewController()]
        )
        load(pager)
        #expect(pager.currentHeaderHeight == 0)
        #expect(pager.stickyState == .collapsed)

        pager.outerScrollView.setContentOffset(CGPoint(x: 0, y: 100), animated: false)
        #expect(pager.stickyState == .collapsed)
    }
}
