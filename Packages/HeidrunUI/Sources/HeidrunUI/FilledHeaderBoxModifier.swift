import CommonTools
import SwiftUI

extension View {
    public func filledHeaderBox() -> some View {
        modifier(FilledHeaderBoxModifier())
    }
}

public struct FilledHeaderBoxModifier: ViewModifier {
    /// Outer height, including the vertical padding around the box.
    public static let height: CGFloat = 40
    public static let outerPadding = Spacing.xxsmall
    /// Height of the visible box.
    public static let boxHeight = height - 2 * outerPadding.rawValue

    public func body(content: Content) -> some View {
        GroupBox {
            content
            .padding(.vertical, .xxxsmall)
            .padding(.horizontal, .xsmall)
            .frame(height: 24)
        }
        .padding(.vertical, Self.outerPadding)
        .frame(height: Self.height)
        .background(.background)
    }
}
