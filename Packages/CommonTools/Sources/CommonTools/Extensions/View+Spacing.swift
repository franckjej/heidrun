import SwiftUI

public extension View {

    /// Convenience method to allow setting spacings along all edges with the `Spacing` enum without needing to use `.rawValue` every time.
    func padding(_ spacing: Spacing) -> some View {
        padding(.all, spacing.rawValue)
    }

    /// Convenience method to allow setting spacings along given edges with the `Spacing` enum without needing to use `.rawValue` every time.
    func padding(_ edges: Edge.Set, _ spacing: Spacing) -> some View {
        padding(edges, spacing.rawValue)
    }
}
