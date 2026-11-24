import UIKit
import SlidePager

/// A self-contained demo of `SlidePagerViewController`.
///
/// Host it from any UIKit app:
///
///     window?.rootViewController = UINavigationController(rootViewController: DemoViewController())
///
/// or wrap it with `UIViewControllerRepresentable` in a SwiftUI app.
///
/// The Configure menu assigns the pager's `open` state from this app, which
/// lives outside the SlidePager module. The header button still animates the
/// height through `updateHeaderHeight(_:animated:)`.
public final class DemoViewController: UIViewController, SlidePagerDelegate {

    private var pager: SlidePagerViewController?
    private let stateLabel = UILabel()
    private let primaryHeader = DemoHeaderView()
    private let alternateHeader = DemoHeaderView(
        title: "Replaced header",
        subtitle: "Assigned through headerView.",
        background: UIColor.systemTeal.withAlphaComponent(0.22)
    )
    private var showingAlternateHeader = false
    private var usingAlternatePages = false
    private var tabsRestyled = false
    private var usingCustomTabBar = false
    private let primaryPages: [UIViewController] = [
        DemoListPage(rows: 60, title: "List"),
        DemoGridPage(itemCount: 120, title: "Grid"),
        DemoShortPage(title: "Short"),
        DemoListPage(rows: 12, title: "List 2"),
    ]
    private let alternatePages: [UIViewController] = [
        DemoListPage(rows: 8, title: "Notes"),
        DemoShortPage(title: "About"),
    ]

    public init() {
        super.init(nibName: nil, bundle: nil)
        title = "SlidePager"
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "slider.horizontal.3"),
            menu: UIMenu(title: "Configure", children: [
                UIDeferredMenuElement.uncached { [weak self] completion in
                    completion(self?.configureActions() ?? [])
                },
            ])
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = "Configure"

        let tabBar = UnderlineTabBarView(titles: titles(of: primaryPages))
        let pager = SlidePagerViewController(
            header: primaryHeader,
            headerHeight: DemoHeaderView.expandedHeight,
            tabBar: tabBar,
            pages: primaryPages
        )
        pager.delegate = self
        let toggleHeight = { [weak pager] in
            guard let pager else { return }
            let midpoint = (DemoHeaderView.collapsedHeight + DemoHeaderView.expandedHeight) / 2
            let grown = pager.currentHeaderHeight > midpoint
            pager.updateHeaderHeight(
                grown ? DemoHeaderView.collapsedHeight : DemoHeaderView.expandedHeight,
                animated: true
            )
        }
        primaryHeader.onToggleHeight = toggleHeight
        alternateHeader.onToggleHeight = toggleHeight

        addChild(pager)
        pager.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pager.view)
        NSLayoutConstraint.activate([
            pager.view.topAnchor.constraint(equalTo: view.topAnchor),
            pager.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            pager.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pager.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        pager.didMove(toParent: self)
        self.pager = pager

        stateLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        stateLabel.textColor = .secondaryLabel
        stateLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stateLabel)
        NSLayoutConstraint.activate([
            stateLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            stateLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            stateLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
        ])
        refreshStateLabel()
    }

    // MARK: - External configuration

    /// Menu actions assign `open` state. They do not call the library's methods
    /// except where animation is the point of the header button.
    private func configureActions() -> [UIMenuElement] {
        guard pager != nil else { return [] }
        return [
            UIMenu(title: "Sticky state", children: [
                stickyAction("Expanded", state: .expanded),
                stickyAction("Halfway", state: .partiallyCollapsed(progress: 0.5)),
                stickyAction("Collapsed", state: .collapsed),
            ]),
            UIMenu(title: "Select page", children: selectPageActions()),
            UIAction(title: usingAlternatePages ? "Restore pages" : "Replace pages") { [weak self] _ in
                self?.togglePages()
            },
            UIAction(title: showingAlternateHeader ? "Restore header" : "Replace header") { [weak self] _ in
                self?.toggleHeader()
            },
            UIAction(title: "Set header height") { [weak self] _ in
                self?.assignHeaderHeight()
            },
            UIAction(title: tabsRestyled ? "Restore tab style" : "Restyle tabs") { [weak self] _ in
                self?.toggleTabStyle()
            },
            UIAction(title: usingCustomTabBar ? "Restore tab bar" : "Swap tab bar") { [weak self] _ in
                self?.toggleTabBar()
            },
        ]
    }

    private func stickyAction(_ title: String, state: StickyState) -> UIAction {
        UIAction(title: title, state: stickyMatches(state) ? .on : .off) { [weak self] _ in
            self?.pager?.stickyState = state
        }
    }

    private func stickyMatches(_ state: StickyState) -> Bool {
        guard let current = pager?.stickyState else { return false }
        switch (current, state) {
        case (.expanded, .expanded), (.collapsed, .collapsed):
            return true
        case (.partiallyCollapsed(let progress), .partiallyCollapsed(let target)):
            return abs(progress - target) < 0.05
        default:
            return false
        }
    }

    private func selectPageActions() -> [UIAction] {
        guard let pager else { return [] }
        return pager.pages.enumerated().map { index, page in
            UIAction(
                title: page.title ?? "Tab \(index + 1)",
                state: pager.selectedIndex == index ? .on : .off
            ) { [weak self] _ in
                self?.pager?.selectedIndex = index
            }
        }
    }

    private func togglePages() {
        guard let pager else { return }
        usingAlternatePages.toggle()
        pager.pages = usingAlternatePages ? alternatePages : primaryPages
        refreshStateLabel()
    }

    private func toggleHeader() {
        guard let pager else { return }
        showingAlternateHeader.toggle()
        pager.headerView = showingAlternateHeader ? alternateHeader : primaryHeader
    }

    private func assignHeaderHeight() {
        guard let pager else { return }
        let midpoint = (DemoHeaderView.collapsedHeight + DemoHeaderView.expandedHeight) / 2
        let grown = pager.currentHeaderHeight > midpoint
        pager.currentHeaderHeight = grown ? DemoHeaderView.collapsedHeight : DemoHeaderView.expandedHeight
    }

    private func toggleTabStyle() {
        tabsRestyled.toggle()
        applyTabStyle()
    }

    private func applyTabStyle() {
        guard let bar = pager?.tabBarView as? UnderlineTabBarView else { return }
        bar.underlineColor = tabsRestyled ? .systemPink : .systemBlue
        bar.titleFont = tabsRestyled
            ? .systemFont(ofSize: 17, weight: .bold)
            : .systemFont(ofSize: 15, weight: .semibold)
        bar.tabTitleColor = tabsRestyled ? .systemOrange : .secondaryLabel
        bar.selectedTabTitleColor = tabsRestyled ? .systemPink : .label
        bar.distribution = tabsRestyled ? .fillEqually : .leading
    }

    private func toggleTabBar() {
        guard let pager else { return }
        usingCustomTabBar.toggle()
        let titles = titles(of: pager.pages)
        let bar: UnderlineTabBarView = usingCustomTabBar
            ? DemoTabBar(titles: titles)
            : UnderlineTabBarView(titles: titles)
        pager.tabBarView = bar
        applyTabStyle()
    }

    private func titles(of pages: [UIViewController]) -> [String] {
        pages.enumerated().map { index, page in
            page.title ?? "Tab \(index + 1)"
        }
    }

    private func refreshStateLabel() {
        guard let pager else { return }
        let title = pager.pages.indices.contains(pager.selectedIndex)
            ? (pager.pages[pager.selectedIndex].title ?? "Tab")
            : "—"
        stateLabel.text = "\(title) · \(pager.stickyState)"
    }

    // MARK: - SlidePagerDelegate

    public func slidePager(_ pager: SlidePagerViewController, didChangeStickyState state: StickyState) {
        refreshStateLabel()
    }

    public func slidePager(_ pager: SlidePagerViewController, didTransitionToPageAt index: Int) {
        refreshStateLabel()
    }
}

