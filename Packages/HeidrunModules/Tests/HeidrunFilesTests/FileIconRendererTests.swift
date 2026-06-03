import Foundation
import Testing
import UniformTypeIdentifiers
@testable import HeidrunFiles
import HeidrunCore

@Suite("FileIconRenderer.resolveUTType")
struct FileIconRendererTests {
    @Test("folders short-circuit to UTType.folder, ignoring filename")
    func folderShortCircuits() {
        let folder = RemoteFile(name: "Photos.jpg", type: .folder)
        #expect(FileIconRenderer.resolveUTType(for: folder) == .folder)
    }

    @Test("unresolved aliases short-circuit to UTType.aliasFile")
    func aliasShortCircuits() {
        let alias = RemoteFile(name: "shortcut", type: .unresolvedAlias)
        #expect(FileIconRenderer.resolveUTType(for: alias) == .aliasFile)
    }

    @Test("filename extension wins when present")
    func extensionTakesPriority() {
        let entry = RemoteFile(name: "report.pdf", type: "BINA", creator: "????")
        let resolved = FileIconRenderer.resolveUTType(for: entry)
        #expect(resolved?.conforms(to: .pdf) == true)
    }

    @Test("falls back to HFS type code when the extension is missing")
    func hfsTypeFallback() {
        // Classic-Mac TextEdit document with no extension, but the wire
        // carries the 'TEXT' type code Heidrun's uploader stamps.
        let entry = RemoteFile(name: "ReadMe", type: "TEXT", creator: "ttxt")
        let resolved = FileIconRenderer.resolveUTType(for: entry)
        #expect(resolved?.conforms(to: .text) == true)
    }

    @Test("returns nil when both extension and HFS type are unknown")
    func unknownEverywhereFallsThrough() {
        // No extension, generic Hotline sentinel '????' for the type —
        // nothing actionable, caller should use the SF Symbol fallback.
        let entry = RemoteFile(name: "blob", type: "????", creator: "????")
        #expect(FileIconRenderer.resolveUTType(for: entry) == nil)
    }

    @Test("an unknown extension still yields a (dynamic) UTI — macOS auto-mints one")
    func unknownExtensionYieldsDynamicUTI() {
        // `UTType(filenameExtension:)` mints a `dyn.xxx` UTI for any
        // extension it doesn't recognise instead of returning nil.
        // That's actually what we want: `NSWorkspace.icon(for:)` then
        // hands back the generic document icon. Documenting the
        // behaviour here so a future refactor doesn't break it on the
        // assumption that "unknown extension == nil".
        let entry = RemoteFile(
            name: "thing.zzznotreal",
            type: "????",
            creator: "????"
        )
        let resolved = FileIconRenderer.resolveUTType(for: entry)
        #expect(resolved != nil)
        #expect(resolved?.isDynamic == true)
    }

    @Test("returns nil when the name has no extension AND the HFS type is unknown")
    func noExtensionAndUnknownHFSFallsThrough() {
        // The genuine "fall through to SF Symbol" path: no extension to
        // mint a dynamic UTI from, and the wire type is the Hotline
        // `????` sentinel.
        let entry = RemoteFile(name: "blob", type: "????", creator: "????")
        #expect(FileIconRenderer.resolveUTType(for: entry) == nil)
    }
}
