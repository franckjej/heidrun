import Foundation

/// Small `Identifiable` wrapper around the URL of a `.heidrunbookmarks`
/// file the user just double-clicked in Finder. `URL` itself isn't
/// `Identifiable`, but SwiftUI's `sheet(item:)` requires the bound
/// value to be — and a struct wrapper is cleaner than a retroactive
/// `Identifiable` conformance on `URL`.
struct PendingBookmarksImport: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
}
