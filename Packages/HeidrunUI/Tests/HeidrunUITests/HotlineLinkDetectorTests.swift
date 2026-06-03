import Foundation
import Testing
@testable import HeidrunUI

@Suite("HotlineLinkDetector")
struct HotlineLinkDetectorTests {

    @Test("matches a single hotline:// link")
    func singleHotline() {
        let text = "Try hotline://server.example.com"
        let hits = HotlineLinkDetector.scan(text)
        #expect(hits.count == 1)
        #expect(hits.first?.url.absoluteString == "hotline://server.example.com")
    }

    @Test("matches heidrun://, http://, and https://")
    func allFourSchemes() {
        let text = """
        heidrun://a.example
        http://b.example
        https://c.example
        hotline://d.example
        """
        let hits = HotlineLinkDetector.scan(text).map { $0.url.absoluteString }
        #expect(hits == [
            "heidrun://a.example",
            "http://b.example",
            "https://c.example",
            "hotline://d.example"
        ])
    }

    @Test("strips trailing sentence punctuation")
    func stripsTrailingPunctuation() {
        let cases = [
            "Visit hotline://server.": "hotline://server",
            "Try https://foo.bar,": "https://foo.bar",
            "Got heidrun://a:5500!": "heidrun://a:5500",
            "ok http://x?": "http://x"
        ]
        for (input, expected) in cases {
            let hits = HotlineLinkDetector.scan(input)
            #expect(hits.first?.url.absoluteString == expected, "input=\(input)")
        }
    }

    @Test("strips a trailing closing paren — (hotline://x)")
    func stripsTrailingParen() {
        let text = "see (hotline://server) for more"
        let hits = HotlineLinkDetector.scan(text)
        #expect(hits.count == 1)
        #expect(hits.first?.url.absoluteString == "hotline://server")
    }

    @Test("returns empty for text with no links")
    func noLinks() {
        #expect(HotlineLinkDetector.scan("just some prose, no urls here").isEmpty)
        #expect(HotlineLinkDetector.scan("").isEmpty)
    }

    @Test("scheme matching is case-insensitive")
    func caseInsensitive() {
        let hits = HotlineLinkDetector.scan("HOTLINE://Server and Https://X")
        #expect(hits.map { $0.url.absoluteString } == [
            "HOTLINE://Server",
            "Https://X"
        ])
    }

    @Test("multiple links on one line, in order")
    func multipleLinks() {
        let text = "first hotline://a.com and then heidrun://b.com/path/to/thing"
        let hits = HotlineLinkDetector.scan(text).map { $0.url.absoluteString }
        #expect(hits == [
            "hotline://a.com",
            "heidrun://b.com/path/to/thing"
        ])
    }

    @Test("range maps to the URL substring in the original text")
    func rangePositioning() {
        let text = "prefix hotline://target.example suffix"
        let hits = HotlineLinkDetector.scan(text)
        #expect(hits.count == 1)
        guard let hit = hits.first else { return }
        #expect(String(text[hit.range]) == "hotline://target.example")
    }

    @Test("hotline:// with login and port is preserved")
    func loginAndPort() {
        let text = "ssh-style hotline://admin:secret@host.example:5500/path"
        let hits = HotlineLinkDetector.scan(text)
        #expect(hits.first?.url.absoluteString
            == "hotline://admin:secret@host.example:5500/path")
    }
}
