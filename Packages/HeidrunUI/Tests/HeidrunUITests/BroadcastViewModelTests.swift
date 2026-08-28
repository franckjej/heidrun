import Testing
@testable import HeidrunUI
import HeidrunCore

@Suite("BroadcastViewModel")
struct BroadcastViewModelTests {
    @Test("raises attention per broadcast and queues each entry")
    @MainActor
    func broadcastRaises() async {
        let (events, continuation) = AsyncStream<HotlineEvent>.makeStream()
        let viewModel = BroadcastViewModel(events: events)
        let recorder = RaiseRecorder()
        viewModel.onAttention = { recorder.raised += 1 }
        let observation = Task { await viewModel.observe() }
        continuation.yield(.broadcastReceived(message: "Server restarts at 22:00"))
        continuation.yield(.broadcastReceived(message: "Back up"))
        continuation.finish()
        await observation.value
        #expect(recorder.raised == 2)
        #expect(viewModel.pending.count == 2)
    }
}

@MainActor
private final class RaiseRecorder {
    var raised = 0
}
