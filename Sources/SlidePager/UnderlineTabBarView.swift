import UIKit

/// A single tab: a title that highlights when selected.
final class TabButton: UIControl {
    private let titleLabel = UILabel()

    /// Called with the button's index on tap.
    var onSelect: ((Int) -> Void)?

    var titleFont: UIFont = .systemFont(ofSize: 15, weight: .semibold) {
        didSet { titleLabel.font = titleFont }
    }

    var textColor: UIColor = .secondaryLabel {
        didSet { updateAppearance() }
    }

    var selectedTextColor: UIColor = .label {
        didSet { updateAppearance() }
    }

    init(title: String, index: Int) {
        super.init(frame: .zero)
        tag = index
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = .button

        titleLabel.text = title
        titleLabel.font = titleFont
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -11),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        ])
        updateAppearance()
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func tapped() {
        onSelect?(tag)
    }

    override var isSelected: Bool {
        didSet {
            updateAppearance()
            accessibilityTraits = isSelected ? [.button, .selected] : .button
        }
    }

    override var intrinsicContentSize: CGSize {
        let size = titleLabel.intrinsicContentSize
        return CGSize(width: size.width + 32, height: size.height + 22)
    }

    private func updateAppearance() {
        titleLabel.textColor = isSelected ? selectedTextColor : textColor
    }
}

/// The default tab bar: a horizontally scrollable row of titles with a
/// sliding underline indicator (Twitter/Instagram profile style).
///
/// All styling properties are `public` and can be changed at any time.
/// Provide any other view conforming to `SlidePagerTabBar` for a fully
/// custom look.
public final class UnderlineTabBarView: UIView, SlidePagerTabBar {
    /// How tabs share the bar's width.
    public enum Distribution: Equatable {
        /// Tabs size to their titles and pack from the leading edge. Extra tabs scroll.
        case leading
        /// Tabs share the bar width equally.
        case fillEqually
    }
    public var preferredHeight: CGFloat { 46 }

    public var onSelection: ((Int) -> Void)?

    /// The color of the sliding underline.
    public var underlineColor: UIColor = .systemBlue {
        didSet { underlineView.backgroundColor = underlineColor }
    }

    public var titleFont: UIFont = .systemFont(ofSize: 15, weight: .semibold) {
        didSet { buttons.forEach { $0.titleFont = titleFont } }
    }

    public var tabTitleColor: UIColor = .secondaryLabel {
        didSet { buttons.forEach { $0.textColor = tabTitleColor } }
    }

    public var selectedTabTitleColor: UIColor = .label {
        didSet { buttons.forEach { $0.selectedTextColor = selectedTabTitleColor } }
    }

    /// `.leading` packs title-sized tabs from the leading edge.
    /// `.fillEqually` gives every tab the same width and fills the bar.
    public var distribution: Distribution = .leading {
        didSet {
            guard distribution != oldValue else { return }
            applyDistribution()
        }
    }

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private(set) var buttons: [TabButton] = []
    private let underlineView = UIView()
    private(set) var selectedIndex: Int = 0
    private var isAnimatingSelection = false
    private var isTrackingTransition = false
    private var fillWidthConstraint: NSLayoutConstraint?

    public init(titles: [String], distribution: Distribution = .leading) {
        super.init(frame: .zero)
        backgroundColor = .systemBackground

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        underlineView.backgroundColor = underlineColor
        underlineView.layer.cornerRadius = 1.5
        scrollView.addSubview(underlineView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])
        fillWidthConstraint = stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        self.distribution = distribution
        applyDistribution()

        reloadTabs(titles: titles)
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        // The first selection happens before the bar has a width, so the
        // underline has nothing to sit under until this layout pass.
        setNeedsLayout()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - SlidePagerTabBar

    public func reloadTabs(titles: [String]) {
        buttons.forEach { $0.removeFromSuperview() }
        buttons = titles.enumerated().map { index, title in
            let button = TabButton(title: title, index: index)
            button.titleFont = titleFont
            button.textColor = tabTitleColor
            button.selectedTextColor = selectedTabTitleColor
            button.onSelect = { [weak self] selected in
                self?.onSelection?(selected)
            }
            stackView.addArrangedSubview(button)
            return button
        }
        if titles.isEmpty {
            selectedIndex = 0
            underlineView.frame = .zero
            return
        }
        setSelectedIndex(min(selectedIndex, titles.count - 1), animated: false)
    }

