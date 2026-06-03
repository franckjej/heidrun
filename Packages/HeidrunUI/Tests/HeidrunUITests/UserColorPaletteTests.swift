import Testing
import SwiftUI
@testable import HeidrunUI

@Suite("UserColorPalette")
struct UserColorPaletteTests {
    @Test("palette ID 0 is unset and returns nil")
    func zeroIsNil() {
        #expect(UserColorPalette.color(forID: 0) == nil)
    }

    @Test("palette ID 1 is white")
    func oneIsWhite() throws {
        let color = try #require(UserColorPalette.color(forID: 1))
        let components = try #require(NSColor(color).usingColorSpace(.sRGB))
        #expect(approxEqual(components.redComponent, 1.0))
        #expect(approxEqual(components.greenComponent, 1.0))
        #expect(approxEqual(components.blueComponent, 1.0))
    }

    @Test("palette ID 36 is pure red — classic Hotline admin")
    func thirtySixIsAdminRed() throws {
        let color = try #require(UserColorPalette.color(forID: 36))
        let components = try #require(NSColor(color).usingColorSpace(.sRGB))
        #expect(approxEqual(components.redComponent, 1.0))
        #expect(approxEqual(components.greenComponent, 0.0))
        #expect(approxEqual(components.blueComponent, 0.0))
    }

    @Test("palette ID 211 is pure blue")
    func twoElevenIsBlue() throws {
        let color = try #require(UserColorPalette.color(forID: 211))
        let components = try #require(NSColor(color).usingColorSpace(.sRGB))
        #expect(approxEqual(components.redComponent, 0.0))
        #expect(approxEqual(components.greenComponent, 0.0))
        #expect(approxEqual(components.blueComponent, 1.0))
    }

    private func approxEqual(_ lhs: CGFloat, _ rhs: CGFloat, tolerance: CGFloat = 0.005) -> Bool {
        abs(lhs - rhs) < tolerance
    }
}
