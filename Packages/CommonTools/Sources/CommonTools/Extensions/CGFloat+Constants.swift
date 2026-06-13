import CoreGraphics

public extension CGFloat {

    // MARK: - Corner radii

    static let cornerLow: CGFloat = 4
    static let cornerMed: CGFloat = 6
    static let cornerHigh: CGFloat = 8
    static let cornerUltraLow: CGFloat = 12
    static let cornerUltraMed: CGFloat = 14
    static let cornerUltraHigh: CGFloat = 16

    @MainActor static var initialAngle: CGFloat = -(.pi * 35)

    @MainActor static func endAngle(progress: CGFloat) -> CGFloat {
        .pi * 114 * progress + .initialAngle
    }
}
