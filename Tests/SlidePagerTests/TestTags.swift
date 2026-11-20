import Testing

/// Tags for filtering the suite from the Test Navigator or a test plan.
extension Tag {
    /// Pure scroll math; no UIKit types are instantiated.
    @Tag static var scrollMath: Self
    /// Suites that instantiate UIKit views headless (no window).
    @Tag static var uiKitHeadless: Self
}
