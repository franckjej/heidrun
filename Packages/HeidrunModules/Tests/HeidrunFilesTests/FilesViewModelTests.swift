import Foundation
import Testing
@testable import HeidrunFiles
import HeidrunCore

@Suite("FilesViewModel")
struct FilesViewModelTests {
    @Test("refresh fills files at the current path")
    @MainActor
    func refreshFillsFiles() async {
        let viewModel = makeViewModel(
            list: { _ in [
                RemoteFile(name: "Public", type: .folder, itemCount: 3),
                RemoteFile(name: "README.txt", type: "TEXT", size: 1024)
            ]
            }
        )
        await viewModel.refresh()
        #expect(viewModel.files.map(\.name) == ["Public", "README.txt"])
    }

    @Test("downloadFile streams the bytes into the given destination URL")
    @MainActor
    func downloadFileWritesToDestination() async throws {
        let payload = Data("export me".utf8)
        let viewModel = makeViewModel(
            beginDownload: { _, _, _ in TransferHandle(transferID: 9, totalSize: UInt64(payload.count)) },
            downloadBytes: { _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(payload)
                    continuation.finish()
                }
            }
        )
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("heidrun-export-\(UUID().uuidString).bin")
        try await viewModel.downloadFile(RemoteFile(name: "note.txt"), at: [], to: destination)
        #expect(try Data(contentsOf: destination) == payload)
        try? FileManager.default.removeItem(at: destination)
    }

    @Test("navigateInto descends only into folders and refreshes")
    @MainActor
    func navigateIntoFolderOnly() async {
        let recorder = PathRecorder()
        let viewModel = makeViewModel(
            list: { path in
                await recorder.record(path)
                return []
            }
        )
        await viewModel.navigateInto(RemoteFile(name: "Pictures", type: .folder, itemCount: 0))
        #expect(viewModel.currentPath.components == ["Pictures"])

        await viewModel.navigateInto(RemoteFile(name: "ignored.txt", type: "TEXT"))
        #expect(viewModel.currentPath.components == ["Pictures"]) // unchanged
        let visited = await recorder.paths.map(\.components)
        #expect(visited.contains(["Pictures"]))
    }

    @Test("navigateUp pops one component")
    @MainActor
    func navigateUpPops() async {
        let viewModel = makeViewModel()
        await viewModel.navigate(to: ["a", "b", "c"])
        #expect(viewModel.currentPath.components == ["a", "b", "c"])
        await viewModel.navigateUp()
        #expect(viewModel.currentPath.components == ["a", "b"])
    }

    @Test("createFolder forwards to the host then refreshes")
    @MainActor
    func createFolderForwards() async {
        let recorder = MutationRecorder()
        let viewModel = makeViewModel(
            create: { path, name in
                await recorder.recordCreate(path: path, name: name)
            }
        )
        await viewModel.createFolder(named: "Public")
        let creates = await recorder.creates
        #expect(creates.first?.name == "Public")
    }

    @Test("deleteAll removes every entry then refreshes exactly once")
    @MainActor
    func deleteAllDeletesEachAndRefreshesOnce() async {
        let deletes = DeleteRecorder()
        let listCalls = CallCounter()
        let viewModel = makeViewModel(
            list: { _ in await listCalls.bump(); return [] },
            deleteEntry: { _, name in await deletes.record(name: name) }
        )
        await viewModel.deleteAll([
            RemoteFile(name: "a.txt"),
            RemoteFile(name: "b.txt", type: .folder)
        ])
        #expect(await deletes.names == ["a.txt", "b.txt"])
        #expect(await listCalls.count == 1)   // one refresh for the whole batch
    }

    @Test("deleteAll with no entries is a no-op (no refresh)")
    @MainActor
    func deleteAllEmptyIsNoOp() async {
        let listCalls = CallCounter()
        let viewModel = makeViewModel(list: { _ in await listCalls.bump(); return [] })
        await viewModel.deleteAll([])
        #expect(await listCalls.isEmpty)
    }

    @Test("download stores the returned handle")
    @MainActor
    func downloadStoresHandle() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("heidrun-download-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let viewModel = makeViewModel(
            beginDownload: { _, _, _ in
                TransferHandle(transferID: 99, totalSize: 4096)
            },
            downloadFolder: { tempDir }
        )
        await viewModel.download(RemoteFile(name: "movie.mov", size: 4096))
        #expect(viewModel.transfers[99]?.totalSize == 4096)
    }

    @Test("cancel removes the handle")
    @MainActor
    func cancelRemovesHandle() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("heidrun-download-cancel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let viewModel = makeViewModel(
            beginDownload: { _, _, _ in TransferHandle(transferID: 1, totalSize: 100) },
            downloadFolder: { tempDir }
        )
        await viewModel.download(RemoteFile(name: "x", size: 100))
        let handle = TransferHandle(transferID: 1, totalSize: 100)
        await viewModel.cancel(handle)
        #expect(viewModel.transfers.isEmpty)
    }

    @Test("download skips when local file already matches the remote size")
    @MainActor
    func downloadSkipsWhenAlreadyComplete() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("heidrun-download-skip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let dest = tempDir.appendingPathComponent("ready.bin")
        let payload = Data(repeating: 0xAB, count: 256)
        try payload.write(to: dest)

        let probe = OffsetProbe()
        let viewModel = makeViewModel(
            beginDownload: { _, _, offset in
                await probe.record(offset)
                return TransferHandle(transferID: 5, totalSize: 256)
            },
            downloadFolder: { tempDir }
        )
        await viewModel.download(RemoteFile(name: "ready.bin", size: 256))
        let recorded = await probe.offsets
        #expect(recorded.isEmpty)            // server was never asked
        #expect(viewModel.transfers.isEmpty) // no transfer state queued
    }

    @Test("download resumes with the on-disk size as the data-fork offset")
    @MainActor
    func downloadResumesWithExistingOffset() async throws {
        let payload = Data((0..<512).map { UInt8($0 & 0xFF) })
        let head = payload.prefix(200)
        let tail = payload.suffix(payload.count - 200)
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("heidrun-download-resume-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        // Seed the partial file (the new resume source) with the first 200 bytes.
        let partialDest = tempDir.appendingPathComponent("split.bin.heidrunpart")
        let finalDest = tempDir.appendingPathComponent("split.bin")
        try Data(head).write(to: partialDest)

        let probe = OffsetProbe()
        let viewModel = makeViewModel(
            beginDownload: { _, _, offset in
                await probe.record(offset)
                // Real servers reply with `transferSize = remaining` —
                // just the bytes the side channel will stream, not the
                // full file size. Mirror that here so the test catches
                // any regression in absolute-progress accounting.
                return TransferHandle(transferID: 11, totalSize: UInt64(tail.count))
            },
            downloadBytes: { _ in
                AsyncThrowingStream { stream in
                    stream.yield(Data(tail))
                    stream.finish()
                }
            },
            downloadFolder: { tempDir }
        )
        await viewModel.download(RemoteFile(name: "split.bin", size: UInt32(payload.count)))

        try await waitFor { @MainActor in
            if case .completed = viewModel.transfers[11]?.status { return true }
            return false
        }

        let written = try Data(contentsOf: finalDest)
        let recorded = await probe.offsets
        #expect(recorded == [200])           // requested resume at byte 200
        #expect(written == payload)          // head + tail recomposed
        #expect(viewModel.transfers[11]?.bytesWritten == UInt64(payload.count))
        // Progress UI must show "X of <full file size>", not "X of <remaining>".
        #expect(viewModel.transfers[11]?.totalSize == UInt64(payload.count))
    }

    @Test("upload reads the file, drives sendUploadBytes, and reports progress")
    @MainActor
    func uploadDrainsFileWithProgress() async throws {
        let payload = Data((0..<1024).map { UInt8($0 & 0xFF) })
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("heidrun-upload-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let fileURL = tempDir.appendingPathComponent("sample.bin")
        try payload.write(to: fileURL)

        let captured = UploadCaptureProbe()
        let viewModel = makeViewModel(
            beginUpload: { _, _, size, _ in
                TransferHandle(transferID: 77, totalSize: UInt64(size))
            },
            sendUploadBytes: { content, handle, name, type, creator, _, _, _, progress in
                await captured.record(content: content, handle: handle, name: name, type: type, creator: creator)
                // Two progress ticks: halfway, then complete.
                let mid = UInt64(content.count / 2)
                await progress(mid)
                await captured.recordProgress(mid)
                await progress(UInt64(content.count))
                await captured.recordProgress(UInt64(content.count))
            }
        )

        await viewModel.upload(fileURL: fileURL)
        try await waitFor { @MainActor in
            if case .completed = viewModel.transfers[77]?.status { return true }
            return false
        }

        let state = try #require(viewModel.transfers[77])
        #expect(state.bytesWritten == UInt64(payload.count))
        #expect(state.totalSize == UInt64(payload.count))

        let recordedContent = await captured.content
        let recordedName = await captured.fileName
        let recordedTicks = await captured.progressTicks
        #expect(recordedContent == payload)
        #expect(recordedName == "sample.bin")
        #expect(recordedTicks.contains(UInt64(payload.count / 2)))
        #expect(recordedTicks.contains(UInt64(payload.count)))
    }

    @Test("upload surfaces HotlineError.fileAlreadyExists as pendingUploadConflict instead of touching the wire")
    @MainActor
    func uploadParksConflictWhenServerRejects() async throws {
        let payload = Data("hello world".utf8)
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("heidrun-upload-conflict-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let fileURL = tempDir.appendingPathComponent("notes.txt")
        try payload.write(to: fileURL)

        let sendCalls = CallCounter()
        let viewModel = makeViewModel(
            beginUpload: { _, _, _, _ in
                throw HotlineError.fileAlreadyExists(
                    message: "file 'notes.txt' already exists at this location"
                )
            },
            sendUploadBytes: { _, _, _, _, _, _, _, _, _ in
                await sendCalls.bump()
            }
        )
        viewModel.currentPath = RemotePath(components: ["Inbox"])

        await viewModel.upload(fileURL: fileURL)

        let conflict = try #require(viewModel.pendingUploadConflict)
        #expect(conflict.targetName == "notes.txt")
        #expect(conflict.targetPath.components == ["Inbox"])
        #expect(conflict.serverMessage.contains("notes.txt"))
        #expect(viewModel.transfers.isEmpty)
        let calls = await sendCalls.count
        #expect(calls == 0)

        viewModel.cancelPendingUpload()
        #expect(viewModel.pendingUploadConflict == nil)
    }

    @Test("download drains the stream into the destination file and completes")
    @MainActor
    func downloadDrainsStreamToDisk() async throws {
        let payload = Data((0..<2048).map { UInt8($0 & 0xFF) })
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("heidrun-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let finished = FinishProbe()
        let viewModel = makeViewModel(
            beginDownload: { _, _, _ in TransferHandle(transferID: 42, totalSize: UInt64(payload.count)) },
            downloadBytes: { _ in
                AsyncThrowingStream { continuation in
                    // Yield in two chunks so we can observe a non-zero progress mid-stream.
                    let half = payload.count / 2
                    continuation.yield(payload.prefix(half))
                    continuation.yield(payload.suffix(payload.count - half))
                    continuation.finish()
                }
            },
            downloadFolder: { tempDir },
            onTransferFinished: { state in
                Task { await finished.record(state) }
            }
        )

        await viewModel.download(RemoteFile(name: "sample.bin", type: "BINA", size: UInt32(payload.count)))

        // Allow the drain Task to run to completion.
        try await waitFor { @MainActor in
            if case .completed = viewModel.transfers[42]?.status { return true }
            return false
        }

        let state = try #require(viewModel.transfers[42])
        #expect(state.bytesWritten == UInt64(payload.count))
        let destination = try #require(state.destination)
        let written = try Data(contentsOf: destination)
        #expect(written == payload)

        let captured = await finished.captured
        #expect(captured.count == 1)
        #expect(captured.first?.id == 42)
    }

    @Test("downloadFolder recreates the server subtree on disk with resource forks")
    @MainActor
    func downloadFolderRecreatesTree() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("heidrun-folder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileData = Data("inner file".utf8)
        let resourceFork = Data("RSRC".utf8)
        let viewModel = makeViewModel(
            beginFolderDownload: { _, _ in TransferHandle(transferID: 55, totalSize: UInt64(fileData.count)) },
            folderDownloadItems: { _, _ in
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
    func downloadFolderResumesPartial() async throws {
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
            folderDownloadItems: { _, resumeProvider in
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
}

private actor FinishProbe {
    private(set) var captured: [FilesViewModel.TransferState] = []
    func record(_ state: FilesViewModel.TransferState) { captured.append(state) }
}

private func waitFor(
    timeout: Duration = .seconds(2),
    _ predicate: @escaping @MainActor () async -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if await predicate() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("waitFor timed out")
}

@Suite("FilesFeature")
struct FilesFeatureTests {
    @Test("static metadata is stable")
    func metadata() {
        #expect(FilesFeature.identifier == "com.heidrun.files")
        #expect(FilesFeature.displayName == "Files")
        #expect(!FilesFeature.systemImage.isEmpty)
    }
}

@Suite("FilesViewModel partial download lifecycle")
struct FilesViewModelPartialDownloadTests {

    private func makeTempFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("HeidrunPartialDLTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private let seed = PartialDownloadMetadata.SeedFields(
        serverAddress: "h.example.org",
        serverPort: 5500,
        serverLogin: "carol",
        serverName: "Example"
    )

    @Test("bytes land in the .heidrunpart file and metadata xattr is attached")
    @MainActor
    func bytesLandInPartialFile() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let viewModel = makeViewModel(
            beginDownload: { _, _, _ in TransferHandle(transferID: 1, totalSize: 8) },
            downloadBytes: { _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(Data([0x01, 0x02]))
                    continuation.yield(Data([0x03, 0x04]))
                    // No finish — drain stays mid-stream so the partial stays on disk.
                }
            },
            downloadFolder: { folder },
            metadataSeed: { self.seed }
        )

        let entry = RemoteFile(name: "foo.bin", size: 8)
        await viewModel.download(entry, mode: .fresh)

        // Give the drain a moment to flush chunks.
        try await Task.sleep(for: .milliseconds(50))

        let partial = folder.appendingPathComponent("foo.bin.heidrunpart")
        let final = folder.appendingPathComponent("foo.bin")
        #expect(FileManager.default.fileExists(atPath: partial.path))
        #expect(!FileManager.default.fileExists(atPath: final.path))

        let metadata = try PartialDownloadXattr.read(from: partial)
        #expect(metadata.remoteFileName == "foo.bin")
        #expect(metadata.serverAddress == "h.example.org")
    }

    @Test("completion renames .heidrunpart -> final and clears the xattr")
    @MainActor
    func renameOnCompletion() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let viewModel = makeViewModel(
            beginDownload: { _, _, _ in TransferHandle(transferID: 1, totalSize: 4) },
            downloadBytes: { _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(Data([0x01, 0x02, 0x03, 0x04]))
                    continuation.finish()
                }
            },
            downloadFolder: { folder },
            metadataSeed: { self.seed }
        )

        let entry = RemoteFile(name: "foo.bin", size: 4)
        await viewModel.download(entry, mode: .fresh)

        try await Task.sleep(for: .milliseconds(80))

        let partial = folder.appendingPathComponent("foo.bin.heidrunpart")
        let final = folder.appendingPathComponent("foo.bin")
        #expect(!FileManager.default.fileExists(atPath: partial.path))
        #expect(FileManager.default.fileExists(atPath: final.path))
        #expect(throws: PartialDownloadMetadataError.xattrMissing) {
            _ = try PartialDownloadXattr.read(from: final)
        }
    }

    @Test("localFileExists(for:) returns true when only the .heidrunpart is on disk")
    @MainActor
    func localExistsRecognisesPartial() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let viewModel = makeViewModel(downloadFolder: { folder })
        let entry = RemoteFile(name: "foo.bin", size: 4)

        // Baseline: no file on disk yet → returns false.
        #expect(!viewModel.localFileExists(for: entry))

        // Drop only the partial; localFileExists should now recognise it.
        try Data().write(to: folder.appendingPathComponent("foo.bin.heidrunpart"))
        #expect(viewModel.localFileExists(for: entry))
    }

    // MARK: - Quick Look preview

    @Test("isPreviewable rejects folders and unsupported extensions")
    @MainActor
    func isPreviewableRejectsNonText() {
        #expect(!FilesViewModel.isPreviewable(RemoteFile(name: "Pictures", type: .folder)))
        #expect(!FilesViewModel.isPreviewable(RemoteFile(name: "movie.mov", type: "MooV")))
        #expect(!FilesViewModel.isPreviewable(RemoteFile(name: "no-extension")))
    }

    @Test("isPreviewable accepts known text extensions and HFS TEXT type")
    @MainActor
    func isPreviewableAcceptsText() {
        #expect(FilesViewModel.isPreviewable(RemoteFile(name: "README.txt")))
        #expect(FilesViewModel.isPreviewable(RemoteFile(name: "notes.MD")))
        #expect(FilesViewModel.isPreviewable(RemoteFile(name: "config.yaml")))
        // No extension but the HFS type carries "TEXT" — should still preview.
        #expect(FilesViewModel.isPreviewable(RemoteFile(name: "readme", type: "TEXT")))
    }

    @Test("previewFile rejects files larger than the preview cap")
    @MainActor
    func previewRejectsOversizedFiles() async {
        let viewModel = makeViewModel()
        let huge = RemoteFile(
            name: "huge.log",
            size: UInt32(FilesViewModel.maxPreviewBytes) + 1
        )
        await viewModel.previewFile(huge)
        guard case .failed(let message) = viewModel.previewState else {
            Issue.record("expected .failed, got \(viewModel.previewState)")
            return
        }
        #expect(message.contains("huge.log"))
        #expect(message.lowercased().contains("limit"))
    }

    @Test("previewFile decodes UTF-8 text into a ready payload")
    @MainActor
    func previewDecodesText() async {
        let body = "hello, world\nzweite Zeile"
        let payload = Data(body.utf8)
        let viewModel = makeViewModel(
            beginDownload: { _, _, _ in TransferHandle(transferID: 17, totalSize: UInt64(payload.count)) },
            downloadBytes: { _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(payload)
                    continuation.finish()
                }
            }
        )
        let entry = RemoteFile(name: "greeting.txt", size: UInt32(payload.count))
        await viewModel.previewFile(entry)
        try? await Task.sleep(for: .milliseconds(50))
        guard case .ready(let preview) = viewModel.previewState else {
            Issue.record("expected .ready, got \(viewModel.previewState)")
            return
        }
        #expect(preview.fileName == "greeting.txt")
        guard case .text(let decoded) = preview.kind else {
            Issue.record("expected .text payload, got \(preview.kind)")
            return
        }
        #expect(decoded == body)
    }

    @Test("previewFile aborts when the server streams past the cap")
    @MainActor
    func previewAbortsOnSurge() async {
        // entry.size lies — claims small but server streams over the cap.
        let entry = RemoteFile(name: "lying.txt", size: 16)
        let chunk = Data(count: 1024 * 1024)  // 1 MB
        let viewModel = makeViewModel(
            beginDownload: { _, _, _ in TransferHandle(transferID: 21, totalSize: 16) },
            downloadBytes: { _ in
                AsyncThrowingStream { continuation in
                    // Six 1 MB chunks > 5 MB cap.
                    for _ in 0..<6 { continuation.yield(chunk) }
                    continuation.finish()
                }
            }
        )
        await viewModel.previewFile(entry)
        try? await Task.sleep(for: .milliseconds(100))
        guard case .failed(let message) = viewModel.previewState else {
            Issue.record("expected .failed, got \(viewModel.previewState)")
            return
        }
        #expect(message.lowercased().contains("size limit"))
    }

    @Test("dismissPreview resets state to idle")
    @MainActor
    func dismissResetsState() async {
        let viewModel = makeViewModel(
            beginDownload: { _, _, _ in TransferHandle(transferID: 5, totalSize: 4) },
            downloadBytes: { _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(Data("hi!".utf8))
                    continuation.finish()
                }
            }
        )
        await viewModel.previewFile(RemoteFile(name: "x.txt", size: 3))
        try? await Task.sleep(for: .milliseconds(50))
        viewModel.dismissPreview()
        #expect(viewModel.previewState == .idle)
    }
}

