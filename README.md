# SlidePager

**Version 1.0.3.** SlidePager is a UIKit sticky-header container with three coordinated parts:

- a header that scrolls out of view
- a tab bar that pins below the top safe-area inset
- pages that swipe horizontally inside a `UIPageViewController`

```
┌──────────────────────────┐
│  Header (collapses)      │   scrolls fully out of view
│  Tab bar (sticky)        │   pins below the top safe-area inset
│  Page 1 | Page 2 | …     │   UIPageViewController, horizontal swipe
└──────────────────────────┘
```

A single vertical `UIScrollView` holds the header, tab bar, and pages, while a scroll-style `UIPageViewController` hosts the pages beneath the tab bar.

While the header is visible, vertical drags scroll the outer container. Once the tab bar reaches its sticky stop, vertical drags scroll the current page. Horizontal swipes stay dedicated to paging, so vertical scrolling and page switching never fight each other.

- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Behavior contract](#behavior-contract)
- [How the scroll coordination works](#how-the-scroll-coordination-works)
- [Custom tab bars](#custom-tab-bars)
- [Headers: fixed and dynamic heights](#headers-fixed-and-dynamic-heights)
- [Configuring state](#configuring-state)
- [Observing state](#observing-state)
- [Running the demo](#running-the-demo)
- [Running the tests](#running-the-tests)
- [Resizability](#resizability)
- [Known trade-offs](#known-trade-offs)
- [License](#license)

## Requirements

- iOS 15+
- Swift 6+
- No third-party dependencies

## Installation

**Xcode:** File → Add Package Dependencies… → `https://github.com/tommyming/SlidePager`

**Package.swift:**

```swift
dependencies: [
    .package(url: "https://github.com/tommyming/SlidePager", from: "1.0.3"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "SlidePager", package: "SlidePager"),
        ]
    ),
]
```

> Swift Package Manager resolves `from:` against git tags (not a field in `Package.swift`), so `1.0.3` refers to the git tag on the repository.

## Quick start

```swift
import SlidePager

let header = ProfileHeaderView() // any UIView
let tabBar = UnderlineTabBarView(titles: ["Posts", "Replies", "Media"])

let posts = PostsPage()
posts.title = "Posts"
let replies = RepliesPage()
replies.title = "Replies"
let media = MediaPage()
media.title = "Media"

let pager = SlidePagerViewController(
    header: header,
    headerHeight: 220,
    tabBar: tabBar,
    pages: [posts, replies, media]
)
pager.delegate = self

// Host it like any UIViewController:
navigationController?.pushViewController(pager, animated: true)
```

`SlidePagerViewController` and its state properties are `open`, so external modules can assign them directly and subclasses can override them. See [Configuring state](#configuring-state).

Pages with scrollable content (`UITableView`, `UICollectionView`, or `UIScrollView`) conform to `SlidePagerPage` and return their scroll view:

```swift
final class PostsPage: UIViewController, SlidePagerPage {
    let tableView = UITableView()

    var pageScrollView: UIScrollView? { tableView }
    // …
}
```

SlidePager never replaces a page scroll view's `delegate` or content insets. Instead, it observes `contentOffset`, coordinates pan ownership so vertical drags on a page collapse the header first, and writes back blocked offsets when the page must stay pinned. It also disables `delaysContentTouches` on coordinated scroll views for immediate response, and temporarily suspends page `bounces` during a cross-boundary handoff before restoring it when the gesture ends.

Pages without scrollable content can omit `SlidePagerPage`; vertical drags anywhere on those pages still collapse and expand the header.

Each page's `title` populates the tab bar. When the pager loads (or when `pages` or `tabBarView` are updated), it calls `reloadTabs(titles:)` with those titles, falling back to `"Tab 1"`, `"Tab 2"`, and so on for any `nil` title. That call replaces any initial titles passed to `UnderlineTabBarView`.

## Behavior contract

| Aspect | Behavior |
|---|---|
| Sticky threshold | The header scrolls completely out of view, and the tab bar pins just below the top safe-area inset (including under translucent navigation bars). |
| Bounce | Both the outer scroll view and each page preserve standard rubber-band bouncing. |
| Short pages | The header still collapses and expands even when the current page cannot scroll. |
| Page positions | All pages remain mounted in memory and retain their individual scroll offsets across tab switches. |
| Header vs. horizontal paging | Switching pages never moves or resets the header; incoming pages stay synced to the current collapse state so nothing jumps. |
| Release behavior | A partially collapsed header rests wherever you release it without snapping. |
| Safe area | The container fills its bounds, places the header below the top safe-area inset, pins the tabs to that inset when collapsed, and updates automatically when safe-area insets change. |

Vertical gesture ownership rules:

| Situation | View that scrolls vertically |
|---|---|
| Header is at least partly visible | Outer scroll view (the page stays at its top resting offset). |
| Tab bar is pinned and the page has scrolled or has room to scroll | Page scroll view (the outer scroll view stays at the sticky offset). |
| Tab bar is pinned, you pull down, and the page reaches its top | Outer scroll view (continues seamlessly to expand the header). |
| Tab bar is pinned and the page cannot scroll | Outer scroll view, including its normal vertical bounce. |
| Mostly horizontal swipe | `UIPageViewController` only (the outer scroll view ignores predominantly horizontal pans). |

## How the scroll coordination works

SlidePager combines simultaneous pan recognition with explicit single-owner offset rules:

1. **Simultaneous recognition and pan policies.** The outer scroll view (`StickyScrollView`) recognizes pans alongside page scroll views and `UIPageViewController`'s internal scroll view. Vertical drags on the paging scroll view are yielded via a `gestureRecognizerShouldBegin` policy and clamped to `contentOffset.y = 0`, while a dedicated `HeaderCollapsePan` on the page area drives the header when the page controller would otherwise capture the touch.
2. **Offset invariants (`ScrollRules`).** Whenever either scroll view moves, pure rules enforce two invariants:
   - While the header is visible, the page remains at its top resting offset (`-adjustedContentInset.top`).
   - While the page is scrolled past its top, the outer scroll view remains pinned at the sticky offset.
3. **Seamless handoffs and coasting.** When a collapse gesture crosses the sticky threshold, leftover travel and flick momentum carry straight into the page (and back into the header on a downward pull or flick). Touching down during deceleration stops coasting cleanly in place without resetting offsets.
4. **Horizontal isolation.** Predominantly horizontal pans are ignored by the outer scroll view and handled exclusively by `UIPageViewController`.

`ScrollRules` is implemented as pure functions covered directly by unit tests without UIKit gestures.

## Custom tab bars

Provide any `UIView` conforming to `SlidePagerTabBar`:

```swift
@MainActor
public protocol SlidePagerTabBar: AnyObject {
    var preferredHeight: CGFloat { get }
    var onSelection: ((Int) -> Void)? { get set }
    func reloadTabs(titles: [String])
    func setSelectedIndex(_ index: Int, animated: Bool)
    func setTransitionProgress(from: Int, to: Int, progress: CGFloat)
}
```

- `preferredHeight` specifies the height reserved for the tab bar.
- Invoke `onSelection` when the user taps a tab.
- `setSelectedIndex(_:animated:)` is called after a swipe settles or a programmatic selection.
- `setTransitionProgress(from:to:progress:)` updates continuously during interactive page swipes, where `progress` moves from `0` (`from`) to `1` (`to`). A default no-op implementation is provided if you only need discrete selection updates.

The built-in `UnderlineTabBarView` is an `open` class styled after Twitter/Instagram profile tabs. You can configure or override `underlineColor`, `titleFont`, `tabTitleColor`, `selectedTabTitleColor`, and `distribution` at any time, and override `preferredHeight` (get-only, `46` by default) in a subclass.

`distribution` defaults to `.leading` (title-sized tabs packed from the leading edge, scrolling horizontally when needed); `.fillEqually` distributes tabs evenly across the bar width. The underline indicator aligns under the selected tab on initial layout and tracks interactive page swipes.

## Headers: fixed and dynamic heights

Pass an explicit `headerHeight`, or pass `nil` to size the header from its Auto Layout fitting size:

```swift
SlidePagerViewController(header: header, headerHeight: nil, tabBar: tabBar, pages: pages)
```

Update the header height at any time—for example, when expanding profile details:

```swift
pager.updateHeaderHeight(320, animated: true)
```

You can also assign `headerView` to swap or remove (`nil`) the header, or assign `currentHeaderHeight` for an un-animated height update (equivalent to `updateHeaderHeight(_:animated: false)`). When the height changes, a fully collapsed header stays collapsed; otherwise, the current collapse offset is preserved and clamped to the new range.

## Configuring state

All configuration properties on `SlidePagerViewController` are `open`. Assigning them from outside the module updates the UI and scroll state immediately. If you override any of them in a subclass, call `super` so the pager applies the change.

| Property | Behavior on assignment |
|---|---|
| `pages` | Replaces the child pages (must be non-empty) and reloads tab titles from each page's `title`. Preserves `selectedIndex` if still in bounds, or clamps it. |
| `selectedIndex` | Switches to that page without animation (same as `selectPage(at:animated: false)`). Out-of-range indices are ignored. |
| `stickyState` | Scrolls the header to `.expanded`, `.collapsed`, or `.partiallyCollapsed(progress:)`. Assignments before load are applied on first layout. |
| `delegate` | Sets the `SlidePagerDelegate` observer. |
| `headerView` | Installs a new header view above the tab bar, or removes it when set to `nil`. |
| `tabBarView` | Replaces the tab bar view, reloads titles from `pages`, and preserves the current selection. |
| `currentHeaderHeight` | Sets an explicit height without animation (same as `updateHeaderHeight(_:animated: false)`). |

```swift
pager.pages = [posts, media]
pager.selectedIndex = 1
pager.stickyState = .collapsed
pager.currentHeaderHeight = 180
pager.headerView = ProfileHeaderView()
pager.tabBarView = UnderlineTabBarView(titles: ["Posts", "Media"])
```

Subclass override example:

```swift
final class LoggingPager: SlidePagerViewController {
    override var stickyState: StickyState {
        get { super.stickyState }
        set { super.stickyState = newValue }
    }
}
```

(`StickyState` is a `public` enum and the protocols are `public`, as Swift restricts `open` to classes and overridable class members.)

## Observing state

```swift
func slidePager(_ pager: SlidePagerViewController, didSelectTabAt index: Int) {
    // User tapped a tab.
}

func slidePager(_ pager: SlidePagerViewController, didTransitionToPageAt index: Int) {
    // A page transition (swipe, tab tap, or selectPage(at:animated:)) settled.
}

func slidePager(_ pager: SlidePagerViewController, didChangeStickyState state: StickyState) {
    switch state {
    case .expanded: …
    case .partiallyCollapsed(let progress): … // 0…1, useful for parallax effects
    case .collapsed: …
    }
}
```

All three `SlidePagerDelegate` methods are optional (with default no-op implementations) and are delivered on `@MainActor`. `didChangeStickyState` fires continuously as the header collapses or expands.

You can also switch pages programmatically with `selectPage(at:animated:)` and read `selectedIndex`, `stickyState`, and `currentHeaderHeight` at any time.

## Running the demo

Open **`Example/SlidePagerDemoApp.xcodeproj`** in Xcode and press **Cmd+R**.

The demo app builds against the local package at `../`, supports iPhone and iPad, and includes a list page, a grid (`UICollectionView`) page, a non-scrolling short page, and a second list page. The header button toggles animated height updates, and the **Configure** menu exercises all `open` state properties from outside the `SlidePager` module.

From the command line (pick an installed simulator from `xcrun simctl list devices available`):

```sh
xcodebuild -project Example/SlidePagerDemoApp.xcodeproj \
    -scheme SlidePagerDemoApp \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
    build
```

> Tip: Passing a destination with only `name=` targets `OS=latest`, so include `OS=` if you are targeting a specific runtime.

## Running the tests

Because SlidePager depends on UIKit, run tests against an iOS Simulator destination rather than plain `swift test` on macOS:

```sh
xcodebuild test \
    -scheme SlidePager \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
```

`SlidePager` is the scheme generated by Swift Package Manager for the package.

## Resizability

SlidePager adapts to dynamic container sizes and environments:

- Avoids `UIScreen.main`, `interfaceOrientation`, and `userInterfaceIdiom`; all geometry is derived from container bounds, trait collections, and safe-area insets.
- Rotation, Split View, Stage Manager, and foldable size changes re-run sticky geometry in `viewDidLayoutSubviews` and `viewSafeAreaInsetsDidChange` while preserving the current collapse state.
- Dynamic top safe-area inset changes update tab pinning and header layout automatically.

## Known trade-offs

- **Coasting continues across boundaries.** Flick deceleration uses normal scroll deceleration in both directions; a downward flick that reaches the top of a scrolled page continues into expanding the header.
- **Horizontal swipes start below the tab bar.** Swiping horizontally on the header itself does not change pages because `UIPageViewController`'s gesture lives below the tab bar.
- **Mounted pages stay in memory.** Each child view controller stays alive to preserve its scroll offset, so particularly heavy pages retain their memory footprint across tab switches.

## License

MIT. See [LICENSE](LICENSE).
