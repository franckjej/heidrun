import SwiftUI

public struct LinearProgressStyle<Stroke: ShapeStyle, Background: ShapeStyle>: ProgressViewStyle {
    public init(stroke: Stroke, fill: Background, cornerRadius: CGFloat = .cornerMed, height: CGFloat = 8.0, animation: Animation = .linear) {
        self.stroke = stroke
        self.fill = fill
        self.cornerRadius = cornerRadius
        self.height = height
        self.animation = animation
    }

    var stroke: Stroke
    var fill: Background
    var cornerRadius: CGFloat = .cornerMed
    var height: CGFloat = 8.0
    var animation: Animation = .linear

    public func makeBody(configuration: Configuration) -> some View {
        let fractionCompleted = configuration.fractionCompleted ?? .zero

        return VStack {
            ZStack(alignment: .topLeading) {
                GeometryReader { geo in
                    withAnimation(animation) {
                        Rectangle()
                            .fill(fill)
                            .frame(width: min(CGFloat(fractionCompleted)*geo.size.width, geo.size.width))
                    }
                }
            }
            .frame(height: height)
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(stroke, lineWidth: 1)
            )
        }
    }
}
