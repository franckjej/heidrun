import Foundation
import AppKit
import QuickLookThumbnailing

// MARK: - stdout helper
//
// CLI dev tool — write directly to stdout via FileHandle so output stays
// consistent with the fputs(..., stderr) pattern already used below for
// diagnostics, and so this file doesn't depend on the cpaLog helper that
// lives in the app proper.
func writeLine(_ message: String) {
    FileHandle.standardOutput.write(Data((message + "\n").utf8))
}

// MARK: - HeiIcon shim
//
// `defaulthl.HeidrunIcons` is an NSArchiver typedstream containing an
// `NSMutableArray` of `HeiIcon` instances. The legacy class encoded three
// fields via unkeyed NSCoding (see legacy/HeidrunModuleFramework/HeiIcon.m):
//
//   - decodeObject()                       → NSImage
//   - decodeObject()                       → NSString (label)
//   - decodeValueOfObjCType:int            → 32-bit iconID
//
// `NSUnarchiver` is deprecated but still functional in Foundation on
// macOS 26. It refuses to instantiate the array's elements unless a class
// named "HeiIcon" is reachable in the runtime — so we provide one here.

@objc(HeiIcon)
final class HeiIcon: NSObject, NSCoding {
    @objc var icon: NSImage?
    @objc var label: String = ""
    @objc var iconID: Int32 = 0

    override init() { super.init() }

    init?(coder: NSCoder) {
        super.init()
        self.icon = coder.decodeObject() as? NSImage
        self.label = (coder.decodeObject() as? String) ?? ""
        var rawID: Int32 = 0
        coder.decodeValue(ofObjCType: "i", at: &rawID)
        self.iconID = rawID
    }

    func encode(with coder: NSCoder) {
        coder.encode(icon)
        coder.encode(label)
        var rawID = iconID
        coder.encodeValue(ofObjCType: "i", at: &rawID)
    }
}

// MARK: - Manifest entry

struct IconManifestEntry: Codable {
    let id: Int
    let label: String
    let file: String
    let width: Int
    let height: Int
}

// MARK: - Conversion driver

