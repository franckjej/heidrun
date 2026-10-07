import Foundation
import ImageIO
import HeidrunCore

/// In-memory Quick Look pipeline for `FilesViewModel`. Streams a
/// small file via the existing download side channel, caps the size,
/// decodes it as text or an image, and exposes the result through `previewState`.
extension FilesViewModel {
    /// Pull `entry` into memory and decode it for the Quick Look panel.
    /// Rejects folders, unsupported types, and anything larger than
    /// `maxPreviewBytes` before opening the side-channel transfer; the
    /// regular Download action remains the path for larger / binary files.
    public func previewFile(_ entry: RemoteFile) async {
        guard Self.isPreviewable(entry) else {
            previewState = .failed("\"\(entry.name)\" can't be previewed.")
            return
        }
        let byteLimit = Self.maxPreviewBytes(for: entry)
        guard UInt64(entry.size) <= byteLimit else {
            let limit = ByteCountFormatter.string(
                fromByteCount: Int64(byteLimit),
                countStyle: .file
            )
            previewState = .failed(
                "\"\(entry.name)\" is larger than the \(limit) preview limit — use Download instead."
            )
            return
        }

        cancelPreview()

        let path = currentPath
        previewState = .loading(fileName: entry.name, fraction: 0)
        previewTask = Task { [weak self] in
            await self?.runPreview(entry: entry, at: path)
        }
    }

    /// Cancel any in-flight preview transfer. Leaves `previewState`
    /// alone so the panel can keep showing the loading row briefly
    /// before the caller dismisses it via `dismissPreview()`.
    public func cancelPreview() {
        previewTask?.cancel()
        previewTask = nil
        if let handle = previewHandle {
            let cancelClosure = cancelTransferAt
            Task { _ = try? await cancelClosure(handle) }
        }
        previewHandle = nil
    }

    /// Clear the preview state. Called when the panel closes so a
    /// reopened panel doesn't flash the previous file's content.
    public func dismissPreview() {
        cancelPreview()
        previewState = .idle
    }

    private func runPreview(entry: RemoteFile, at path: RemotePath) async {
        let handle: TransferHandle
        do {
            handle = try await beginDownload(path, entry.name, 0)
        } catch {
            previewState = .failed(String(describing: error))
            return
        }
        previewHandle = handle

        let expectedTotal = max(UInt64(entry.size), 1)
        let byteLimit = Self.maxPreviewBytes(for: entry)
        var buffer = Data()
        buffer.reserveCapacity(min(Int(entry.size), Int(byteLimit)))

        do {
            for try await chunk in downloadBytes(handle) {
                if Task.isCancelled { return }
                buffer.append(chunk)
                if UInt64(buffer.count) > byteLimit {
                    let cancelClosure = cancelTransferAt
                    let abortedHandle = handle
                    Task { _ = try? await cancelClosure(abortedHandle) }
                    previewHandle = nil
                    previewState = .failed("Preview aborted — file exceeded the size limit.")
                    return
                }
                let fraction = min(1.0, Double(buffer.count) / Double(expectedTotal))
                previewState = .loading(fileName: entry.name, fraction: fraction)
            }
        } catch {
            previewHandle = nil
            if Task.isCancelled { return }
            previewState = .failed(String(describing: error))
            return
        }

        previewHandle = nil
        if Task.isCancelled { return }

        if Self.isPreviewableImage(entry) {
            guard Self.isDecodableImage(buffer) else {
                previewState = .failed("Couldn't decode \"\(entry.name)\" as an image.")
                return
            }
            previewState = .ready(PreviewPayload(fileName: entry.name, kind: .image(buffer)))
            return
        }

        guard let decoded = Self.decodeAsText(buffer) else {
            previewState = .failed("Couldn't decode \"\(entry.name)\" as text.")
            return
        }
        previewState = .ready(
            PreviewPayload(fileName: entry.name, kind: .text(decoded))
        )
    }

    /// True when ImageIO recognises the bytes and yields at least one frame.
    nonisolated static func isDecodableImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 0
    }

    /// Try a small ordered list of encodings; pick the first that round-trips
    /// without producing replacement characters. MacRoman comes after UTF-8
    /// because old Hotline trees still ship MacRoman-encoded text, and Latin-1
    /// is the last-resort fallback that always succeeds for any byte sequence.
    private static func decodeAsText(_ data: Data) -> String? {
        for encoding: String.Encoding in [.utf8, .macOSRoman, .isoLatin1] {
            if let result = String(data: data, encoding: encoding) {
                return result
            }
        }
        return nil
    }
}
