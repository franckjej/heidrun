import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

/// Read-only metadata for one icon, decoded once at startup from
/// `icons.json` produced by `HeidrunIconConverter`.
public struct IconCatalogEntry: Codable, Hashable, Sendable {
    public let id: Int
    public let label: String
    public let file: String
    public let width: Int
    public let height: Int
}

/// One catalog of bundled icon assets, addressed by numeric ID.
///
/// Heidrun ships two sets: the standard 16x16 user icons under
/// `Resources/Icons/`, and the matching 16x1 horizontal banner stripes
/// under `Resources/BMIcons/` (legacy "background icons"). Both share
/// the same `icons.json` manifest for IDs and labels; the banner set
/// resolves files by prepending `BM-` to the manifest's filename and
/// returns its own fixed `width`/`height`.
@MainActor
public final class IconSet {
    public let name: String

    let entriesByID: [Int: IconCatalogEntry]

    private let resolveURL: (IconCatalogEntry) -> URL?

    /// Fixed dimensions exposed to consumers — overrides the manifest's
    /// width/height when set (banner set ships 16x1 even though the
    /// manifest's icon-N entry says 16x16).
    private let fixedDimensions: (width: Int, height: Int)?

    private var cgImageCache: [Int: CGImage] = [:]
    #if canImport(AppKit)
    private var nsImageCache: [Int: NSImage] = [:]
    #endif
    private var loggedMissingIDs: Set<Int> = []

    init(
        name: String,
        entriesByID: [Int: IconCatalogEntry],
        fixedDimensions: (width: Int, height: Int)?,
        resolveURL: @escaping (IconCatalogEntry) -> URL?
    ) {
        self.name = name
        self.entriesByID = entriesByID
        self.fixedDimensions = fixedDimensions
        self.resolveURL = resolveURL
    }

    public var allEntries: [IconCatalogEntry] {
        entriesByID.values.sorted(by: { $0.id < $1.id })
    }

    public func label(forID id: Int) -> String? {
        entriesByID[id]?.label
    }

    public func entry(forID id: Int) -> IconCatalogEntry? {
        guard let entry = entriesByID[id] else { return nil }
        if let dimensions = fixedDimensions {
            return IconCatalogEntry(
                id: entry.id,
                label: entry.label,
                file: entry.file,
                width: dimensions.width,
                height: dimensions.height
            )
        }
        return entry
    }

    public func cgImage(forID id: Int) -> CGImage? {
        if let cached = cgImageCache[id] { return cached }
        guard let entry = entriesByID[id] else {
            return nil
        }
        guard let url = resolveURL(entry) else {
            return nil
        }
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }
        cgImageCache[id] = image
        return image
    }

    #if canImport(AppKit)
    public func image(forID id: Int) -> NSImage? {
        if let cached = nsImageCache[id] { return cached }
        guard let entry = entriesByID[id] else {
            return nil
        }
        guard let url = resolveURL(entry) else {
            return nil
        }
        guard let image = NSImage(contentsOf: url) else {
            return nil
        }
        let pixelWidth = fixedDimensions?.width ?? entry.width
        let pixelHeight = fixedDimensions?.height ?? entry.height
        image.size = NSSize(width: pixelWidth, height: pixelHeight)
        nsImageCache[id] = image
        return image
    }
    #endif
}

@MainActor
public final class IconCatalog {
    public static let shared = IconCatalog()

    public let icons: IconSet
    public let banners: IconSet

    private init() {
        let bundle = Bundle.module
        let manifestURL = bundle.url(forResource: "icons", withExtension: "json", subdirectory: "Icons")
            ?? bundle.url(forResource: "icons", withExtension: "json")

        let entries: [IconCatalogEntry]
        if
            let manifestURL,
            let data = try? Data(contentsOf: manifestURL),
            let decoded = try? JSONDecoder().decode([IconCatalogEntry].self, from: data) {
            entries = decoded
        } else {
            entries = []
        }

        let entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })

        self.icons = IconSet(
            name: "icons",
            entriesByID: entriesByID,
            fixedDimensions: nil,
            resolveURL: { entry in
                Self.bundleURL(forFile: entry.file)
            }
        )

        // Banner set is enumerated DIRECTLY from `BM-icon-*.png` resources
        // in the bundle — the BM and icon ID namespaces are independent
        // (only 11 of 791 BM files share IDs with the icon manifest), so
        // deriving from icons.json would expose only that 11-banner sliver.
        // Labels fall back to "Banner #N" when no icon manifest entry
        // exists for the matching ID.
        let bannerEntries: [(Int, IconCatalogEntry)] = Self.bannerFiles().compactMap { fileName in
            guard let bannerID = Self.bannerID(fromFileName: fileName) else { return nil }
            let label = entriesByID[bannerID]?.label ?? "Banner #\(bannerID)"
            let entry = IconCatalogEntry(
                id: bannerID,
                label: label,
                file: fileName,
                width: 16,
                height: 1
            )
            return (bannerID, entry)
        }
        self.banners = IconSet(
            name: "banners",
            entriesByID: Dictionary(uniqueKeysWithValues: bannerEntries),
            fixedDimensions: (width: 16, height: 1),
            resolveURL: { entry in
                Self.bundleURL(forFile: entry.file)
            }
        )
    }

    /// Discover every `BM-icon-*.png` resource bundled with HeidrunUI.
    /// SwiftPM's `.process` flattens the `BMIcons/` subdirectory, so the
    /// files sit at the bundle root next to `icon-*.png`.
    private static func bannerFiles() -> [String] {
        guard let resourceURL = Bundle.module.resourceURL else { return [] }
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: resourceURL.path)) ?? []
        return contents.filter { $0.hasPrefix("BM-icon-") && $0.hasSuffix(".png") }
    }

    /// Parse `123` out of `"BM-icon-123.png"`.
    private static func bannerID(fromFileName fileName: String) -> Int? {
        var name = fileName
        if name.hasPrefix("BM-icon-") { name.removeFirst("BM-icon-".count) }
        if name.hasSuffix(".png") { name.removeLast(".png".count) }
        return Int(name)
    }

    private static func bundleURL(forFile file: String) -> URL? {
        let bundle = Bundle.module
        let pieces = file.split(separator: ".", omittingEmptySubsequences: false)
        let base = pieces.dropLast().joined(separator: ".")
        let ext = pieces.last.map(String.init) ?? ""
        return bundle.url(forResource: base, withExtension: ext)
        ?? bundle.url(forResource: file, withExtension: nil)
    }
}
