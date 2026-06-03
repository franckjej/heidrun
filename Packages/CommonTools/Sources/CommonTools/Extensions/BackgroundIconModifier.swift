import SwiftUI
import Foundation

public struct BackgroundIcon: ViewModifier {
    let image: Image
    let size: CGSize
    let color: Color
    let opacity: Double
    @ViewBuilder
    public func body(content: Content) -> some View {
        ZStack(alignment: .center) {
            content
           image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: size.width, maxHeight: size.height, alignment: .center)
                .foregroundColor(color)
                .zIndex(0)
                .opacity(opacity)
        }
    }
}
extension View {
    @ViewBuilder
    public func cpaBackgroundIcon(_ image: Image = Image("CPABackgroundIcon"), size: CGSize = CGSize(width: 196, height: 196), color: Color = .secondary, opacity: Double = 0.1) -> some View {
        modifier(BackgroundIcon(image: image, size: size, color: color, opacity: opacity))
    }
}
