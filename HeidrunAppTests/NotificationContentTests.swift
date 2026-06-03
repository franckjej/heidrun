import Foundation
import Testing
import UserNotifications
@testable import Heidrun
import HeidrunFiles

/// Regression coverage for the pure `HotlineEvent → UNMutableNotificationContent`
/// mapping. Every per-event mapping carries title, body, and grouping wiring
/// the click handler relies on; these tests pin each piece so future edits to
/// the mapping cannot silently drop the host identifier into `userInfo` or
/// strip the `threadIdentifier` that drives per-server stacking in Notification
/// Center.
@MainActor
@Suite("NotificationContent.makeContent")
struct NotificationContentTests {
    private let sampleHost = HostIdentity(
        id: "host-uuid-123",
        displayName: "Carpe Diem"
    )

    @Test("connected → title, body uses host display name, threadIdentifier set")
    func mapsConnected() {
        let content = NotificationContent.makeContent(for: .connected, host: sampleHost)
        #expect(content.title == "Connected")
        #expect(content.body == "Carpe Diem")
        #expect(content.threadIdentifier == "host-uuid-123")
        #expect(content.userInfo[NotificationContent.UserInfoKey.hostID] as? String == "host-uuid-123")
        #expect(content.userInfo[NotificationContent.UserInfoKey.eventKind] as? String == "connected")
        #expect(content.sound == nil)
    }

    @Test("disconnected with reason → body appends the reason after an em dash")
    func mapsDisconnectedWithReason() {
        let content = NotificationContent.makeContent(
            for: .disconnected(reason: "Connection lost."),
            host: sampleHost
        )
        #expect(content.title == "Disconnected")
        #expect(content.body == "Carpe Diem — Connection lost.")
        #expect(content.userInfo[NotificationContent.UserInfoKey.eventKind] as? String == "disconnected")
    }

    @Test("disconnected without reason → body is just the host name")
    func mapsDisconnectedWithoutReason() {
        let content = NotificationContent.makeContent(
            for: .disconnected(reason: nil),
            host: sampleHost
        )
        #expect(content.title == "Disconnected")
        #expect(content.body == "Carpe Diem")
    }

    @Test("private message → title is sender, body is message, subtitle is host")
    func mapsPrivateMessage() {
        let content = NotificationContent.makeContent(
            for: .privateMessage(senderName: "Erika", body: "yo"),
            host: sampleHost
        )
        #expect(content.title == "Erika")
        #expect(content.body == "yo")
        #expect(content.subtitle == "Carpe Diem")
        #expect(content.userInfo[NotificationContent.UserInfoKey.eventKind] as? String == "privateMessage")
    }

    @Test("private message body longer than 120 chars is truncated with ellipsis")
    func truncatesLongPrivateMessage() {
        let longBody = String(repeating: "x", count: 200)
        let content = NotificationContent.makeContent(
            for: .privateMessage(senderName: "Erika", body: longBody),
            host: sampleHost
        )
        #expect(content.body.count == 120)
        #expect(content.body.hasSuffix("…"))
    }

    @Test("chat invite with message → title names the inviter, body is the message")
    func mapsChatInviteWithMessage() {
        let content = NotificationContent.makeContent(
            for: .chatInvite(senderName: "Lars", message: "join us"),
            host: sampleHost
        )
        #expect(content.title == "Chat invitation from Lars")
        #expect(content.body == "join us")
    }

    @Test("chat invite without message → body falls back to a generic line")
    func mapsChatInviteWithoutMessage() {
        let content = NotificationContent.makeContent(
            for: .chatInvite(senderName: "Lars", message: nil),
            host: sampleHost
        )
        #expect(content.title == "Chat invitation from Lars")
        #expect(content.body == "wants to chat")
    }

    @Test("download finished → title says Download, body is the filename")
    func mapsDownloadFinished() {
        let content = NotificationContent.makeContent(
            for: .transferFinished(filename: "movie.mp4", direction: .download),
            host: sampleHost
        )
        #expect(content.title == "Download complete")
        #expect(content.body == "movie.mp4")
        #expect(content.subtitle == "Carpe Diem")
    }

    @Test("upload finished → title says Upload")
    func mapsUploadFinished() {
        let content = NotificationContent.makeContent(
            for: .transferFinished(filename: "notes.txt", direction: .upload),
            host: sampleHost
        )
        #expect(content.title == "Upload complete")
        #expect(content.body == "notes.txt")
    }

    @Test("news posted → title is fixed, body is the (truncated) text")
    func mapsNewsPosted() {
        let content = NotificationContent.makeContent(
            for: .newsPosted(text: "fresh news"),
            host: sampleHost
        )
        #expect(content.title == "News")
        #expect(content.body == "fresh news")
        #expect(content.userInfo[NotificationContent.UserInfoKey.eventKind] as? String == "newsPosted")
    }

    @Test("broadcast → title is host, subtitle is 'Server broadcast', body is the text, no sound")
    func broadcastContent() {
        let host = HostIdentity(id: "host-broadcast", displayName: "TastyBytes")
        let content = NotificationContent.makeContent(
            for: .broadcast(text: "Maintenance window starts in 5 minutes."),
            host: host
        )
        #expect(content.title == "TastyBytes")
        #expect(content.subtitle == "Server broadcast")
        #expect(content.body == "Maintenance window starts in 5 minutes.")
        #expect(content.sound == nil)
        #expect(content.threadIdentifier == "host.host-broadcast.broadcast")
        #expect(content.userInfo[NotificationContent.UserInfoKey.eventKind] as? String == "broadcast")
    }

    @Test("truncate keeps strings under the limit unchanged")
    func truncatePassesShortStringsThrough() {
        #expect(NotificationContent.truncate("short", to: 10) == "short")
    }

    @Test("truncate trims the input and appends a horizontal ellipsis")
    func truncateAppendsEllipsis() {
        let truncated = NotificationContent.truncate("abcdefghij", to: 5)
        #expect(truncated.count == 5)
        #expect(truncated.hasSuffix("…"))
    }
}
