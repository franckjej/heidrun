import AppKit

/// A simple class to go between the functional style of SwiftUI and the
/// specific needs for #selectors in NSMenuItem.
///
/// For this to work, you must keep a reference to this Proxy object until the
/// context menu has disappeared.
final class NSMenuItemProxy: NSObject {
    var title: String
    var keyEquivalent: String

    typealias Action = () -> Void
    var action: Action?

    private var isSeparator = false

    init(title: String, keyEquivalent: String, action: Action?) {
        self.title = title
        self.keyEquivalent = keyEquivalent
        self.action = action
    }

    static func separator() -> NSMenuItemProxy {
        NSMenuItemProxy(isSeparator: ())
    }
    private init(isSeparator: Void) {
        // Unused
        self.title = ""
        self.keyEquivalent = ""
        self.action = nil

        self.isSeparator = true
    }

    func createMenuItem() -> NSMenuItem {
        if isSeparator {
            return NSMenuItem.separator()
        }

        let item = NSMenuItem(title: title, action: nil, keyEquivalent: keyEquivalent)
        if action != nil {
            item.isEnabled = true
            item.target = self
            item.action = #selector(NSMenuItemProxy.handleAction)
        }

        return item
    }

    @objc private func handleAction() {
        guard let action = self.action else { return }

        action()
    }
}
