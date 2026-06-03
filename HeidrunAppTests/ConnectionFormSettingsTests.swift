import Testing
import HeidrunCore
@testable import Heidrun

@Suite("ConnectionForm.connectionSettings")
struct ConnectionFormSettingsTests {
    /// Regression: the Connect path must carry the pinned TLS fingerprint
    /// the user already trusted, otherwise every reconnect re-prompts the
    /// trust sheet (the pin is read back from the bookmark but was dropped
    /// when building the settings handed to `connect`).
    @Test("carries the pinned TLS certificate through to the settings")
    func carriesPinnedCertificate() {
        let settings = ConnectionForm.connectionSettings(
            name: "Tom's BBS",
            address: "hotline.example.com",
            port: 5502,
            nickname: "Jens",
            login: "jens",
            iconID: 0,
            emoji: nil,
            useTLS: true,
            pinnedCertificateSHA256: "abc123def456"
        )

        #expect(settings.pinnedCertificateSHA256 == "abc123def456")
        #expect(settings.useTLS)
    }

    @Test("trims name and address and clamps the icon ID")
    func trimsAndClamps() {
        let settings = ConnectionForm.connectionSettings(
            name: "  Tom's BBS  ",
            address: "  hotline.example.com  ",
            port: 5500,
            nickname: "Jens",
            login: "jens",
            iconID: 99_999,
            emoji: nil,
            useTLS: false,
            pinnedCertificateSHA256: nil
        )

        #expect(settings.name == "Tom's BBS")
        #expect(settings.address == "hotline.example.com")
        #expect(settings.icon == UInt16(clamping: 99_999))
        #expect(settings.pinnedCertificateSHA256 == nil)
    }
}
