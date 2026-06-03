import Foundation
import HeidrunCore

/// Tri-state per-bookmark override for the global auto-reconnect default.
///
/// - `inherit`: defer to the global setting in Settings → Connection.
/// - `alwaysOn`: auto-reconnect this bookmark even if the global toggle is off.
/// - `alwaysOff`: never auto-reconnect this bookmark, even if the global toggle is on.
public enum AutoReconnectOverride: String, Codable, Sendable, Hashable, CaseIterable {
    case inherit
    case alwaysOn
    case alwaysOff
}

/// A curated server bookmark. Wraps `ConnectionSettings` with a stable
/// identity so the roster UI can survive renames and address edits.
///
/// Password material is never carried on the value — it lives in the
/// macOS Keychain via the host's `KeychainPasswordStore`, keyed by
/// `(address, port, login)`.
public struct Bookmark: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var settings: ConnectionSettings
    public var autoReconnect: AutoReconnectOverride

    public init(
        id: UUID = UUID(),
        settings: ConnectionSettings,
        autoReconnect: AutoReconnectOverride = .inherit
    ) {
        self.id = id
        self.settings = settings
        self.autoReconnect = autoReconnect
    }

    private enum CodingKeys: String, CodingKey {
        case id, settings, autoReconnect
    }

    // Hand-written decoder so v1 JSON blobs (no `autoReconnect` key) load
    // with the default value rather than throwing.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.settings = try container.decode(ConnectionSettings.self, forKey: .settings)
        self.autoReconnect = try container.decodeIfPresent(
            AutoReconnectOverride.self, forKey: .autoReconnect
        ) ?? .inherit
    }
}
