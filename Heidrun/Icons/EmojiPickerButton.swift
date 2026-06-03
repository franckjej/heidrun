import SwiftUI
import AppKit
import HeidrunUI
import CommonTools

/// Picks a single emoji used as the user's avatar overlay.
///
/// Implementation note: an earlier version handed the job off to the
/// system Character Palette (`NSApp.orderFrontCharacterPalette(_:)`)
/// and tried to capture the pick via a hidden 1×1 `TextField`. That
/// pattern was a focus race — `@FocusState` propagates async, so when
/// the palette opened with the button still first responder, picks
/// could land on the previous text field (or nowhere) and the
/// `@AppStorage` write never happened. This rewrite mirrors
/// `IconPickerButton`: a self-contained popover, fed by the bundled
/// Unicode catalog (`EmojiCatalog`). Each pick writes the binding
/// directly from a `Button` action — no focus juggling, no draft layer.
struct EmojiPickerButton: View {
    @Binding var emoji: String
    @State private var showingPicker = false

    var body: some View {
        Button {
            showingPicker.toggle()
        } label: {
            HStack(spacing: Spacing.xsmall.rawValue) {
                Text(emoji.isEmpty ? "—" : emoji)
                    .font(.system(size: 24))
                    .frame(width: 28, height: 28)
                Text(emoji.isEmpty ? "Pick an emoji" : "Change emoji…")
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, .xsmall)
            .padding(.vertical, .xxsmall)
            .overlay {
                RoundedRectangle(cornerRadius: .cornerMed, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
            EmojiPickerPopover(
                selectedEmoji: $emoji,
                onPick: { showingPicker = false }
            )
            .frame(width: 380, height: 440)
        }
    }
}

private struct EmojiPickerPopover: View {
    @Binding var selectedEmoji: String
    let onPick: () -> Void

    @State private var searchQuery: String = ""
    @FocusState private var searchFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 36, maximum: 44), spacing: 4)]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xsmall.rawValue) {
            searchBar
                .padding(.horizontal, .small)
                .padding(.top, .small)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.xsmall.rawValue, pinnedViews: [.sectionHeaders]) {
                    if searchQuery.isEmpty {
                        ForEach(EmojiCatalog.all, id: \.group) { entry in
                            Section {
                                emojiGrid(emojis: entry.emojis)
                            } header: {
                                sectionHeader(Self.localizationKey(for: entry.group))
                            }
                        }
                    } else {
                        Section {
                            emojiGrid(emojis: filteredEmojis)
                        } header: {
                            sectionHeader("Results")
                        }
                    }
                }
                .padding(.horizontal, .small)
                .padding(.bottom, .small)
            }
        }
        .onAppear { searchFocused = true }
    }

    private var searchBar: some View {
        HStack(spacing: Spacing.xsmall.rawValue) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search emojis", text: $searchQuery)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .onSubmit { commitFirstMatch() }
            if !selectedEmoji.isEmpty {
                Button("Clear") {
                    selectedEmoji = ""
                    onPick()
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func sectionHeader(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, .xxsmall)
            .background(.background)
    }

    private func emojiGrid(emojis: [CatalogEmoji]) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
            ForEach(emojis, id: \.glyph) { entry in
                Button {
                    commit(entry.glyph)
                } label: {
                    Text(entry.glyph)
                        .font(.system(size: 22))
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(entry.glyph == selectedEmoji
                                      ? Color.accentColor.opacity(0.25)
                                      : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(entry.name)
            }
        }
    }

    private var filteredEmojis: [CatalogEmoji] {
        let needle = searchQuery
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        guard !needle.isEmpty else { return [] }
        var matches: [CatalogEmoji] = []
        for entry in EmojiCatalog.all {
            for emoji in entry.emojis where emoji.name.lowercased().contains(needle) {
                matches.append(emoji)
            }
        }
        return matches
    }

    private func commitFirstMatch() {
        if let first = filteredEmojis.first {
            commit(first.glyph)
        }
    }

    private func commit(_ glyph: String) {
        selectedEmoji = glyph
        onPick()
    }

    /// Literal keys so `xcstringstool extract` can see every group name —
    /// runtime `LocalizedStringKey(entry.group.displayName)` would be
    /// invisible to the extractor and the headers would stay English.
    private static func localizationKey(for group: EmojiGroup) -> LocalizedStringKey {
        switch group {
        case .smileysEmotion:
            "Smileys & Emotion"
        case .peopleBody:
            "People & Body"
        case .animalsNature:
            "Animals & Nature"
        case .foodDrink:
            "Food & Drink"
        case .travelPlaces:
            "Travel & Places"
        case .activities:
            "Activities"
        case .objects:
            "Objects"
        case .symbols:
            "Symbols"
        case .flags:
            "Flags"
        }
    }
}
