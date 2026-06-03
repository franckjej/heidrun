import Foundation

/// The credential operations the app's call sites use. `KeychainPasswordStore`
/// delegates to a conformer of this protocol when its `mockBackend` is set,
/// so isolated debug runs and tests can swap in a non-keychain backing.
public protocol CredentialStoring: Sendable {
    func saveOrLog(_ password: String, for key: KeychainPasswordStore.Key, unlockPrompt: String?)
    func deleteOrLog(for key: KeychainPasswordStore.Key)
    func read(for key: KeychainPasswordStore.Key, unlockPrompt: String?) throws -> String?
    func cachedOrRead(for key: KeychainPasswordStore.Key, prompt: String?) -> String?
    func hasSavedPassword(for key: KeychainPasswordStore.Key) -> Bool
    func findAnyLogin(forAddress address: String, port: UInt16) -> String?
}

/// A plain in-memory credential store used by isolated debug runs and tests.
/// No keychain, no crypto, no Touch ID — just a locked dictionary. An empty
/// string counts as "no password," mirroring the keychain store's contract.
public final class InMemoryCredentialStore: CredentialStoring, @unchecked Sendable {
    private var storage: [KeychainPasswordStore.Key: String] = [:]
    private let lock = NSLock()

    public init() {}

    public func saveOrLog(_ password: String, for key: KeychainPasswordStore.Key, unlockPrompt: String?) {
        lock.lock(); defer { lock.unlock() }
        storage[key] = password
    }

    public func deleteOrLog(for key: KeychainPasswordStore.Key) {
        lock.lock(); defer { lock.unlock() }
        storage[key] = nil
    }

    public func read(for key: KeychainPasswordStore.Key, unlockPrompt: String?) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    public func cachedOrRead(for key: KeychainPasswordStore.Key, prompt: String?) -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let value = storage[key], !value.isEmpty else { return nil }
        return value
    }

    public func hasSavedPassword(for key: KeychainPasswordStore.Key) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return storage[key]?.isEmpty == false
    }

    public func findAnyLogin(forAddress address: String, port: UInt16) -> String? {
        lock.lock(); defer { lock.unlock() }
        // Key.canonical already normalised stored addresses; normalise the
        // needle the same way. Port is accepted for API symmetry but, like
        // the real store, isn't part of the match (the account is port-free).
        let needle = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return storage.keys.first { $0.address == needle }?.login
    }
}
