import UIKit
import Testing
@testable import SlidePager

/// Proves styling properties are `open` and overridable outside the module.
private final class TallUnderlineTabBar: UnderlineTabBarView {
    override var preferredHeight: CGFloat { 64 }
}

/// `UnderlineTabBarView` behavior not covered by `UnderlineTabBarViewTests`:
/// styling propagation, invalid indices, progress clamping, and empty reloads.
@MainActor
@Suite(.tags(.uiKitHeadless))
struct UnderlineTabBarStylingTests {

    private func makeLaidOutBar(titles: [String] = ["One", "Two", "Three"]) -> UnderlineTabBarView {
        let bar = UnderlineTabBarView(titles: titles)
        bar.frame = CGRect(x: 0, y: 0, width: 320, height: bar.preferredHeight)
        bar.layoutIfNeeded()
        return bar
    }

    /// Finds the 3pt underline indicator by shape, mirroring the existing tests.
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

    // MARK: - Styling

    @Test("a subclass can override the open preferred height")
    func subclassOverridesPreferredHeight() {
        let bar = TallUnderlineTabBar(titles: ["One"])
        #expect(bar.preferredHeight == 64)
        bar.underlineColor = .systemPink
        #expect(bar.underlineColor == .systemPink)
    }

    @Test("style properties propagate to every tab")
    func stylingPropagates() {
        let bar = makeLaidOutBar()
        let font = UIFont.monospacedSystemFont(ofSize: 20, weight: .bold)
        let unselected = UIColor.systemRed
        let selected = UIColor.systemGreen

        bar.titleFont = font
        bar.tabTitleColor = unselected
        bar.selectedTabTitleColor = selected

        for button in bar.buttons {
            #expect(button.titleFont == font)
            #expect(button.textColor == unselected)
            #expect(button.selectedTextColor == selected)
        }
    }

    @Test("underline color retints the indicator")
    func underlineColorRetints() {
        let bar = makeLaidOutBar()
        bar.underlineColor = .systemOrange
        #expect(underlineView(in: bar)?.backgroundColor == .systemOrange)
    }

    // MARK: - Invalid indices

    @Test("out-of-range selection is ignored", arguments: [-1, 3, 99])
    func invalidSelectionIgnored(index: Int) {
        let bar = makeLaidOutBar()
        bar.setSelectedIndex(1, animated: false)
        bar.setSelectedIndex(index, animated: false)

        #expect(bar.selectedIndex == 1)
        #expect(bar.buttons[1].isSelected)
        #expect(!bar.buttons[0].isSelected)
    }

    @Test("out-of-range transition progress is ignored", arguments: [-1, 3])
    func invalidTransitionIgnored(badIndex: Int) {
        let bar = makeLaidOutBar()
        let before = underlineView(in: bar)?.frame

        bar.setTransitionProgress(from: badIndex, to: 0, progress: 0.5)
        bar.setTransitionProgress(from: 0, to: badIndex, progress: 0.5)

        #expect(underlineView(in: bar)?.frame == before)
    }

    // MARK: - Progress clamping

    @Test("transition progress clamps to 0…1")
    func transitionProgressClamps() {
        let bar = makeLaidOutBar(titles: ["One", "Two"])

        bar.setTransitionProgress(from: 0, to: 1, progress: 1)
        let full = underlineView(in: bar)?.frame
        bar.setSelectedIndex(0, animated: false)
        let start = underlineView(in: bar)?.frame
        #expect(full != start)

        bar.setTransitionProgress(from: 0, to: 1, progress: 2.5)
        #expect(underlineView(in: bar)?.frame == full)

        bar.setTransitionProgress(from: 0, to: 1, progress: -3)
        #expect(underlineView(in: bar)?.frame == start)
    }

    // MARK: - Reloads

    @Test("reloading with no titles clears the bar and resets selection")
    func emptyReload() {
        let bar = makeLaidOutBar()
        bar.setSelectedIndex(2, animated: false)

        bar.reloadTabs(titles: [])
        #expect(bar.buttons.isEmpty)
        #expect(bar.selectedIndex == 0)

        bar.reloadTabs(titles: ["Solo"])
        #expect(bar.buttons.count == 1)
        #expect(bar.selectedIndex == 0)
        #expect(bar.buttons[0].isSelected)
    }

    // MARK: - Distribution

    @Test("distribution toggles the tab scroller")
    func distributionTogglesScrolling() {
        let bar = makeLaidOutBar()
        let scroller = bar.subviews.compactMap { $0 as? UIScrollView }.first
        #expect(scroller?.isScrollEnabled == true)

        bar.distribution = .fillEqually
        bar.layoutIfNeeded()
        #expect(scroller?.isScrollEnabled == false)

        bar.distribution = .leading
        bar.layoutIfNeeded()
        #expect(scroller?.isScrollEnabled == true)
    }

    // MARK: - Accessibility & sizing

    @Test("selection flips accessibility traits and labels stay set")
    func accessibilityTraits() {
        let bar = makeLaidOutBar()
        bar.setSelectedIndex(1, animated: false)

        #expect(bar.buttons[1].accessibilityTraits.contains(.selected))
        #expect(!bar.buttons[0].accessibilityTraits.contains(.selected))
        #expect(bar.buttons[0].accessibilityTraits.contains(.button))
        #expect(bar.buttons[0].accessibilityLabel == "One")
    }

    @Test("a tab sizes to its title plus padding")
    func tabIntrinsicSize() {
        let button = TabButton(title: "Profile", index: 0)
        let label = UILabel()
        label.text = "Profile"
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        let labelSize = label.intrinsicContentSize

        #expect(abs(button.intrinsicContentSize.width - (labelSize.width + 32)) < 0.5)
        #expect(abs(button.intrinsicContentSize.height - (labelSize.height + 22)) < 0.5)
    }
}
