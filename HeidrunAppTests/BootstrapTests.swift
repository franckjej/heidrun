import Testing
@testable import Heidrun

@Suite("Bootstrap")
struct BootstrapTests {
    @Test("HeidrunAppTests target compiles and runs")
    func smoke() {
        #expect(true)
    }
}