    public func setSelectedIndex(_ index: Int, animated: Bool) {
        guard buttons.indices.contains(index) else { return }
        selectedIndex = index
        for (position, button) in buttons.enumerated() {
            button.isSelected = (position == index)
        }
        isTrackingTransition = false
        updateUnderline(animated: animated)
        scrollSelectionIntoView(animated: animated)
    }

    public func setTransitionProgress(from: Int, to: Int, progress: CGFloat) {
        guard buttons.indices.contains(from), buttons.indices.contains(to) else { return }
        let clamped = min(max(progress, 0), 1)
        let start = underlineFrame(for: from)
        let end = underlineFrame(for: to)
        guard start != .zero, end != .zero else { return }
        isTrackingTransition = clamped > 0.001 && clamped < 0.999
        underlineView.frame = CGRect(
            x: start.minX + (end.minX - start.minX) * clamped,
            y: start.minY,
            width: start.width + (end.width - start.width) * clamped,
            height: start.height
        )
    }

    // MARK: - Layout

    override public func layoutSubviews() {
        super.layoutSubviews()
        guard !isAnimatingSelection, !isTrackingTransition, bounds.width > 0 else { return }
        // The stack often finishes measuring tabs after this pass. Ask for one
        // more layout so the indicator is visible at the initial selection
        // instead of staying at zero until the next interaction.
        scrollView.layoutIfNeeded()
        guard buttons.indices.contains(selectedIndex) else { return }
        let frame = underlineFrame(for: selectedIndex)
        guard frame.width > 0 else { return }
        underlineView.isHidden = false
        underlineView.frame = frame
    }

    private func applyDistribution() {
        switch distribution {
        case .leading:
            stackView.distribution = .fill
            fillWidthConstraint?.isActive = false
            scrollView.isScrollEnabled = true
        case .fillEqually:
            stackView.distribution = .fillEqually
            fillWidthConstraint?.isActive = true
            scrollView.isScrollEnabled = false
            scrollView.contentOffset = .zero
        }
        setNeedsLayout()
    }

    private func underlineFrame(for index: Int) -> CGRect {
        guard buttons.indices.contains(index) else { return .zero }
        let button = buttons[index]
        let buttonWidth = button.bounds.width > 0 ? button.bounds.width : button.intrinsicContentSize.width
        guard buttonWidth > 0 else { return .zero }
        let midX: CGFloat
        if button.bounds.width > 0 {
            // `button.frame` is in the stack, not the scroll view. Convert so the
            // indicator sits on the tab it is following.
            midX = scrollView.convert(CGPoint(x: button.bounds.midX, y: 0), from: button).x
        } else {
            var x = stackView.layoutMargins.left
            for candidate in buttons.prefix(index) {
                x += candidate.intrinsicContentSize.width + stackView.spacing
            }
            midX = x + buttonWidth / 2
        }
        let width = min(28, max(12, buttonWidth - 16))
        return CGRect(x: midX - width / 2, y: bounds.height - 3, width: width, height: 3)
    }

    private func updateUnderline(animated: Bool) {
        guard bounds.width > 0, buttons.indices.contains(selectedIndex) else { return }
        let target = underlineFrame(for: selectedIndex)
        guard target != .zero else { return }
        if animated, underlineView.frame != .zero {
            isAnimatingSelection = true
            UIView.animate(
                withDuration: 0.25,
                delay: 0,
                options: [.curveEaseInOut, .beginFromCurrentState],
                animations: { self.underlineView.frame = target },
                completion: { [weak self] _ in self?.isAnimatingSelection = false }
            )
        } else {
            underlineView.frame = target
        }
    }

    private func scrollSelectionIntoView(animated: Bool) {
        guard buttons.indices.contains(selectedIndex), scrollView.bounds.width > 0 else { return }
        let button = buttons[selectedIndex]
        let targetX = button.frame.midX - scrollView.bounds.width / 2
        let maxX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
        let x = min(max(0, targetX), maxX)
        scrollView.setContentOffset(CGPoint(x: x, y: 0), animated: animated)
    }
}
