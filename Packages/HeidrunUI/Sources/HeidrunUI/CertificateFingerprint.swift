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
}
