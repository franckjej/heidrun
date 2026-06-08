import Foundation
import SwiftUI

/// Three-step density preset for written-content surfaces (user list,
/// file list, chat, news, message threads) with a per-preset body-size
/// override.
///
/// macOS doesn't expose iPhone-style Dynamic Type, and the project mixes
/// SwiftUI with AppKit table/text wrappers, so we publish our own
/// three-step token and let the user override the body size per preset.
/// Non-body sizes (caption, icon, row height) follow the preset — picker
/// icons + cell chrome stay coherent even when body text is nudged.
///
/// Persisted under:
///   - `Heidrun.contentSize` (String, preset rawValue)
///   - `Heidrun.contentSize.<preset>.body` (Double, 0 = use built-in)
public struct ContentSize: Sendable, Hashable {
    /// `@frozen` so external consumers can `switch` without `@unknown
    /// default`. We don't plan more presets; adding one would warrant
    /// updating every switch anyway.
    @frozen public enum Preset: String, CaseIterable, Hashable, Sendable {
        case compact
        case standard
        case comfortable

        public var defaultBodyPointSize: CGFloat {
            switch self {
            case .compact:
                return 11
            case .standard:
                return 13   // matches `NSFont.systemFontSize`
            case .comfortable:
                return 15
            }
        }

        /// Fixed per preset (not tracking body override) so cell chrome
        /// stays consistent with the preset's overall density.
        public var iconSize: CGFloat {
            switch self {
            case .compact:
                return 16
            case .standard:
                return 20
            case .comfortable:
                return 24
            }
        }

        /// File-table row height. Generous enough that `.inset`
        /// selection has visible padding.
        public var rowHeight: CGFloat {
            switch self {
            case .compact:
                return 30
            case .standard:
                return 34
            case .comfortable:
                return 38
            }
        }

        /// Primary-navigation sidebar (the host's feature picker). One
        /// step taller than `rowHeight` so the selection pill breathes.
        public var sidebarRowHeight: CGFloat {
            switch self {
            case .compact:
                return 46
            case .standard:
                return 48
            case .comfortable:
                return 50
            }
        }

        /// User-list inspector — avatar + name. `iconSize * 2` keeps the
        /// avatar comfortably centred at every preset.
        public var userListRowHeight: CGFloat {
            iconSize * 2
        }

        /// Bookmark sidebar — two-line cell (name + login). Extra
        /// 16pt (`Spacing.small`, inlined to keep CommonTools self-
        /// contained) for the rounded selection pill's breathing room.
        public var bookmarkRowHeight: CGFloat {
            iconSize * 2 + 16
        }
    }

    /// The user-facing density *selection*. Persisted under
    /// `Heidrun.contentSize`. The three named cases keep `Preset`'s raw
    /// values so existing stored prefs parse unchanged; `system` follows
    /// the macOS sidebar icon size (`EnvironmentValues.sidebarRowSize`)
    /// and resolves to a concrete `Preset` at render time.
    @frozen public enum DensityMode: String, CaseIterable, Hashable, Sendable {
        case compact
        case standard
        case comfortable
        case system

        /// Concrete preset this selection renders as. `system` maps the
        /// OS sidebar row size; any non-small/large value (incl. medium)
        /// resolves to `.standard`.
        public func resolvedPreset(systemRowSize: SidebarRowSize) -> Preset {
            switch self {
            case .compact:
                return .compact
            case .standard:
                return .standard
            case .comfortable:
                return .comfortable
            case .system:
                switch systemRowSize {
                case .small:
                    return .compact
                case .large:
                    return .comfortable
                default:
                    return .standard
                }
            }
        }
    }

    /// Bounds on the inline +/- so the user can't go unreadable or
    /// overshoot the preset's row height geometry.
    public static let bodyPointSizeRange: ClosedRange<CGFloat> = 9...20

    public let preset: Preset

    /// Either the preset default or a per-preset override clamped to
    /// `bodyPointSizeRange`.
    public let bodyPointSize: CGFloat

    /// `body - 2pt`, never less than 8pt.
    public var captionPointSize: CGFloat { max(8, bodyPointSize - 2) }

    public var iconSize: CGFloat { preset.iconSize }
    public var rowHeight: CGFloat { preset.rowHeight }
    public var sidebarRowHeight: CGFloat { preset.sidebarRowHeight }
    public var userListRowHeight: CGFloat { preset.userListRowHeight }
    public var bookmarkRowHeight: CGFloat { preset.bookmarkRowHeight }

    /// `bodyPointSize: nil` uses the preset's built-in default.
    public init(preset: Preset, bodyPointSize: CGFloat? = nil) {
        self.preset = preset
        if let override = bodyPointSize {
            self.bodyPointSize = override
                .clamped(to: Self.bodyPointSizeRange)
        } else {
            self.bodyPointSize = preset.defaultBodyPointSize
        }
    }

    public static let `default` = ContentSize(preset: .standard)

    public static let compact     = ContentSize(preset: .compact)
    public static let standard    = ContentSize(preset: .standard)
    public static let comfortable = ContentSize(preset: .comfortable)
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
