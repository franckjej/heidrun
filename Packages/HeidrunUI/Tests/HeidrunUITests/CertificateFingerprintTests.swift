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

    @Test("a SHA-256 fingerprint splits into two rows of 16 pairs")
    func linesSplitsSHA256() {
        let hex = String(repeating: "ab", count: 32)
        let rows = CertificateFingerprint.lines(hex).split(separator: "\n")
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0 == String(repeating: "AB:", count: 15) + "AB" })
    }

    @Test("a short fingerprint stays on one line")
    func linesShortInput() {
        #expect(CertificateFingerprint.lines("aabb") == "AA:BB")
    }
}
