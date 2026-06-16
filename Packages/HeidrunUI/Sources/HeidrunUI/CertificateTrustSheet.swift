import SwiftUI
import HeidrunCore
import CommonTools

/// Modal shown when a TLS handshake needs a user trust decision — either
/// first-use of a self-signed cert (`.untrustedNoPin`) or a changed cert on
/// a pinned bookmark (`.pinMismatch`).
public struct CertificateTrustSheet: View {
    private let challenge: CertificateTrustChallenge
    private let onDecision: (CertificateTrustDecision) -> Void

    public init(
        challenge: CertificateTrustChallenge,
        onDecision: @escaping (CertificateTrustDecision) -> Void
    ) {
        self.challenge = challenge
        self.onDecision = onDecision
    }

    private var isMismatch: Bool { challenge.reason == .pinMismatch }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(
                isMismatch ? String(localized: "Certificate changed", bundle: .module) : String(localized: "Untrusted certificate", bundle: .module),
                systemImage: isMismatch ? "exclamationmark.triangle" : "lock.trianglebadge.exclamationmark"
            )
            .font(.headline)

            Text(headline)
                .fixedSize(horizontal: false, vertical: true)

            if isMismatch, let pinned = challenge.pinnedFingerprint {
                fingerprintRow("Pinned", CertificateFingerprint.grouped(pinned))
                fingerprintRow("Now", CertificateFingerprint.grouped(challenge.presentedFingerprint))
            } else {
                fingerprintRow("SHA-256", CertificateFingerprint.grouped(challenge.presentedFingerprint))
            }

            HStack {
                Button(String(localized: "Cancel", bundle: .module), role: .cancel) { onDecision(.reject) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isMismatch ? String(localized: "Trust New Certificate", bundle: .module) : String(localized: "Trust & Connect", bundle: .module)) {
                    onDecision(.trust)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.medium)
        .frame(width: 420)
        .closeOnCmdW { onDecision(.reject) }
    }

    private var headline: String {
        let endpoint = "\(challenge.host):\(challenge.port)"
        if isMismatch {
            return "\(endpoint) presented a certificate that does NOT match the one you trusted. This is expected if the operator rebuilt the server — otherwise, beware."
        }
        return "\(endpoint) presented a self-signed certificate. Trust it only if you recognise this fingerprint."
    }

    private func fingerprintRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
        }
    }
}
