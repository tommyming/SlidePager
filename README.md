# SlidePager

**Version 1.0.0.** A reusable UIKit container: **sticky header + tab bar +
horizontally paged content**, with native-feeling nested-scroll coordination.

```
┌──────────────────────────┐
│  Header (collapses)      │   scrolls fully out of view
│  Tab bar (sticky)        │   pins below the top safe-area inset
│  Page 1 | Page 2 | …     │   UIPageViewController, horizontal swipe
└──────────────────────────┘
```

Everything lives inside one vertical `UIScrollView`. A `UIPageViewController`
(scroll style) hosts the pages beneath the tab bar. While the header is
visible the outer scroll view owns vertical pans; once the tab bar pins, the
current page's scroll view takes over — with no gesture fighting and no
interference with horizontal paging.

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

`1.0.0` is the git tag. Swift Package Manager does not read a version out of
`Package.swift`, so that tag has to exist on the repository before `from:`
resolves.

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

Each page that should participate in the nested-scroll coordination exposes
its primary scroll view:

```swift
final class PostsPage: UIViewController, SlidePagerPage {
    let tableView = UITableView()

    var pageScrollView: UIScrollView? { tableView }
    // …
}
```

The container never replaces a page scroll view's delegate or content insets.
It observes `contentOffset`, writes that offset back when the page is not
allowed to scroll, and coordinates pan ownership so a vertical drag on the
page collapses the header first. During that hand-off it temporarily sets the
page's `bounces` to `false` and restores the previous value when the gesture
ends. Pages without a scroll view (conformance omitted) work too; the header
still collapses from anywhere on them.

Tab titles come from each page's `title`. When the pager loads it calls
`reloadTabs(titles:)` with those titles, or `Tab 1`, `Tab 2`, … when `title`
is nil. That replaces whatever titles were passed to `UnderlineTabBarView`.

## Behavior contract

| Aspect | Behavior |
|---|---|
| Sticky threshold | Full collapse: the header scrolls completely away and the tab bar pins just below the top safe-area inset (under translucent nav bars). |
| Bounce | Native rubber-banding everywhere — outer scroll view and pages. |
| Short pages | The header always allows collapsing, even if the current page can't scroll. |
| Page positions | Preserved independently. Every page stays alive and keeps its own scroll offset across switches. |
| Header vs. horizontal paging | The header is completely independent of page swipes: it never moves or resets when switching tabs, and the incoming page is synced to the current collapse amount so nothing jumps. |
| Release behavior | Stay put: a partially collapsed header stays exactly where the user left it (no snapping). |
| Safe area | Edge-to-edge. The component fills the screen, lays the header out below the top safe-area inset (nav bar / status bar), and pins tabs below it. Safe-area changes while running are handled live. |

Vertical gesture rules ("who is allowed to scroll"):

| Situation | Allowed to scroll vertically |
|---|---|
| Header at least partly visible | Outer scroll view (the page is held at its top) |
| Tabs pinned, page has content below | Page's scroll view (outer held at the sticky point) |
| Tabs pinned, user pulls down, page reaches its top | Outer scroll view expands the header |
| Tabs pinned, page can't scroll (short page) | Outer scroll view (including its native bounce) |
| Any horizontal swipe | UIPageViewController only — the outer scroll view ignores predominantly horizontal pans |

## How the scroll coordination works

The container uses the **simultaneous-gesture + "who is allowed to scroll"**
technique:

1. The outer scroll view (a `UIScrollView` subclass) recognizes pan gestures
   *simultaneously* with any other scroll view's pan — including the pages'
   table/collection views and the `UIPageViewController`'s internal scroll
   view. The page controller's pan is gated so a vertical drag is not claimed
   by the horizontal pager, and a collapse pan on the page area drives the
   header when that pager would otherwise eat the gesture.
2. Because both scroll views track the finger, the container enforces two
   invariants (`ScrollRules`) whenever either `contentOffset` changes:
   - **Header visible → the page is pinned at its top resting offset.**
   - **Page scrolled past its top → the outer scroll view is pinned exactly
     at the sticky offset.**
3. Writing the disallowed view's offset back — frame by frame — produces the
   seamless hand-off: mid-drag, the moment the outer scroll view reaches the
   sticky point the page becomes free; the moment the page reaches its top
   the outer scroll view becomes free.
