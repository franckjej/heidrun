import Foundation
import HeidrunCore

extension ConnectionForm {
    /// Single source of truth mapping the form's editable fields to a
    /// `ConnectionSettings`. Both the Connect path (`submit`) and the
    /// Save path route through here so a field (notably the pinned
    /// TLS certificate) can't be wired into one and silently dropped
    /// from the other. Trims `name`/`address` and clamps the icon ID
    /// just as the callers used to inline.
    ///
    /// `nonisolated static` so it can be unit-tested without
    /// instantiating the SwiftUI view. Lives in its own file so
    /// `ConnectionForm.swift` stays under the 800-line cap.
    nonisolated static func connectionSettings(
        name: String,
        address: String,
        port: UInt16,
        nickname: String,
        login: String,
        iconID: Int,
        emoji: String?,
        useTLS: Bool,
        pinnedCertificateSHA256: String?
    ) -> ConnectionSettings {
        ConnectionSettings(
            name: name.trimmingCharacters(in: .whitespaces),
            address: address.trimmingCharacters(in: .whitespaces),
            port: port,
            nickname: nickname,
            login: login,
            icon: UInt16(clamping: iconID),
            useTLS: useTLS,
            pinnedCertificateSHA256: pinnedCertificateSHA256,
            emoji: emoji
        )
    }
}
