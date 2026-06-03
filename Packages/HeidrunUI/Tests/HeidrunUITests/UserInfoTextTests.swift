import Testing
import HeidrunCore
@testable import HeidrunUI

@Suite("UserInfoText")
struct UserInfoTextTests {
    @Test("full format includes nickname, account, socket, and profile")
    func formatsFull() {
        let info = UserInfo(
            user: User(socket: 12, nickname: "Erika"),
            accountLogin: "erika",
            infoText: "hello world"
        )
        let text = UserInfoText.format(info)
        #expect(text.contains("Nickname: Erika"))
        #expect(text.contains("Account: erika"))
        #expect(text.contains("Socket: 12"))
        #expect(text.contains("Profile:"))
        #expect(text.contains("hello world"))
    }

    @Test("empty account and profile render as an em dash")
    func emptyFields() {
        let info = UserInfo(user: User(socket: 1, nickname: "Bob"), accountLogin: "", infoText: "")
        let text = UserInfoText.format(info)
        #expect(text.contains("Account: —"))
        #expect(text.contains("Profile:\n—"))
    }

    @Test("basic format covers nickname and socket without a profile")
    func basicFormat() {
        let text = UserInfoText.basic(User(socket: 9, nickname: "Carol"))
        #expect(text.contains("Nickname: Carol"))
        #expect(text.contains("Socket: 9"))
        #expect(!text.contains("Profile:"))
    }

    @Test("displayName prefixes the emoji when present, else bare nickname")
    func displayNameEmoji() {
        #expect(UserInfoText.displayName(User(socket: 1, nickname: "silver:box")) == "silver:box")
        #expect(
            UserInfoText.displayName(User(socket: 1, nickname: "silver:box", emoji: "🎸"))
            == "🎸 silver:box"
        )
        // Junk in the emoji field is sanitised to a single grapheme.
        #expect(
            UserInfoText.displayName(User(socket: 1, nickname: "x", emoji: "🎸🎸hello"))
            == "🎸 x"
        )
    }
}