@MainActor
private func makeViewModel(
    list: @escaping @Sendable (RemotePath) async throws -> [RemoteFile] = { _ in [] },
    create: @escaping @Sendable (RemotePath, String) async throws -> Void = { _, _ in },
    deleteEntry: @escaping @Sendable (RemotePath, String) async throws -> Void = { _, _ in },
    rename: @escaping @Sendable (RemotePath, String, String) async throws -> Void = { _, _, _ in },
    setComment: @escaping @Sendable (RemotePath, String, String) async throws -> Void = { _, _, _ in },
    moveEntry: @escaping @Sendable (RemotePath, String, RemotePath) async throws -> Void = { _, _, _ in },
    fetchFileInfo: @escaping @Sendable (RemotePath, String) async throws -> RemoteFileInfo = { _, name in
        RemoteFileInfo(file: RemoteFile(name: name))
    },
    beginDownload: @escaping @Sendable (RemotePath, String, UInt32) async throws -> TransferHandle = { _, _, _ in TransferHandle(transferID: 0, totalSize: 0) },
    beginUpload: @escaping @Sendable (RemotePath, String, UInt32, Bool) async throws -> TransferHandle = { _, _, _, _ in TransferHandle(transferID: 0, totalSize: 0) },
    cancelTransfer: @escaping @Sendable (TransferHandle) async throws -> Void = { _ in },
    downloadBytes: @escaping @Sendable (TransferHandle) -> AsyncThrowingStream<Data, Error> = { _ in
        AsyncThrowingStream { $0.finish() }
    },
    sendUploadBytes: @escaping FilesViewModel.UploadSender = { _, _, _, _, _, _, _, _, _ in },
    beginFolderDownload: @escaping @Sendable (RemotePath, String) async throws -> TransferHandle
        = { _, _ in TransferHandle(transferID: 0, totalSize: 0) },
    folderDownloadItems: @escaping FilesViewModel.FolderDownloadStreamer
        = { _, _ in AsyncThrowingStream { $0.finish() } },
    downloadFolder: @escaping @Sendable () -> URL = FilesViewModel.defaultDownloadFolder,
    onTransferFinished: (@MainActor @Sendable (FilesViewModel.TransferState) -> Void)? = nil,
    metadataSeed: @escaping @Sendable () -> PartialDownloadMetadata.SeedFields? = { nil }
) -> FilesViewModel {
    FilesViewModel(
        listFiles: list,
        createFolderAt: create,
        deleteEntryAt: deleteEntry,
        renameAt: rename,
        setCommentAt: setComment,
        moveEntryAt: moveEntry,
        fetchFileInfoAt: fetchFileInfo,
        beginDownload: beginDownload,
        beginUpload: beginUpload,
        cancelTransferAt: cancelTransfer,
        downloadBytes: downloadBytes,
        sendUploadBytes: sendUploadBytes,
        beginFolderDownload: beginFolderDownload,
        folderDownloadItems: folderDownloadItems,
        downloadFolderURL: downloadFolder,
        onTransferFinished: onTransferFinished,
        metadataSeed: metadataSeed
    )
}

