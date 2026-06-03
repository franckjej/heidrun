import SwiftUI

@frozen public enum RoundedBorderStyle {
    case roundedBorder, bottomLine, none
}

private struct RoundedBorder: ViewModifier {
    let style: RoundedBorderStyle
    let cornerRadius: CGFloat
    let borderColor: Color
    let lineWidth: CGFloat

    func body(content: Content) -> some View {
        switch style {
        case .roundedBorder:
            content
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: lineWidth)
                )
        case .bottomLine:
            VStack(alignment: .leading, spacing: 0) {
                content
                Spacer()
                    .frame(height: lineWidth)
                    .frame(maxWidth: .infinity)
                    .background(borderColor)
                    .offset(x: 0, y: -4.0)
                    .scaleEffect(0.97)
            }
        default:
            content
        }
    }
}

public extension View {
    func roundedBorder(borderStyle: RoundedBorderStyle = .roundedBorder, cornerRadius: CGFloat = .cornerLow, borderColor: Color =  Color(.systemGray.withAlphaComponent(0.7)), lineWidth: CGFloat = 1.0) -> some View {
        modifier(RoundedBorder(style: borderStyle, cornerRadius: cornerRadius, borderColor: borderColor, lineWidth: lineWidth))
    }
}

struct RoundedBorder_Previews: PreviewProvider {
    static var previews: some View {
        Text("some text")
            .padding(.medium)
            .roundedBorder()
    }
}
