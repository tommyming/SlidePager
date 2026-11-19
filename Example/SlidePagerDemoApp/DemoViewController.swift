import UIKit
import SlidePager

/// A self-contained demo of `SlidePagerViewController`.
///
/// Host it from any UIKit app:
///
///     window?.rootViewController = UINavigationController(rootViewController: DemoViewController())
///
/// or wrap it with `UIViewControllerRepresentable` in a SwiftUI app.
public final class DemoViewController: UIViewController, SlidePagerDelegate {

    private var pager: SlidePagerViewController?
    private let stateLabel = UILabel()

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

        let header = DemoHeaderView()
        let tabBar = UnderlineTabBarView(titles: ["List", "Grid", "Short", "List 2"])

        let pages: [UIViewController] = [
            DemoListPage(rows: 60, title: "List"),
            DemoGridPage(itemCount: 120, title: "Grid"),
            DemoShortPage(title: "Short"),
            DemoListPage(rows: 12, title: "List 2"),
        ]

        let pager = SlidePagerViewController(
            header: header,
            headerHeight: DemoHeaderView.expandedHeight,
            tabBar: tabBar,
            pages: pages
        )
        pager.delegate = self
        header.onToggleHeight = { [weak pager] in
            guard let pager = pager else { return }
            let midpoint = (DemoHeaderView.collapsedHeight + DemoHeaderView.expandedHeight) / 2
            let grown = pager.currentHeaderHeight > midpoint
            pager.updateHeaderHeight(
                grown ? DemoHeaderView.collapsedHeight : DemoHeaderView.expandedHeight,
                animated: true
            )
        }

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
        stateLabel.text = String(describing: StickyState.expanded)
        stateLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stateLabel)
        NSLayoutConstraint.activate([
            stateLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            stateLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
        ])
    }

    // MARK: - SlidePagerDelegate

    public func slidePager(_ pager: SlidePagerViewController, didChangeStickyState state: StickyState) {
        stateLabel.text = String(describing: state)
    }
}

// MARK: - Demo header

final class DemoHeaderView: UIView {
    static let expandedHeight: CGFloat = 230
    static let collapsedHeight: CGFloat = 140

    var onToggleHeight: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.systemIndigo.withAlphaComponent(0.15)

        let titleLabel = UILabel()
        titleLabel.text = "SlidePager"
        titleLabel.font = .systemFont(ofSize: 34, weight: .bold)

        let subtitleLabel = UILabel()
        subtitleLabel.text = "Scroll vertically, swipe horizontally, tap tabs."
        subtitleLabel.font = .systemFont(ofSize: 15)
        subtitleLabel.textColor = .secondaryLabel

        let button = UIButton(type: .system)
        button.setTitle("Toggle header size", for: .normal)
        button.addTarget(self, action: #selector(toggleTapped), for: .touchUpInside)

        for subview in [titleLabel, subtitleLabel, button] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
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
