import Foundation
import AppKit
import QuartzCore

public final class DisplayLink: @unchecked Sendable {
    @MainActor
    public init (window: NSWindow, _ callback: @Sendable @escaping () -> Void) {
        _callback = callback
        _link = window.displayLink(target: _DisplayTarget(self), selector: #selector(_DisplayTarget._callback))
        _link.add(to: RunLoop.main, forMode: RunLoop.Mode.common)
    }

    fileprivate let _callback: @Sendable () -> Void

    private var _link: CADisplayLink!

    deinit {
        _link.invalidate()
    }

    func pause() {
        _link.isPaused = true
    }
    func resume() {
        _link.isPaused = false
    }
}

/// Retained by CADisplayLink.
private class _DisplayTarget {

    init (_ link: DisplayLink) {
        _link = link
    }

    weak var _link: DisplayLink!

    @objc func _callback() {
        _link?._callback()
    }
}
extension CADisplayLink: @unchecked @retroactive Sendable { }
