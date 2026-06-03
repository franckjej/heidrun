import Foundation
import Testing
@testable import Heidrun

/// The gating logic behind the close/quit confirmation prompts. The
/// `NSAlert` presentation isn't exercised here — only the decision of
/// *whether* to prompt, which is the part with branches worth pinning.
@Suite("DisconnectConfirmation")
struct DisconnectConfirmationTests {
    @Test("window close: prompts only when enabled AND the window is connected")
    func windowClose() {
        #expect(DisconnectConfirmation.shouldConfirmWindowClose(enabled: true, isConnected: true) == true)
        #expect(DisconnectConfirmation.shouldConfirmWindowClose(enabled: true, isConnected: false) == false)
        #expect(DisconnectConfirmation.shouldConfirmWindowClose(enabled: false, isConnected: true) == false)
        #expect(DisconnectConfirmation.shouldConfirmWindowClose(enabled: false, isConnected: false) == false)
    }

    @Test("quit: prompts only when enabled AND a connection is live")
    func quit() {
        #expect(DisconnectConfirmation.shouldConfirmQuit(enabled: true, hasLiveConnections: true) == true)
        #expect(DisconnectConfirmation.shouldConfirmQuit(enabled: true, hasLiveConnections: false) == false)
        #expect(DisconnectConfirmation.shouldConfirmQuit(enabled: false, hasLiveConnections: true) == false)
        #expect(DisconnectConfirmation.shouldConfirmQuit(enabled: false, hasLiveConnections: false) == false)
    }
}
