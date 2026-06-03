import Foundation
import Testing
@testable import HeidrunNews
import HeidrunUI

@Suite("NewsPostsTranscriptProjection")
struct NewsPostsTranscriptProjectionTests {

    @Test("single post is one body line")
    func single() {
        let lines = NewsPostsTranscriptProjection.lines(from: ["hello"])

        #expect(lines.count == 1)
        #expect(lines[0].segments.map(\.style) == [.body])
        #expect(lines[0].segments[0].text == "hello")
        #expect(lines[0].id == "post-0")
    }

    @Test("two posts are separated by one empty TranscriptLine")
    func twoPostsSeparator() {
        let lines = NewsPostsTranscriptProjection.lines(from: ["first", "second"])

        #expect(lines.count == 3)
        #expect(lines[0].segments.map(\.style) == [.body])
        #expect(lines[0].segments[0].text == "first")
        #expect(lines[1].segments.isEmpty)
        #expect(lines[1].id == "blank-after-0")
        #expect(lines[2].segments[0].text == "second")
        #expect(lines[2].id == "post-1")
    }

    @Test("three posts have two separator lines")
    func threePosts() {
        let lines = NewsPostsTranscriptProjection.lines(from: ["a", "b", "c"])

        #expect(lines.count == 5)
        #expect(lines.map(\.id) ==
                ["post-0", "blank-after-0", "post-1", "blank-after-1", "post-2"])
    }

    @Test("multiline post body is preserved as one TranscriptLine")
    func multilinePost() {
        let lines = NewsPostsTranscriptProjection.lines(
            from: ["paragraph 1\nparagraph 2"]
        )

        #expect(lines.count == 1)
        #expect(lines[0].segments[0].text == "paragraph 1\nparagraph 2")
    }

    @Test("empty posts array yields empty result")
    func emptyInput() {
        let lines = NewsPostsTranscriptProjection.lines(from: [])
        #expect(lines.isEmpty)
    }
}
