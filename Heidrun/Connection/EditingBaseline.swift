import HeidrunBookmarks

/// Snapshot of the connect form's editable fields, taken the moment the
/// form hydrates from a selected bookmark. The live form is compared
/// against this baseline to decide whether "Save bookmark" overwrites the
/// selected bookmark silently or first asks the user.
///
/// Password / "remember password" are deliberately excluded: they live in
/// the macOS Keychain keyed by `(address, port, login)`, not on the
/// bookmark entry, so changing only the password is not an edit to the
/// bookmark itself.
struct EditingBaseline: Equatable {
    var name: String
    var address: String
    var port: UInt16
    var useTLS: Bool
    var pinnedCertificateSHA256: String?
    var nickname: String
    var login: String
    var autoReconnectOverride: AutoReconnectOverride
}
