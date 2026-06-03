import CryptoKit
import Foundation
import LocalAuthentication
import Security
import os

/// Generic-password keychain wrapper for server credentials. Keyed by
/// `(address, port, login)` — call sites use `Key.canonical(...)` so the
/// lowercasing / trimming policy stays in one place.
///
/// Storage:
/// - Plain mode (default): UTF-8 bytes, `kSecAttrAccessibleWhenUnlocked-
///   ThisDeviceOnly`, no ACL, no Touch ID prompts.
/// - Biometric mode (`useBiometricACL == true`): the password is sealed
///   with the AES-GCM vault key from `BiometricVaultKeyStore` and the
///   keychain row STILL carries no ACL. The vault key is what holds the
///   `.userPresence` protection — keeping the unlocked key in process
///   memory bypasses Apple's ~10s per-item biometric reuse cap, so one
///   Touch ID prompt per app launch covers every saved password.
///
/// Encrypted blobs start with magic `0xFE 0x01` — invalid UTF-8 lead
/// bytes, so the read path can fork plain vs encrypted with no extra
/// keychain attribute. Plain rows from before biometric was enabled
/// keep working without migration.
public enum KeychainPasswordStore {

    /// Composite identity. `port` lives on the struct for API symmetry
    /// but is intentionally NOT part of the keychain account string — a
    /// user's credentials are the same whether they connect cleartext on
    /// 5500 or TLS on 5502, and the form auto-shifts ports on TLS toggle.
    public struct Key: Hashable, Sendable {
        public let address: String
        public let port: UInt16
        public let login: String

        public static func canonical(address: String, port: UInt16, login: String) -> Key {
            Key(
                address: address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                port: port,
                login: login.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        public var account: String { "\(address):\(login)" }

        /// Legacy port-bearing account strings used before the key dropped
        /// port. Probed on lookup misses so a one-time migration rewrites
        /// the entry under the canonical key without re-prompting. Covers
        /// the actual port first (typical case) plus the canonical TLS
        /// sibling quartet (5500/5501 cleartext, 5502/5503 TLS).
        public var legacyAccounts: [String] {
            let siblings: Set<UInt16> = [5500, 5501, 5502, 5503]
            let ordered = [port] + siblings.subtracting([port]).sorted()
            return ordered.map { "\(address):\($0):\(login)" }
        }
    }

    public enum KeychainError: Error, Sendable, Equatable {
        case unexpectedStatus(OSStatus)
        case malformedItem
        /// Vault key unavailable — Touch ID cancelled or no biometry.
        case vaultKeyUnavailable
    }

    private static let service = "org.tastybytes.heidrun.server-password"
    private static let log = Logger(
        subsystem: "org.tastybytes.heidrun",
        category: "KeychainPasswordStore"
    )

    /// `0xFE` is invalid as a UTF-8 leading byte, so any read that starts
    /// with this is guaranteed to be ciphertext rather than plaintext.
    private static let encryptedMagic: [UInt8] = [0xFE, 0x01]

    /// App-wide toggle the host writes on launch / Settings change. False
    /// by default so test runs (no UI) keep writing plain items.
    nonisolated(unsafe) public static var useBiometricACL: Bool = false

    /// Set by isolated debug runs and tests to route every op away from
    /// the real keychain. `nil` in production.
    nonisolated(unsafe) public static var mockBackend: (any CredentialStoring)?

    public static var isBiometricAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error
        )
    }

    public static func save(
        _ password: String,
        for key: Key,
        requireBiometric: Bool = false,
        unlockPrompt: String? = nil
    ) throws {
        let payload: Data
        if requireBiometric {
            guard let vaultKey = BiometricVaultKeyStore.unlock(
                prompt: unlockPrompt ?? "Unlock Heidrun saved passwords"
            ) else {
                throw KeychainError.vaultKeyUnavailable
            }
            let ciphertext = try vaultKey.sealCombined(Data(password.utf8))
            payload = Data(encryptedMagic) + ciphertext
        } else {
            payload = Data(password.utf8)
        }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.account
        ]

