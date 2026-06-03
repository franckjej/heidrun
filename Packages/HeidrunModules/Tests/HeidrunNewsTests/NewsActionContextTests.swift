import Foundation
import Testing
@testable import HeidrunNews

@MainActor
@Suite("NewsActionContext")
struct NewsActionContextTests {
    @Test("copyPost invokes the supplied closure")
    func copyPost_invokesClosure() {
        var fired = false
        let context = NewsActionContext(
            hasSelection: true,
            canEdit: true,
            copyPost: { fired = true },
            copyThread: {},
            reply: {},
            edit: {},
            delete: {},
            hasSelectedBundle: false,
            copyBundleContents: {}
        )
        context.copyPost()
        #expect(fired)
    }

    @Test("each closure is independently dispatched")
    func eachClosureDispatches() {
        var hits: [String] = []
        let context = NewsActionContext(
            hasSelection: true,
            canEdit: true,
            copyPost: { hits.append("post") },
            copyThread: { hits.append("thread") },
            reply: { hits.append("reply") },
            edit: { hits.append("edit") },
            delete: { hits.append("delete") },
            hasSelectedBundle: false,
            copyBundleContents: { hits.append("bundle") }
        )
        context.copyThread()
        context.reply()
        context.edit()
        context.delete()
        #expect(hits == ["thread", "reply", "edit", "delete"])
    }

    @Test("flags carry through as constructed")
    func flagsPropagate() {
        let context = NewsActionContext(
            hasSelection: false,
            canEdit: false,
            copyPost: {},
            copyThread: {},
            reply: {},
            edit: {},
            delete: {},
            hasSelectedBundle: false,
            copyBundleContents: {}
        )
        #expect(context.hasSelection == false)
        #expect(context.canEdit == false)
    }

    @Test("copyBundleContents invokes the supplied closure")
    func copyBundleContents_invokesClosure() {
        var fired = false
        let context = NewsActionContext(
            hasSelection: false,
            canEdit: false,
            copyPost: {},
            copyThread: {},
            reply: {},
            edit: {},
            delete: {},
            hasSelectedBundle: true,
            copyBundleContents: { fired = true }
        )
        context.copyBundleContents()
        #expect(fired)
    }

    @Test("hasSelectedBundle carries through as constructed")
    func hasSelectedBundle_propagates() {
        let context = NewsActionContext(
            hasSelection: false,
            canEdit: false,
            copyPost: {},
            copyThread: {},
            reply: {},
            edit: {},
            delete: {},
            hasSelectedBundle: true,
            copyBundleContents: {}
        )
        #expect(context.hasSelectedBundle == true)
    }
}
