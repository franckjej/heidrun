import Foundation
import Testing
@testable import HeidrunUI
#if canImport(AppKit)
import AppKit
#endif

@MainActor
@Suite("IconCatalog")
struct IconCatalogTests {
    // MARK: - Icons (16x16)

    @Test("icons set is populated from the bundled manifest")
    func iconsSetIsPopulated() {
        let entries = IconCatalog.shared.icons.allEntries
        #expect(entries.count > 100, "expected many bundled icons, got \(entries.count)")
    }

    @Test("icons set entries are sorted by id")
    func iconsAreSortedByID() {
        let ids = IconCatalog.shared.icons.allEntries.map(\.id)
        #expect(ids == ids.sorted())
    }

    @Test("icons set entries are well-formed")
    func iconsAreWellFormed() {
        for entry in IconCatalog.shared.icons.allEntries.prefix(20) {
            #expect(!entry.file.isEmpty)
            #expect(entry.width > 0)
            #expect(entry.height > 0)
        }
    }

    @Test("a known iconID resolves to a label in the icons set")
    func knownIconHasLabel() {
        let label = IconCatalog.shared.icons.label(forID: 128)
        #expect(label != nil)
        #expect(label?.isEmpty == false)
    }

    #if canImport(AppKit)
    @Test("icons.image(forID:) loads NSImage data for a known entry")
    func iconImageLoadsForKnownEntry() {
        guard let firstEntry = IconCatalog.shared.icons.allEntries.first else {
            Issue.record("icons set has no entries")
            return
        }
        #expect(IconCatalog.shared.icons.image(forID: firstEntry.id) != nil)
    }

    @Test("icons.image(forID:) returns nil for an unknown id")
    func iconImageNilForUnknownID() {
        #expect(IconCatalog.shared.icons.image(forID: -99999) == nil)
    }
    #endif

    // MARK: - Banners (16x1)

    @Test("banners set is populated from BM-icon-*.png resources, independent of icon manifest")
    func bannersSetIsPopulated() {
        // BM and icon IDs share no namespace — the BMIcons/ folder ships
        // its own set of files independent of icons.json. We expect a
        // healthy population (~hundreds), not the tiny intersection.
        let bannerCount = IconCatalog.shared.banners.allEntries.count
        #expect(bannerCount > 100, "expected many banners, got \(bannerCount)")
    }

    @Test("banners.entry(forID:) reports 16x1 fixed dimensions")
    func bannerEntryReportsFixedDimensions() {
        guard let firstBanner = IconCatalog.shared.banners.allEntries.first else {
            Issue.record("banner set is empty")
            return
        }
        let entry = IconCatalog.shared.banners.entry(forID: firstBanner.id)
        #expect(entry?.width == 16)
        #expect(entry?.height == 1)
    }

    @Test("banners.cgImage(forID:) returns a 16x1 image for a known banner")
    func bannerImageHasExpectedDimensions() {
        guard let firstBanner = IconCatalog.shared.banners.allEntries.first else {
            Issue.record("banner set is empty")
            return
        }
        let image = IconCatalog.shared.banners.cgImage(forID: firstBanner.id)
        #expect(image != nil)
        #expect(image?.width == 16)
        #expect(image?.height == 1)
    }

    @Test("banners.cgImage(forID:) returns nil for an unknown id")
    func bannerImageNilForUnknownID() {
        #expect(IconCatalog.shared.banners.cgImage(forID: -99999) == nil)
    }
}
