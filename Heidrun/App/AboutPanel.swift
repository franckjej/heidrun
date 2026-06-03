import SwiftUI
import AppKit
import CommonTools

/// Custom About window — replaces the stock `orderFrontStandardAboutPanel`
/// with an icon-forward, chrome-minimal panel. Entry point stays
/// `AboutPanel.show()` so the app menu wiring is unchanged.
enum AboutPanel {
    @MainActor private static var window: NSWindow?

    @MainActor
    static func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate()
            return
        }

        let hosting = NSHostingController(rootView: AboutView())
        let panel = NSWindow(contentViewController: hosting)
        panel.styleMask = [.titled, .closable, .fullSizeContentView]
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isReleasedWhenClosed = false
        panel.center()
        window = panel

        panel.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
    }
}

/// The About panel's content. Reads name/version/copyright from the
/// bundle so they track the build without hard-coding.
private struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
    private var copyright: String {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? ""
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            VStack(spacing: 3) {
                Text(verbatim: "Heidrun")
                    .font(.system(size: 24, weight: .semibold))
                Text("A Mac client for the Hotline protocol.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Text("Version \(version) (\(build))")
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Divider().frame(width: 200)

            VStack(spacing: 2) {
                Text(verbatim: "Original Heidrun by Göran Granström · 2002")
                Text(verbatim: "Swift 6 port by Jens Francke and Friends · 2026")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            if !copyright.isEmpty {
                Text(verbatim: copyright)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, .large)
        .padding(.top, .large)
        .padding(.bottom, .medium)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }
}
