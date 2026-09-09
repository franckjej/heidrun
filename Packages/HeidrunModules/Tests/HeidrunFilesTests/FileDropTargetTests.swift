import AppKit
import Testing
@testable import HeidrunFiles
import HeidrunCore

@Suite("FileDropTarget")
struct FileDropTargetTests {
    private let files: [RemoteFile] = [
        .parentPlaceholder,
        RemoteFile(name: "Drop Box", type: .folder),
        RemoteFile(name: "readme.txt"),
        RemoteFile(name: "link", type: .unresolvedAlias)
    ]

    @Test("a drop directly on a real folder row targets that folder")
    func folderRow() {
        let target = FileDropTarget.folder(atRow: 1, dropOperation: .on, in: files)
        #expect(target?.name == "Drop Box")
    }

    @Test("drops between rows, on files, on aliases, on the .. row, or out of range go to the current folder")
    func fallsBackToCurrentFolder() {
        #expect(FileDropTarget.folder(atRow: 1, dropOperation: .above, in: files) == nil)
        #expect(FileDropTarget.folder(atRow: 2, dropOperation: .on, in: files) == nil)
        #expect(FileDropTarget.folder(atRow: 3, dropOperation: .on, in: files) == nil)
        #expect(FileDropTarget.folder(atRow: 0, dropOperation: .on, in: files) == nil)
        #expect(FileDropTarget.folder(atRow: -1, dropOperation: .on, in: files) == nil)
        #expect(FileDropTarget.folder(atRow: 9, dropOperation: .on, in: files) == nil)
    }
}
