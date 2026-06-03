import Foundation
import SwiftUI

public struct WindowAccessor: NSViewRepresentable {
    @Binding public var window: NSWindow?

    public init(window: Binding<NSWindow?>) {
        self._window = window
    }

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.window = view.window
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {}
}
