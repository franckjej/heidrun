import SwiftUI
import HeidrunCore
import HeidrunUI

public enum AdminFeature: HeidrunFeature {
    public static let identifier  = "com.heidrun.admin"
    public static let displayName = "Admin"
    public static let systemImage = "inset.filled.rectangle.and.person.filled"

    @MainActor
    public static func makeContentView(client: any HotlineClient) -> AnyView {
        AnyView(AdminView(viewModel: AdminViewModel(client: client)))
    }
}
