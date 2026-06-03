import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
import UIKit
#endif

public extension Color {
    static let klear = Color(.underPageBackgroundColor.withAlphaComponent(0.0001))
}

public extension Color {
    init(light: Color, dark: Color) {
#if canImport(UIKit)
        self.init(light: UIColor(light), dark: UIColor(dark))
#else
        self.init(light: NSColor(light), dark: NSColor(dark))
#endif
    }

#if canImport(UIKit)
    init(light: UIColor, dark: UIColor) {
#if os(watchOS)
        // watchOS does not support light mode / dark mode
        // Per Apple HIG, prefer dark-style interfaces
        self.init(uiColor: dark)
#else
        self.init(uiColor: UIColor(dynamicProvider: { traits in
            switch traits.userInterfaceStyle {
            case .light, .unspecified:
                return light

            case .dark:
                return dark

            @unknown default:
                assertionFailure("Unknown userInterfaceStyle: \(traits.userInterfaceStyle)")
                return light
            }
        }))
#endif
    }
#endif

#if canImport(AppKit)
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            switch appearance.name {
            case .aqua,
                    .vibrantLight,
                    .accessibilityHighContrastAqua,
                    .accessibilityHighContrastVibrantLight:
                return light

            case .darkAqua,
                    .vibrantDark,
                    .accessibilityHighContrastDarkAqua,
                    .accessibilityHighContrastVibrantDark:
                return dark

            default:
                assertionFailure("Unknown appearance: \(appearance.name)")
                return light
            }
        }))
    }
#endif
}

extension Color: @retroactive RawRepresentable {
    public init?(rawValue: String) {
        guard let data = Data(base64Encoded: rawValue),
              let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) else {
            return nil
        }
        self = Color(nsColor: color)
    }

    public var rawValue: String {
        let data = try? NSKeyedArchiver.archivedData(withRootObject: NSColor(self), requiringSecureCoding: false)
        return data?.base64EncodedString() ?? ""
    }
}

public extension Color {
    private var luminance: Double {
        // 1. Convert SwiftUI Color to UIColor
        let nsColor = NSColor(self).usingColorSpace(.deviceRGB)
        // 2. Extract RGB values
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        nsColor?.getRed(&red, green: &green, blue: &blue, alpha: nil)

        // 3. Compute luminance.
        return 0.2126 * Double(red) + 0.7152 * Double(green) + 0.0722 * Double(blue)
    }
    var accessibleErrorFontColor: Color {
       luminance > 0.5 ? .init("ErrorColorOnLight", bundle: .main) : .init("ErrorColorOnDark", bundle: .main)
    }
}
