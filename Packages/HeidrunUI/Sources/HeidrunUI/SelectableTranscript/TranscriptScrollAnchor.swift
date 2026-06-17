import CoreGraphics

/// Persisted scroll intent for a `SelectableTranscript`.
///
/// The transcript is an `NSViewRepresentable`; switching features tears
/// its `NSScrollView` down and rebuilds it at the top, so "keep me at the
/// bottom" can't be inferred from the rebuilt view's geometry — a fresh
/// view is genuinely at the top. The intent therefore has to live
/// somewhere longer-lived than the view. Hand a transcript an anchor owned
/// by the caller's (hoisted) view-model and it survives the teardown.
///
/// Updated only from user-driven live scrolls, so layout- and
/// programmatic-scroll bounds changes never clobber the recorded intent.
@MainActor
public final class TranscriptScrollAnchor {
    /// True while the user is parked at (or near) the bottom — the live
    /// transcript should follow new lines. Defaults true so a freshly
    /// shown surface starts pinned to the latest line.
    public var followsBottom: Bool = true

    /// Last user-set scroll offset (clip-view origin Y), restored verbatim
    /// when `followsBottom` is false.
    public var offsetY: CGFloat = 0

    public init() {}
}
