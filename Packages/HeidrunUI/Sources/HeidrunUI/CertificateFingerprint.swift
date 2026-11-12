import Foundation

/// Display helpers for SHA-256 certificate fingerprints. HeidrunCore stores
/// the raw lowercase-hex string; the UI shows uppercase colon-grouped pairs
/// (`AA:BB:CC…`) the way Keychain Access and browsers do.
public enum CertificateFingerprint {
    public static func grouped(_ hex: String) -> String {
        let upper = Array(hex.uppercased())
        return stride(from: 0, to: upper.count, by: 2)
            .map { start in
                String(upper[start..<min(start + 2, upper.count)])
            }
            .joined(separator: ":")
    }

    /// The full grouped fingerprint split into lines of `pairsPerLine`
    /// pairs, so a SHA-256 (32 pairs) shows as two even rows.
    public static func lines(_ hex: String, pairsPerLine: Int = 16) -> String {
        let pairs = grouped(hex).split(separator: ":").map(String.init)
        return stride(from: 0, to: pairs.count, by: max(pairsPerLine, 1))
            .map { start in
                pairs[start..<min(start + max(pairsPerLine, 1), pairs.count)].joined(separator: ":")
            }
            .joined(separator: "\n")
    }
}
