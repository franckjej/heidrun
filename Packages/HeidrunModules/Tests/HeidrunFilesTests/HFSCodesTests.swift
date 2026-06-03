import Foundation
import Testing
@testable import HeidrunFiles
import HeidrunCore

@Suite("HFSCodes")
struct HFSCodesTests {
    @Test("Plain text extensions map to TEXT/ttxt")
    func textVariants() {
        for ext in ["txt", "text", "md", "csv", "json", "swift"] {
            let pair = HFSCodes.resolve(extension: ext)
            #expect(pair.type.stringValue == "TEXT", "extension \(ext)")
            #expect(pair.creator.stringValue == "ttxt", "extension \(ext)")
        }
    }

    @Test("Common bitmap extensions use Photoshop's 8BIM creator")
    func bitmapCreator() {
        for ext in ["jpg", "jpeg", "png", "gif", "tif", "tiff", "bmp"] {
            #expect(HFSCodes.resolve(extension: ext).creator.stringValue == "8BIM", "extension \(ext)")
        }
        #expect(HFSCodes.resolve(extension: "png").type.stringValue == "PNGf")
        #expect(HFSCodes.resolve(extension: "jpg").type.stringValue == "JPEG")
    }

    @Test("DMG / pkg / iso use the disk-image / installer creator ddsk")
    func diskImages() {
        for ext in ["dmg", "iso", "img", "pkg", "mpkg"] {
            #expect(HFSCodes.resolve(extension: ext).creator.stringValue == "ddsk", "extension \(ext)")
        }
    }

    @Test("Unknown extension falls back to BINA/????")
    func fallbackUnknown() {
        let pair = HFSCodes.resolve(extension: "xyznotreal")
        #expect(pair == HFSCodes.unknown)
        #expect(pair.type.stringValue == "BINA")
        #expect(pair.creator.stringValue == "????")
    }

    @Test("Empty extension falls back to unknown")
    func fallbackEmpty() {
        #expect(HFSCodes.resolve(extension: "") == HFSCodes.unknown)
        #expect(HFSCodes.resolve(extension: "   ") == HFSCodes.unknown)
    }

    @Test("Extension lookup is case-insensitive")
    func caseInsensitive() {
        #expect(HFSCodes.resolve(extension: "TXT") == HFSCodes.resolve(extension: "txt"))
        #expect(HFSCodes.resolve(extension: "JPG") == HFSCodes.resolve(extension: "jpg"))
        #expect(HFSCodes.resolve(extension: "DmG") == HFSCodes.resolve(extension: "dmg"))
    }

    @Test("Extension with a leading dot is tolerated")
    func leadingDotTolerated() {
        #expect(HFSCodes.resolve(extension: ".pdf") == HFSCodes.resolve(extension: "pdf"))
        #expect(HFSCodes.resolve(extension: ".pdf").type.stringValue == "PDF ")
    }

    @Test("resolve(fileURL:) reads the URL's pathExtension")
    func fromFileURL() {
        let url = URL(fileURLWithPath: "/tmp/example.dmg")
        let pair = HFSCodes.resolve(fileURL: url)
        #expect(pair.type.stringValue == "udif")
        #expect(pair.creator.stringValue == "ddsk")
    }

    @Test("resolve(fileURL:) on a file with no extension falls back to unknown")
    func fromFileURLNoExtension() {
        let url = URL(fileURLWithPath: "/tmp/README")
        #expect(HFSCodes.resolve(fileURL: url) == HFSCodes.unknown)
    }

    @Test("resolve(fileURL:) prefers com.apple.FinderInfo over the extension table")
    func finderInfoWinsOverExtension() throws {
        // .pdf would normally map to PDF /CARO via the extension table —
        // stamping TEXT/MSWD onto the file's FinderInfo proves the
        // xattr takes precedence.
        let url = try makeTempFile(suffix: ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeFinderInfo(type: "TEXT", creator: "MSWD", at: url)

        let pair = HFSCodes.resolve(fileURL: url)
        #expect(pair.type.stringValue == "TEXT")
        #expect(pair.creator.stringValue == "MSWD")
    }

    @Test("resolve(fileURL:) falls back to the extension when FinderInfo is all-zero")
    func allZeroFinderInfoFallsBackToExtension() throws {
        let url = try makeTempFile(suffix: ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeRawFinderInfo([UInt8](repeating: 0, count: 32), at: url)

        let pair = HFSCodes.resolve(fileURL: url)
        #expect(pair.type.stringValue == "PDF ")
        #expect(pair.creator.stringValue == "CARO")
    }

    @Test("resolve(fileURL:) with no extension AND no FinderInfo lands on unknown")
    func noExtensionNoFinderInfo() throws {
        let url = try makeTempFile(suffix: "")
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(HFSCodes.resolve(fileURL: url) == HFSCodes.unknown)
    }

    // MARK: - Helpers

    private func makeTempFile(suffix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hfscodes-\(UUID().uuidString)\(suffix)")
        FileManager.default.createFile(atPath: url.path, contents: Data("probe".utf8))
        return url
    }

    private func writeFinderInfo(type: String, creator: String, at url: URL) throws {
        var bytes = [UInt8](repeating: 0, count: 32)
        let typeBytes = Array(type.utf8.prefix(4))
        let creatorBytes = Array(creator.utf8.prefix(4))
        for (offset, byte) in typeBytes.enumerated() { bytes[offset] = byte }
        for (offset, byte) in creatorBytes.enumerated() { bytes[4 + offset] = byte }
        try writeRawFinderInfo(bytes, at: url)
    }

    private func writeRawFinderInfo(_ bytes: [UInt8], at url: URL) throws {
        let result = url.path.withCString { path in
            "com.apple.FinderInfo".withCString { attribute in
                bytes.withUnsafeBufferPointer { buffer in
                    setxattr(path, attribute, buffer.baseAddress, buffer.count, 0, 0)
                }
            }
        }
        if result != 0 {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
    }
}
