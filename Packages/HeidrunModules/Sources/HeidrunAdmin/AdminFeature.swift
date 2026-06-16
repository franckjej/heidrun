import SwiftUI
import HeidrunCore
import HeidrunUI

public enum AdminFeature: HeidrunFeature {
    public static let identifier  = "com.heidrun.admin"
    public static var displayName: String { String(localized: "Admin", bundle: .module) }
    public static let systemImage = "rectangle.badge.person.crop"

    @MainActor
    public static func makeContentView(client: any HotlineClient) -> AnyView {
        AnyView(AdminView(viewModel: AdminViewModel(client: client)))
    }
}
