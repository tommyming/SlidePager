import UIKit
import Testing
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
@Suite(.tags(.uiKitHeadless))
struct SlidePagerViewControllerTests {

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

    @Test func `Initial selection and sticky state`() {
        let pager = makePager()
        load(pager)

        #expect(pager.selectedIndex == 0)
        #expect(pager.stickyState == .expanded)
        #expect(pager.currentHeaderHeight == 200)
        #expect(pager.pages.count == 3)
    }

    @Test func `Programmatic select notifies the delegate`() {
        let pager = makePager()
        load(pager)

        let recorder = DelegateRecorder()
        pager.delegate = recorder
        pager.selectPage(at: 2, animated: false)

        #expect(pager.selectedIndex == 2)
        #expect(recorder.transitions == [2])
    }

    @Test func `Selecting the same page is a no-op`() {
        let pager = makePager()
        load(pager)
        let recorder = DelegateRecorder()
        pager.delegate = recorder

        pager.selectPage(at: 0, animated: false)

        #expect(pager.selectedIndex == 0)
        #expect(recorder.transitions.isEmpty)
    }

    @Test func `Sticky state changes fire the delegate`() {
        let pager = makePager()
        load(pager)

        let recorder = DelegateRecorder()
        pager.delegate = recorder

        // Collapse fully by driving the outer scroll view to its sticky point.
        pager.outerScrollView.setContentOffset(CGPoint(x: 0, y: 200), animated: false)
        #expect(pager.stickyState == .collapsed)
        #expect(recorder.states.contains(.collapsed))

        // And expand again.
        pager.outerScrollView.setContentOffset(CGPoint(x: 0, y: 0), animated: false)
        #expect(pager.stickyState == .expanded)
    }

    @Test func `Expanded header pins page scrolling`() {
        let pager = makePager()
        load(pager)

        pager.selectPage(at: 1, animated: false)
        let page = pager.pages[1] as! TestListPage

        // While the header is visible, any attempt to scroll the page is
        // pinned back to its top resting offset.
        page.tableView.contentOffset = CGPoint(x: 0, y: 80)
        #expect(abs(page.tableView.contentOffset.y) < ScrollRules.epsilon + 0.1)
    }

    @Test func `Collapsed header lets the page scroll`() {
        let pager = makePager()
        load(pager)

        let page = pager.pages[0] as! TestListPage
        page.tableView.contentSize = CGSize(width: 390, height: 4000)

        pager.outerScrollView.setContentOffset(CGPoint(x: 0, y: 200), animated: false)
        #expect(pager.stickyState == .collapsed)

        page.tableView.contentOffset = CGPoint(x: 0, y: 80)
        #expect(abs(page.tableView.contentOffset.y - 80) < ScrollRules.epsilon + 0.1)
        #expect(abs(pager.outerScrollView.contentOffset.y - 200) < ScrollRules.epsilon + 0.1)
    }

    @Test func `Outer content extends by the header height`() {
        let pager = makePager()
        load(pager)

        #expect(
            pager.outerScrollView.contentSize.height > pager.outerScrollView.bounds.height + 100,
            "outer content must be taller than the viewport or a drag cannot collapse the header"
        )
    }

    @Test func `Expanded header page pan yields so the header can collapse`() {
        let pager = makePager()
        load(pager)
        let page = pager.pages[0] as! TestListPage

        // iOS requires the scroll view to remain its pan's delegate.
        #expect(page.tableView.panGestureRecognizer.delegate === page.tableView)
        #expect(
            !page.tableView.gestureRecognizerShouldBegin(page.tableView.panGestureRecognizer),
            "while the header is expanded, a vertical drag on the page must fail so the header can collapse"
        )
    }

    @Test func `Collapse pan covers the page controller`() {
        let pager = makePager()
        load(pager)
        #expect(
            gestureRecognizers(in: pager.view).contains { $0.name == StickyPanBypass.collapsePanName },
            "a drag on the page controller needs a pan that can collapse the header"
        )
    }

    @Test func `Paging scroll view stays its own pan delegate`() throws {
        let pager = makePager()
        load(pager)
        let paging = try #require(
            scrollViews(in: pager.view).first {
                $0 !== pager.outerScrollView && !($0 is UITableView) && $0.bounds.height > 100
            }
        )
        #expect(paging.panGestureRecognizer.delegate === paging)
        #expect(!paging.delaysContentTouches)
    }

    @Test func `Paging scroll view tracks with the outer pan`() throws {
        let pager = makePager()
        load(pager)

        let candidates = scrollViews(in: pager.view).filter {
            $0 !== pager.outerScrollView && !($0 is UITableView)
        }
        // The page controller's queuing scroll view is the tall horizontal one,
        // not the tab bar's short scroller.
        let pagingScrollView = try #require(
            candidates.first { $0.bounds.height > 100 },
            "UIPageViewController should host a horizontal scroll view"
        )
        let outerPan = pager.outerScrollView.panGestureRecognizer
        let allowed = outerPan.delegate?.gestureRecognizer?(
            outerPan,
            shouldRecognizeSimultaneouslyWith: pagingScrollView.panGestureRecognizer
        )
        #expect(allowed == true)
        #expect(pagingScrollView.isScrollEnabled)
    }

    @Test func `Outer pan recognizes simultaneously with the page pan`() {
        let pager = makePager()
        load(pager)
        let page = pager.pages[0] as! TestListPage

        let outerPan = pager.outerScrollView.panGestureRecognizer
        let pagePan = page.tableView.panGestureRecognizer
        let allowed = outerPan.delegate?.gestureRecognizer?(
            outerPan,
            shouldRecognizeSimultaneouslyWith: pagePan
        )
        #expect(
            allowed == true,
            "the outer pan delegate must allow the page pan to track so the header can collapse first"
        )
    }

    @Test func `Header height update preserves the pinned state`() {
        let pager = makePager()
        load(pager)

        // Collapse fully (outer offset == header height).
        pager.outerScrollView.setContentOffset(CGPoint(x: 0, y: 200), animated: false)
        #expect(pager.stickyState == .collapsed)

        // Growing the header while collapsed keeps it collapsed.
        pager.updateHeaderHeight(300, animated: false)
        pager.view.layoutIfNeeded()
        #expect(pager.currentHeaderHeight == 300)
        #expect(pager.stickyState == .collapsed)

        // Shrinking while collapsed keeps it collapsed, too.
        pager.updateHeaderHeight(120, animated: false)
        pager.view.layoutIfNeeded()
        #expect(pager.currentHeaderHeight == 120)
        #expect(pager.stickyState == .collapsed)
    }

    @Test func `No header means the tab bar pins immediately`() {
        let pages = [TestListPage(title: "One"), TestListPage(title: "Two")]
        let pager = SlidePagerViewController(
            tabBar: UnderlineTabBarView(titles: ["One", "Two"]),
            pages: pages
        )
        load(pager)

        #expect(pager.currentHeaderHeight == 0)
        #expect(pager.stickyState == .collapsed)
    }

    // MARK: - Traversal helpers

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
}
