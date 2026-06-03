import Foundation

/// Should this process use an isolated data store (separate
/// `UserDefaults` suite + in-memory credential store) instead of the
/// user's production data? Safe by default: plain Debug builds isolate
/// (so ⌘R can't touch real bookmarks / passwords); Release always uses
/// production; a Debug build launched with `UseProductionData` opts back
/// in. Tests stay on `.standard` so existing test suites keep their own
/// discipline.
enum AppDataEnvironment {
    static let isolatedSuiteName = "org.tastybytes.heidrun.debug"

    /// Matched with or without leading dashes (`UseProductionData`,
    /// `-UseProductionData`, `--UseProductionData`).
    static let productionFlagName = "UseProductionData"

    /// Exact match on the dash-stripped token — an unrelated argument
    /// that merely contains the name doesn't trip it.
    static func hasProductionFlag(in arguments: [String]) -> Bool {
        arguments.contains { argument in
            String(argument.drop(while: { character in character == "-" })) == productionFlagName
        }
    }

    /// Pure isolation decision — the unit under test.
    static func shouldIsolate(
        isDebugBuild: Bool,
        hasProductionFlag: Bool,
        isRunningUnderTests: Bool
    ) -> Bool {
        isDebugBuild && !hasProductionFlag && !isRunningUnderTests
    }

    static let isIsolated: Bool = {
        #if DEBUG
        let isDebugBuild = true
        #else
        let isDebugBuild = false
        #endif
        return shouldIsolate(
            isDebugBuild: isDebugBuild,
            hasProductionFlag: hasProductionFlag(in: ProcessInfo.processInfo.arguments),
            isRunningUnderTests: TestEnvironment.isRunningUnderTests
        )
    }()

    /// Every store and `@AppStorage` should read through this.
    nonisolated(unsafe) static let defaults: UserDefaults = {
        guard isIsolated else { return .standard }
        return UserDefaults(suiteName: isolatedSuiteName) ?? .standard
    }()

    /// Isolated Debug runs land in a `Heidrun-Debug` sibling directory
    /// so ⌘R never dirties the user's real bookmark folder.
    static let bookmarksDirectoryURL: URL = {
        let supportDir: URL
        do {
            supportDir = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            supportDir = FileManager.default.temporaryDirectory
        }
        let leaf = isIsolated ? "Heidrun-Debug" : "Heidrun"
        return supportDir
            .appendingPathComponent(leaf, isDirectory: true)
            .appendingPathComponent("Bookmarks", isDirectory: true)
    }()
}
