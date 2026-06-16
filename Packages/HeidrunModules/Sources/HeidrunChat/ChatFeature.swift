import SwiftUI
import HeidrunCore
import HeidrunUI

/// `HeidrunFeature` conformance for the chat module.
///
/// The host imports `HeidrunChat`, registers `ChatFeature.self` in its
/// feature list, and the chat tab appears in the sidebar with the right
/// label and icon. Selecting it asks `makeContentView(client:)` for the
/// detail view.
public enum ChatFeature: HeidrunFeature {
    public static let identifier  = "com.heidrun.chat"
    public static var displayName: String { String(localized: "Chat", bundle: .module) }
    public static let systemImage = "text.bubble"

    /// Chat is the only feature that needs the connected-users list visible
    /// alongside its content (for DMs and info lookups).
    public static let wantsUserListInspector = true

    /// Fallback factory required by `HeidrunFeature`. The main host
    /// (`HostView`) does NOT use this for chat — it renders the
    /// connection's hoisted, long-lived `ConnectionHandle.chatVM` so chat
    /// history and the topic persist across module switches. This path
    /// only runs for a standalone presentation, and the VM it builds
    /// still seeds its topic from `connectionInfo.publicChatSubject` via
    /// the `ChatViewModel(client:)` convenience init.
    @MainActor
    public static func makeContentView(client: any HotlineClient) -> AnyView {
        AnyView(ChatView(viewModel: ChatViewModel(client: client)))
    }
}
