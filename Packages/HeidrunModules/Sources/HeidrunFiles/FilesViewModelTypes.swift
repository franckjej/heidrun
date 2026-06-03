import Foundation
import HeidrunCore

extension FilesViewModel {
    public enum TransferStatus: Sendable, Equatable {
        case running
        case completed
        case failed(String)
    }

    /// `resume` only fires for downloads — uploads can't resume from a
    /// partial local file without an explicit user action.
    public enum TransferDirection: Sendable, Hashable {
        case download
        case upload
    }

    /// Kept on the transfer state so the TaskManager can compute a
    /// rolling speed.
    public struct TransferSample: Sendable, Hashable {
        public let at: Date
        public let bytes: UInt64

        public init(at: Date, bytes: UInt64) {
            self.at = at
            self.bytes = bytes
        }
    }

    public struct TransferState: Identifiable, Sendable, Equatable {
        public let handle: TransferHandle
        public let displayName: String
        public let destination: URL?
        public let direction: TransferDirection
        /// Needed for resume — `FilesViewModel.currentPath` may have
        /// moved on by the time the user retries.
        public let sourcePath: RemotePath
        /// Carried for downloads so resume can re-issue with the same
        /// size/type info. `nil` for uploads.
        public let sourceFile: RemoteFile?
        public var bytesWritten: UInt64
        public var status: TransferStatus
        /// Last 8 samples — slope smooths short jitter without lagging.
        public var samples: [TransferSample]

        public init(
            handle: TransferHandle,
            displayName: String,
            destination: URL?,
            direction: TransferDirection,
            sourcePath: RemotePath,
            sourceFile: RemoteFile? = nil,
            bytesWritten: UInt64,
            status: TransferStatus,
            samples: [TransferSample] = []
        ) {
            self.handle = handle
            self.displayName = displayName
            self.destination = destination
            self.direction = direction
            self.sourcePath = sourcePath
            self.sourceFile = sourceFile
            self.bytesWritten = bytesWritten
            self.status = status
            self.samples = samples
        }

        public var id: UInt32 { handle.transferID }

        /// Downloads: use the original file size, NOT `handle.totalSize`
        /// (the server reports bytes-to-send = full minus resume offset).
        /// Uploads: `handle.totalSize` is correct — full size from start.
        public var totalSize: UInt64 {
            if direction == .download, let sourceFile {
                return UInt64(sourceFile.size)
            }
            return handle.totalSize
        }

        public var fraction: Double {
            guard totalSize > 0 else { return 0 }
            return min(1.0, Double(bytesWritten) / Double(totalSize))
        }

        /// Zero until two samples span a positive interval, so a
        /// freshly-started transfer doesn't flash a bogus rate.
        public var speedBytesPerSec: Double {
            guard let first = samples.first,
                  let last = samples.last,
                  last.at > first.at else { return 0 }
            let elapsed = last.at.timeIntervalSince(first.at)
            let deltaBytes = Double(last.bytes &- first.bytes)
            return max(0, deltaBytes / elapsed)
        }

        /// Append a sample, capping the buffer so old data doesn't drag
        /// the speed estimate down.
        public mutating func recordSample(bytes: UInt64, at: Date = Date()) {
            samples.append(TransferSample(at: at, bytes: bytes))
            if samples.count > 8 {
                samples.removeFirst(samples.count - 8)
            }
        }
    }

    // MARK: - Quick Look preview

    /// Phase 1 carries text only; PDF / image / AV variants slot in
    /// here without changing call sites that switch on `kind`.
    public enum PreviewKind: Sendable, Equatable {
        case text(String)
    }

    /// Decoded contents of a file pulled into memory for preview.
    public struct PreviewPayload: Sendable, Equatable {
        public let fileName: String
        public let kind: PreviewKind

        public init(fileName: String, kind: PreviewKind) {
            self.fileName = fileName
            self.kind = kind
        }
    }

    public enum PreviewState: Sendable, Equatable {
        case idle
        case loading(fileName: String, fraction: Double)
        case ready(PreviewPayload)
        case failed(String)

        public var fileName: String? {
            switch self {
            case .idle, .failed:
                return nil
            case .loading(let name, _):
                return name
            case .ready(let payload):
                return payload.fileName
            }
        }
    }
}
