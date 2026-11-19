import XCTest
@testable import SlidePager

private final class TestListPage: UIViewController, SlidePagerPage {
    let tableView = UITableView()

    var pageScrollView: UIScrollView? { tableView }

    init(title: String) {
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
    }
}

@MainActor
private final class DelegateRecorder: SlidePagerDelegate {
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

@MainActor
final class SlidePagerViewControllerTests: XCTestCase {

    private func makePager() -> SlidePagerViewController {
        let pages = [
            TestListPage(title: "One"),
            TestListPage(title: "Two"),
            TestListPage(title: "Three"),
        ]
        return SlidePagerViewController(
            header: UIView(),
            headerHeight: 200,
            tabBar: UnderlineTabBarView(titles: ["One", "Two", "Three"]),
            pages: pages
        )
    }

    /// Loads the pager with a concrete size, since unit-test views have no window.
    private func load(_ pager: SlidePagerViewController) {
        pager.loadViewIfNeeded()
        pager.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        pager.view.layoutIfNeeded()
    }

    func testInitialSelectionAndStickyState() {
        let pager = makePager()
        load(pager)

        XCTAssertEqual(pager.selectedIndex, 0)
        XCTAssertEqual(pager.stickyState, .expanded)
        XCTAssertEqual(pager.currentHeaderHeight, 200)
        XCTAssertEqual(pager.pages.count, 3)
    }

    func testProgrammaticSelectNotifiesDelegate() {
        let pager = makePager()
        load(pager)

        let recorder = DelegateRecorder()
        pager.delegate = recorder
        pager.selectPage(at: 2, animated: false)

        XCTAssertEqual(pager.selectedIndex, 2)
        XCTAssertEqual(recorder.transitions, [2])
    }

    func testSelectingSamePageIsNoOp() {
        let pager = makePager()
        load(pager)
        let recorder = DelegateRecorder()
        pager.delegate = recorder

        pager.selectPage(at: 0, animated: false)

        XCTAssertEqual(pager.selectedIndex, 0)
        XCTAssertTrue(recorder.transitions.isEmpty)
    }

    func testStickyStateChangesFireDelegate() {
        let pager = makePager()
        load(pager)

        let recorder = DelegateRecorder()
        pager.delegate = recorder

        // Collapse fully by driving the outer scroll view to its sticky point.
        pager.outerScrollView.setContentOffset(CGPoint(x: 0, y: 200), animated: false)
        XCTAssertEqual(pager.stickyState, .collapsed)
        XCTAssertTrue(recorder.states.contains(.collapsed))

        // And expand again.
        pager.outerScrollView.setContentOffset(CGPoint(x: 0, y: 0), animated: false)
        XCTAssertEqual(pager.stickyState, .expanded)
    }

    func testExpandedHeaderPinsPageScrolling() {
        let pager = makePager()
        load(pager)

        pager.selectPage(at: 1, animated: false)
        let page = pager.pages[1] as! TestListPage

        // While the header is visible, any attempt to scroll the page is
        // pinned back to its top resting offset.
        page.tableView.contentOffset = CGPoint(x: 0, y: 80)
        XCTAssertEqual(page.tableView.contentOffset.y, 0, accuracy: ScrollRules.epsilon + 0.1)
    }

    func testCollapsedHeaderLetsPageScroll() {
        let pager = makePager()
        load(pager)

        let page = pager.pages[0] as! TestListPage
        page.tableView.contentSize = CGSize(width: 390, height: 4000)

        pager.outerScrollView.setContentOffset(CGPoint(x: 0, y: 200), animated: false)
        XCTAssertEqual(pager.stickyState, .collapsed)

        page.tableView.contentOffset = CGPoint(x: 0, y: 80)
        XCTAssertEqual(page.tableView.contentOffset.y, 80, accuracy: ScrollRules.epsilon + 0.1)
        XCTAssertEqual(pager.outerScrollView.contentOffset.y, 200, accuracy: ScrollRules.epsilon + 0.1)
    }

    func testOuterContentExtendsByHeaderHeight() {
        let pager = makePager()
        load(pager)

        XCTAssertGreaterThan(
            pager.outerScrollView.contentSize.height,
            pager.outerScrollView.bounds.height + 100,
            "outer content must be taller than the viewport or a drag cannot collapse the header"
        )
    }

