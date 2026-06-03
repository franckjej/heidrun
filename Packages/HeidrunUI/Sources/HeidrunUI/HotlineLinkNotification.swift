import Foundation

public extension Notification.Name {
    /// Posted when the user clicks a `hotline://` or `heidrun://` URL
    /// inside a transcript / news body. The host app's RootView listens
    /// and runs the normal connection-dispatch flow (`handleIncomingURL`)
    /// directly — bypassing `NSWorkspace.open(_:)` so macOS doesn't
    /// auto-spawn an empty WindowGroup instance for the URL receipt on
    /// top of the connection window we open explicitly.
    ///
    /// `userInfo[HotlineLinkClick.urlKey]` carries the `URL`. External
    /// link receipt (Finder double-click, browser, mail) is unrelated —
    /// it still flows through SwiftUI's `.onOpenURL`.
    static let heidrunHotlineLinkClicked = Notification.Name("HeidrunHotlineLinkClicked")
}

public enum HotlineLinkClick {
    public static let urlKey = "url"

    /// Post a click event for the given URL. Returns `true` when the
    /// URL is one of our schemes and the notification was posted —
    /// callers (NSTextView delegate, SwiftUI `OpenURLAction`) use the
    /// return value to decide whether to suppress the default
    /// `NSWorkspace.open` fall-through.
    @discardableResult
    public static func post(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "hotline" || scheme == "heidrun" else {
            return false
        }
        NotificationCenter.default.post(
            name: .heidrunHotlineLinkClicked,
            object: nil,
            userInfo: [urlKey: url]
        )
        return true
    }
}
