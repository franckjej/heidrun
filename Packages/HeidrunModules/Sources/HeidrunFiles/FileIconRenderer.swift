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
        if entry.isFolder {
            switch FolderRole(name: entry.name) {
            case .dropBox: return dropBoxFolderIcon()
            case .upload: return uploadFolderIcon()
            case .normal: break
            }
        }
        if let utType = resolveUTType(for: entry) {
            return NSWorkspace.shared.icon(for: utType)
        }
        return NSImage(
            systemSymbolName: "doc",
            accessibilityDescription: nil
        ) ?? NSImage()
    }

    // MARK: - Folder roles

    /// Finder's own drop-folder icon (the one on ~/Public/Drop Box).
    /// Falls back to the plain folder icon if the legacy lookup vanishes.
    private static func dropBoxFolderIcon() -> NSImage {
        legacySystemIcon(hfsType: kDropFolderIcon) ?? NSWorkspace.shared.icon(for: .folder)
    }

    /// Plain Finder folder with a white up-arrow badge, placed where the
    /// drop-folder icon carries its down-arrow so the pair reads as siblings.
    private static func uploadFolderIcon() -> NSImage {
        let base = NSWorkspace.shared.icon(for: .folder)
        let canvas = NSSize(width: 128, height: 128)
        return NSImage(size: canvas, flipped: false) { rect in
            base.draw(in: rect)
            let badgeSide = rect.width * 0.34
            let badgeRect = NSRect(
                x: rect.midX - badgeSide / 2,
                y: rect.midY - badgeSide / 2 - rect.height * 0.06,
                width: badgeSide,
                height: badgeSide
            )
            // Translucent like the system drop-folder badge, not a hard white ring.
            let configuration = NSImage.SymbolConfiguration(pointSize: badgeSide, weight: .regular)
                .applying(.init(paletteColors: [NSColor.white.withAlphaComponent(0.65)]))
            if let arrow = NSImage(systemSymbolName: "arrow.up.circle", accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration) {
                arrow.draw(in: badgeRect)
            }
            return true
        }
    }

    /// `-[NSWorkspace iconForFileType:]` for a classic HFS icon code.
    /// Deprecated API reached via the selector so the compiler stays quiet.
    private static func legacySystemIcon(hfsType code: Int) -> NSImage? {
        let selector = NSSelectorFromString("iconForFileType:")
        let workspace = NSWorkspace.shared
        guard workspace.responds(to: selector) else { return nil }
        let typeString = NSFileTypeForHFSTypeCode(OSType(code))
        return workspace.perform(selector, with: typeString)?.takeUnretainedValue() as? NSImage
    }
}
