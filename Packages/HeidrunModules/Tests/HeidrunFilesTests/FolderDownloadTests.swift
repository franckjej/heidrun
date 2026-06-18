import Foundation
import Testing
@testable import HeidrunFiles
import HeidrunCore

@Suite("FilesViewModel folder download")
struct FolderDownloadTests {
    @Test("downloadFolder recreates the server subtree on disk with resource forks")
    @MainActor
    func recreatesTree() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("heidrun-folder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileData = Data("inner file".utf8)
        let resourceFork = Data("RSRC".utf8)
        let viewModel = makeViewModel(
            beginFolderDownload: { _, _ in TransferHandle(transferID: 55, totalSize: UInt64(fileData.count)) },
            folderDownloadItems: { _, _, _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(FolderDownloadItem(relativePath: ["Sub"], isDirectory: true))
                    continuation.yield(FolderDownloadItem(
                        relativePath: ["Sub", "inner.txt"],
                        isDirectory: false,
                        data: fileData,
                        resourceFork: resourceFork
                    ))
                    continuation.finish()
                }
            },
            downloadFolder: { tempDir }
        )

        await viewModel.downloadFolder(RemoteFile(name: "Docs", type: .folder, itemCount: 2))
        try await waitFor { @MainActor in
            if case .completed = viewModel.transfers[55]?.status { return true }
            return false
        }

        let subURL = tempDir.appendingPathComponent("Docs/Sub", isDirectory: true)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: subURL.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)

        let innerURL = tempDir.appendingPathComponent("Docs/Sub/inner.txt")
        #expect(try Data(contentsOf: innerURL) == fileData)
        let rsrcURL = innerURL.appendingPathComponent("..namedfork/rsrc")
        #expect(try Data(contentsOf: rsrcURL) == resourceFork)
    }

    @Test("downloadFolder resumes a file already partly on disk")
    @MainActor
    func resumesPartial() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("heidrun-folder-resume-\(UUID().uuidString)")
        let subURL = tempDir.appendingPathComponent("Docs/Sub", isDirectory: true)
        try FileManager.default.createDirectory(at: subURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 7 bytes already on disk — the resume provider must report this
        // offset so the server's tail appends instead of overwriting.
        try Data("already".utf8).write(to: subURL.appendingPathComponent("inner.txt"))

        let viewModel = makeViewModel(
            beginFolderDownload: { _, _ in TransferHandle(transferID: 56, totalSize: 0) },
            folderDownloadItems: { _, resumeProvider, _ in
                AsyncThrowingStream { continuation in
                    let resume = resumeProvider(["Sub", "inner.txt"])
                    continuation.yield(FolderDownloadItem(
                        relativePath: ["Sub", "inner.txt"],
                        isDirectory: false,
                        data: Data(" more".utf8),
                        dataForkOffset: resume?.dataForkOffset ?? 0
                    ))
                    continuation.finish()
                }
            },
            downloadFolder: { tempDir }
        )

        await viewModel.downloadFolder(RemoteFile(name: "Docs", type: .folder))
        try await waitFor { @MainActor in
            if case .completed = viewModel.transfers[56]?.status { return true }
            return false
        }

        let final = try Data(contentsOf: tempDir.appendingPathComponent("Docs/Sub/inner.txt"))
        #expect(final == Data("already more".utf8))
    }

    @Test("downloadFolder finishes at 100% using the server's folder transfer size")
    @MainActor
    func finishesAtFullProgress() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("heidrun-folder-progress-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileData = Data(repeating: 0xAB, count: 64)
        // The server reports the *framed* envelope total (larger than the
        // data fork). totalSize must come from the handle, not the folder
        // entry's size (which is 0), and the tile must snap to 100%.
        let framedTotal: UInt64 = 200
        let viewModel = makeViewModel(
            beginFolderDownload: { _, _ in TransferHandle(transferID: 71, totalSize: framedTotal) },
            folderDownloadItems: { _, _, _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(FolderDownloadItem(
                        relativePath: ["a.bin"],
                        isDirectory: false,
                        data: fileData
                    ))
                    continuation.finish()
                }
            },
            downloadFolder: { tempDir }
        )

        await viewModel.downloadFolder(RemoteFile(name: "Docs", type: .folder, itemCount: 1))
        try await waitFor { @MainActor in
            if case .completed = viewModel.transfers[71]?.status { return true }
            return false
        }

        let state = try #require(viewModel.transfers[71])
        #expect(state.totalSize == framedTotal)
        #expect(state.fraction == 1.0)
    }

    @Test("downloadFolder accumulates the decoder's live progress deltas")
    @MainActor
    func reportsLiveProgress() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("heidrun-folder-live-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // totalSize (1000) differs from the reported deltas (120+80=200) so
        // observing bytesWritten == 200 can only come from the live deltas,
        // not the final snap-to-total.
        let viewModel = makeViewModel(
            beginFolderDownload: { _, _ in TransferHandle(transferID: 80, totalSize: 1000) },
            folderDownloadItems: { _, _, progress in
                AsyncThrowingStream { continuation in
                    Task {
                        await progress(120)
                        await progress(80)
                        // Hold before completing so the live value is observable
                        // before the snap-to-total overwrites it.
                        try? await Task.sleep(for: .milliseconds(120))
                        continuation.yield(FolderDownloadItem(
                            relativePath: ["a.bin"],
                            isDirectory: false,
                            data: Data(count: 200)
                        ))
                        continuation.finish()
                    }
                }
            },
            downloadFolder: { tempDir }
        )

        await viewModel.downloadFolder(RemoteFile(name: "Docs", type: .folder))
        try await waitFor { @MainActor in viewModel.transfers[80]?.bytesWritten == 200 }
        try await waitFor { @MainActor in
            if case .completed = viewModel.transfers[80]?.status { return true }
            return false
        }
        #expect(viewModel.transfers[80]?.bytesWritten == 1000)
    }
}
