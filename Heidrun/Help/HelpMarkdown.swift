import SwiftUI
import CommonTools

/// Tiny block-level markdown renderer for Heidrun's bundled help
/// pages. We don't ship a full markdown engine — SwiftUI's
/// `LocalizedStringKey`-backed `Text` already handles inline markdown
/// (bold, italic, links) for free, so we only need to recognise the
/// block-level constructs our help pages actually use:
///
/// - `# Heading`     → large title
/// - `## Heading`    → section title
/// - `### Heading`   → subsection title
/// - `- item`        → bullet line
/// - blank line      → paragraph separator
/// - everything else → paragraph (rendered with inline markdown)
enum HelpMarkdown {

    /// One renderable chunk of a help document.
    enum Block: Identifiable {
        case heading(level: Int, text: String, id: UUID = UUID())
        case bullet(text: String, id: UUID = UUID())
        case paragraph(text: String, id: UUID = UUID())

        var id: UUID {
            switch self {
            case .heading(_, _, let id),
                 .bullet(_, let id),
                 .paragraph(_, let id):
                return id
            }
        }
    }

    /// Parse a markdown blob into a flat list of blocks. Lines are
    /// joined into paragraphs across non-empty lines so wrapping in
    /// the source file doesn't introduce hard breaks in the rendered
    /// output — same convention as the actual CommonMark spec.
    static func parse(_ source: String) -> [Block] {
        var blocks: [Block] = []
        var paragraphBuffer: [String] = []

        func flushParagraph() {
            guard !paragraphBuffer.isEmpty else { return }
            let text = paragraphBuffer.joined(separator: " ")
            blocks.append(.paragraph(text: text))
            paragraphBuffer.removeAll(keepingCapacity: true)
        }

        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph()
                continue
            }
            if line.hasPrefix("### ") {
                flushParagraph()
                blocks.append(.heading(level: 3, text: String(line.dropFirst(4))))
            } else if line.hasPrefix("## ") {
                flushParagraph()
                blocks.append(.heading(level: 2, text: String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                flushParagraph()
                blocks.append(.heading(level: 1, text: String(line.dropFirst(2))))
            } else if line.hasPrefix("- ") {
                flushParagraph()
                blocks.append(.bullet(text: String(line.dropFirst(2))))
            } else {
                paragraphBuffer.append(line)
            }
        }
        flushParagraph()
        return blocks
    }
}

/// Renders a help document — file name without extension — as a
/// vertical stack of blocks. Loads the bundled markdown lazily once
/// per topic and re-renders the parsed blocks; missing files fall
/// back to a clear placeholder so a typo in `HelpTopic.fileName`
/// surfaces in the UI rather than silently showing nothing.
struct HelpDocumentView: View {
    let topic: HelpTopic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(blocks) { block in
                    render(block)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.medium)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func render(_ block: HelpMarkdown.Block) -> some View {
        switch block {
        case let .heading(level, text, _):
            Text(text)
                .font(headingFont(for: level))
                .fontWeight(.semibold)
                .padding(.top, level == 1 ? 0 : 8)
        case let .bullet(text, _):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .foregroundStyle(.secondary)
                Text(LocalizedStringKey(text))
                Spacer(minLength: 0)
            }
        case let .paragraph(text, _):
            Text(LocalizedStringKey(text))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1:
            return .largeTitle
        case 2:
            return .title2
        default:
            return .headline
        }
    }

    private var blocks: [HelpMarkdown.Block] {
        guard let url = Bundle.main.url(forResource: topic.fileName, withExtension: "md"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return [.paragraph(text: "_Help content missing for \(topic.displayName)._")]
        }
        return HelpMarkdown.parse(text)
    }
}
