import Foundation
import Testing
@testable import HeidrunFiles
import HeidrunCore

@Suite("FileSelectionMapping")
struct FileSelectionMappingTests {
    private let files = [
        RemoteFile(name: "a.txt"),
        RemoteFile(name: "b.txt", type: .folder),
        RemoteFile(name: "c.txt")
    ]

    @Test("rowIndexes maps selected ids to their row positions")
    func rowIndexesFromSelection() {
        let rows = FileSelectionMapping.rowIndexes(for: ["a.txt", "c.txt"], in: files)
        #expect(rows == IndexSet([0, 2]))
    }

    @Test("rowIndexes ignores ids not present in the listing")
    func rowIndexesIgnoresMissing() {
        let rows = FileSelectionMapping.rowIndexes(for: ["a.txt", "gone.txt"], in: files)
        #expect(rows == IndexSet(integer: 0))
    }

    @Test("selection maps rows back to ids, skipping out-of-range rows")
    func selectionFromRows() {
        let ids = FileSelectionMapping.selection(forRows: IndexSet([1, 2, 99]), in: files)
        #expect(ids == ["b.txt", "c.txt"])
    }

    @Test("empty selection round-trips to no rows")
    func emptyRoundTrip() {
        #expect(FileSelectionMapping.rowIndexes(for: [], in: files).isEmpty)
        #expect(FileSelectionMapping.selection(forRows: IndexSet(), in: files).isEmpty)
    }
}
