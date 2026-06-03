import AppKit
import UniformTypeIdentifiers
import HeidrunCore

/// Picks a meaningful icon for a `RemoteFile` row in the file table.
///
/// Previous behaviour: every file row got the generic `doc` SF Symbol,
/// every folder got `folder`, both flat-tinted. The wire already carries
/// each entry's classic-Mac `(type, creator)` 4CC pair plus the filename,
/// so we can do better — render the real Finder icon the user expects.
///
/// Resolution order:
///   1. UTI from the filename extension (most reliable on modern macOS).
///   2. UTI from the wire's HFS type code (`UTType(tag:tagClass:.osType, …)`).
///      Picks up legacy uploads where the extension was stripped or never
///      existed but the classic type code (e.g. `TEXT`, `JPEG`, `APPL`)
///      survived round-tripping through Heidrun's upload envelope —
///      `HFSCodes.swift` stamps these on every upload.
///   3. SF Symbol fallback (`doc`) when neither lookup yields a UTI.
///
/// Folders and unresolved aliases short-circuit to the dedicated
/// `NSWorkspace` icons so they look right even when the wire's type is
/// the generic `fldr` / `alis`.
enum FileIconRenderer {
    /// Returns an icon sized to the file table's cell glyph (`displaySize`).
    /// `NSWorkspace.shared.icon(for:)` always returns a freshly-allocated
    /// `NSImage` we own, so it's safe to mutate `.size` in place.
    static func icon(for entry: RemoteFile, size: NSSize = displaySize) -> NSImage {
        let base = baseIcon(for: entry)
        base.size = size
        return base
    }

    /// Cell glyph size matched to the `imageView` constraint in
    /// `FileTableView.makeCell`. Bumped from 18 to 20 so the real Finder
    /// icons don't look crushed next to the row text.
    static let displaySize = NSSize(width: 20, height: 20)

    /// Pure UTI resolution — exposed for unit tests so they don't have to
    /// touch `NSWorkspace`. `nil` means "fall back to the SF Symbol".
    static func resolveUTType(for entry: RemoteFile) -> UTType? {
        if entry.isFolder { return .folder }
        if entry.isUnresolvedAlias { return .aliasFile }

        // 1) Filename extension.
        let pathExtension = (entry.name as NSString).pathExtension
        if !pathExtension.isEmpty,
           let viaExtension = UTType(filenameExtension: pathExtension) {
            return viaExtension
        }

        // 2) HFS type code from the wire. `????` (the Hotline "no specific
        //    type" sentinel) and a blank pad would both yield bogus UTIs,
        //    so skip them. The Swift overlay of `UTTagClass` doesn't
        //    expose a static for the classic-Mac OSType class on macOS,
        //    so build it from its canonical string identifier.
        let typeString = entry.type.stringValue
        let trimmed = typeString.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, trimmed != "????",
           let viaHFS = UTType(
            tag: typeString,
            tagClass: UTTagClass(rawValue: "com.apple.ostype"),
            conformingTo: nil
           ) {
            return viaHFS
        }
        return nil
    }

    // MARK: - Implementation

    private static func baseIcon(for entry: RemoteFile) -> NSImage {
        if let utType = resolveUTType(for: entry) {
            return NSWorkspace.shared.icon(for: utType)
        }
        return NSImage(
            systemSymbolName: "doc",
            accessibilityDescription: nil
        ) ?? NSImage()
    }
}
