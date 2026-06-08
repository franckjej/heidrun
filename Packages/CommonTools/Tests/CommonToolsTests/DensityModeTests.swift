import Testing
import SwiftUI
@testable import CommonTools

@Suite struct DensityModeTests {
    @Test func namedModesMapToTheirPreset() {
        #expect(ContentSize.DensityMode.compact.resolvedPreset(systemRowSize: .large) == .compact)
        #expect(ContentSize.DensityMode.standard.resolvedPreset(systemRowSize: .small) == .standard)
        #expect(ContentSize.DensityMode.comfortable.resolvedPreset(systemRowSize: .small) == .comfortable)
    }

    @Test func systemModeFollowsSidebarRowSize() {
        #expect(ContentSize.DensityMode.system.resolvedPreset(systemRowSize: .small) == .compact)
        #expect(ContentSize.DensityMode.system.resolvedPreset(systemRowSize: .medium) == .standard)
        #expect(ContentSize.DensityMode.system.resolvedPreset(systemRowSize: .large) == .comfortable)
    }

    @Test func rawValuesMatchLegacyPresetRawValues() {
        #expect(ContentSize.DensityMode.compact.rawValue == ContentSize.Preset.compact.rawValue)
        #expect(ContentSize.DensityMode.standard.rawValue == ContentSize.Preset.standard.rawValue)
        #expect(ContentSize.DensityMode.comfortable.rawValue == ContentSize.Preset.comfortable.rawValue)
        #expect(ContentSize.DensityMode(rawValue: "system") == .system)
    }

    @Test func sizeModeIntegerMapsToSidebarRowSize() {
        #expect(ContentSize.DensityMode.sidebarRowSize(forSizeMode: 1) == .small)
        #expect(ContentSize.DensityMode.sidebarRowSize(forSizeMode: 2) == .medium)
        #expect(ContentSize.DensityMode.sidebarRowSize(forSizeMode: 3) == .large)
        // Unset (0) and any out-of-range value fall back to medium.
        #expect(ContentSize.DensityMode.sidebarRowSize(forSizeMode: 0) == .medium)
        #expect(ContentSize.DensityMode.sidebarRowSize(forSizeMode: 99) == .medium)
    }

    @Test func systemRowSizeReadsTheGlobalDefaultsKey() {
        let suiteName = "densityMode.systemRowSize"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        // NOTE: an explicit value in the suite is required — an *unset* key
        // falls through to the machine's live NSGlobalDomain value, so a
        // "default → medium" assertion would be non-deterministic here.

        defaults.set(1, forKey: ContentSize.DensityMode.systemSidebarSizeDefaultsKey)
        #expect(ContentSize.DensityMode.systemRowSize(from: defaults) == .small)

        defaults.set(3, forKey: ContentSize.DensityMode.systemSidebarSizeDefaultsKey)
        let rowSize = ContentSize.DensityMode.systemRowSize(from: defaults)
        #expect(rowSize == .large)
        // End-to-end: system mode resolves through the size read from defaults.
        #expect(ContentSize.DensityMode.system.resolvedPreset(systemRowSize: rowSize) == .comfortable)
    }
}
