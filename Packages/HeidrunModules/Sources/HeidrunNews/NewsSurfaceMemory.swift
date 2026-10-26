import SwiftUI

/// Last Board/Threaded pick per server (`address:port`); overrides the
/// default news view on the next connect.
public enum NewsSurfaceMemory {
    public static let storageKey = "Heidrun.newsSurfaceByServer"

    public static func serverKey(address: String, port: UInt16) -> String {
        "\(address.lowercased()):\(port)"
    }

    public static func surface(for serverKey: String, defaults: UserDefaults = .standard) -> NewsSurface? {
        let stored = defaults.dictionary(forKey: storageKey)?[serverKey] as? String
        return stored.flatMap(NewsSurface.init(rawValue:))
    }

    public static func record(_ surface: NewsSurface, for serverKey: String, defaults: UserDefaults = .standard) {
        var stored = defaults.dictionary(forKey: storageKey) ?? [:]
        stored[serverKey] = surface.rawValue
        defaults.set(stored, forKey: storageKey)
    }

    /// Board/Threaded switch binding that remembers the pick for this server.
    @MainActor
    static func selection(of threaded: ThreadedNewsViewModel, serverKey: String?) -> Binding<NewsSurface> {
        Binding(
            get: { threaded.surface },
            set: { newSurface in
                threaded.surface = newSurface
                if let serverKey {
                    record(newSurface, for: serverKey)
                }
            }
        )
    }
}

extension NewsDefaultSurface {
    /// A remembered per-server pick wins over the global default.
    func overridden(by remembered: NewsSurface?) -> NewsDefaultSurface {
        switch remembered {
        case .board:
            .board
        case .threaded:
            .threaded
        case nil:
            self
        }
    }
}
