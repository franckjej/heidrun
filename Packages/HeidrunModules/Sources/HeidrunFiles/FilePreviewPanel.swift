import SwiftUI
import AppKit
import HeidrunCore
import HeidrunUI
import CommonTools

/// SwiftUI body of the Quick Look panel. Reads `previewState` off the
/// view-model so the panel updates in place when the user picks a new
/// file while the panel is open.
struct FilePreviewPanel: View {
    @Bindable var viewModel: FilesViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content(for: viewModel.previewState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 420, idealWidth: 580, minHeight: 320, idealHeight: 480)
    }

    private var header: some View {
        HStack(spacing: Spacing.xsmall.rawValue) {
            Image(systemName: "eye")
                .foregroundStyle(.secondary)
            Text(viewModel.previewState.fileName ?? "Quick Look")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if case .loading = viewModel.previewState {
                Button("Cancel") { viewModel.cancelPreview() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, .small)
        .padding(.vertical, .xsmall)
    }

    @ViewBuilder
    private func content(for state: FilesViewModel.PreviewState) -> some View {
        switch state {
        case .idle:
            placeholder(title: "Select a file to preview")
        case .loading(_, let fraction):
            VStack(spacing: Spacing.small.rawValue) {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 240)
                Text("Loading…")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.medium)
        case .ready(let payload):
            payloadBody(for: payload)
        case .failed(let message):
            placeholder(
                title: "Couldn’t preview",
                subtitle: message,
                isError: true
            )
        }
    }

    @ViewBuilder
    private func payloadBody(for payload: FilesViewModel.PreviewPayload) -> some View {
        switch payload.kind {
        case .text(let body):
            ScrollView([.vertical, .horizontal]) {
                Text(body)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.small)
            }
        }
    }

    @ViewBuilder
    private func placeholder(
        title: String,
        subtitle: String? = nil,
        isError: Bool = false
    ) -> some View {
        VStack(spacing: Spacing.xsmall.rawValue) {
            Image(systemName: isError ? "exclamationmark.triangle" : "eye")
                .font(.system(size: 32, weight: .ultraLight))
                .foregroundStyle(isError ? Color.red : Color.secondary)
            Text(title)
                .font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .padding(.horizontal, .medium)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Owns the `NSPanel` that hosts `FilePreviewPanel`. Lives on a `@State`
/// in `FilesView` so it survives view re-renders. The panel is a
/// utility-style floating panel: it stays above the connection window,
/// doesn't steal focus, and can be reused for successive previews.
@MainActor
final class FilePreviewWindowController {
    private var panel: NSPanel?
    private var hostingController: NSHostingController<FilePreviewPanel>?
    private weak var attachedViewModel: FilesViewModel?
    // NSWindow.delegate is weak, and the controller is the sole owner —
    // making this `weak` would let the delegate be deallocated immediately.
    // swiftlint:disable:next weak_delegate
    private var panelDelegate: PanelDelegate?

    /// Bring the panel up for `viewModel`. If it's already open, just
    /// foregrounds it — the panel re-reads the view-model's
    /// `previewState`, so the body updates without a reattach.
    ///
    /// `serverIdentifier`, when supplied, is used to derive a per-server
    /// frame autosave name so each Hotline server remembers its own
    /// preview panel size/position via `UserDefaults`.
    func show(
        for viewModel: FilesViewModel,
        near hostWindow: NSWindow?,
        serverIdentifier: String? = nil
    ) {
        if let panel, attachedViewModel === viewModel {
            panel.orderFront(nil)
            return
        }

        let host = NSHostingController(rootView: FilePreviewPanel(viewModel: viewModel))
        host.sizingOptions = [.minSize, .intrinsicContentSize]

        if let panel {
            panel.contentViewController = host
            hostingController = host
            attachedViewModel = viewModel
            panel.orderFront(nil)
            return
        }

        let newPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 480),
            styleMask: [
                .titled,
                .closable,
                .resizable,
                .utilityWindow,
                .nonactivatingPanel
            ],
            backing: .buffered,
            defer: false
        )
        newPanel.title = "Quick Look"
        newPanel.contentViewController = host
        newPanel.isFloatingPanel = true
        newPanel.hidesOnDeactivate = false
        newPanel.becomesKeyOnlyIfNeeded = true
        newPanel.isReleasedWhenClosed = false
        newPanel.collectionBehavior.insert(.fullScreenAuxiliary)

        let delegate = PanelDelegate(controller: self)
        newPanel.delegate = delegate
        panelDelegate = delegate

        // Center on the host first; setFrameAutosaveName will overwrite
        // that with the persisted frame if one exists. If nothing is
        // persisted yet, the centered position becomes the seed.
        positionPanel(newPanel, near: hostWindow)
        applyFrameAutosave(to: newPanel, serverIdentifier: serverIdentifier)
        newPanel.orderFront(nil)

        panel = newPanel
        hostingController = host
        attachedViewModel = viewModel
    }

    /// Build a stable, file-system-safe autosave key from the server
    /// identifier and hand it to AppKit. Falls back to a single global
    /// key when no identifier is supplied so the legacy
    /// `FilesFeature.makeContentView` path still benefits from
    /// persistence.
    private func applyFrameAutosave(to panel: NSPanel, serverIdentifier: String?) {
        let suffix: String
        if let serverIdentifier, !serverIdentifier.isEmpty {
            // NSWindow doesn't restrict autosave names, but keep them
            // free of unusual characters so the UserDefaults key stays
            // tidy and easy to spot in `defaults read`.
            let safe = serverIdentifier
                .lowercased()
                .map { character -> Character in
                    character.isLetter || character.isNumber
                        ? character
                        : "-"
                }
            suffix = "." + String(safe)
        } else {
            suffix = ""
        }
        panel.setFrameAutosaveName("Heidrun.PreviewPanel\(suffix)")
    }

    /// Close the panel programmatically (e.g. when the connection is torn
    /// down). Safe to call when nothing is open.
    func close() {
        panel?.close()
    }

    private func positionPanel(_ panel: NSPanel, near hostWindow: NSWindow?) {
        guard let hostWindow else {
            panel.center()
            return
        }
        let panelFrame = panel.frame
        let hostFrame = hostWindow.frame
        var origin = NSPoint(
            x: hostFrame.midX - panelFrame.width / 2,
            y: hostFrame.midY - panelFrame.height / 2
        )
        if let screen = hostWindow.screen ?? NSScreen.main {
            let screenFrame = screen.visibleFrame
            origin.x = min(max(screenFrame.minX, origin.x), screenFrame.maxX - panelFrame.width)
            origin.y = min(max(screenFrame.minY, origin.y), screenFrame.maxY - panelFrame.height)
        }
        panel.setFrameOrigin(origin)
    }

    fileprivate func handlePanelClosed() {
        attachedViewModel?.dismissPreview()
        panel = nil
        hostingController = nil
        panelDelegate = nil
        attachedViewModel = nil
    }

    private final class PanelDelegate: NSObject, NSWindowDelegate {
        weak var controller: FilePreviewWindowController?

        init(controller: FilePreviewWindowController) {
            self.controller = controller
        }

        func windowWillClose(_ notification: Notification) {
            controller?.handlePanelClosed()
        }
    }
}
