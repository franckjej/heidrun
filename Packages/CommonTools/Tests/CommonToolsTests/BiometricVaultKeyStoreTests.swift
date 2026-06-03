import Foundation
import Security
import Testing
import CommonTools

/// Guards the vault-key regeneration hazard: a vault-key read that fails
/// *transiently* (user cancelled Touch ID, auth failed, or any unexpected
/// keychain error) must never be treated as "no key exists," because that
/// path mints a fresh key — deleting the real one and orphaning every
/// password encrypted under it.
@Suite("BiometricVaultKeyStore vault-key read policy")
struct BiometricVaultKeyStoreTests {
    @Test("a successful read classifies as .success")
    func successClassifies() {
        #expect(BiometricVaultKeyStore.classifyVaultKeyRead(errSecSuccess) == .success)
    }

    @Test("item-not-found classifies as .absent")
    func notFoundClassifies() {
        #expect(BiometricVaultKeyStore.classifyVaultKeyRead(errSecItemNotFound) == .absent)
    }

    @Test("a cancelled Touch ID prompt classifies as .unreadable")
    func userCancelledClassifies() {
        #expect(BiometricVaultKeyStore.classifyVaultKeyRead(errSecUserCanceled) == .unreadable)
    }

    @Test("an auth failure classifies as .unreadable")
    func authFailedClassifies() {
        #expect(BiometricVaultKeyStore.classifyVaultKeyRead(errSecAuthFailed) == .unreadable)
    }

    @Test("an unexpected keychain error classifies as .unreadable, not .absent")
    func otherErrorClassifies() {
        #expect(BiometricVaultKeyStore.classifyVaultKeyRead(errSecParam) == .unreadable)
    }

    @Test("only a genuinely absent key mints a fresh one")
    func mintsOnlyWhenAbsent() {
        #expect(BiometricVaultKeyStore.unlockAction(for: .absent) == .mintNew)
    }

    @Test("a successful read uses the existing key")
    func usesExistingOnSuccess() {
        #expect(BiometricVaultKeyStore.unlockAction(for: .success) == .useExisting)
    }

    @Test("an unreadable key bails — never mints, so the real key survives")
    func bailsOnUnreadable() {
        #expect(BiometricVaultKeyStore.unlockAction(for: .unreadable) == .bail)
    }
}