4. Horizontal paging stays smooth because the outer scroll view refuses to
   begin for predominantly horizontal pans, so a horizontal swipe belongs
   entirely to the page view controller.
5. Momentum hand-off: when a collapse gesture carries enough velocity to pass
   the sticky point, the leftover distance is redirected into the current
   page so scrolling doesn't stop dead when the tab bar pins.

The rules are implemented as pure functions (`ScrollRules`) and unit-tested
independently of UIKit gestures.

## Custom tab bars

Provide any view that conforms to `SlidePagerTabBar`:

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

- `preferredHeight` is how much vertical space the container reserves.
- Call `onSelection` when the user taps a tab.
- `setSelectedIndex` is called by the container to keep your tab bar in sync
  after swipes and programmatic transitions.
- `setTransitionProgress` runs while the user is swiping between pages
  (`progress` is `0` at `from` and `1` at `to`). It has an empty default, so a
  custom tab bar can omit it and only update on `setSelectedIndex`.

The built-in `UnderlineTabBarView` (Twitter/Instagram-style sliding
underline) exposes styling properties: `underlineColor`, `titleFont`,
`tabTitleColor`, `selectedTabTitleColor`, and `distribution`.
`.leading` (the default) packs title-sized tabs from the leading edge and
scrolls when they overflow. `.fillEqually` gives every tab the same width.
The underline is under the selected tab from the first layout, and it slides
with the page while you swipe.

## Headers: fixed and dynamic heights

Pass an explicit height, or pass `nil` to derive it from the header's autolayout
fitting size:

```swift
SlidePagerViewController(header: header, headerHeight: nil, tabBar: tabBar, pages: pages)
```

For dynamic headers (e.g. a profile that grows), update at any time:

```swift
pager.updateHeaderHeight(320, animated: true)
```

If the header was fully collapsed it stays fully collapsed; otherwise the
current collapse amount is preserved.

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

All three are optional. `SlidePagerDelegate` is `@MainActor`. `didChangeStickyState`
fires continuously while the header collapses/expands.

Programmatic control: `selectPage(at:animated:)`, `selectedIndex`,
`stickyState`, `currentHeaderHeight`.

## Running the demo

The easiest way is the bundled example app:

> Open **`Example/SlidePagerDemoApp.xcodeproj`** in Xcode and press Cmd+R.

It builds against the local package (referenced as `../`), runs on iPhone and
iPad, and shows list, grid, short, and a second list page, plus a header that
toggles its height at runtime. From the CLI:

```sh
xcodebuild -project Example/SlidePagerDemoApp.xcodeproj \
    -scheme SlidePagerDemoApp \
    -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' \
    build
```

A destination with only `name` is treated as `OS=latest`. Pass `OS=`, or name
a simulator that is on the newest runtime (`xcrun simctl list devices
available`).

The demo itself is also available as the `SlidePagerDemo` library product,
containing a self-contained `DemoViewController`, if you prefer hosting it in
your own app:

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

UIKit requires an iOS destination (plain `swift test` on macOS cannot link
UIKit):

```sh
xcodebuild test \
    -scheme SlidePager-Package \
    -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0'
```

Same destination rule as the demo: a bare `name` means `OS=latest`.

(The `SlidePager-Package` scheme is the aggregate scheme SPM generates; it
includes the test target. The plain `SlidePager` scheme only builds the
library.)

## Resizability

The component is built for modern, dynamically-sized scenes:

- No `UIScreen.main`, no `interfaceOrientation`, no `userInterfaceIdiom` —
  all geometry comes from the container's own bounds, trait collection, and
  safe-area insets.
- Rotation, split-screen, Stage Manager, and foldable size changes re-run the
  sticky geometry (`viewDidLayoutSubviews`,
  `viewSafeAreaInsetsDidChange`) while preserving the current collapse state.
- Safe areas are treated as asymmetric and dynamic: tabs pin below the
  *current* top inset, and the header reflows when it changes at runtime.

## Known trade-offs

- **Header flicks coast.** A flick that is moving the header keeps going
  after the finger lifts, with normal scroll deceleration, in both directions.
  A flick that brings a scrolled page back to its top continues into the header.
- **Horizontal swipes on the header itself do not page** — the page view
  controller's gesture area starts below the tab bar.
- Pages are kept alive for position preservation; very heavy pages pay the
  memory cost of staying in memory.

## License

MIT. See [LICENSE](LICENSE).
