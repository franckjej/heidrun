import SwiftUI
import AppKit
import CommonTools

// MARK: - SwiftUI environment

/// Read via `@Environment(\.heidrunContentSize)`.
public struct HeidrunContentSizeKey: EnvironmentKey {
    public static let defaultValue: ContentSize = .default
}

public extension EnvironmentValues {
    var heidrunContentSize: ContentSize {
        get { self[HeidrunContentSizeKey.self] }
        set { self[HeidrunContentSizeKey.self] = newValue }
    }
}

public extension View {
    /// Posts `heidrunContentSizeChanged` on change so AppKit consumers
    /// (NSTableView wrappers, NSTextView transcript) — which don't see
    /// SwiftUI environment changes — can refresh fonts + row heights.
    func heidrunContentSize(_ size: ContentSize) -> some View {
        environment(\.heidrunContentSize, size)
            .onChange(of: size, initial: false) { _, newValue in
                NotificationCenter.default.post(
                    name: .heidrunContentSizeChanged,
                    object: nil,
                    userInfo: [HeidrunContentSizeNotificationKey: newValue]
                )
            }
    }

    /// Scene-root wiring: reads `Heidrun.contentSize` and pipes through
    /// `heidrunContentSize`. Pair with `.defaultAppStorage(...)` so the
    /// right suite is read.
    func heidrunContentSizeFromStorage() -> some View {
        modifier(ContentSizeFromStorageModifier())
    }

    /// Apply `ContentSize`'s body point size to this view.
    func heidrunBody() -> some View {
        modifier(HeidrunBodyModifier())
    }

    /// Apply `ContentSize`'s caption point size to this view.
    func heidrunCaption() -> some View {
        modifier(HeidrunCaptionModifier())
    }
}

private struct ContentSizeFromStorageModifier: ViewModifier {
    @AppStorage(ContentSizeReader.presetStorageKey)
    private var modeRawValue: String = ContentSize.default.preset.rawValue

    // The macOS "Sidebar icon size" preference (NSGlobalDomain). Read via
    // `@AppStorage` so SwiftUI re-resolves the density when the user
    // changes it. `\.sidebarRowSize` can't be used: SwiftUI only seeds it
    // inside a `.sidebar`-styled `List`, which Heidrun's AppKit sidebars
    // are not. `2` (medium) matches the OS default when the key is unset.
    @AppStorage(ContentSize.DensityMode.systemSidebarSizeDefaultsKey)
    private var systemSizeMode: Int = 2

    // `0` means "use the preset's built-in body size". The picker's +/-
    // writes here; the storage modifier reads the one matching the
    // resolved preset.
    @AppStorage(ContentSizeReader.bodyOverrideKey(for: .compact))
    private var compactBody: Double = 0
    @AppStorage(ContentSizeReader.bodyOverrideKey(for: .standard))
    private var standardBody: Double = 0
    @AppStorage(ContentSizeReader.bodyOverrideKey(for: .comfortable))
    private var comfortableBody: Double = 0

    func body(content: Content) -> some View {
        let mode = ContentSize.DensityMode(rawValue: modeRawValue) ?? .standard
        let rowSize = ContentSize.DensityMode.sidebarRowSize(forSizeMode: systemSizeMode)
        let preset = mode.resolvedPreset(systemRowSize: rowSize)
        let override = bodyOverride(for: preset)
        let resolved = ContentSize(preset: preset, bodyPointSize: override)
        // `heidrunContentSize(_:)` posts `.heidrunContentSizeChanged` when
        // `resolved` changes, so AppKit consumers reflow when the OS
        // sidebar size flips while on system mode.
        return content.heidrunContentSize(resolved)
    }

    private func bodyOverride(for preset: ContentSize.Preset) -> CGFloat? {
        let raw: Double
        switch preset {
        case .compact:
            raw = compactBody
        case .standard:
            raw = standardBody
        case .comfortable:
            raw = comfortableBody
        }
        return raw > 0 ? CGFloat(raw) : nil
    }
}

private struct HeidrunBodyModifier: ViewModifier {
    @Environment(\.heidrunContentSize) private var contentSize
    func body(content: Content) -> some View {
        content.font(.system(size: contentSize.bodyPointSize))
    }
}

private struct HeidrunCaptionModifier: ViewModifier {
    @Environment(\.heidrunContentSize) private var contentSize
    func body(content: Content) -> some View {
        content.font(.system(size: contentSize.captionPointSize))
    }
}

// MARK: - AppKit bridge

/// `userInfo[HeidrunContentSizeNotificationKey]` carries the new value.
/// AppKit consumers observe this and call `reloadData()` / refresh fonts.
public extension Notification.Name {
    static let heidrunContentSizeChanged = Notification.Name("HeidrunContentSizeChanged")
}

public let HeidrunContentSizeNotificationKey = "contentSize"

/// One-shot read for AppKit code that needs to draw without owning an
/// observer chain. Reads `UserDefaults.standard` — pass the value
/// explicitly via `init` when the call site has the SwiftUI env.
public enum ContentSizeReader {
    public static func current(in defaults: UserDefaults = .standard) -> ContentSize {
        let stored = defaults.string(forKey: presetStorageKey)
            ?? ContentSize.default.preset.rawValue
        let mode = ContentSize.DensityMode(rawValue: stored) ?? .standard
        let preset: ContentSize.Preset
        if mode == .system {
            // Resolve the OS "Sidebar icon size" directly — it lives in
            // `UserDefaults` (NSGlobalDomain), so this read needs no SwiftUI
            // environment.
            preset = mode.resolvedPreset(
                systemRowSize: ContentSize.DensityMode.systemRowSize(from: defaults)
            )
        } else {
            preset = ContentSize.Preset(rawValue: stored) ?? .standard
        }
        let override = defaults.double(forKey: bodyOverrideKey(for: preset))
        return ContentSize(
            preset: preset,
            bodyPointSize: override > 0 ? CGFloat(override) : nil
        )
    }

    /// Mirrors `AppStorageKeys.contentSize` — kept as a literal so
    /// HeidrunUI doesn't have to depend on the app target.
    public static let presetStorageKey = "Heidrun.contentSize"

    /// `0` means "no override, use the preset's built-in body size".
    public static func bodyOverrideKey(for preset: ContentSize.Preset) -> String {
        "Heidrun.contentSize.\(preset.rawValue).body"
    }

    /// Legacy / discoverability alias for `presetStorageKey`.
    public static let storageKey = presetStorageKey
}
