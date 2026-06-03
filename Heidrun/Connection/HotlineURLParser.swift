import Foundation
import HeidrunCore

/// Parse an incoming `hotline://` or `heidrun://` URL into
/// `ConnectionSettings` so the app can launch a connection from a
/// link the user clicked in a browser, Mail, or a `.heidrunbookmarks`
/// export from a peer.
///
/// Wire format mirrors the de-facto Hotline URL scheme:
///
///     hotline://[<login>[:<password>]@]<host>[:<port>]
///     heidrun://[<login>[:<password>]@]<host>[:<port>]
///
/// We accept `<password>` for compatibility but **do not** thread it
/// through to `ConnectionSettings` — saved passwords live in the
/// Keychain and a URL-embedded password would bypass that. The
/// connection form will prompt for a password the normal way.
///
/// Returns `nil` for any URL that isn't a Hotline link (unknown
/// scheme, no host, no port, etc.) so the caller can pass other URLs
/// (e.g. `.heidrunbookmarks` / `.heidrunpart` document opens) through
/// their own handlers unchanged.
enum HotlineURLParser {
    static let recognisedSchemes: Set<String> = ["hotline", "heidrun"]
    static let defaultPort: UInt16 = 5500

    static func parse(_ url: URL) -> ConnectionSettings? {
        guard let scheme = url.scheme?.lowercased(),
              recognisedSchemes.contains(scheme)
        else { return nil }
        guard let host = url.host?.trimmingCharacters(in: .whitespaces),
              !host.isEmpty
        else { return nil }
        let port = url.port.map { UInt16(clamping: $0) } ?? defaultPort
        let login = url.user ?? ""
        // ad-hoc connections have no bookmark, so `name` stays empty —
        // the chat header / window title fall back to the address.
        return ConnectionSettings(
            name: "",
            address: host,
            port: port,
            nickname: "",
            login: login,
            useTLS: false
        )
    }
}
