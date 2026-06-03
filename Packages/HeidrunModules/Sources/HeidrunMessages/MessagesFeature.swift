import SwiftUI
import HeidrunCore
import HeidrunUI

public enum MessagesFeature: HeidrunFeature {
    public static let identifier  = "com.heidrun.messages"
    public static let displayName = "Messages"
    public static let systemImage = "envelope"

    @MainActor
    public static func makeContentView(client: any HotlineClient) -> AnyView {
        AnyView(MessagesView(viewModel: MessagesViewModel(client: client)))
    }
}
