import SwiftUI

extension View {
    /// Attach a Cmd+W keyboard shortcut to dismiss a sheet/panel via
    /// `action`. A single `.keyboardShortcut` can only register one
    /// combo per Button, so this hangs the shortcut off an invisible
    /// background button alongside whatever cancel/close affordance
    /// the sheet already exposes.
    public func closeOnCmdW(_ action: @escaping () -> Void) -> some View {
        background(
            Button("", action: action)
                .keyboardShortcut("w", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
    }
}
