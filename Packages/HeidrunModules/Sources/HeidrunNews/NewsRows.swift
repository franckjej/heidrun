import SwiftUI
import CommonTools
import HeidrunCore
import HeidrunUI

// MARK: - Rows

struct BundleRow: View {
    let bundle: NewsBundle
    let isSelected: Bool

    private var iconName: String {
        bundle.kind == .bundle ? "folder.fill" : "tray.full.fill"
    }

    private var iconTint: Color {
        bundle.kind == .bundle ? .accentColor : .secondary
    }

    var body: some View {
        HStack(spacing: Spacing.xsmall.rawValue) {
            Image(systemName: iconName)
                .foregroundStyle(isSelected ? Color.white : iconTint)
                .frame(width: 16)

            Text(bundle.title.isEmpty ? "(untitled)" : bundle.title)
                .lineLimit(1)
                .foregroundStyle(isSelected ? Color.white : .primary)

            Spacer(minLength: Spacing.xxsmall.rawValue)

            if bundle.size > 0 {
                Text("(\(bundle.size))")
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : .secondary)
            }
        }
        .heidrunBody()
        .padding(.vertical, .xsmall)
        .padding(.horizontal, .xsmall)
        .background(
            RoundedRectangle(cornerRadius: .cornerMed, style: .continuous)
                .fill(isSelected ? Color.accentColor : .clear)
        )
    }
}

struct ThreadRow: View {
    let thread: NewsThread
    let depth: Int
    let isSelected: Bool

    private var title: String {
        thread.elements.first?.title.nonEmpty ?? "Untitled"
    }

    private var author: String? {
        thread.elements.first?.author.nonEmpty
    }

    private var sizeText: String? {
        guard let size = thread.elements.first?.size, size > 0 else { return nil }
        return "\(size) B"
    }

    var body: some View {
        HStack(spacing: Spacing.xsmall.rawValue) {
            // Indent per reply depth. `Spacing.medium` (24pt) per level
            // (vs. the previous 16pt) so deep chains read as clearly
            // nested rather than "barely offset". Matches the Mail /
            // Slack hierarchy step.
            if depth > 0 {
                Spacer().frame(width: CGFloat(depth) * Spacing.medium.rawValue)
            }
            Image(systemName: depth == 0 ? "text.bubble.fill" : "arrow.turn.down.right")
                .foregroundStyle(isSelected ? Color.white : (depth == 0 ? Color.accentColor : .secondary))
                .frame(width: 16)

            Text(title)
                .lineLimit(1)
                .foregroundStyle(isSelected ? Color.white : .primary)

            Spacer(minLength: Spacing.xxsmall.rawValue)

            if let author {
                Text(author)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : .secondary)
            }
            if let sizeText {
                Text(sizeText)
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : .secondary)
                    .frame(width: 50, alignment: .trailing)
            }
            if let display = thread.postDate.displayableAbsolute {
                Text(display)
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : .secondary)
            }
        }
        .heidrunBody()
        .padding(.vertical, .xsmall)
        .padding(.horizontal, .xsmall)
        .background(
            RoundedRectangle(cornerRadius: .cornerMed, style: .continuous)
                .fill(isSelected ? Color.accentColor : .clear)
        )
    }
}

// MARK: - Reply nesting

/// One row in the thread tree — a thread plus its depth in the reply
/// chain. `parentID == 0` means "root reply" (depth 0); deeper rows are
/// children of an earlier row.
struct ThreadNode: Identifiable {
    let thread: NewsThread
    let depth: Int
    var id: UInt16 { thread.threadID }
}

/// Flatten the thread list into display order, indenting each row by its
/// depth in the parentID chain. Threads whose `parentID` doesn't match
/// any thread in the input (orphans) are promoted to root.
func buildThreadTree(_ threads: [NewsThread]) -> [ThreadNode] {
    let knownIDs = Set(threads.map(\.threadID))
    let byParent: [UInt16: [NewsThread]] = Dictionary(grouping: threads) { thread in
        knownIDs.contains(thread.parentID) ? thread.parentID : 0
    }
    var result: [ThreadNode] = []
    func walk(parent: UInt16, depth: Int) {
        let children = (byParent[parent] ?? []).sorted { $0.postDate < $1.postDate }
        for child in children {
            result.append(ThreadNode(thread: child, depth: depth))
            walk(parent: child.threadID, depth: depth + 1)
        }
    }
    walk(parent: 0, depth: 0)
    return result
}

// MARK: - Helpers

extension String {
    /// `nil` when this string is empty, otherwise itself. Lets call sites
    /// say `text.nonEmpty ?? "Untitled"`. Module-internal so the news
    /// row views and the body pane share it.
    var nonEmpty: String? { isEmpty ? nil : self }
}

extension Date {
    /// Reasonable cutoff for "we think this date came back broken".
    /// Hotline didn't exist before 1996; anything before 1990 is
    /// definitely a wire-decode glitch (typical symptom: `.distantPast`).
    private static let plausibleEpoch = Date(timeIntervalSince1970: 631152000) // 1990-01-01

    /// Relative-style description, or `nil` if the date is implausibly old.
    var displayableRelative: String? {
        guard self >= Self.plausibleEpoch else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: .now)
    }

    /// Absolute-style description, or `nil` if the date is implausibly old.
    var displayableAbsolute: String? {
        guard self >= Self.plausibleEpoch else { return nil }
        return formatted(date: .abbreviated, time: .shortened)
    }
}
