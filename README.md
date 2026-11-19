# SlidePager

**Version 1.0.0.** SlidePager is a UIKit container with three parts:

- a header that scrolls out of view
- a tab bar that stays below the top safe-area inset
- pages that swipe left and right

```
┌──────────────────────────┐
│  Header (collapses)      │   scrolls fully out of view
│  Tab bar (sticky)        │   stays below the top safe-area inset
│  Page 1 | Page 2 | …     │   UIPageViewController, horizontal swipe
└──────────────────────────┘
```

One vertical `UIScrollView` holds the header, the tab bar, and the pages. A `UIPageViewController` (scroll style) shows the pages under the tab bar.

While the header is visible, the outer scroll view scrolls vertically. After the tab bar reaches its stop, the current page scroll view scrolls vertically. A horizontal swipe still changes the page. The two gestures do not fight.

- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Behavior contract](#behavior-contract)
- [How the scroll coordination works](#how-the-scroll-coordination-works)
- [Custom tab bars](#custom-tab-bars)
- [Headers: fixed and dynamic heights](#headers-fixed-and-dynamic-heights)
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

**Xcode:** File → Add Package Dependencies… → `https://github.com/tommyming/SlidePager`.

**Package.swift:**

```swift
dependencies: [
    .package(url: "https://github.com/tommyming/SlidePager", from: "1.0.0"),
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

`1.0.0` is the git tag. Swift Package Manager does not read a version from `Package.swift`. The tag must exist on the repository before `from:` resolves.

## Quick start

```swift
import SlidePager

let header = ProfileHeaderView()                       // any UIView
let tabBar = UnderlineTabBarView(titles: ["Posts", "Replies", "Media"])

let posts = PostsPage()
posts.title = "Posts"
let replies = RepliesPage()
replies.title = "Replies"
let media = MediaPage()
media.title = "Media"

let pages: [UIViewController] = [posts, replies, media]

let pager = SlidePagerViewController(
    header: header,
    headerHeight: 220,
    tabBar: tabBar,
    pages: pages
)
pager.delegate = self

// Host it like any view controller, e.g.:
navigationController?.pushViewController(pager, animated: true)
```

A page that joins the nested scroll returns its main scroll view:

```swift
final class PostsPage: UIViewController, SlidePagerPage {
    let tableView = UITableView()

    var pageScrollView: UIScrollView? { tableView }
    // …
}
```

The container does not replace a page scroll view's delegate. It does not replace content insets. It reads `contentOffset`. When the page must not scroll, the container writes that offset back. It also decides which pan may move, so a vertical drag on the page collapses the header first.

During that transfer, the container sets the page `bounces` to `false`. When the gesture ends, it restores the previous value.

A page with no scroll view can omit `SlidePagerPage`. The header still collapses from any point on that page.

Each page `title` becomes a tab title. When the pager loads, it calls `reloadTabs(titles:)` with those titles. A nil `title` becomes `Tab 1`, `Tab 2`, and so on. That call replaces the titles you passed to `UnderlineTabBarView`.

## Behavior contract

| Aspect | Behavior |
|---|---|
| Sticky threshold | The header scrolls fully out of view. The tab bar then stops just below the top safe-area inset, including under a translucent navigation bar. |
| Bounce | The outer scroll view and each page use normal rubber-banding. |
| Short pages | The header can still collapse when the current page cannot scroll. |
| Page positions | Each page stays in memory. Each page keeps its own scroll offset when you change tabs. |
| Header vs. horizontal paging | A page swipe does not move or reset the header. The pager sets the incoming page to the current collapse amount, so the screen does not jump. |
| Release behavior | A partly collapsed header stays where you release it. It does not snap. |
| Safe area | The component fills the screen. It places the header below the top safe-area inset (navigation bar or status bar) and stops the tabs below that inset. It updates this layout when the safe area changes. |

Vertical gesture rules (which view may scroll):

| Situation | View that may scroll vertically |
|---|---|
| Header is at least partly visible | Outer scroll view. The page stays at its top. |
| The tab bar is at its stop, and the page has content below | Page scroll view. The outer scroll view stays at the sticky offset. |
| The tab bar is at its stop, you pull down, and the page reaches its top | Outer scroll view. It expands the header. |
| The tab bar is at its stop, and the page cannot scroll | Outer scroll view, including its normal bounce. |
| Any horizontal swipe | `UIPageViewController` only. The outer scroll view ignores a pan that is mostly horizontal. |

## How the scroll coordination works

The container uses two ideas at the same time: both pans can recognize, and only one view may scroll.

1. The outer scroll view is a `UIScrollView` subclass. It recognizes a pan at the same time as any other scroll view pan. That includes page table views, page collection views, and the scroll view inside `UIPageViewController`. The container blocks the page controller pan from claiming a vertical drag. A collapse pan on the page area moves the header when that pager would otherwise claim the gesture.
2. Both scroll views follow the finger. `ScrollRules` then keeps two rules whenever either `contentOffset` changes:
   - When the header is visible, the page stays at its top resting offset.
   - When the page is past its top, the outer scroll view stays at the sticky offset.
3. The container writes the blocked offset back on each frame. The transfer happens during the drag. When the outer scroll view reaches the sticky offset, the page may scroll. When the page reaches its top, the outer scroll view may scroll.
4. A mostly horizontal pan does not start the outer scroll view. That swipe belongs only to the page view controller.
5. A collapse gesture can move past the sticky offset. The container then gives the remaining distance to the current page. Scrolling does not stop when the tab bar reaches its stop.

`ScrollRules` is a set of pure functions. The unit tests cover those functions without UIKit gestures.

## Custom tab bars

Use any view that conforms to `SlidePagerTabBar`:

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

- `preferredHeight` is the vertical space the container reserves.
- Call `onSelection` when the user taps a tab.
- The container calls `setSelectedIndex` after a swipe or a programmatic change. Your tab bar stays in sync.
- `setTransitionProgress` runs while the user swipes between pages. `progress` is `0` at `from` and `1` at `to`. The default does nothing. A custom tab bar can omit it and update only in `setSelectedIndex`.

`UnderlineTabBarView` is the built-in tab bar. It shows a sliding underline, in the same style as Twitter and Instagram profile tabs. You can set `underlineColor`, `titleFont`, `tabTitleColor`, `selectedTabTitleColor`, and `distribution`.

`.leading` is the default. Tabs use the width of their titles, start at the leading edge, and scroll when they do not fit. `.fillEqually` gives every tab the same width. The underline sits under the selected tab on the first layout. It moves with the page during a swipe.

## Headers: fixed and dynamic heights

Pass a height, or pass `nil`. `nil` uses the header Auto Layout fitting size:

```swift
SlidePagerViewController(header: header, headerHeight: nil, tabBar: tabBar, pages: pages)
```

You can change the height later. A profile header that grows is one example:

```swift
pager.updateHeaderHeight(320, animated: true)
```

A fully collapsed header stays fully collapsed. In every other state, the pager keeps the current collapse distance. It clamps that distance to the new range.

## Observing state

```swift
func slidePager(_ pager: SlidePagerViewController, didSelectTabAt index: Int) {
    // The user tapped a tab.
}

func slidePager(_ pager: SlidePagerViewController, didTransitionToPageAt index: Int) {
    // A transition (swipe, tab tap, or selectPage(at:animated:)) settled.
}

func slidePager(_ pager: SlidePagerViewController, didChangeStickyState state: StickyState) {
    switch state {
    case .expanded: …
    case .partiallyCollapsed(let progress): … // 0…1, great for parallax
    case .collapsed: …
    }
}
```

All three methods are optional. `SlidePagerDelegate` is `@MainActor`. `didChangeStickyState` fires continuously while the header collapses or expands.

You can also call `selectPage(at:animated:)` and read `selectedIndex`, `stickyState`, and `currentHeaderHeight`.

## Running the demo

The example app is the shortest path:

> Open **`Example/SlidePagerDemoApp.xcodeproj`** in Xcode and press Cmd+R.

The project builds the local package at `../`. It runs on iPhone and iPad. It shows a list page, a grid page, a short page, and a second list page. The header can change height while the app runs.

From the CLI:

```sh
xcodebuild -project Example/SlidePagerDemoApp.xcodeproj \
    -scheme SlidePagerDemoApp \
    -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' \
    build
```

A destination with only `name` means `OS=latest`. Pass `OS=`, or use a simulator that is on the newest runtime. List simulators with `xcrun simctl list devices available`.

You can also host the demo in your own app. The `SlidePagerDemo` library product contains `DemoViewController`:

```swift
import SlidePagerDemo

// SceneDelegate.swift
func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
           options connectionOptions: UIScene.ConnectionOptions) {
    guard let windowScene = scene as? UIWindowScene else { return }
    let window = UIWindow(windowScene: windowScene)
    window.rootViewController = UINavigationController(rootViewController: DemoViewController())
    window.makeKeyAndVisible()
    self.window = window
}
```

Or from SwiftUI:

```swift
import SwiftUI
import SlidePagerDemo

struct DemoHost: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        UINavigationController(rootViewController: DemoViewController())
    }
    func updateUIViewController(_ vc: UIViewController, context: Context) {}
}
```

## Running the tests

UIKit needs an iOS destination. Plain `swift test` on macOS cannot link UIKit.

```sh
xcodebuild test \
    -scheme SlidePager-Package \
    -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0'
```

The destination rule is the same as the demo. A bare `name` means `OS=latest`.

`SlidePager-Package` is the aggregate scheme that Swift Package Manager generates. It includes the test target. The `SlidePager` scheme only builds the library.

## Resizability

The component uses the size of the current scene:

- It does not use `UIScreen.main`, `interfaceOrientation`, or `userInterfaceIdiom`. Geometry comes from the container bounds, the trait collection, and the safe-area insets.
- Rotation, split screen, Stage Manager, and a foldable size change run the sticky layout again. The methods are `viewDidLayoutSubviews` and `viewSafeAreaInsetsDidChange`. The current collapse state stays the same.
- The top inset can differ from the other insets, and it can change while the app runs. Tabs stop below the current top inset. The header lays out again when that inset changes.

## Known trade-offs

- **A header flick continues after you lift your finger.** Deceleration is the normal scroll deceleration, in both directions. A flick that returns a scrolled page to its top continues into the header.
- **A horizontal swipe on the header does not change the page.** The page view controller gesture starts below the tab bar.
- Each page stays in memory so its scroll position stays. A very heavy page uses that memory the whole time.

## License

MIT. See [LICENSE](LICENSE).
