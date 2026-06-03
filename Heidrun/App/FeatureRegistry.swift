import HeidrunUI
import HeidrunChat
import HeidrunMessages
import HeidrunNews
import HeidrunFiles
import HeidrunAdmin

/// Static list of every feature library the host bundles, in sidebar
/// display order. Drop one to remove it from the UI (and drop the
/// matching `import` plus the package dependency in `Package.swift` to
/// stop linking it entirely).
///
/// Agreement is intentionally not listed: the server's agreement banner
/// is presented as a one-shot sheet over `HostView` (see
/// `AgreementSheet`) rather than as a sidebar tab.
@MainActor
enum FeatureRegistry {
    static let all: [any HeidrunFeature.Type] = [
        ChatFeature.self,
        NewsFeature.self,
        FilesFeature.self,
        MessagesFeature.self,
        AdminFeature.self
    ]
}
