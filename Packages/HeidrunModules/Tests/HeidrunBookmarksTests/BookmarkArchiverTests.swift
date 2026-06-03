import Foundation
import Testing
import HeidrunCore
@testable import HeidrunBookmarks

@Suite("BookmarkArchiver")
struct BookmarkArchiverTests {

    private func makeBookmark(_ name: String = "Test") -> Bookmark {
        Bookmark(settings: ConnectionSettings(
            name: name,
            address: "\(name.lowercased()).example.com",
            port: 5500,
            nickname: "tester",
            login: "bob",
            icon: 410
        ))
    }

    @Test("archive then unarchive round-trips settings")
    func archiveUnarchiveRoundTrip() throws {
        let originals = [makeBookmark("First"), makeBookmark("Second")]
        let data = try BookmarkArchiver.archive(originals) { _ in nil }
        let decoded = try BookmarkArchiver.unarchive(data) { _, _ in }

        #expect(decoded.count == 2)
        #expect(decoded.map(\.settings.name) == ["First", "Second"])
        #expect(decoded.map(\.settings.address) == ["first.example.com", "second.example.com"])
        #expect(decoded.map(\.settings.icon) == [410, 410])
        // Fresh UUIDs on unarchive — legacy has no id field, so we
        // never preserve it. Locks the contract down so a future
        // "preserve ids" change can't silently slip through.
        #expect(decoded[0].id != originals[0].id)
        #expect(decoded[1].id != originals[1].id)
    }

    @Test("archive reads passwords via the injected closure")
    func archiveCallsReadPassword() throws {
        let mark = makeBookmark("WithPwd")
        let key = KeychainPasswordKey(address: mark.settings.address, port: mark.settings.port, login: mark.settings.login)
        var observedKeys: [KeychainPasswordKey] = []
        _ = try BookmarkArchiver.archive([mark]) { askedKey in
            observedKeys.append(askedKey)
            return "secret"
        }
        #expect(observedKeys == [key])
    }

    @Test("unarchive writes passwords via the injected closure when present")
    func unarchiveCallsWritePassword() throws {
        let mark = makeBookmark("WithPwd")
        let data = try BookmarkArchiver.archive([mark]) { _ in "hunter2" }

        var observed: [(String, KeychainPasswordKey)] = []
        _ = try BookmarkArchiver.unarchive(data) { password, key in
            observed.append((password, key))
        }
        #expect(observed.count == 1)
        #expect(observed.first?.0 == "hunter2")
        #expect(observed.first?.1.address == mark.settings.address)
    }

    @Test("unarchive skips writePassword when the field is empty")
    func unarchiveSkipsEmptyPassword() throws {
        let mark = makeBookmark()
        let data = try BookmarkArchiver.archive([mark]) { _ in "" }

        var observed: [(String, KeychainPasswordKey)] = []
        _ = try BookmarkArchiver.unarchive(data) { password, key in
            observed.append((password, key))
        }
        #expect(observed.isEmpty)
    }

    @Test("archive/unarchive round-trips useTLS + the pinned certificate fingerprint")
    func pinRoundTrips() throws {
        var settings = ConnectionSettings(name: "Pinned", address: "h", useTLS: true)
        settings.pinnedCertificateSHA256 = "deadbeef"
        let data = try BookmarkArchiver.archive([Bookmark(settings: settings)]) { _ in nil }
        let decoded = try BookmarkArchiver.unarchive(data) { _, _ in }
        #expect(decoded.first?.settings.useTLS == true)
        #expect(decoded.first?.settings.pinnedCertificateSHA256 == "deadbeef")
    }

    @Test("unarchive of a dict without the pin key yields nil pin + cleartext default")
    func legacyDictNoPin() throws {
        let mark = makeBookmark("Old")   // helper sets neither useTLS nor a pin
        let data = try BookmarkArchiver.archive([mark]) { _ in nil }
        let decoded = try BookmarkArchiver.unarchive(data) { _, _ in }
        #expect(decoded.first?.settings.pinnedCertificateSHA256 == nil)
        #expect(decoded.first?.settings.useTLS == false)
    }

    @Test("unarchive throws unexpectedRootType when root is not an array")
    func unarchiveRejectsWrongRoot() throws {
        let bogus = try NSKeyedArchiver.archivedData(
            withRootObject: NSDictionary(),
            requiringSecureCoding: true
        )
        do {
            _ = try BookmarkArchiver.unarchive(bogus) { _, _ in }
            Issue.record("expected throw")
        } catch BookmarkArchiveError.unexpectedRootType {
            // ok
        }
    }

    @Test("unarchive throws missingField when a required key is absent")
    func unarchiveRejectsMissingField() throws {
        let incomplete: NSDictionary = ["Address": "foo", "Port": 5500]  // no Name
        let data = try NSKeyedArchiver.archivedData(
            withRootObject: NSArray(array: [incomplete]),
            requiringSecureCoding: true
        )
        do {
            _ = try BookmarkArchiver.unarchive(data) { _, _ in }
            Issue.record("expected throw")
        } catch BookmarkArchiveError.missingField(let field) {
            #expect(field == "Name")
        }
    }

    @Test("unarchive throws cannotDecode on raw garbage bytes")
    func unarchiveRejectsGarbageBytes() throws {
        let garbage = Data([0xDE, 0xAD, 0xBE, 0xEF])
        do {
            _ = try BookmarkArchiver.unarchive(garbage) { _, _ in }
            Issue.record("expected throw")
        } catch BookmarkArchiveError.cannotDecode {
            // ok
        }
    }
}
