import SwiftUI
import HeidrunCore
import HeidrunUI

public enum AgreementFeature: HeidrunFeature {
    public static let identifier  = "com.heidrun.agreement"
    public static var displayName: String { String(localized: "Agreement", bundle: .module) }
    public static let systemImage = "doc.text"

    @MainActor
    public static func makeContentView(client: any HotlineClient) -> AnyView {
        AnyView(AgreementView(viewModel: AgreementViewModel(client: client)))
    }
}
