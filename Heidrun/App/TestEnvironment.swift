import Foundation

/// Detects whether the current process was launched by `xcodebuild test`
/// / the Xcode test runner. Read via the `XCTestConfigurationFilePath`
/// env var that XCTest's bootstrap sets before injecting the test
/// bundle into the host app.
///
/// Used to short-circuit session restoration in tests: the
/// `HeidrunAppTests` bundle loads INTO `Heidrun.app`, which means
/// `HeidrunMainApp.init` runs in the test process. Without this gate
/// the test process would auto-reconnect to the user's last-live
/// bookmark, dance with `BiometricVaultKeyStore` and `KeychainPasswordStore`
/// in an environment that can't reliably authenticate, and regenerate
/// the AES vault key — silently invalidating every saved password the
/// user encrypted under the prior key.
enum TestEnvironment {
    /// True when running inside a Mac test bundle host. `XCTestConfigurationFilePath`
    /// is the canonical test-detection sentinel — present for both
    /// XCTest and Swift Testing runs because Swift Testing piggybacks
    /// on the XCTest runner on Apple platforms.
    static var isRunningUnderTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
