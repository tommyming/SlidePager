import XCTest
@testable import SlidePager

@MainActor
final class UnderlineTabBarViewTests: XCTestCase {

    private func makeLaidOutBar(titles: [String]) -> UnderlineTabBarView {
        let bar = UnderlineTabBarView(titles: titles)
        bar.frame = CGRect(x: 0, y: 0, width: 320, height: bar.preferredHeight)
        bar.layoutIfNeeded()
        return bar
    }

    func testReloadBuildsButtonsAndSelectsFirst() {
        let bar = makeLaidOutBar(titles: ["One", "Two", "Three"])
        XCTAssertEqual(bar.buttons.count, 3)
        XCTAssertEqual(bar.selectedIndex, 0)
        XCTAssertTrue(bar.buttons[0].isSelected)
        XCTAssertFalse(bar.buttons[1].isSelected)
        XCTAssertFalse(bar.buttons[2].isSelected)
    }

    func testSetSelectedIndexUpdatesSelection() {
        let bar = makeLaidOutBar(titles: ["One", "Two", "Three"])
        bar.setSelectedIndex(2, animated: false)
        XCTAssertEqual(bar.selectedIndex, 2)
        XCTAssertTrue(bar.buttons[2].isSelected)
        XCTAssertFalse(bar.buttons[0].isSelected)
    }

    func testReloadTabsClampsSelection() {
        let bar = makeLaidOutBar(titles: ["One", "Two", "Three"])
        bar.setSelectedIndex(2, animated: false)
        bar.reloadTabs(titles: ["Only"])
        XCTAssertEqual(bar.selectedIndex, 0)
        XCTAssertEqual(bar.buttons.count, 1)
        XCTAssertTrue(bar.buttons[0].isSelected)
    }

    func testSelectionCallbackFires() {
        let bar = makeLaidOutBar(titles: ["One", "Two"])
        var selected: Int?
        bar.onSelection = { selected = $0 }
        bar.buttons[1].onSelect?(1)
        XCTAssertEqual(selected, 1)
    }

    func testTransitionProgressFollowsBetweenTabs() {
        let bar = makeLaidOutBar(titles: ["One", "Two", "Three"])
        bar.setSelectedIndex(0, animated: false)
        let start = underlineMidX(in: bar)
        bar.setTransitionProgress(from: 0, to: 1, progress: 1)
        let end = underlineMidX(in: bar)
        bar.setTransitionProgress(from: 0, to: 1, progress: 0.5)
        let mid = underlineMidX(in: bar)

        XCTAssertGreaterThan(end, start)
        XCTAssertEqual(mid, (start + end) / 2, accuracy: 1)
    }

    private func underlineView(in bar: UnderlineTabBarView) -> UIView? {
        func find(in view: UIView) -> UIView? {
            if abs(view.bounds.height - 3) < 0.5, view.bounds.width > 0, !(view is UIScrollView) {
                return view
            }
            for subview in view.subviews {
                if let found = find(in: subview) { return found }
            }
            return nil
        }
        return find(in: bar)
    }

    private func underlineMidX(in bar: UnderlineTabBarView) -> CGFloat {
        guard let underline = underlineView(in: bar) else {
            XCTFail("missing underline")
            return 0
        }
        return underline.frame.midX
    }

    func testInitialUnderlineSitsUnderTheFirstTab() {
        let bar = makeLaidOutBar(titles: ["One", "Two", "Three"])
        let underline = underlineView(in: bar)
        XCTAssertNotNil(underline)
        XCTAssertFalse(underline?.isHidden ?? true)
        XCTAssertGreaterThan(underline?.bounds.width ?? 0, 0)
        let firstMidX = bar.buttons[0].convert(CGPoint(x: bar.buttons[0].bounds.midX, y: 0), to: bar).x
        XCTAssertEqual(underline?.frame.midX ?? 0, firstMidX, accuracy: 1)
    }

    func testLeadingPacksTabsFromTheLeadingEdge() {
        let bar = makeLaidOutBar(titles: ["One", "Two"])
        bar.distribution = .leading
        bar.layoutIfNeeded()
        XCTAssertLessThan(bar.buttons[1].frame.maxX, bar.bounds.width - 40)
    }

    func testFillEquallySharesTheBarWidth() {
        let bar = makeLaidOutBar(titles: ["One", "Two", "Three"])
        bar.distribution = .fillEqually
        bar.layoutIfNeeded()
        let widths = bar.buttons.map(\.bounds.width)
        XCTAssertEqual(widths[0], widths[1], accuracy: 1)
        XCTAssertEqual(widths[1], widths[2], accuracy: 1)
        XCTAssertGreaterThan(widths[0], 60)
    }

    func testPreferredHeightIsPositive() {
        XCTAssertGreaterThan(makeLaidOutBar(titles: ["One"]).preferredHeight, 0)
    }
}
