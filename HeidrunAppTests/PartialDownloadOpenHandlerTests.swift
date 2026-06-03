import Darwin
import Foundation
import Testing
@testable import Heidrun
import HeidrunCore

@Suite("PartialDownloadOpenHandler")
struct PartialDownloadOpenHandlerTests {

    private func temporaryPartial(withXattr metadata: PartialDownloadMetadata?) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HeidrunOpenHandlerTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("foo.dmg.heidrunpart")
        try Data("partial".utf8).write(to: url)
        if let metadata {
            try PartialDownloadXattr.write(metadata, to: url)
        }
        return url
    }

    private func makeMetadata() -> PartialDownloadMetadata {
        PartialDownloadMetadata(
            serverAddress: "h.example.org",
            serverPort: 5500,
            serverLogin: "",
            serverName: "Example",
            remotePath: ["pub"],
            remoteFileName: "foo.dmg",
            totalSize: 1024
        )
    }

    @Test("well-formed partial yields a PartialResumeRequest")
    @MainActor
    func wellFormedYieldsResume() throws {
        let url = try temporaryPartial(withXattr: makeMetadata())
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let handler = PartialDownloadOpenHandler()
        let outcome = handler.handle(url: url)

        switch outcome {
        case .resume(let request):
            #expect(request.url == url)
            #expect(request.metadata.remoteFileName == "foo.dmg")
            #expect(request.bytesOnDisk == UInt64("partial".utf8.count))
        case .unreadable, .ignore:
            Issue.record("expected .resume")
        }
    }

    @Test("missing xattr yields .unreadable with a useful reason")
    @MainActor
    func missingXattrYieldsUnreadable() throws {
        let url = try temporaryPartial(withXattr: nil)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let handler = PartialDownloadOpenHandler()
        let outcome = handler.handle(url: url)

        switch outcome {
        case .unreadable(let value):
            #expect(value.url == url)
            #expect(value.reason.lowercased().contains("missing")
                 || value.reason.lowercased().contains("no resume info"))
        case .resume, .ignore:
            Issue.record("expected .unreadable")
        }
    }

    @Test("non-partial URLs are ignored")
    @MainActor
    func nonPartialIgnored() {
        let url = URL(fileURLWithPath: "/tmp/not-a-partial.txt")
        let handler = PartialDownloadOpenHandler()
        switch handler.handle(url: url) {
        case .ignore:
            break
        case .resume, .unreadable:
            Issue.record("expected .ignore")
        }
    }

    /// Writes `payload` directly to the `com.heidrun.resumeinfo` xattr,
    /// bypassing `PartialDownloadXattr.write` so we can fabricate
    /// non-JSON or schema-mismatched blobs that the production write
    /// path would reject.
    private func setResumeXattr(_ payload: Data, on url: URL) {
        let result = url.withUnsafeFileSystemRepresentation { (path: UnsafePointer<CChar>?) -> Int32 in
            payload.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Int32 in
                setxattr(path, "com.heidrun.resumeinfo", buffer.baseAddress, buffer.count, 0, 0)
            }
        }
        #expect(result == 0)
    }

    @Test("malformed JSON in xattr yields .unreadable with a 'malformed' reason")
    @MainActor
    func malformedJSONYieldsUnreadable() throws {
        let url = try temporaryPartial(withXattr: nil)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        setResumeXattr(Data("not json".utf8), on: url)

        let handler = PartialDownloadOpenHandler()
        let outcome = handler.handle(url: url)

        switch outcome {
        case .unreadable(let value):
            #expect(value.url == url)
            #expect(value.reason.lowercased().contains("malformed"))
        case .resume, .ignore:
            Issue.record("expected .unreadable")
        }
    }

    @Test("unsupported schema version yields .unreadable mentioning the version")
    @MainActor
    func unsupportedSchemaYieldsUnreadable() throws {
        let url = try temporaryPartial(withXattr: nil)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let bogus = PartialDownloadMetadata(
            schemaVersion: 999,
            serverAddress: "h.example.org",
            serverPort: 5500,
            serverLogin: "",
            serverName: "Example",
            remotePath: ["pub"],
            remoteFileName: "foo.dmg",
            totalSize: 1024
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = try encoder.encode(bogus)
        setResumeXattr(payload, on: url)

        let handler = PartialDownloadOpenHandler()
        let outcome = handler.handle(url: url)

        switch outcome {
        case .unreadable(let value):
            #expect(value.url == url)
            #expect(value.reason.lowercased().contains("unsupported schema version 999"))
        case .resume, .ignore:
            Issue.record("expected .unreadable")
        }
    }
}
