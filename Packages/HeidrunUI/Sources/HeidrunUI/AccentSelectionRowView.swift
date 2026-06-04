import AppKit

/// Row view that keeps the `.inset` selection capsule fully emphasised
/// even when the table view isn't first responder. The default
/// `NSTableRowView` flips `isEmphasized` to `false` when the table
/// loses key (clicking into the body pane, opening a context menu /
/// sheet, the system steals focus), which fades the capsule to a faint
/// grey — visually indistinguishable from "not selected" on a white
/// background. In a 3-pane news browser the user has to keep track of
/// which row they picked, so emphasis stays on; `interiorBackgroundStyle`
/// follows automatically and the cell text keeps its white-on-accent
/// look.
///
/// Overriding `drawSelection(in:)` does NOT solve this — `.inset` style
/// tables paint the capsule themselves (the override is never called).
public final class AccentSelectionRowView: NSTableRowView {
    override public var isEmphasized: Bool {
        get { true }
        set { /* always emphasised */ }
    }

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}

/// `NSTextField` and `NSImageView` consume `mouseDown` (and accept first
/// responder) even when they're configured as inert labels. Inside a
/// table-view cell that steals key state from the table the instant a
/// click lands on a label, which makes the freshly-set selection capsule
/// repaint as "unselected" the same frame the user clicked — the user
/// sees a flash and the row never appears to stay selected. Returning
/// `nil` from `hitTest` makes the view transparent to mouse events so
/// the click goes straight to the row / table view.

public final class InertLabel: NSTextField {
    override public func hitTest(_ point: NSPoint) -> NSView? { nil }

    public convenience init() {
        self.init(labelWithString: "")
    }
}

public final class InertImageView: NSImageView {
    override public func hitTest(_ point: NSPoint) -> NSView? { nil }
}
