import Testing
@testable import Heidrun

@Suite("AppDataEnvironment.shouldIsolate")
struct AppDataEnvironmentTests {
    @Test("a release build never isolates")
    func releaseNeverIsolates() {
        #expect(AppDataEnvironment.shouldIsolate(isDebugBuild: false, hasProductionFlag: false, isRunningUnderTests: false) == false)
    }

    @Test("a debug build with the production flag does not isolate")
    func debugWithFlagDoesNotIsolate() {
        #expect(AppDataEnvironment.shouldIsolate(isDebugBuild: true, hasProductionFlag: true, isRunningUnderTests: false) == false)
    }

    @Test("a debug build under tests does not isolate")
    func debugUnderTestsDoesNotIsolate() {
        #expect(AppDataEnvironment.shouldIsolate(isDebugBuild: true, hasProductionFlag: false, isRunningUnderTests: true) == false)
    }

    @Test("a plain debug run isolates")
    func plainDebugIsolates() {
        #expect(AppDataEnvironment.shouldIsolate(isDebugBuild: true, hasProductionFlag: false, isRunningUnderTests: false) == true)
    }
}

@Suite("AppDataEnvironment.hasProductionFlag")
struct AppDataEnvironmentFlagTests {
    @Test("matches the flag typed without a leading dash")
    func matchesBareName() {
        #expect(AppDataEnvironment.hasProductionFlag(in: ["/bin/Heidrun", "UseProductionData"]) == true)
    }

    @Test("matches the flag with a single leading dash")
    func matchesSingleDash() {
        #expect(AppDataEnvironment.hasProductionFlag(in: ["-UseProductionData"]) == true)
    }

    @Test("matches the flag with a double leading dash")
    func matchesDoubleDash() {
        #expect(AppDataEnvironment.hasProductionFlag(in: ["--UseProductionData"]) == true)
    }

    @Test("is false when the flag is absent")
    func falseWhenAbsent() {
        #expect(AppDataEnvironment.hasProductionFlag(in: ["/bin/Heidrun", "-OtherFlag"]) == false)
    }

    @Test("is false for an empty argument list")
    func falseWhenEmpty() {
        #expect(AppDataEnvironment.hasProductionFlag(in: []) == false)
    }

    @Test("does not match an unrelated arg that merely contains the name")
    func noSubstringFalsePositive() {
        #expect(AppDataEnvironment.hasProductionFlag(in: ["-NotUseProductionDataReally"]) == false)
    }
}
