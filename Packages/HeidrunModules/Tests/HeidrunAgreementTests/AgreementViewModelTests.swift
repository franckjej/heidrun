import Foundation
import Testing
@testable import HeidrunAgreement
import HeidrunCore

@Suite("AgreementViewModel")
struct AgreementViewModelTests {
    @Test("captures the most recent agreement banner")
    @MainActor
    func capturesAgreement() async {
        let (events, continuation) = AsyncStream<HotlineEvent>.makeStream()
        let viewModel = AgreementViewModel(
            events: events,
            agree: { _, _ in },
            disconnect: { }
        )

        let observation = Task { await viewModel.observe() }

        continuation.yield(.agreementReceived(text: "first version", autoAgree: false))
        continuation.yield(.agreementReceived(text: "second version", autoAgree: true))
        continuation.finish()

        await observation.value

        #expect(viewModel.text == "second version")
        #expect(viewModel.autoAgree)
    }

    @Test("accept forwards nickname and icon, then clears the banner")
    @MainActor
    func acceptForwards() async throws {
        let (events, continuation) = AsyncStream<HotlineEvent>.makeStream()
        let recorder = AgreementRecorder()
        let viewModel = AgreementViewModel(
            events: events,
            agree: { nick, icon in await recorder.recordAgree(nickname: nick, icon: icon) },
            disconnect: { },
            defaultNickname: "Tom",
            defaultIcon: 12
        )

        let observation = Task { await viewModel.observe() }
        continuation.yield(.agreementReceived(text: "Welcome", autoAgree: false))
        continuation.finish()
        await observation.value

        try await viewModel.accept()

        let calls = await recorder.agreeCalls
        #expect(calls.count == 1)
        #expect(calls.first?.nickname == "Tom")
        #expect(calls.first?.icon == 12)
        #expect(viewModel.text == nil)
    }

    @Test("decline disconnects and clears the banner")
    @MainActor
    func declineDisconnects() async {
        let (events, continuation) = AsyncStream<HotlineEvent>.makeStream()
        let recorder = AgreementRecorder()
        let viewModel = AgreementViewModel(
            events: events,
            agree: { _, _ in },
            disconnect: { await recorder.recordDisconnect() }
        )

        let observation = Task { await viewModel.observe() }
        continuation.yield(.agreementReceived(text: "Welcome", autoAgree: false))
        continuation.finish()
        await observation.value

        await viewModel.decline()

        let count = await recorder.disconnectCount
        #expect(count == 1)
        #expect(viewModel.text == nil)
    }
}

@Suite("AgreementFeature")
struct AgreementFeatureTests {
    @Test("static metadata is stable")
    func metadata() {
        #expect(AgreementFeature.identifier  == "com.heidrun.agreement")
        #expect(AgreementFeature.displayName == "Agreement")
        #expect(!AgreementFeature.systemImage.isEmpty)
    }
}

private actor AgreementRecorder {
    struct AgreeCall: Sendable, Hashable {
        let nickname: String
        let icon: UInt16
    }

    private(set) var agreeCalls: [AgreeCall] = []
    private(set) var disconnectCount = 0

    func recordAgree(nickname: String, icon: UInt16) {
        agreeCalls.append(AgreeCall(nickname: nickname, icon: icon))
    }

    func recordDisconnect() {
        disconnectCount += 1
    }
}
