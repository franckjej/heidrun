import Foundation
import Testing
@testable import Heidrun
import CommonTools

@MainActor
@Suite("KeychainPasswordStore.findAnyLogin")
struct KeychainPasswordStoreFindLoginTests {
    @Test("returns nil when no entry exists for the address")
    func returnsNilWhenNoEntries() {
        let address = "findlogin-\(UUID().uuidString).example"
        #expect(KeychainPasswordStore.findAnyLogin(forAddress: address, port: 5500) == nil)
    }

    @Test("finds the login by address prefix")
    func findsByAddressPrefix() throws {
        let address = "findlogin-\(UUID().uuidString).example"
        let key = KeychainPasswordStore.Key.canonical(address: address, port: 5500, login: "alice")
        defer { try? KeychainPasswordStore.delete(for: key) }
        try KeychainPasswordStore.save("secret", for: key)
        #expect(KeychainPasswordStore.findAnyLogin(forAddress: address, port: 5500) == "alice")
    }

    @Test("matches the address case-insensitively while preserving login case")
    func caseInsensitiveAddress() throws {
        let unique = UUID().uuidString
        let address = "FindLogin-\(unique).Example"
        let key = KeychainPasswordStore.Key.canonical(address: address, port: 5500, login: "BobCase")
        defer { try? KeychainPasswordStore.delete(for: key) }
        try KeychainPasswordStore.save("secret", for: key)
        // Query with a differently-cased address; the returned login
        // keeps its original case.
        #expect(KeychainPasswordStore.findAnyLogin(forAddress: address.uppercased(), port: 5500) == "BobCase")
    }

    @Test("does not match a different address")
    func ignoresDifferentAddress() throws {
        let address = "findlogin-\(UUID().uuidString).example"
        let other = "findlogin-\(UUID().uuidString).example"
        let key = KeychainPasswordStore.Key.canonical(address: address, port: 5500, login: "carol")
        defer { try? KeychainPasswordStore.delete(for: key) }
        try KeychainPasswordStore.save("secret", for: key)
        #expect(KeychainPasswordStore.findAnyLogin(forAddress: other, port: 5500) == nil)
    }
}
