import Foundation
import Testing
@testable import Heidrun

@Suite("TestEnvironment")
struct TestEnvironmentTests {
    @Test("isRunningUnderTests is true while the test bundle is loaded")
    func detectsTestRuntime() {
        // This test passing proves both:
        //   1. The XCTestConfigurationFilePath env var IS set when
        //      our tests run (so the gate fires in the production
        //      `HeidrunMainApp.init` / `applicationWillTerminate`
        //      paths during a real `xcodebuild test`).
        //   2. The helper reads it correctly.
        // If the helper ever drifts (env-var rename, alternative
        // launch path), this test catches it before the session-
        // restoration gate silently goes off.
        #expect(TestEnvironment.isRunningUnderTests == true)
    }
}
