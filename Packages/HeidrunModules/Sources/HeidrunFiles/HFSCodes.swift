import Foundation
import HeidrunCore

/// Static map from a file extension to the classic-Mac `(type, creator)`
/// FourCharCode pair clients used to carry on each Hotline upload's FILP
/// envelope. Modern macOS doesn't store HFS type/creator on the filesystem
/// any more, so without this table every upload from Heidrun would land
/// on the server with the generic `.file` / `.unknown` defaults — which
/// is exactly what was producing `????` / `....` in Get Info before this
/// existed (see HeidrunCore's `FourCharCode.file` / `.unknown`).
///
/// The mappings track the conventions the original Mac OS classic
/// applications used (so files visible on a real Hotline 1.x server keep
/// looking sensible there): `TEXT/ttxt` for plain text, `JPEG/8BIM` for
/// JPEG, etc. Unknown extensions fall back to `BINA/????` — the same
/// generic "binary" pair MacBinary writers shipped with.
public enum HFSCodes {
    /// Pair of HFS codes to stamp on an upload. Qualified to
    /// `HeidrunCore.FourCharCode` because the bare name also resolves
    /// to the CoreFoundation `UInt32` typealias from MacTypes.h.
    public struct Pair: Equatable, Sendable {
        public let type: HeidrunCore.FourCharCode
        public let creator: HeidrunCore.FourCharCode

        public init(type: HeidrunCore.FourCharCode, creator: HeidrunCore.FourCharCode) {
            self.type = type
            self.creator = creator
        }
    }

    /// Catch-all when the extension isn't in the table or the URL has
    /// none. `BINA` is what classic MacBinary writers used for "opaque
    /// blob"; `????` is the Hotline "no specific creator" sentinel.
    public static let unknown = Pair(type: "BINA", creator: "????")

    /// Resolve a file URL to its `(type, creator)` pair. Prefers the
    /// file's real `com.apple.FinderInfo` xattr — where Classic Mac
    /// files persist their type + creator codes across APFS/HFS+ —
    /// and only falls back to the extension table when no usable
    /// FinderInfo is present.
    ///
    /// "Usable" means: xattr exists, is at least 8 bytes, AND the
    /// type/creator pair isn't all zeros. Modern macOS frequently
    /// leaves a 32-byte all-zero FinderInfo on files that came in
    /// through download/copy paths — that's the same signal as "no
    /// info set" and stamping `\0\0\0\0/\0\0\0\0` on the upload would
    /// be strictly worse than the extension guess.
    public static func resolve(fileURL: URL) -> Pair {
        if let stored = readFinderInfo(at: fileURL) {
            return stored
        }
        return resolve(extension: fileURL.pathExtension)
    }

    /// Read the type + creator pair (first 8 bytes) of the file's
    /// `com.apple.FinderInfo` xattr. Returns `nil` when the xattr is
    /// missing, shorter than 8 bytes, or carries an all-zero pair.
    ///
    /// We allocate the full 32 bytes the xattr is documented to carry:
    /// macOS `getxattr` fails with `ERANGE` when the destination
    /// buffer is smaller than the stored attribute, so an 8-byte
    /// buffer would silently fall through to the extension table even
    /// on files with real codes.
    private static func readFinderInfo(at url: URL) -> Pair? {
        let attribute = "com.apple.FinderInfo"
        var buffer = [UInt8](repeating: 0, count: 32)
        let read = url.path.withCString { path in
            attribute.withCString { attributeName in
                getxattr(path, attributeName, &buffer, buffer.count, 0, 0)
            }
        }
        guard read >= 8, buffer.prefix(8).contains(where: { $0 != 0 }) else { return nil }
        return Pair(
            type: HeidrunCore.FourCharCode(buffer[0], buffer[1], buffer[2], buffer[3]),
            creator: HeidrunCore.FourCharCode(buffer[4], buffer[5], buffer[6], buffer[7])
        )
    }

    /// Resolve a bare extension (without the leading dot, but tolerant
    /// of one). Empty → `unknown`.
    public static func resolve(extension rawExtension: String) -> Pair {
        let key = rawExtension
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !key.isEmpty else { return unknown }
        return table[key] ?? unknown
    }

