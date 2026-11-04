import SwiftUI
import CommonTools
import HeidrunBookmarks

/// "Bookmarks menu" group in the connect form: None / ⌃⌘1 … ⌃⌘9.
/// Taken slots show their owner, including the edited bookmark's own slot.
struct MenuShortcutPicker: View {
    @Binding var slot: Int?
    let labelColumnWidth: CGFloat
    /// Display name of the bookmark holding a slot, if any.
    let ownerName: (Int) -> String?

    var body: some View {
        GroupBox {
            HStack(alignment: .center, spacing: 10) {
                Text("Shortcut")
                    .frame(width: labelColumnWidth, alignment: .trailing)
                    .foregroundStyle(.secondary)
                Picker("", selection: $slot) {
                    Text("None").tag(Int?.none)
                    ForEach(Array(Bookmark.menuShortcutSlotRange), id: \.self) { candidate in
                        Text(verbatim: optionTitle(for: candidate)).tag(Int?.some(candidate))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 200, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(.xxsmall)
        } label: {
            Label("Bookmarks menu", systemImage: "keyboard")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private func optionTitle(for candidate: Int) -> String {
        let glyph = "⌃⌘\(candidate)"
        guard let owner = ownerName(candidate) else { return glyph }
        return "\(glyph) — \(owner)"
    }
}