/// An `open` subclass from the demo app. Its height is reserved by the pager
/// because `preferredHeight` can be overridden outside the module.
private final class DemoTabBar: UnderlineTabBarView {
    override var preferredHeight: CGFloat { 58 }

    override init(titles: [String], distribution: Distribution = .leading) {
        super.init(titles: titles, distribution: distribution)
        underlineColor = .systemTeal
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

// MARK: - Demo header

final class DemoHeaderView: UIView {
    static let expandedHeight: CGFloat = 230
    static let collapsedHeight: CGFloat = 140

    var onToggleHeight: (() -> Void)?

    init(
        title: String = "SlidePager",
        subtitle: String = "Scroll, swipe, tap tabs, or open Configure.",
        buttonTitle: String = "Toggle header size",
        background: UIColor = UIColor.systemIndigo.withAlphaComponent(0.15)
    ) {
        super.init(frame: .zero)
        backgroundColor = background

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 34, weight: .bold)

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = .systemFont(ofSize: 15)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0

        let button = UIButton(type: .system)
        button.setTitle(buttonTitle, for: .normal)
        button.addTarget(self, action: #selector(toggleTapped), for: .touchUpInside)

        for subview in [titleLabel, subtitleLabel, button] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
            button.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
            button.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func toggleTapped() {
        onToggleHeight?()
    }
}

// MARK: - Demo pages

/// A table page: the classic case for sticky coordination.
final class DemoListPage: UIViewController, SlidePagerPage, UITableViewDataSource {
    let tableView = UITableView()
    private let rows: Int

    var pageScrollView: UIScrollView? { tableView }

    init(rows: Int, title: String) {
        self.rows = rows
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
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var configuration = cell.defaultContentConfiguration()
        configuration.text = "Row \(indexPath.row + 1)"
        configuration.secondaryText = "Keeps its own scroll position"
        cell.contentConfiguration = configuration
        cell.accessoryType = .disclosureIndicator
        return cell
    }
}

/// A collection page: same coordination, different scroll view kind.
final class DemoGridPage: UIViewController, SlidePagerPage, UICollectionViewDataSource {
    let collectionView: UICollectionView
    private let itemCount: Int
    private let palette: [UIColor] = [
        .systemBlue, .systemTeal, .systemIndigo,
        .systemOrange, .systemPink, .systemGreen,
    ]

    var pageScrollView: UIScrollView? { collectionView }

    init(itemCount: Int, title: String) {
        self.itemCount = itemCount
        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0 / 3.0),
            heightDimension: .fractionalHeight(1.0)
        ))
        item.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2)
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .fractionalWidth(1.0 / 3.0)
            ),
            subitems: [item]
        )
        let layout = UICollectionViewCompositionalLayout(section: NSCollectionLayoutSection(group: group))
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        collectionView.dataSource = self
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        itemCount
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
        cell.backgroundColor = palette[indexPath.item % palette.count]
        cell.layer.cornerRadius = 8
        cell.clipsToBounds = true
        return cell
    }
}

/// A page with no scroll view at all: the header still collapses (drag up
/// anywhere), it just never hands off to a page.
final class DemoShortPage: UIViewController {
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
        view.backgroundColor = .secondarySystemBackground

        let label = UILabel()
        label.text = """
            This page cannot scroll.

            Swipe up here anyway — the header still collapses, because \
            the outer scroll view always allows it.
            Swipe down to bring the header back.
            """
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 17, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}