func main() {
    let fileManager = FileManager.default
    let args = CommandLine.arguments

    // Default I/O: legacy file at repo's legacy/, output to HeidrunUI Resources.
    let cwd = fileManager.currentDirectoryPath
    let defaultInput = "\(cwd)/legacy/defaulthl.HeidrunIcons"
    let defaultOutput = "\(cwd)/Sources/HeidrunUI/Resources/Icons"

    let inputPath = args.count > 1 ? args[1] : defaultInput
    let outputDir = args.count > 2 ? args[2] : defaultOutput

    guard let data = try? Data(contentsOf: URL(fileURLWithPath: inputPath)) else {
        fputs("error: cannot read \(inputPath)\n", stderr)
        exit(1)
    }
    writeLine("Input:  \(inputPath) (\(data.count) bytes)")
    writeLine("Output: \(outputDir)")

    try? fileManager.createDirectory(
        atPath: outputDir,
        withIntermediateDirectories: true
    )

    // NSUnarchiver lookup via runtime — Swift can't import it directly because
    // it's marked unavailable, but the symbol is still in Foundation.
    guard let unarchiverClass = NSClassFromString("NSUnarchiver") as? NSObject.Type else {
        fputs("error: NSUnarchiver class is not present on this system\n", stderr)
        exit(2)
    }

    let unarchiveSel = Selector(("unarchiveObjectWithData:"))
    guard unarchiverClass.responds(to: unarchiveSel) else {
        fputs("error: NSUnarchiver doesn't respond to +unarchiveObjectWithData:\n", stderr)
        exit(2)
    }

    typealias UnarchiveFn = @convention(c) (AnyObject, Selector, NSData) -> AnyObject?
    let imp = unsafeBitCast(unarchiverClass.method(for: unarchiveSel), to: UnarchiveFn.self)
    let unarchivedRaw = imp(unarchiverClass, unarchiveSel, data as NSData)

    guard let array = unarchivedRaw as? NSArray else {
        fputs("error: top-level archive object isn't an array (got \(String(describing: unarchivedRaw)))\n", stderr)
        exit(3)
    }
    writeLine("Decoded array: \(array.count) entries")

    var manifest: [IconManifestEntry] = []
    var skipped = 0

    for (index, element) in array.enumerated() {
        guard let heiIcon = element as? HeiIcon else {
            fputs("warning: entry \(index) is not a HeiIcon (\(type(of: element)))\n", stderr)
            skipped += 1
            continue
        }

        let iconID = Int(heiIcon.iconID)
        // Labels in the legacy archive are stored Pascal-string style: the
        // first byte is the length of the rest. If that pattern holds, strip
        // it. Otherwise leave the label intact.
        let rawLabel = heiIcon.label
        let label: String = {
            guard let first = rawLabel.unicodeScalars.first,
                  first.value < 0x20,
                  Int(first.value) == rawLabel.unicodeScalars.count - 1
            else { return rawLabel }
            return String(rawLabel.dropFirst())
        }()

        guard let image = heiIcon.icon else {
            fputs("warning: icon \(iconID) (\(label.isEmpty ? "<unlabeled>" : label)) has no NSImage\n", stderr)
            skipped += 1
            continue
        }

        // The 2002 Heidrun icon package stores its NSImages as
        // NSPICTImageRep — Apple's deprecated QuickDraw PICT format.
        // Modern AppKit can no longer draw PICT directly: both
        // tiffRepresentation and cgImage(forProposedRect:context:hints:)
        // return empty results. However, Quick Look's thumbnailing
        // pipeline still understands PICT, so we round-trip the PICT
        // bytes through a temp file → QLThumbnailGenerator → CGImage.
        let reps = image.representations
        let bitmapRep = reps.compactMap({ $0 as? NSBitmapImageRep }).first
        let pictRep = reps.compactMap({ $0 as? NSPICTImageRep }).first

        var pngData: Data?
        var width = 0
        var height = 0

        // Path A: direct NSBitmapImageRep → PNG (fast path for non-PICT icons).
        if let bitmap = bitmapRep {
            width = bitmap.pixelsWide
            height = bitmap.pixelsHigh
            pngData = bitmap.representation(using: .png, properties: [:])
        }

        // Path B: PICT via Quick Look. Write to a temp file, ask QL for a
        // thumbnail, encode the resulting CGImage as PNG. This is the only
        // viable path on macOS 11+; AppKit's own PICT renderer is dead.
        if pngData == nil, let pictRep {
            let pictData = pictRep.pictRepresentation
            var withHeader = Data(count: 512)        // 512-byte PICT preamble
            withHeader.append(pictData)
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("heidrun-icon-\(iconID)-\(UUID().uuidString).pict")
            try? withHeader.write(to: tempURL)
            defer { try? fileManager.removeItem(at: tempURL) }

            // Sync wrapper around the async QL API; the bottleneck is the
            // PICT renderer, not the dispatch.
            let semaphore = DispatchSemaphore(value: 0)
            var resultCG: CGImage?
            let request = QLThumbnailGenerator.Request(
                fileAt: tempURL,
                size: CGSize(width: 16, height: 16),
                scale: 1.0,
                representationTypes: .thumbnail
            )
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
                resultCG = rep?.cgImage
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 5.0)

            if let cg = resultCG {
                width = cg.width
                height = cg.height
                let bmp = NSBitmapImageRep(cgImage: cg)
                pngData = bmp.representation(using: .png, properties: [:])
            }
        }

        guard let pngData else {
            fputs("warning: icon \(iconID) (\(label.isEmpty ? "<unlabeled>" : label)) could not be encoded to PNG\n", stderr)
            skipped += 1
            continue
        }

        let fileName = "icon-\(iconID).png"
        let outURL = URL(fileURLWithPath: outputDir).appendingPathComponent(fileName)
        do {
            try pngData.write(to: outURL)
        } catch {
            fputs("warning: write failed for \(outURL.path): \(error)\n", stderr)
            skipped += 1
            continue
        }

        manifest.append(IconManifestEntry(
            id: iconID,
            label: label,
            file: fileName,
            width: width,
            height: height
        ))
    }

    // Sort the manifest by iconID for deterministic output.
    manifest.sort { $0.id < $1.id }

    let manifestURL = URL(fileURLWithPath: outputDir).appendingPathComponent("icons.json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
        let json = try encoder.encode(manifest)
        try json.write(to: manifestURL)
    } catch {
        fputs("error: writing manifest failed: \(error)\n", stderr)
        exit(4)
    }

    writeLine("Wrote \(manifest.count) icons, \(skipped) skipped")
    writeLine("Manifest: \(manifestURL.path)")
}

main()
