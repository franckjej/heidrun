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
}