        let updateAttrs: [String: Any] = [
            kSecValueData as String: payload,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            // Almost certainly a stale legacy row with its own ACL (pre-
            // vault-key experiments). Drop so the Add below mints clean.
            try? delete(for: key)
        }

        var addAttrs = baseQuery
        addAttrs[kSecValueData as String] = payload
        addAttrs[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(addAttrs as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unexpectedStatus(addStatus)
        }
    }

    /// Returns `nil` when no entry exists or the vault key is unavailable
    /// (user cancelled Touch ID, biometry not configured). Throws on
    /// genuine keychain or crypto failures.
    public static func read(for key: Key, unlockPrompt: String? = nil) throws -> String? {
        if let mock = mockBackend { return try mock.read(for: key, unlockPrompt: unlockPrompt) }
        if let data = try readData(account: key.account) {
            return try decode(data, unlockPrompt: unlockPrompt)
        }
        // Probe legacy port-bearing entries; on hit migrate to the
        // canonical name so future lookups don't need this fallback.
        for legacyAccount in key.legacyAccounts where legacyAccount != key.account {
            guard let data = try readData(account: legacyAccount) else { continue }
            let plaintext = try decode(data, unlockPrompt: unlockPrompt)
            if let plaintext, !plaintext.isEmpty {
                migrate(plaintext: plaintext, from: legacyAccount, to: key)
            }
            return plaintext
        }
        return nil
    }

    /// `nil` on item-not-found and on user-cancel / auth-failed so the
    /// caller can fall through to a legacy-account probe.
    private static func readData(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        if status == errSecUserCanceled { return nil }
        if status == errSecAuthFailed { return nil }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        guard let data = result as? Data else {
            throw KeychainError.malformedItem
        }
        return data
    }

