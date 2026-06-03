import Foundation
import Testing
import HeidrunCore
@testable import Heidrun

@Suite("HotlineURLParser")
struct HotlineURLParserTests {
    @Test("plain host with no port defaults to 5500")
    func plainHost() throws {
        let settings = try #require(HotlineURLParser.parse(URL(string: "hotline://example.com")!))
        #expect(settings.address == "example.com")
        #expect(settings.port == 5500)
        #expect(settings.login.isEmpty)
        #expect(settings.useTLS == false)
    }

    @Test("explicit port is honoured")
    func explicitPort() throws {
        let settings = try #require(HotlineURLParser.parse(URL(string: "hotline://example.com:5510")!))
        #expect(settings.address == "example.com")
        #expect(settings.port == 5510)
    }

    @Test("login is parsed from the user info component")
    func loginUser() throws {
        let settings = try #require(HotlineURLParser.parse(URL(string: "hotline://guest@example.com")!))
        #expect(settings.login == "guest")
    }

    @Test("password in URL is parsed but intentionally not threaded into settings")
    func passwordIgnored() throws {
        let settings = try #require(HotlineURLParser.parse(URL(string: "hotline://guest:secret@example.com")!))
        #expect(settings.login == "guest")
        // ConnectionSettings has no password field — passwords live in
        // the Keychain. Documented behaviour: URL passwords are
        // accepted by the parser (no failure) but not propagated.
    }

    @Test("heidrun:// alias is equivalent to hotline://")
    func heidrunSchemeAlias() throws {
        let hotline = try #require(HotlineURLParser.parse(URL(string: "hotline://example.com:5510")!))
        let heidrun = try #require(HotlineURLParser.parse(URL(string: "heidrun://example.com:5510")!))
        #expect(hotline.address == heidrun.address)
        #expect(hotline.port == heidrun.port)
    }

    @Test("scheme matching is case-insensitive")
    func caseInsensitiveScheme() throws {
        #expect(HotlineURLParser.parse(URL(string: "HOTLINE://example.com")!) != nil)
        #expect(HotlineURLParser.parse(URL(string: "Heidrun://example.com")!) != nil)
    }

    @Test("unknown scheme returns nil so the caller can route elsewhere")
    func unknownSchemeReturnsNil() {
        #expect(HotlineURLParser.parse(URL(string: "file:///tmp/foo")!) == nil)
        #expect(HotlineURLParser.parse(URL(string: "https://example.com")!) == nil)
        #expect(HotlineURLParser.parse(URL(string: "ftp://example.com")!) == nil)
    }

    @Test("missing host returns nil")
    func missingHost() {
        // `hotline://` with no host is malformed for our purposes —
        // we can't open a connection without an address.
        let url = URL(string: "hotline://")!
        #expect(HotlineURLParser.parse(url) == nil)
    }

    @Test("ad-hoc connection from URL has an empty bookmark name")
    func emptyBookmarkName() throws {
        // URL-launched connections don't belong to a saved bookmark,
        // so `name` stays empty — the chat header / window title fall
        // back to the address (verified in ChatViewModel).
        let settings = try #require(HotlineURLParser.parse(URL(string: "hotline://example.com")!))
        #expect(settings.name.isEmpty)
    }
}
