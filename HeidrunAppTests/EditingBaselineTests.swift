import Testing
import HeidrunBookmarks
@testable import Heidrun

@Suite("EditingBaseline")
struct EditingBaselineTests {
    private func sample() -> EditingBaseline {
        EditingBaseline(
            name: "Tom's BBS",
            address: "bbs.example.org",
            port: 5500,
            useTLS: false,
            pinnedCertificateSHA256: nil,
            nickname: "Jens",
            login: "jens",
            autoReconnectOverride: .inherit
        )
    }

    @Test("identical fields compare equal")
    func identicalCompareEqual() {
        let first = sample()
        let second = sample()
        #expect(first == second)
    }

    @Test("a changed address compares unequal")
    func changedAddressUnequal() {
        var edited = sample()
        edited.address = "other.example.org"
        #expect(edited != sample())
    }

    @Test("a changed port compares unequal")
    func changedPortUnequal() {
        var edited = sample()
        edited.port = 5501
        #expect(edited != sample())
    }

    @Test("a changed TLS flag compares unequal")
    func changedTLSUnequal() {
        var edited = sample()
        edited.useTLS = true
        #expect(edited != sample())
    }

    @Test("a changed auto-reconnect override compares unequal")
    func changedOverrideUnequal() {
        var edited = sample()
        edited.autoReconnectOverride = .alwaysOn
        #expect(edited != sample())
    }
}
