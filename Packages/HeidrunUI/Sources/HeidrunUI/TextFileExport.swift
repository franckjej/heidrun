import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Generic drag payload for exporting text out of Heidrun to anywhere:
/// plain text (`String`) for editors / Mail / a Finder text clipping, and
/// a `.txt` file for the Desktop / Finder. Shared by chat transcripts,
/// user info, etc.
public struct TextFileExport: Transferable {
    /// File-name base (no extension) used for the exported `.txt`.
    public let fileName: String
    public let text: String

    public init(fileName: String, text: String) {
        self.fileName = fileName
        self.text = text
    }

    public static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.text)
        FileRepresentation(exportedContentType: .plainText) { export in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(TextFileExport.sanitize(export.fileName))
                .appendingPathExtension("txt")
            try export.text.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }

    /// Build a SYNCHRONOUS drag source for text: a plain-text data rep
    /// (editors / a Finder text clipping) plus a `.txt` file rep, both
    /// filled immediately. AppKit `.onDrag { ... }` returns this; it
    /// initiates reliably inside Lists/Tables where SwiftUI `.draggable`
    /// gets swallowed, and has no async promise to stall a Finder drop.
    public static func makeItemProvider(fileName: String, text: String) -> NSItemProvider {
        let base = sanitize(fileName)
        let provider = NSItemProvider()
        provider.suggestedName = base
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.utf8PlainText.identifier,
            visibility: .all
        ) { completion in
            completion(Data(text.utf8), nil)
            return nil
        }
        provider.registerFileRepresentation(
            forTypeIdentifier: UTType.plainText.identifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            do {
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(base)
                    .appendingPathExtension("txt")
                try text.write(to: url, atomically: true, encoding: .utf8)
                completion(url, false, nil)
            } catch {
                completion(nil, false, error)
            }
            return nil
        }
        return provider
    }

    /// Replace path-hostile characters so the name is a valid filename.
    public static func sanitize(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalid = CharacterSet(charactersIn: "/:\\")
        let cleaned = trimmed.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.isEmpty ? "Export" : cleaned
    }
}
