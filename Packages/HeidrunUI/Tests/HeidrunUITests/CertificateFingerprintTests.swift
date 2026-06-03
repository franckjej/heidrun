import Testing
@testable import HeidrunUI

@Suite("CertificateFingerprint")
struct CertificateFingerprintTests {
    @Test("formats lowercase hex into uppercase colon-grouped pairs")
    func grouped() {
        #expect(CertificateFingerprint.grouped("aabbcc") == "AA:BB:CC")
    }

    @Test("odd-length input is returned uppercased without crashing")
    func oddLength() {
        #expect(CertificateFingerprint.grouped("abc") == "AB:C")
    }

    @Test("empty input yields empty string")
    func empty() {
        #expect(CertificateFingerprint.grouped("").isEmpty)
    }
}
