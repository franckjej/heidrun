import SwiftUI
import HeidrunUI
import CommonTools

/// Compact icon picker: shows the current icon thumbnail and opens a
/// popover with a searchable grid sourced from `IconCatalog.shared`.
/// Use anywhere a Hotline user-icon ID needs to be picked (agreement
/// sheet, settings, future profile editor) instead of exposing the raw
/// numeric ID via a stepper.
struct IconPickerButton: View {
    @Binding var iconID: UInt16
    @State private var showingPicker = false

    var body: some View {
        Button {
            showingPicker.toggle()
        } label: {
            HStack(spacing: Spacing.xsmall.rawValue) {
                IconThumbnail(id: Int(iconID), size: 28)
                Text(IconCatalog.shared.icons.label(forID: Int(iconID)) ?? "Pick an Icon")
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
            IconPickerPopover(selectedID: Binding(
                get: { Int(iconID) },
                set: { iconID = UInt16(clamping: $0) }
            )) {
                showingPicker = false
            }
            .frame(width: 360, height: 380)
        }
    }
}

private struct IconPickerPopover: View {
    @Binding var selectedID: Int
    let onPick: () -> Void

    @State private var query: String = ""

    private let columns = [GridItem(.adaptive(minimum: 52, maximum: 64), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxsmall.rawValue) {
            HStack(spacing: Spacing.xxsmall.rawValue) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter by name or ID", text: $query)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    ForEach(filteredEntries, id: \.id) { entry in
                        Button {
                            selectedID = entry.id
                            onPick()
                        } label: {
                            VStack(spacing: 2) {
                                IconThumbnail(id: entry.id, size: 32)
                                Text(verbatim: "\(entry.id)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.xxsmall)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(entry.id == selectedID
                                          ? Color.accentColor.opacity(0.25)
                                          : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(entry.id == selectedID ? Color.accentColor : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                        .help(entry.label.isEmpty ? "ID \(entry.id)" : "\(entry.label) (ID \(entry.id))")
                    }
                }
                .padding(.vertical, .xxsmall)
            }

            Divider()
            selectedDetail
        }
        .padding(.small)
    }

    /// Metadata for the current selection (label · ID · pixel size), so the
    /// picker doubles as the icon-ID/size reference the gallery used to be.
    @ViewBuilder
    private var selectedDetail: some View {
        if let chosen = IconCatalog.shared.icons.entry(forID: selectedID) {
            HStack(spacing: Spacing.xsmall.rawValue) {
                IconThumbnail(id: chosen.id, size: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text(chosen.label.isEmpty ? "(no label)" : chosen.label)
                        .font(.caption)
                        .lineLimit(1)
                    Text(verbatim: "ID \(chosen.id) · \(chosen.width)×\(chosen.height)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        } else {
            Text("Icon ID \(selectedID) is not in the bundled catalog")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var filteredEntries: [IconCatalogEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let all = IconCatalog.shared.icons.allEntries
        guard !trimmed.isEmpty else { return all }
        let needle = trimmed.lowercased()
        if let queryID = Int(trimmed) {
            return all.filter { $0.id == queryID || $0.label.lowercased().contains(needle) }
        }
        return all.filter { $0.label.lowercased().contains(needle) }
    }
}

/// Renders the bundled icon for `id`, falling back to an SF Symbol when
/// the catalog has no entry. Pixel-aligned (`.interpolation(.none)`) so
/// the original 16×16 / 32×32 PNGs stay crisp when scaled.
struct IconThumbnail: View {
    let id: Int
    var size: CGFloat = 32

    var body: some View {
        if let cgImage = IconCatalog.shared.icons.cgImage(forID: id) {
            Image(decorative: cgImage, scale: 1, orientation: .up)
                .interpolation(.none)
                .resizable()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "person.crop.square")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(.secondary)
        }
    }
}
