import AppKit
import Testing
import CommonTools
@testable import HeidrunFiles

@Suite("PageSnapshot")
struct PageSnapshotTests {
    private let standard = ContentSize(preset: .standard)

    private func makeSnapshot(
        size: CGSize,
        appearance: NSAppearance.Name,
        contentSize: ContentSize = ContentSize(preset: .standard)
    ) throws -> PageSnapshot {
        let context = try #require(CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try #require(context.makeImage())
        return PageSnapshot(image: image, size: size, appearance: appearance, contentSize: contentSize)
    }

    @Test("fits a page of the same size and appearance")
    func fitsSameSizeAndAppearance() throws {
        let snapshot = try makeSnapshot(size: CGSize(width: 400, height: 300), appearance: .aqua)
        #expect(snapshot.fits(size: CGSize(width: 400, height: 300), appearance: .aqua, contentSize: standard))
    }

    @Test("doesn't fit after a resize")
    func rejectsOtherSize() throws {
        let snapshot = try makeSnapshot(size: CGSize(width: 400, height: 300), appearance: .aqua)
        #expect(!snapshot.fits(size: CGSize(width: 500, height: 300), appearance: .aqua, contentSize: standard))
    }

    @Test("doesn't fit after a light/dark switch")
    func rejectsOtherAppearance() throws {
        let snapshot = try makeSnapshot(size: CGSize(width: 400, height: 300), appearance: .darkAqua)
        #expect(!snapshot.fits(size: CGSize(width: 400, height: 300), appearance: .aqua, contentSize: standard))
    }

    @Test("doesn't fit after a content density or text size change")
    func rejectsOtherContentSize() throws {
        let snapshot = try makeSnapshot(size: CGSize(width: 400, height: 300), appearance: .aqua)
        let size = CGSize(width: 400, height: 300)
        #expect(!snapshot.fits(size: size, appearance: .aqua, contentSize: ContentSize(preset: .comfortable)))
        #expect(!snapshot.fits(size: size, appearance: .aqua, contentSize: ContentSize(preset: .standard, bodyPointSize: 9)))
    }
}