    func testExpandedHeaderPagePanYieldsSoHeaderCanCollapse() {
        let pager = makePager()
        load(pager)
        let page = pager.pages[0] as! TestListPage

        // iOS requires the scroll view to remain its pan's delegate.
        XCTAssertTrue(page.tableView.panGestureRecognizer.delegate === page.tableView)
        XCTAssertFalse(
            page.tableView.gestureRecognizerShouldBegin(page.tableView.panGestureRecognizer),
            "while the header is expanded, a vertical drag on the page must fail so the header can collapse"
        )
    }

    func testCollapsePanCoversThePageController() {
        let pager = makePager()
        load(pager)
        XCTAssertTrue(
            gestureRecognizers(in: pager.view).contains { $0.name == StickyPanBypass.collapsePanName },
            "a drag on the page controller needs a pan that can collapse the header"
        )
    }

    func testPagingScrollViewStaysItsOwnPanDelegate() {
        let pager = makePager()
        load(pager)
        let paging = scrollViews(in: pager.view).first {
            $0 !== pager.outerScrollView && !($0 is UITableView) && $0.bounds.height > 100
        }
        XCTAssertNotNil(paging)
        XCTAssertTrue(paging!.panGestureRecognizer.delegate === paging)
        XCTAssertFalse(paging!.delaysContentTouches)
    }

    func testPagingScrollViewTracksWithOuterPan() {
        let pager = makePager()
        load(pager)

        let candidates = scrollViews(in: pager.view).filter {
            $0 !== pager.outerScrollView && !($0 is UITableView)
        }
        // The page controller's queuing scroll view is the tall horizontal one,
        // not the tab bar's short scroller.
        let pagingScrollView = candidates.first { $0.bounds.height > 100 }
        XCTAssertNotNil(pagingScrollView, "UIPageViewController should host a horizontal scroll view")
        let outerPan = pager.outerScrollView.panGestureRecognizer
        let allowed = outerPan.delegate?.gestureRecognizer?(
            outerPan,
            shouldRecognizeSimultaneouslyWith: pagingScrollView!.panGestureRecognizer
        )
        XCTAssertEqual(allowed, true)
        XCTAssertTrue(pagingScrollView!.isScrollEnabled)
    }

    private func gestureRecognizers(in view: UIView) -> [UIGestureRecognizer] {
        var found = view.gestureRecognizers ?? []
        for subview in view.subviews {
            found.append(contentsOf: gestureRecognizers(in: subview))
        }
        return found
    }

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        var found: [UIScrollView] = []
        if let scrollView = view as? UIScrollView {
            found.append(scrollView)
        }
        for subview in view.subviews {
            found.append(contentsOf: scrollViews(in: subview))
        }
        return found
    }

    func testOuterPanRecognizesSimultaneouslyWithPagePan() {
        let pager = makePager()
        load(pager)
        let page = pager.pages[0] as! TestListPage

        let outerPan = pager.outerScrollView.panGestureRecognizer
        let pagePan = page.tableView.panGestureRecognizer
        let allowed = outerPan.delegate?.gestureRecognizer?(
            outerPan,
            shouldRecognizeSimultaneouslyWith: pagePan
        )
        XCTAssertEqual(
            allowed,
            true,
            "outer pan delegate is \(String(describing: type(of: outerPan.delegate))); it must allow the page pan to track so the header can collapse first"
        )
    }

    func testHeaderHeightUpdatePreservesPinnedState() {
        let pager = makePager()
        load(pager)

        // Collapse fully (outer offset == header height).
        pager.outerScrollView.setContentOffset(CGPoint(x: 0, y: 200), animated: false)
        XCTAssertEqual(pager.stickyState, .collapsed)

        // Growing the header while collapsed keeps it collapsed.
        pager.updateHeaderHeight(300, animated: false)
        pager.view.layoutIfNeeded()
        XCTAssertEqual(pager.currentHeaderHeight, 300)
        XCTAssertEqual(pager.stickyState, .collapsed)

        // Shrinking while collapsed keeps it collapsed, too.
        pager.updateHeaderHeight(120, animated: false)
        pager.view.layoutIfNeeded()
        XCTAssertEqual(pager.currentHeaderHeight, 120)
        XCTAssertEqual(pager.stickyState, .collapsed)
    }

    func testNoHeaderTabBarPinsImmediately() {
        let pages = [TestListPage(title: "One"), TestListPage(title: "Two")]
        let pager = SlidePagerViewController(
            tabBar: UnderlineTabBarView(titles: ["One", "Two"]),
            pages: pages
        )
        load(pager)

        XCTAssertEqual(pager.currentHeaderHeight, 0)
        XCTAssertEqual(pager.stickyState, .collapsed)
    }
}
