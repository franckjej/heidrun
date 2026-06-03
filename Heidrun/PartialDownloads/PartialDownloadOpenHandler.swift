import Foundation
import HeidrunCore

/// Inbound file-open request from Finder. The host wires this into
/// `HostState.pendingResume` (or `.pendingUnreadablePartial`) so the
/// resume sheet pops over whatever phase is currently showing.
struct PartialResumeRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let url: URL
    let metadata: PartialDownloadMetadata
    let bytesOnDisk: UInt64
}

/// Surfaces a `.heidrunpart` Heidrun couldn't fully parse — file
/// is still on disk but missing or malformed resume metadata.
struct PartialDownloadUnreadable: Identifiable, Equatable, Sendable {
    let id: UUID
    let url: URL
    let reason: String
}

/// Outcome of `PartialDownloadOpenHandler.handle(url:)`. The host
/// branches on this to decide which (if any) sheet to present.
enum PartialDownloadOpenOutcome: Sendable {
    case resume(PartialResumeRequest)
    case unreadable(PartialDownloadUnreadable)
    case ignore
}

@MainActor
final class PartialDownloadOpenHandler {

    func handle(url: URL) -> PartialDownloadOpenOutcome {
        guard PartialDownloadURL.isPartial(url) else { return .ignore }

        let bytesOnDisk: UInt64
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            bytesOnDisk = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        } catch {
            return .unreadable(.init(
                id: UUID(),
                url: url,
                reason: "Heidrun couldn't read the partial download (\(error.localizedDescription))."
            ))
        }

        do {
            let metadata = try PartialDownloadXattr.read(from: url)
            return .resume(.init(
                id: UUID(),
                url: url,
                metadata: metadata,
                bytesOnDisk: bytesOnDisk
            ))
        } catch PartialDownloadMetadataError.xattrMissing {
            return .unreadable(.init(
                id: UUID(),
                url: url,
                reason: "Resume info missing on this download. It can still be revealed in Finder."
            ))
        } catch PartialDownloadMetadataError.malformedJSON {
            return .unreadable(.init(
                id: UUID(),
                url: url,
                reason: "Resume info on this download is malformed."
            ))
        } catch PartialDownloadMetadataError.unsupportedSchema(let version) {
            return .unreadable(.init(
                id: UUID(),
                url: url,
                reason: "Resume info uses unsupported schema version \(version)."
            ))
        } catch PartialDownloadMetadataError.xattrUnreadable(let message) {
            return .unreadable(.init(
                id: UUID(),
                url: url,
                reason: "Resume info couldn't be read (\(message))."
            ))
        } catch {
            return .unreadable(.init(
                id: UUID(),
                url: url,
                reason: "Resume info couldn't be read (\(error.localizedDescription))."
            ))
        }
    }
}
