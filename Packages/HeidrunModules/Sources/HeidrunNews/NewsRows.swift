import Foundation

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
