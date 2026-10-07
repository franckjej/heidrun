import Testing
import HeidrunCore
@testable import HeidrunFiles

@Suite("TransferDrawer visibility")
struct TransferDrawerTests {
    private func transfer(_ transferID: UInt32, _ status: FilesViewModel.TransferStatus) -> FilesViewModel.TransferState {
        FilesViewModel.TransferState(
            handle: TransferHandle(transferID: transferID, totalSize: 1),
            displayName: "file-\(transferID)",
            destination: nil,
            direction: .upload,
            sourcePath: [],
            bytesWritten: 0,
            status: status
        )
    }

    @Test("hidden without transfers, shown until dismissed")
    func dismissal() {
        #expect(!TransferDrawer.isShown([:], dismissedThroughID: nil))
        let finished = [UInt32(3): transfer(3, .completed)]
        #expect(TransferDrawer.isShown(finished, dismissedThroughID: nil))
        #expect(!TransferDrawer.isShown(finished, dismissedThroughID: 3))
    }

    @Test("a newer or running transfer brings the drawer back")
    func reappears() {
        let newer = [UInt32(3): transfer(3, .completed), 4: transfer(4, .completed)]
        #expect(TransferDrawer.isShown(newer, dismissedThroughID: 3))
        let running = [UInt32(3): transfer(3, .running)]
        #expect(TransferDrawer.isShown(running, dismissedThroughID: 3))
    }
}
