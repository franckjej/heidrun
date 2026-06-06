import CommonTools
import SwiftUI

extension View {
    public func filledHeaderBox() -> some View {
        modifier(FilledHeaderBoxModifier())
    }
}

public struct FilledHeaderBoxModifier: ViewModifier {
    public func body(content: Content) -> some View {
        GroupBox {
            content
            .padding(.vertical, .xxxsmall)
            .padding(.horizontal, .xsmall)
            .frame(height: 24)
        }
        .padding(.vertical, .xxsmall)
        .frame(height: 40)
        .background(.background)
    }
}
