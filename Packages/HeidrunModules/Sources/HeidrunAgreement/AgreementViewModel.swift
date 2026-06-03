import Foundation
import Observation
import HeidrunCore

/// View-model for the agreement banner the server presents during login.
///
/// Subscribes to `HotlineEvent.agreementReceived`, keeps the latest banner
/// text, and exposes accept/decline actions that round-trip to the server.
@Observable
@MainActor
public final class AgreementViewModel {
    /// Latest agreement text the server pushed. `nil` while none has been
    /// received yet, or once the user has acted on it.
    public private(set) var text: String?

    /// `true` when the server hinted that auto-agreement is permitted (the
    /// host's UI typically still asks the user to confirm).
    public private(set) var autoAgree: Bool = false

    /// Two-way bound nickname used when accepting.
    public var nickname: String

    /// Two-way bound icon ID used when accepting.
    public var icon: UInt16

    private let events: AsyncStream<HotlineEvent>
    private let agree: @Sendable (String, UInt16) async throws -> Void
    private let disconnect: @Sendable () async -> Void

    public init(
        events: AsyncStream<HotlineEvent>,
        agree: @escaping @Sendable (String, UInt16) async throws -> Void,
        disconnect: @escaping @Sendable () async -> Void,
        defaultNickname: String = "",
        defaultIcon: UInt16 = 0
    ) {
        self.events = events
        self.agree = agree
        self.disconnect = disconnect
        self.nickname = defaultNickname
        self.icon = defaultIcon
    }

    public convenience init(
        client: any HotlineClient,
        defaultNickname: String = "",
        defaultIcon: UInt16 = 0
    ) {
        self.init(
            events: client.events,
            agree: { [client] nick, icon in
                // heidrun-server derives identity from login (107); its 121
                // handler is a no-op, and the emoji was already sent at login.
                try await client.agreeToAgreement(nickname: nick, icon: icon, emoji: nil)
            },
            disconnect: { [client] in
                await client.disconnect()
            },
            defaultNickname: defaultNickname,
            defaultIcon: defaultIcon
        )
    }

    /// SwiftUI `.task { await viewModel.observe() }` entry point.
    public func observe() async {
        for await event in events {
            if case let .agreementReceived(text, autoAgree) = event {
                self.text = text
                self.autoAgree = autoAgree
            }
        }
    }

    public func accept() async throws {
        try await agree(nickname, icon)
        text = nil
    }

    public func decline() async {
        await disconnect()
        text = nil
    }
}
