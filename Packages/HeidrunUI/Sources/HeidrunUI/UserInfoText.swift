import HeidrunCore

/// Pure plain-text formatters for exporting a user's info (drag-out).
public enum UserInfoText {
    /// The user's name for copy/paste and mentions: the emoji avatar (if
    /// any) followed by the nickname, e.g. `🎸 silver:box`. Falls back to
    /// the bare nickname when there's no emoji. Uses the same sanitisation
    /// as rendering so a junk emoji field never bloats the copied text.
    public static func displayName(_ user: User) -> String {
        if let emoji = EmojiAvatar.sanitized(user.emoji) {
            return "\(emoji) \(user.nickname)"
        }
        return user.nickname
    }

    /// Full info, after a Get-Info fetch (includes the server profile text).
    public static func format(_ info: UserInfo) -> String {
        let account = info.accountLogin.isEmpty ? "—" : info.accountLogin
        let profile = info.infoText.isEmpty ? "—" : info.infoText
        return """
        Nickname: \(displayName(info.user))
        Account: \(account)
        Socket: \(info.user.socket)
        Status: \(info.user.status.flags.displayLabel)

        Profile:
        \(profile)
        """
    }

    /// Basic info available from the user-list row alone (no fetch / no
    /// server profile text).
    public static func basic(_ user: User) -> String {
        """
        Nickname: \(displayName(user))
        Socket: \(user.socket)
        Status: \(user.status.flags.displayLabel)
        """
    }
}
