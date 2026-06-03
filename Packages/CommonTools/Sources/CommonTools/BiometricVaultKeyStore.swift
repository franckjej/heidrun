import CryptoKit
import Foundation
import LocalAuthentication
import Security
import os

/// Single biometric-protected AES-256 key that encrypts every saved
/// server password. The vault key lives as ONE keychain item with
/// `.userPresence` ACL — so the user is prompted for Touch ID exactly
/// once per app launch regardless of bookmark count. Per-server password
/// items are plain rows holding AES-GCM ciphertext that decrypt for
/// free once the vault key is cached in RAM.
///
/// Apple caps direct biometric-ACL reuse at 10 seconds, but the
/// `SymmetricKey` we hold is just RAM — it stays valid for the process
/// lifetime (or until `lock()`).
public enum BiometricVaultKeyStore {
    /// Distinct service so the vault row can't collide with per-server
    /// password rows. The `.master-key` suffix is the legacy on-disk
    /// identifier — kept as-is so existing rows resolve after the rename.
    private static let service = "org.tastybytes.heidrun.master-key"
    private static let account = "primary"

    private static let log = Logger(
        subsystem: "org.tastybytes.heidrun",
        category: "BiometricVaultKeyStore"
    )

    nonisolated(unsafe) private static var cachedKey: SymmetricKey?
    private static let cacheLock = NSLock()

    public static var isUnlocked: Bool {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cachedKey != nil
    }

    /// How a vault-key read resolved, separating "no key exists yet"
    /// (safe to mint) from "a key exists but I couldn't read it this
    /// moment" (must NOT mint).
    public enum VaultKeyReadStatus: Equatable {
        case success
        /// `errSecItemNotFound` — no row exists.
        case absent
        /// Row may exist but is unreadable right now (Touch ID cancel,
        /// auth failed, transient keychain error).
        case unreadable
    }

    public enum VaultKeyUnlockAction: Equatable {
        case useExisting
        case mintNew
        /// Return `nil` WITHOUT minting. Minting would delete the real
        /// key and orphan every saved password.
        case bail
    }

    /// Only literal `errSecItemNotFound` means "no key exists yet". Every
    /// other non-success — user cancellation, auth failure, anything —
    /// is `.unreadable`, because a key may exist that we couldn't read.
    public static func classifyVaultKeyRead(_ osStatus: OSStatus) -> VaultKeyReadStatus {
        switch osStatus {
        case errSecSuccess:
            return .success
        case errSecItemNotFound:
            return .absent
        default:
            return .unreadable
        }
    }

    /// **The core safety policy.** Only `.absent` mints. `.unreadable`
    /// must `.bail` — never mint — so a cancelled Touch ID prompt can't
    /// destroy the real key and orphan saved passwords.
    public static func unlockAction(for status: VaultKeyReadStatus) -> VaultKeyUnlockAction {
        switch status {
        case .success:
            return .useExisting
        case .absent:
            return .mintNew
        case .unreadable:
            return .bail
        }
    }

    /// Returns `nil` if the user dismisses the Touch ID sheet, a saved
    /// key can't be read this moment, or no biometric authenticator is
    /// available. `prompt` is the Touch ID sheet's localized reason.
    /// Idempotent: callers in the same session share the cached key.
    public static func unlock(prompt: String) -> SymmetricKey? {
        cacheLock.lock()
        if let cached = cachedKey {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let read = readExistingVaultKey(prompt: prompt)
        switch unlockAction(for: read.status) {
        case .useExisting:
            guard let existing = read.key else { return nil }
            cacheLock.lock()
            cachedKey = existing
            cacheLock.unlock()
            return existing
        case .bail:
            return nil
        case .mintNew:
            // The Add path attaches a biometric ACL but doesn't prompt
            // (Apple only prompts on RETRIEVAL of an ACL-protected
            // secret, not on creation).
            guard let fresh = generateAndStoreVaultKey() else { return nil }
            cacheLock.lock()
            cachedKey = fresh
            cacheLock.unlock()
            return fresh
        }
    }

    /// Drop the in-memory key so the next `unlock` re-prompts. Does NOT
    /// delete the keychain row.
    public static func lock() {
        cacheLock.lock()
        cachedKey = nil
        cacheLock.unlock()
    }

    /// Remove the vault key entirely. After this every previously-
    /// encrypted password becomes undecryptable; callers must flush the
    /// per-server rows that depended on it. Intended for explicit "reset
    /// Heidrun's saved passwords" UI.
    public static func destroy() {
        cacheLock.lock()
        cachedKey = nil
        cacheLock.unlock()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        _ = SecItemDelete(query as CFDictionary)
    }

    // MARK: - Keychain plumbing

    private static func readExistingVaultKey(
        prompt: String
    ) -> (status: VaultKeyReadStatus, key: SymmetricKey?) {
        let context = LAContext()
        context.localizedReason = prompt
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]
        var result: CFTypeRef?
        let osStatus = SecItemCopyMatching(query as CFDictionary, &result)
        switch classifyVaultKeyRead(osStatus) {
        case .success:
            guard let data = result as? Data else {
                // Read reported success but no data — treat as
                // unreadable (never mint); a key clearly exists.
                log.error("Vault key read succeeded without data")
                return (.unreadable, nil)
            }
            return (.success, SymmetricKey(data: data))
        case .absent:
            return (.absent, nil)
        case .unreadable:
            // User cancelling Touch ID is normal; only log unexpected
            // failures.
            if osStatus != errSecUserCanceled && osStatus != errSecAuthFailed {
                log.error("Vault key read failed: status=\(osStatus, privacy: .public)")
            }
            return (.unreadable, nil)
        }
    }

    private static func generateAndStoreVaultKey() -> SymmetricKey? {
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        guard let accessControl = makeAccessControl() else {
            log.error("SecAccessControlCreateWithFlags returned nil for vault key")
            return nil
        }
        // Drop any stale stub so SecItemAdd doesn't trip
        // errSecDuplicateItem on a half-created row.
        _ = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ] as CFDictionary)

        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: keyData,
            kSecAttrAccessControl as String: accessControl
        ]
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else {
            log.error("Vault key SecItemAdd failed: status=\(status, privacy: .public)")
            return nil
        }
        return newKey
    }

    private static func makeAccessControl() -> SecAccessControl? {
        var error: Unmanaged<CFError>?
        let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence,
            &error
        )
        if let error {
            log.error(
                "SecAccessControlCreateWithFlags failed: \(error.takeRetainedValue() as Error, privacy: .public)"
            )
            return nil
        }
        return accessControl
    }
}

// MARK: - AES-GCM helpers

extension SymmetricKey {
    /// Encrypt and return the AES-GCM combined form (nonce ‖ ciphertext ‖
    /// tag).
    func sealCombined(_ plaintext: Data) throws -> Data {
        let sealed = try AES.GCM.seal(plaintext, using: self)
        guard let combined = sealed.combined else {
            throw CryptoKitError.underlyingCoreCryptoError(error: 0)
        }
        return combined
    }

    func openCombined(_ combined: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(box, using: self)
    }
}