    private static func migrate(plaintext: String, from legacyAccount: String, to key: Key) {
        saveOrLog(plaintext, for: key)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: legacyAccount
        ]
        let status = SecItemDelete(deleteQuery as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            log.error("Legacy keychain entry delete failed (status \(status, privacy: .public))")
        } else {
            log.debug("Migrated keychain entry from \(legacyAccount, privacy: .public) to \(key.account, privacy: .public)")
        }
    }

    private static func decode(_ data: Data, unlockPrompt: String?) throws -> String? {
        if data.count >= encryptedMagic.count,
           data[data.startIndex] == encryptedMagic[0],
           data[data.startIndex + 1] == encryptedMagic[1] {
            guard let vaultKey = BiometricVaultKeyStore.unlock(
                prompt: unlockPrompt ?? "Unlock Heidrun saved passwords"
            ) else {
                return nil
            }
            let ciphertext = data.subdata(in: (data.startIndex + encryptedMagic.count)..<data.endIndex)
            let plaintext = try vaultKey.openCombined(ciphertext)
            return String(data: plaintext, encoding: .utf8)
        }
        guard let plain = String(data: data, encoding: .utf8) else {
            throw KeychainError.malformedItem
        }
        return plain
    }

    /// Never prompts — uses `kSecReturnAttributes: true` to bypass ACL
    /// evaluation. Probes legacy accounts so a bookmark saved before the
    /// port-drop migration still reports as having a password.
    public static func hasSavedPassword(for key: Key) -> Bool {
        if let mock = mockBackend { return mock.hasSavedPassword(for: key) }
        if accountExists(key.account) { return true }
        for legacyAccount in key.legacyAccounts where legacyAccount != key.account {
            if accountExists(legacyAccount) { return true }
        }
        return false
    }

    private static func accountExists(_ account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess
    }

    /// First saved login for `address` across all entries. Used by the
    /// tracker-pick flow to recover the login the user previously
    /// authenticated with when there's no bookmark.
    ///
    /// Tolerates legacy port-bearing accounts (`"<address>:<port>:<login>"`)
    /// by stripping a leading numeric segment from the suffix.
    public static func findAnyLogin(forAddress address: String, port: UInt16) -> String? {
        if let mock = mockBackend { return mock.findAnyLogin(forAddress: address, port: port) }
        let needle = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            return nil
        }
        let prefix = "\(needle):"
        for item in items {
            // Compare against the lowercased prefix but derive the suffix
            // from the original account string so the login's case is
            // preserved (case-sensitive on some servers). ASCII lowercase
            // preserves length so `dropFirst` lines up on the original.
            guard let account = item[kSecAttrAccount as String] as? String,
                  account.lowercased().hasPrefix(prefix)
            else { continue }
            let suffix = String(account.dropFirst(prefix.count))
            if let colonIndex = suffix.firstIndex(of: ":"),
               UInt16(suffix[..<colonIndex]) != nil {
                return String(suffix[suffix.index(after: colonIndex)...])
            }
            return suffix
        }
        return nil
    }

    /// Idempotent — no throw when the item already doesn't exist.
    public static func delete(for key: Key) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.account
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { return }
        throw KeychainError.unexpectedStatus(status)
    }

    /// Best-effort save: failures are logged but never thrown. Honours
    /// `useBiometricACL`. Updates the session cache on success.
    public static func saveOrLog(_ password: String, for key: Key, unlockPrompt: String? = nil) {
        if let mock = mockBackend { mock.saveOrLog(password, for: key, unlockPrompt: unlockPrompt); return }
        let requireBiometric = useBiometricACL && isBiometricAvailable
        do {
            try save(password, for: key, requireBiometric: requireBiometric, unlockPrompt: unlockPrompt)
            updateCache(password, for: key)
            return
        } catch KeychainError.vaultKeyUnavailable {
            // User cancelled the Touch ID prompt. Fall back to a plain
            // save so Remember-password keeps working — they can re-
            // enable biometric later by re-saving once unlocked.
            log.error("Vault key unavailable; falling back to plain keychain save")
        } catch {
            log.error("Keychain save failed: \(error, privacy: .public)")
            return
        }
        do {
            try save(password, for: key, requireBiometric: false)
            updateCache(password, for: key)
        } catch {
            log.error("Keychain save failed (fallback): \(error, privacy: .public)")
        }
    }

    public static func deleteOrLog(for key: Key) {
        if let mock = mockBackend { mock.deleteOrLog(for: key); return }
        do {
            try delete(for: key)
            updateCache(nil, for: key)
        } catch {
            log.error("Keychain delete failed: \(error, privacy: .public)")
        }
    }

    // MARK: - Session cache

    /// Per-process cache of read passwords. Avoids the keychain auth-
    /// prompt tax on auto-reconnect cycles and session restoration.
    /// Cleared on launch, never persisted.
    nonisolated(unsafe) private static var sessionCache: [String: String] = [:]
    private static let cacheLock = NSLock()

    public static func cachedOrRead(for key: Key, prompt: String? = nil) -> String? {
        if let mock = mockBackend { return mock.cachedOrRead(for: key, prompt: prompt) }
        cacheLock.lock()
        if let cached = sessionCache[key.account] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        guard let value = try? read(for: key, unlockPrompt: prompt), !value.isEmpty else { return nil }
        cacheLock.lock()
        sessionCache[key.account] = value
        cacheLock.unlock()
        return value
    }

    public static func updateCache(_ password: String?, for key: Key) {
        cacheLock.lock()
        if let password, !password.isEmpty {
            sessionCache[key.account] = password
        } else {
            sessionCache[key.account] = nil
        }
        cacheLock.unlock()
    }

    public static func clearSessionCache() {
        cacheLock.lock()
        sessionCache.removeAll()
        cacheLock.unlock()
    }
}
