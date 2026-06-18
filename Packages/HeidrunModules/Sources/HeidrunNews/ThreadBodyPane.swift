import SwiftUI
import HeidrunCore
import HeidrunUI
import CommonTools

/// The read pane for the selected post's body. Split out of
/// `ThreadedNewsScreen` so the body-load lifecycle (`isLoadingBody`,
/// `loadedThread`) only invalidates this subtree — keeping body fetches
/// from recreating the sibling `ThreadOutlineView`.
struct ThreadBodyPane: View {
    let viewModel: ThreadedNewsViewModel
    @Binding var replyTarget: NewsThread?

    var body: some View {
        if viewModel.isLoadingBody {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let thread = viewModel.loadedThread, let element = thread.elements.first {
            ScrollView {
                // `Spacing.xsmall` (8pt) between the header row, the
                // hairline divider, and the body — so the divider does
                // the visual-separation work and the gap on each side
                // is breathing room, not a full margin.
                VStack(alignment: .leading, spacing: Spacing.xsmall.rawValue) {
                    HStack(spacing: Spacing.xsmall.rawValue) {
                        if let author = element.author.nonEmpty {
                            Label(author, systemImage: "person.fill")
                                .labelStyle(.titleAndIcon)
                        }
                        if let display = thread.postDate.displayableAbsolute {
                            Text(display)
                        }
                        Spacer()
                        Button {
                            replyTarget = thread
                        } label: {
                            Label(String(localized: "Reply…", bundle: .module), systemImage: "arrowshape.turn.up.left")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .heidrunCaption()
                    .foregroundStyle(.secondary)

                    Divider()

                    if let body = element.body.nonEmpty {
                        Text(linkifyAttributed(body))
                            .heidrunBody()
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .environment(\.openURL, OpenURLAction { url in
                                // hotline/heidrun → in-app dispatch (no extra
                                // empty window); everything else (http(s))
                                // falls to the system default.
                                HotlineLinkClick.post(url) ? .handled : .systemAction
                            })
                    } else {
                        Text("(empty)", bundle: .module)
                            .heidrunBody()
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView(
                String(localized: "No Thread Selected", bundle: .module),
                systemImage: "doc.text",
                description: Text("Pick a thread above to read its body here.", bundle: .module)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Build an `AttributedString` with `.link` runs on hotline/heidrun/http(s)
    /// URLs so `Text` clicks dispatch through `.onOpenURL` → connection. The
    /// threaded-news-body counterpart to SelectableTranscript.
    private func linkifyAttributed(_ body: String) -> AttributedString {
        var attributed = AttributedString(body)
        for link in HotlineLinkDetector.scan(body) {
            let nsRange = NSRange(link.range, in: body)
            guard let attributedRange = Range(nsRange, in: attributed) else { continue }
            attributed[attributedRange].link = link.url
        }
        return attributed
    }
}
