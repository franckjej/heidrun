import Foundation
import Testing
@testable import HeidrunFiles
import HeidrunCore

@Suite("FilesViewModel drop boxes and upload gating")
struct FilesViewModelDropBoxTests {
    @Test("entering a drop box without the privilege shows the drop box message and returns to the parent")
    @MainActor
    func dropBoxRefusalReturnsToParent() async {
        var presented: [String] = []
        let viewModel = makeViewModel(
            list: { path in
                if path.containsDropBox { throw HotlineError.serverError(id: 1, message: "nope") }
                return [RemoteFile(name: "Drop Box", type: .folder)]
            },
            present: { presented.append($0.localizedDescription) }
        )
        viewModel.updatePrivileges([.downloadFiles])
        await viewModel.navigate(to: ["Drop Box"])
        #expect(viewModel.currentPath.isRoot)
        #expect(viewModel.files.map(\.name) == ["Drop Box"])
        #expect(presented.count == 1)
        #expect(presented.first?.contains("drop box") == true)
    }

    @Test("a listing failure inside a drop box with the privilege is surfaced as-is")
    @MainActor
    func dropBoxFailureWithPrivilegePassesThrough() async {
        var presented: [String] = []
        let viewModel = makeViewModel(
            list: { _ in throw HotlineError.serverError(id: 1, message: "gone") },
            present: { presented.append($0.localizedDescription) }
        )
        viewModel.updatePrivileges([.downloadFiles, .viewDropBoxes])
        await viewModel.navigate(to: ["Drop Box"])
        #expect(viewModel.currentPath == ["Drop Box"])
        #expect(presented.first?.contains("drop box") == false)
    }

    @Test("canUpload fails open without privilege info")
    @MainActor
    func canUploadFailsOpen() {
        let viewModel = makeViewModel()
        #expect(viewModel.canUpload(to: []))
    }

    @Test("canUpload without uploadAnywhere is limited to upload folders and drop boxes")
    @MainActor
    func canUploadWithoutAnywhere() {
        let viewModel = makeViewModel()
        viewModel.updatePrivileges([.uploadFiles])
        #expect(!viewModel.canUpload(to: []))
        #expect(!viewModel.canUpload(to: ["Software"]))
        #expect(viewModel.canUpload(to: ["Uploads"]))
        #expect(viewModel.canUpload(to: ["Drop Box", "Inner"]))
    }

    @Test("canUpload with uploadAnywhere allows plain folders; without uploadFiles nothing")
    @MainActor
    func canUploadAnywhereAndNone() {
        let viewModel = makeViewModel()
        viewModel.updatePrivileges([.uploadFiles, .uploadAnywhere])
        #expect(viewModel.canUpload(to: ["Software"]))
        viewModel.updatePrivileges([.uploadAnywhere])
        #expect(!viewModel.canUpload(to: ["Uploads"]))
    }

    @Test("uploadFolder honours an explicit target path")
    @MainActor
    func uploadFolderExplicitPath() async throws {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("heidrun-upload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: folderURL.appendingPathComponent("a.txt"))
        defer { try? FileManager.default.removeItem(at: folderURL) }

        let recorded = Recorder<RemotePath>()
        let viewModel = FilesViewModel(
            listFiles: { _ in [] },
            createFolderAt: { _, _ in },
            deleteEntryAt: { _, _ in },
            renameAt: { _, _, _ in },
            setCommentAt: { _, _, _ in },
            moveEntryAt: { _, _, _ in },
            fetchFileInfoAt: { _, name in RemoteFileInfo(file: RemoteFile(name: name)) },
            beginDownload: { _, _, _ in TransferHandle(transferID: 0, totalSize: 0) },
            beginUpload: { _, _, _, _ in TransferHandle(transferID: 0, totalSize: 0) },
            beginFolderUpload: { path, _, _, _, _ in
                await recorded.append(path)
                return TransferHandle(transferID: 7, totalSize: 1)
            },
            cancelTransferAt: { _ in }
        )
        await viewModel.uploadFolder(folderURL: folderURL, at: ["Drop Box"])
        #expect(await recorded.values == [["Drop Box"]])
    }
}

actor Recorder<Value: Sendable> {
    private(set) var values: [Value] = []
    func append(_ value: Value) { values.append(value) }
}
