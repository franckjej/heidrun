import SwiftUI
import HeidrunCore
import HeidrunUI

public enum NewsFeature: HeidrunFeature {
    public static let identifier  = "com.heidrun.news"
    public static let displayName = "News"
    public static let systemImage = "newspaper"

    @MainActor
    public static func makeContentView(client: any HotlineClient) -> AnyView {
        AnyView(NewsContent(client: client))
    }
}

/// Async-loads the connection's nickname once, then renders `NewsView`
/// with the resolved value. Read once at content-construction time;
/// if the user changes nickname mid-session, the cached value is stale
/// until the next reconnect — acceptable because `canEdit` is a UI
/// gate, not a security check (server enforces ownership).
@MainActor
private struct NewsContent: View {
    let client: any HotlineClient
    @State private var ownNickname: String = ""
    @State private var resolvedNickname = false

    var body: some View {
        NewsView(client: client, ownNickname: ownNickname)
            .task(id: resolvedNickname) {
                guard !resolvedNickname else { return }
                let nickname = await client.connectionInfo.settings.nickname
                ownNickname = nickname
                resolvedNickname = true
            }
    }
}

/// Host entry point that renders `NewsView` from view-models hoisted onto
/// the connection (so the composer draft + browse state survive feature
/// switches), resolving the edit-gate nickname once like `NewsContent`.
@MainActor
public struct HostedNewsView: View {
    private let plain: PlainNewsViewModel
    private let threaded: ThreadedNewsViewModel
    private let client: any HotlineClient
    @State private var ownNickname: String = ""
    @State private var resolvedNickname = false

    public init(
        plain: PlainNewsViewModel,
        threaded: ThreadedNewsViewModel,
        client: any HotlineClient
    ) {
        self.plain = plain
        self.threaded = threaded
        self.client = client
    }

    public var body: some View {
        NewsView(plain: plain, threaded: threaded, client: client, ownNickname: ownNickname)
            .task(id: resolvedNickname) {
                guard !resolvedNickname else { return }
                ownNickname = await client.connectionInfo.settings.nickname
                resolvedNickname = true
            }
    }
}