    /// Curated table. Kept lowercase. The pairings mirror what classic
    /// Mac OS apps wrote: SimpleText/TextEdit for text, Photoshop's
    /// `8BIM` creator for the common bitmaps, QuickTime Player's `TVOD`
    /// for movies, Disk Copy / Disk Utility's `ddsk` for disk images.
    /// Add new rows here when a real extension surfaces in the wild —
    /// no need to chase every long-tail format; the `unknown` fallback
    /// is what classic clients would have shown anyway.
    private static let table: [String: Pair] = [
        // --- Text ---
        "txt": Pair(type: "TEXT", creator: "ttxt"),
        "text": Pair(type: "TEXT", creator: "ttxt"),
        "rtf": Pair(type: "RTF ", creator: "ttxt"),
        "html": Pair(type: "TEXT", creator: "MOSS"),
        "htm": Pair(type: "TEXT", creator: "MOSS"),
        "md": Pair(type: "TEXT", creator: "ttxt"),
        "csv": Pair(type: "TEXT", creator: "ttxt"),
        "json": Pair(type: "TEXT", creator: "ttxt"),
        "xml": Pair(type: "TEXT", creator: "ttxt"),
        "log": Pair(type: "TEXT", creator: "ttxt"),
        "swift": Pair(type: "TEXT", creator: "ttxt"),
        "c": Pair(type: "TEXT", creator: "ttxt"),
        "h": Pair(type: "TEXT", creator: "ttxt"),
        "m": Pair(type: "TEXT", creator: "ttxt"),
        "mm": Pair(type: "TEXT", creator: "ttxt"),

        // --- Documents ---
        "pdf": Pair(type: "PDF ", creator: "CARO"),
        "doc": Pair(type: "WDBN", creator: "MSWD"),
        "docx": Pair(type: "WDBN", creator: "MSWD"),
        "xls": Pair(type: "XLS ", creator: "XCEL"),
        "xlsx": Pair(type: "XLS ", creator: "XCEL"),
        "ppt": Pair(type: "SLD ", creator: "PPT3"),
        "pptx": Pair(type: "SLD ", creator: "PPT3"),

        // --- Images ---
        "jpg": Pair(type: "JPEG", creator: "8BIM"),
        "jpeg": Pair(type: "JPEG", creator: "8BIM"),
        "png": Pair(type: "PNGf", creator: "8BIM"),
        "gif": Pair(type: "GIFf", creator: "8BIM"),
        "tif": Pair(type: "TIFF", creator: "8BIM"),
        "tiff": Pair(type: "TIFF", creator: "8BIM"),
        "bmp": Pair(type: "BMP ", creator: "8BIM"),
        "psd": Pair(type: "8BPS", creator: "8BIM"),
        "heic": Pair(type: "heic", creator: "????"),

        // --- Audio / Video ---
        "mov": Pair(type: "MooV", creator: "TVOD"),
        "mp4": Pair(type: "mp4 ", creator: "TVOD"),
        "m4v": Pair(type: "M4V ", creator: "TVOD"),
        "m4a": Pair(type: "M4A ", creator: "TVOD"),
        "mp3": Pair(type: "MPG3", creator: "TVOD"),
        "wav": Pair(type: "WAVE", creator: "TVOD"),
        "aif": Pair(type: "AIFF", creator: "TVOD"),
        "aiff": Pair(type: "AIFF", creator: "TVOD"),
        "flac": Pair(type: "flac", creator: "TVOD"),
        "avi": Pair(type: "VfW ", creator: "TVOD"),

        // --- Archives ---
        "zip": Pair(type: "ZIP ", creator: "SITx"),
        "sit": Pair(type: "SIT!", creator: "SIT!"),
        "sitx": Pair(type: "SITx", creator: "SITx"),
        "hqx": Pair(type: "TEXT", creator: "SITx"),
        "tar": Pair(type: "TARF", creator: "SITx"),
        "gz": Pair(type: "Gzip", creator: "SITx"),
        "tgz": Pair(type: "TARF", creator: "SITx"),
        "bz2": Pair(type: "BZp2", creator: "SITx"),

        // --- Disk images / installers ---
        "dmg": Pair(type: "udif", creator: "ddsk"),
        "iso": Pair(type: "ISO ", creator: "ddsk"),
        "img": Pair(type: "IMG ", creator: "ddsk"),
        "pkg": Pair(type: "pkg ", creator: "ddsk"),
        "mpkg": Pair(type: "mpkg", creator: "ddsk"),

        // --- macOS apps ---
        "app": Pair(type: "APPL", creator: "????")
    ]
}
