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
    /// Valid Bookmarks-menu shortcut slots: ⌃⌘1 … ⌃⌘9.
    public static let menuShortcutSlotRange = 1...9

    public let id: UUID
    public var settings: ConnectionSettings
    public var autoReconnect: AutoReconnectOverride
    /// ⌃⌘<slot> in the Bookmarks menu; `nil` = no shortcut.
    public var menuShortcutSlot: Int?

    public init(
        id: UUID = UUID(),
        settings: ConnectionSettings,
        autoReconnect: AutoReconnectOverride = .inherit,
        menuShortcutSlot: Int? = nil
    ) {
        self.id = id
        self.settings = settings
        self.autoReconnect = autoReconnect
        self.menuShortcutSlot = menuShortcutSlot
    }

    private enum CodingKeys: String, CodingKey {
        case id, settings, autoReconnect, menuShortcutSlot
    }

    // Hand-written decoder so older blobs (no `autoReconnect` /
    // `menuShortcutSlot` key) load with defaults rather than throwing.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.settings = try container.decode(ConnectionSettings.self, forKey: .settings)
        self.autoReconnect = try container.decodeIfPresent(
            AutoReconnectOverride.self, forKey: .autoReconnect
        ) ?? .inherit
        let slot = try container.decodeIfPresent(Int.self, forKey: .menuShortcutSlot)
        self.menuShortcutSlot = slot.flatMap { Self.menuShortcutSlotRange.contains($0) ? $0 : nil }
    }
}
