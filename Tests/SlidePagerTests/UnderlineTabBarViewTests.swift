import UIKit
import Testing
@testable import SlidePager

@MainActor
@Suite(.tags(.uiKitHeadless))
struct UnderlineTabBarViewTests {

    private func makeLaidOutBar(titles: [String]) -> UnderlineTabBarView {
        let bar = UnderlineTabBarView(titles: titles)
        bar.frame = CGRect(x: 0, y: 0, width: 320, height: bar.preferredHeight)
        bar.layoutIfNeeded()
        return bar
    }

    /// Finds the 3pt underline indicator by shape.
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

    private func underlineMidX(in bar: UnderlineTabBarView) throws -> CGFloat {
        try #require(underlineView(in: bar)).frame.midX
    }

    @Test func `Reload builds buttons and selects first`() {
        let bar = makeLaidOutBar(titles: ["One", "Two", "Three"])
        #expect(bar.buttons.count == 3)
        #expect(bar.selectedIndex == 0)
        #expect(bar.buttons[0].isSelected)
        #expect(!bar.buttons[1].isSelected)
        #expect(!bar.buttons[2].isSelected)
    }

    @Test func `Set selected index updates selection`() {
        let bar = makeLaidOutBar(titles: ["One", "Two", "Three"])
        bar.setSelectedIndex(2, animated: false)
        #expect(bar.selectedIndex == 2)
        #expect(bar.buttons[2].isSelected)
        #expect(!bar.buttons[0].isSelected)
    }

    @Test func `Reload tabs clamps selection`() {
        let bar = makeLaidOutBar(titles: ["One", "Two", "Three"])
        bar.setSelectedIndex(2, animated: false)
        bar.reloadTabs(titles: ["Only"])
        #expect(bar.selectedIndex == 0)
        #expect(bar.buttons.count == 1)
        #expect(bar.buttons[0].isSelected)
    }

    @Test func `Selection callback fires`() {
        let bar = makeLaidOutBar(titles: ["One", "Two"])
        var selected: Int?
        bar.onSelection = { selected = $0 }
        bar.buttons[1].onSelect?(1)
        #expect(selected == 1)
    }

    @Test func `Transition progress follows between tabs`() throws {
        let bar = makeLaidOutBar(titles: ["One", "Two", "Three"])
        bar.setSelectedIndex(0, animated: false)
        let start = try underlineMidX(in: bar)
        bar.setTransitionProgress(from: 0, to: 1, progress: 1)
        let end = try underlineMidX(in: bar)
        bar.setTransitionProgress(from: 0, to: 1, progress: 0.5)
        let mid = try underlineMidX(in: bar)

        #expect(end > start)
        #expect(abs(mid - (start + end) / 2) < 1)
    }

    @Test func `Initial underline sits under the first tab`() throws {
        let bar = makeLaidOutBar(titles: ["One", "Two", "Three"])
        let underline = try #require(underlineView(in: bar))
        #expect(!underline.isHidden)
        #expect(underline.bounds.width > 0)
        let firstMidX = bar.buttons[0].convert(CGPoint(x: bar.buttons[0].bounds.midX, y: 0), to: bar).x
        #expect(abs(underline.frame.midX - firstMidX) < 1)
    }

    @Test func `Leading packs tabs from the leading edge`() {
        let bar = makeLaidOutBar(titles: ["One", "Two"])
        bar.distribution = .leading
        bar.layoutIfNeeded()
        #expect(bar.buttons[1].frame.maxX < bar.bounds.width - 40)
    }

    @Test func `Fill equally shares the bar width`() {
        let bar = makeLaidOutBar(titles: ["One", "Two", "Three"])
        bar.distribution = .fillEqually
        bar.layoutIfNeeded()
        let widths = bar.buttons.map(\.bounds.width)
        #expect(abs(widths[0] - widths[1]) < 1)
        #expect(abs(widths[1] - widths[2]) < 1)
        #expect(widths[0] > 60)
    }

    @Test func `Preferred height is positive`() {
        #expect(makeLaidOutBar(titles: ["One"]).preferredHeight > 0)
    }
}
