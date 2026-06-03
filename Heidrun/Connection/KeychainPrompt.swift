import HeidrunCore

/// Build the "Sign in to <server>" copy shown above the keychain
/// Touch ID / password sheet when an ACL-protected saved password is
/// read. Lives at app scope rather than inside `CommonTools` because
/// `ConnectionSettings` is a `HeidrunCore` type — `CommonTools` doesn't
/// depend on `HeidrunCore`, and we don't want it to.
@MainActor
func keychainPrompt(for settings: ConnectionSettings) -> String {
    let label = settings.name.isEmpty ? settings.address : settings.name
    return "Sign in to \(label)"
}

/// Same shape as the `ConnectionSettings` overload, for call sites
/// that only have a friendly name string (e.g. a `.heidrunpart`
/// metadata blob).
@MainActor
func keychainPrompt(forServerLabel label: String) -> String {
    "Sign in to \(label)"
}
