import AppKit

/// Read-only `NSTextView` configured for transcript display.
///
/// Three overrides keep the experience clean:
///   - `writeSelection(to:types:)` writes only `.string` (plain text), so
///     paste into any app always yields the user-confirmed transcript
///     format instead of RTF.
///   - `menu(for:)` strips Font / Spelling / Substitutions submenus.
///   - the `NSTextViewDelegate` link hook routes `hotline://`/`heidrun://`
///     clicks via `HotlineLinkClick.post` instead of `NSWorkspace.open`,
///     so the in-app dispatch doesn't trigger macOS's auto-spawn of an
///     extra WindowGroup instance for the URL receipt.
final class SelectableTextView: NSTextView, NSTextViewDelegate {

    override func writeSelection(
        to pboard: NSPasteboard,
        types: [NSPasteboard.PasteboardType]
    ) -> Bool {
        let selected = (string as NSString)
            .substring(with: selectedRange())
        guard !selected.isEmpty else { return false }
        pboard.declareTypes([.string], owner: nil)
        return pboard.setString(selected, forType: .string)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(
            withTitle: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        menu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        return menu
    }

    // MARK: - NSTextViewDelegate

    func textView(
        _ textView: NSTextView,
        clickedOnLink link: Any,
        at charIndex: Int
    ) -> Bool {
        let url: URL? = {
            if let urlLink = link as? URL { return urlLink }
            if let stringLink = link as? String { return URL(string: stringLink) }
            return nil
        }()
        guard let url else { return false }
        // Returning true tells NSTextView "I handled this click — don't
        // invoke NSWorkspace.open." We only consume hotline/heidrun;
        // http(s) etc. fall through to the default browser path.
        return HotlineLinkClick.post(url)
    }
}
