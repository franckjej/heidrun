import AppKit
import Testing
@testable import HeidrunFiles

@Suite("PageSnapshot")
struct PageSnapshotTests {
    private func makeSnapshot(size: CGSize, appearance: NSAppearance.Name) throws -> PageSnapshot {
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
        return PageSnapshot(image: image, size: size, appearance: appearance)
    }

    @Test("fits a page of the same size and appearance")
    func fitsSameSizeAndAppearance() throws {
        let snapshot = try makeSnapshot(size: CGSize(width: 400, height: 300), appearance: .aqua)
        #expect(snapshot.fits(size: CGSize(width: 400, height: 300), appearance: .aqua))
    }

    @Test("doesn't fit after a resize")
    func rejectsOtherSize() throws {
        let snapshot = try makeSnapshot(size: CGSize(width: 400, height: 300), appearance: .aqua)
        #expect(!snapshot.fits(size: CGSize(width: 500, height: 300), appearance: .aqua))
    }

    @Test("doesn't fit after a light/dark switch")
    func rejectsOtherAppearance() throws {
        let snapshot = try makeSnapshot(size: CGSize(width: 400, height: 300), appearance: .darkAqua)
        #expect(!snapshot.fits(size: CGSize(width: 400, height: 300), appearance: .aqua))
    }
}
