import Foundation

/// One entry in the Help window's sidebar. Each topic resolves to a
/// markdown file bundled in the app under `Heidrun/Help/*.md` — the
/// resource name (without extension) is `fileName`.
enum HelpTopic: String, CaseIterable, Identifiable {
    case connecting       = "help-connecting"
    case filesAndTransfers = "help-files-transfers"
    case bookmarks        = "help-bookmarks"
    case settings         = "help-settings"

    var id: String { rawValue }

    /// Sidebar label.
    var displayName: String {
        switch self {
        case .connecting:
            return "Connecting & Agreements"
        case .filesAndTransfers:
            return "Files & Transfers"
        case .bookmarks:
            return "Bookmarks"
        case .settings:
            return "Settings"
        }
    }

    /// Sidebar icon. Outline glyphs to match the rest of the app.
    var systemImage: String {
        switch self {
        case .connecting:
            return "network"
        case .filesAndTransfers:
            return "arrow.up.arrow.down.circle"
        case .bookmarks:
            return "bookmark"
        case .settings:
            return "gearshape"
        }
    }

    /// The bundled markdown's filename stem (we'll look it up with
    /// `Bundle.main.url(forResource:withExtension:)`).
    var fileName: String { rawValue }
}
