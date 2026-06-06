import Testing
import Foundation
import HeidrunCore
@testable import HeidrunUI

@Suite("ErrorPresenter")
@MainActor
struct ErrorPresenterTests {
    private struct Described: LocalizedError {
        var errorDescription: String? { "a described failure" }
    }

    @Test("maps a HotlineError to its userMessage")
    func mapsHotlineError() {
        let message = ErrorPresenter.message(for: HotlineError.serverError(id: 1, message: "no dice"))
        #expect(message == HotlineError.serverError(id: 1, message: "no dice").userMessage)
        // userMessage capitalises the first char ("No dice"); assert the
        // server's payload survives regardless of case.
        #expect(message.localizedCaseInsensitiveContains("no dice"))
    }

    @Test("maps a LocalizedError to its errorDescription")
    func mapsLocalizedError() {
        #expect(ErrorPresenter.message(for: Described()) == "a described failure")
    }

    @Test("maps a plain NSError to its localizedDescription")
    func mapsNSError() {
        let error = NSError(domain: "Test", code: 7, userInfo: [NSLocalizedDescriptionKey: "plain failure"])
        #expect(ErrorPresenter.message(for: error) == "plain failure")
    }

    @Test("present sets current; dismiss clears it")
    func presentAndDismiss() {
        let presenter = ErrorPresenter()
        #expect(presenter.current == nil)
        presenter.present(Described())
        #expect(presenter.current?.message == "a described failure")
        presenter.dismiss()
        #expect(presenter.current == nil)
    }

    @Test("an explicit title overrides the default")
    func explicitTitle() {
        let presenter = ErrorPresenter()
        presenter.present(Described(), title: "Couldn't do the thing")
        #expect(presenter.current?.title == "Couldn't do the thing")
        presenter.present(title: "Local title", message: "local message")
        #expect(presenter.current?.title == "Local title")
        #expect(presenter.current?.message == "local message")
    }
}
