import SwiftUI

/// Classic Hotline 256-entry user-name colour palette, bundled as
/// `Resources/user_colors.data` (the same blob shipped by the original
/// Heidrun and by Hotline Communications' reference client).
///
/// Wire format — 2056 bytes total: a 10-byte preamble, then 255 entries
/// of 8 bytes each. Each entry is `UInt16 id` followed by three
/// `UInt16` channels (R, G, B), big-endian. Only the upper byte of
/// each channel is significant, matching the classic 6×6×6 web-safe
/// cube the palette encodes. `paletteID == 0` is the implicit
/// "no preference" slot and resolves to `nil` rather than a colour, so
/// callers can fall back to whatever default the surrounding UI wants.
///
/// Servers set `UserStatus.color` per user; admin/sysOp roles
/// typically come through as palette ID 36 (#ff0000), which is why the
/// classic Hotline UI shows admins in bright red without any
/// client-side flag check.
public enum UserColorPalette {
    /// Look up the colour the server assigned to a user. Returns `nil`
    /// for ID 0 (the unset/default slot) so the caller can supply its
    /// own default — typically `.primary`.
    public static func color(forID paletteID: UInt8) -> Color? {
        guard paletteID != 0, paletteID < entries.count else { return nil }
        return entries[Int(paletteID)]
    }

    /// Lazily-decoded palette. `nil` for index 0 (the "unset" slot)
    /// and for any index past the end of the bundled blob (defensive —
    /// the real file is always 255 entries).
    private static let entries: [Color?] = loadEntries()

    private static func loadEntries() -> [Color?] {
        guard let bundleURL = Bundle.module.url(forResource: "user_colors", withExtension: "data"),
              let blob = try? Data(contentsOf: bundleURL) else {
            return Array(repeating: nil, count: 256)
        }
        let preamble = 10
        let stride = 8
        let entryCount = max(0, (blob.count - preamble) / stride)
        var result: [Color?] = Array(repeating: nil, count: 256)
        for paletteID in 1...255 where paletteID <= entryCount {
            // Per HEClient.m -getColorForPaletteID: the entry is laid
            // out as [UInt16 id][UInt16 R][UInt16 G][UInt16 B] but the
            // lookup formula skips the leading id field and reads RGB
            // directly: `offset = 8*(pID-1) + 10`.
            let offset = preamble + (paletteID - 1) * stride
            let red = blob.upperByte(at: offset)
            let green = blob.upperByte(at: offset + 2)
            let blue = blob.upperByte(at: offset + 4)
            result[paletteID] = Color(
                .sRGB,
                red: Double(red) / 255,
                green: Double(green) / 255,
                blue: Double(blue) / 255,
                opacity: 1
            )
        }
        return result
    }
}

private extension Data {
    /// Read the upper byte of a 16-bit big-endian channel — the
    /// classic palette stores 16 bits per channel but the low byte is
    /// always zero, so only the high byte is meaningful for display.
    func upperByte(at offset: Int) -> UInt8 {
        guard offset >= 0, offset < count else { return 0 }
        return self[startIndex + offset]
    }
}
