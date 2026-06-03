import SwiftUI

public struct Hairline: View {
    public init(color: Color = Color.gray.opacity(0.3)) {
        self.color = color
    }
    // MARK: - Init
    let color: Color

    // MARK: - View

    public var body: some View {
        Spacer()
            .frame(height: 0.5)
            .frame(maxWidth: .infinity)
            .background(color)
    }
}
