import SwiftUI
import HeidrunUI
import CommonTools

/// Picker for the local "user list theme" banner. Banners are decorative
/// stripes painted behind the whole user list — purely a local
/// preference, never sent over the wire. `bannerID == 0` means "no
/// banner" and the picker exposes a "None" row at the top so users can
/// turn the theme off.
struct BannerPickerButton: View {
    @Binding var bannerID: UInt16
    @State private var showingPicker = false

    var body: some View {
        Button {
            showingPicker.toggle()
        } label: {
            HStack(spacing: Spacing.xsmall.rawValue) {
                BannerTriggerPreview(id: Int(bannerID))
                Text(triggerLabel)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, .xsmall)
            .padding(.vertical, .xxsmall)
            .overlay(
                RoundedRectangle(cornerRadius: .cornerMed, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
            BannerPickerPopover(selectedID: Binding(
                get: { Int(bannerID) },
                set: { bannerID = UInt16(clamping: $0) }
            )) {
                showingPicker = false
            }
            .frame(width: 360, height: 380)
        }
    }

    private var triggerLabel: String {
        if bannerID == 0 { return String(localized: "None") }
        return IconCatalog.shared.banners.label(forID: Int(bannerID)) ?? "Banner #\(bannerID)"
    }
}

private struct BannerPickerPopover: View {
    @Binding var selectedID: Int
    let onPick: () -> Void

    @State private var query: String = ""

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
                LazyVStack(alignment: .leading, spacing: 4) {
                    BannerRow(id: 0, label: String(localized: "None"), isSelected: selectedID == 0) {
                        selectedID = 0
                        onPick()
                    }

                    ForEach(filteredEntries, id: \.id) { entry in
                        BannerRow(
                            id: entry.id,
                            label: entry.label.isEmpty ? "#\(entry.id)" : entry.label,
                            isSelected: entry.id == selectedID
                        ) {
                            selectedID = entry.id
                            onPick()
                        }
                    }
                }
                .padding(.vertical, .xxsmall)
            }
        }
        .padding(.small)
    }

    private var filteredEntries: [IconCatalogEntry] {
        let all = IconCatalog.shared.banners.allEntries
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return all }
        let needle = trimmed.lowercased()
        if let queryID = Int(trimmed) {
            return all.filter { $0.id == queryID || $0.label.lowercased().contains(needle) }
        }
        return all.filter { $0.label.lowercased().contains(needle) }
    }
}

/// One row in the banner picker. The 16x1 stripe is stretched to a wide
/// preview rectangle so the user sees the same color pattern they'll get
/// behind the user list.
private struct BannerRow: View {
    let id: Int
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                BannerTriggerPreview(id: id, width: 120)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .lineLimit(1)
                    Group {
                        if id == 0 {
                            Text("no backdrop")
                        } else {
                            Text(verbatim: "ID \(id)")
                        }
                    }
                    .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, .xsmall)
            .padding(.vertical, .xxxsmall)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Compact banner swatch used in the trigger button and picker rows. For
/// `id == 0` or unknown IDs, shows a hollow "no banner" placeholder.
private struct BannerTriggerPreview: View {
    let id: Int
    var width: CGFloat = 56

    var body: some View {
        Group {
            if id != 0, let cgImage = IconCatalog.shared.banners.cgImage(forID: id) {
                Image(decorative: cgImage, scale: 1, orientation: .up)
                    .resizable()
                    .interpolation(.medium)
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(.separator, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .background(Color.clear)
            }
        }
        .frame(width: width, height: 16)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}
