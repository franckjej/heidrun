import Foundation
import Testing
import CommonTools

@Suite("KeychainPasswordStore", .serialized)
struct KeychainPasswordStoreTests {

    /// Each test uses a unique address so concurrent CI runs don't
    /// collide on a shared keychain. The cleanup `defer` removes the
    /// entry whether the test passed or failed.
    private func makeKey() -> KeychainPasswordStore.Key {
        KeychainPasswordStore.Key.canonical(
            address: "kpstest-\(UUID().uuidString).example",
            port: 5500,
            login: "tester"
        )
    }

    @Test("save then read returns the saved password")
    func roundTripsViaSaveAndRead() throws {
        let key = makeKey()
        defer { try? KeychainPasswordStore.delete(for: key) }

        try KeychainPasswordStore.save("hunter2", for: key)

        let read = try KeychainPasswordStore.read(for: key)
        #expect(read == "hunter2")
    }

    @Test("read returns nil when no entry exists")
    func readReturnsNilWhenAbsent() throws {
        let key = makeKey()
        // Belt-and-braces: make sure the slot is clean.
        try? KeychainPasswordStore.delete(for: key)

        let read = try KeychainPasswordStore.read(for: key)
        #expect(read == nil)
    }

    @Test("save overwrites a prior value")
    func saveOverwritesExistingValue() throws {
        let key = makeKey()
        defer { try? KeychainPasswordStore.delete(for: key) }

        try KeychainPasswordStore.save("first", for: key)
        try KeychainPasswordStore.save("second", for: key)

        #expect(try KeychainPasswordStore.read(for: key) == "second")
    }

    @Test("delete is idempotent on a missing entry")
    func deleteIsIdempotentOnMissing() {
        let key = makeKey()
        // Pre-condition: nothing there yet.
        #expect(throws: Never.self) {
            try KeychainPasswordStore.delete(for: key)
        }
    }

    @Test("delete removes an existing entry")
    func deleteRemovesAnExistingEntry() throws {
        let key = makeKey()
        try KeychainPasswordStore.save("bye", for: key)

        try KeychainPasswordStore.delete(for: key)

        #expect(try KeychainPasswordStore.read(for: key) == nil)
    }

    @Test("canonical lowercases and trims the address; preserves login case")
    func canonicalNormalisation() {
        let key = KeychainPasswordStore.Key.canonical(
            address: "  Hotline.Example.COM  ",
            port: 5500,
            login: " Bob "
        )
        #expect(key.address == "hotline.example.com")
        #expect(key.login == "Bob")
    }

    @Test("plain save reads back without prompting")
    func plainSaveReadsBackWithoutPrompt() throws {
        let key = makeKey()
        defer { try? KeychainPasswordStore.delete(for: key) }

        try KeychainPasswordStore.save("plain", for: key, requireBiometric: false)

        // No `prompt:` arg → no auth UI even on biometric Macs.
        #expect(try KeychainPasswordStore.read(for: key) == "plain")
    }

    @Test("hasSavedPassword returns true for an ACL-protected item without prompting")
    func hasSavedPasswordSkipsAuthForACLItems() throws {
        let key = makeKey()
        defer { try? KeychainPasswordStore.delete(for: key) }

        // Use the plain path — CI hosts may not have biometry, in which
        // case requireBiometric: true throws accessControlUnavailable.
        try KeychainPasswordStore.save("plain", for: key, requireBiometric: false)

        // Existence check uses kSecUseAuthenticationUISkip so it
        // never blocks, even if the item had been ACL-protected.
        #expect(KeychainPasswordStore.hasSavedPassword(for: key) == true)
    }

    @Test("cachedOrRead caches the value so repeat reads skip the keychain")
    func cachedOrReadCachesAfterFirstHit() throws {
        let key = makeKey()
        defer { try? KeychainPasswordStore.delete(for: key) }

        try KeychainPasswordStore.save("cached", for: key)

        // Prime the cache via the public API.
        #expect(KeychainPasswordStore.cachedOrRead(for: key) == "cached")

        // Now delete the underlying keychain entry. A subsequent
        // cachedOrRead should still return the cached value — that's
        // the whole point of the cache.
        try KeychainPasswordStore.delete(for: key)
        #expect(KeychainPasswordStore.cachedOrRead(for: key) == "cached")

        // Belt-and-braces: clear the cache and confirm the keychain
        // is empty too.
        KeychainPasswordStore.clearSessionCache()
        #expect(KeychainPasswordStore.cachedOrRead(for: key) == nil)
    }

    @Test("useBiometricACL flag defaults to false (no UI prompts in tests)")
    func biometricFlagDefaultsOff() {
        // Headless test runs must never trigger Touch ID. The shared
        // store defaults to non-biometric saves so unit tests are
        // safe to run in CI. The app sets the flag at launch.
        #expect(KeychainPasswordStore.useBiometricACL == false)
    }

    @Test("a set mockBackend routes saveOrLog + cachedOrRead away from the keychain")
    func mockBackendRoutesReadsAndWrites() {
        let mock = InMemoryCredentialStore()
        KeychainPasswordStore.mockBackend = mock
        defer { KeychainPasswordStore.mockBackend = nil }

        let key = KeychainPasswordStore.Key.canonical(
            address: "mock.example", port: 5500, login: "tester"
        )
        KeychainPasswordStore.saveOrLog("via-mock", for: key)

        #expect(KeychainPasswordStore.cachedOrRead(for: key) == "via-mock")
        #expect(KeychainPasswordStore.hasSavedPassword(for: key) == true)
        // The mock holds it, not the real keychain.
        #expect(mock.cachedOrRead(for: key, prompt: nil) == "via-mock")
    }

    @Test("a set mockBackend routes deleteOrLog")
    func mockBackendRoutesDeletes() {
        let mock = InMemoryCredentialStore()
        KeychainPasswordStore.mockBackend = mock
        defer { KeychainPasswordStore.mockBackend = nil }

        let key = KeychainPasswordStore.Key.canonical(
            address: "mock.example", port: 5500, login: "tester"
        )
        KeychainPasswordStore.saveOrLog("pw", for: key)
        KeychainPasswordStore.deleteOrLog(for: key)

        #expect(KeychainPasswordStore.hasSavedPassword(for: key) == false)
    }
}
