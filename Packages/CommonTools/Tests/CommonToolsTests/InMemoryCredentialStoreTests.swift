import Foundation
import Testing
import CommonTools

@Suite("InMemoryCredentialStore")
struct InMemoryCredentialStoreTests {
    private func makeKey(address: String = "host.example", login: String = "bob") -> KeychainPasswordStore.Key {
        KeychainPasswordStore.Key.canonical(address: address, port: 5500, login: login)
    }

    @Test("saveOrLog then cachedOrRead returns the value")
    func savedValueReadsBack() {
        let store = InMemoryCredentialStore()
        let key = makeKey()
        store.saveOrLog("hunter2", for: key, unlockPrompt: nil)
        #expect(store.cachedOrRead(for: key, prompt: nil) == "hunter2")
    }

    @Test("read returns the value; nil when absent")
    func readReflectsStorage() throws {
        let store = InMemoryCredentialStore()
        let key = makeKey()
        #expect(try store.read(for: key, unlockPrompt: nil) == nil)
        store.saveOrLog("pw", for: key, unlockPrompt: nil)
        #expect(try store.read(for: key, unlockPrompt: nil) == "pw")
    }

    @Test("deleteOrLog removes the value")
    func deleteRemoves() {
        let store = InMemoryCredentialStore()
        let key = makeKey()
        store.saveOrLog("pw", for: key, unlockPrompt: nil)
        store.deleteOrLog(for: key)
        #expect(store.hasSavedPassword(for: key) == false)
        #expect(store.cachedOrRead(for: key, prompt: nil) == nil)
    }

    @Test("hasSavedPassword is false for an empty value")
    func emptyValueIsNotSaved() {
        let store = InMemoryCredentialStore()
        let key = makeKey()
        store.saveOrLog("", for: key, unlockPrompt: nil)
        #expect(store.hasSavedPassword(for: key) == false)
        #expect(store.cachedOrRead(for: key, prompt: nil) == nil)
    }

    @Test("saveOrLog overwrites a prior value")
    func overwriteReplaces() {
        let store = InMemoryCredentialStore()
        let key = makeKey()
        store.saveOrLog("first", for: key, unlockPrompt: nil)
        store.saveOrLog("second", for: key, unlockPrompt: nil)
        #expect(store.cachedOrRead(for: key, prompt: nil) == "second")
    }

    @Test("findAnyLogin returns the login for a matching address, nil otherwise")
    func findsLoginByAddress() {
        let store = InMemoryCredentialStore()
        store.saveOrLog("pw", for: makeKey(address: "Host.Example", login: "Bob"), unlockPrompt: nil)
        // Address is normalised (lowercased/trimmed) by Key.canonical.
        #expect(store.findAnyLogin(forAddress: "host.example", port: 5500) == "Bob")
        #expect(store.findAnyLogin(forAddress: "other.example", port: 5500) == nil)
    }
}
