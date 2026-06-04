import SwiftUI

extension View {
    /// Attach Cmd+W and Cmd+. (the macOS-standard Cancel chord) so
    /// either dismisses the sheet/panel via `action`. A single
    /// `.keyboardShortcut` can only register one combo per Button, so
    /// each chord hangs off its own zero-size invisible background
    /// button alongside whatever cancel/close affordance the sheet
    /// already exposes.
    public func closeOnCmdW(_ action: @escaping () -> Void) -> some View {
        background(
            ZStack {
                shortcutCatcher(key: "w", action: action)
                shortcutCatcher(key: ".", action: action)
            }
        )
    }

    private func shortcutCatcher(
        key: KeyEquivalent,
        action: @escaping () -> Void
    ) -> some View {
        Button("", action: action)
            .keyboardShortcut(key, modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}
