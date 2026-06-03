import Testing
import HeidrunCore
@testable import Heidrun

@Suite("HostView.addressSubtitle")
struct HostViewTitleTests {
    private func settings(useTLS: Bool, port: UInt16) -> ConnectionSettings {
        ConnectionSettings(
            name: "Tom's BBS",
            address: "hotline.example.com",
            port: port,
            nickname: "Jens",
            useTLS: useTLS
        )
    }

    // Two spaces after the lock glyph is deliberate — the subtitle's
    // smaller font needs the extra breathing room next to the emoji.
    @Test("a TLS connection gets a closed-lock prefix")
    func tlsShowsClosedLock() {
        let subtitle = HostView.addressSubtitle(for: settings(useTLS: true, port: 5502))
        #expect(subtitle == "🔒  hotline.example.com:5502")
    }

    @Test("a cleartext connection gets an open-lock prefix")
    func cleartextShowsOpenLock() {
        let subtitle = HostView.addressSubtitle(for: settings(useTLS: false, port: 5500))
        #expect(subtitle == "🔓  hotline.example.com:5500")
    }

    @Test("no settings yields an empty subtitle")
    func noSettingsIsEmpty() {
        #expect(HostView.addressSubtitle(for: nil).isEmpty)
    }
}