private actor OffsetProbe {
    private(set) var offsets: [UInt32] = []
    func record(_ value: UInt32) { offsets.append(value) }
}

private actor UploadCaptureProbe {
    private(set) var content = Data()
    private(set) var fileName: String = ""
    private(set) var handle = TransferHandle(transferID: 0, totalSize: 0)
    private(set) var progressTicks: [UInt64] = []
    private(set) var type: HeidrunCore.FourCharCode = .unknown
    private(set) var creator: HeidrunCore.FourCharCode = .unknown

    func record(
        content: Data,
        handle: TransferHandle,
        name: String,
        type: HeidrunCore.FourCharCode = .unknown,
        creator: HeidrunCore.FourCharCode = .unknown
    ) {
        self.content = content
        self.handle = handle
        self.fileName = name
        self.type = type
        self.creator = creator
    }

    func recordProgress(_ value: UInt64) {
        progressTicks.append(value)
    }
}

private actor PathRecorder {
    private(set) var paths: [RemotePath] = []
    func record(_ path: RemotePath) { paths.append(path) }
}

private actor MutationRecorder {
    struct Create: Sendable, Hashable {
        let path: RemotePath
        let name: String
    }
    private(set) var creates: [Create] = []
    func recordCreate(path: RemotePath, name: String) {
        creates.append(Create(path: path, name: name))
    }
}

private actor DeleteRecorder {
    private(set) var names: [String] = []
    func record(name: String) { names.append(name) }
}

private actor CallCounter {
    private(set) var count = 0
    var isEmpty: Bool { count < 1 }
    func bump() { count += 1 }
}
