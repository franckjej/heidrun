# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/); the
project adheres to [Semantic Versioning](https://semver.org/).

## [1.0.5] — 2026-06-07

### Added
- Privilege-aware controls now cover **file** and **news** operations too
  (1.0.4 brought them to the admin controls). When a server reports your
  account's privileges, Download / Upload / New Folder / Rename / Delete and
  the news Post / Reply / Edit / Delete / bundle actions disable for accounts
  that aren't allowed to use them. A convenience only — the server still
  enforces every action — and fail-open on servers that don't report them.

### Fixed
- News actions the server denied (e.g. deleting a post without permission)
  used to fail silently; they now surface the server's error.

### Developer
- Protocol console: replies are correlated per connection, so two connections
  to the same server no longer mislabel each other's replies. The User Access
  push (TX 354) is labelled `userAccess`.

## [1.0.4] — 2026-06-07

### Added
- Privilege-aware admin controls. When a server reports your account's
  access privileges, the Admin tab, **Edit Account**, and **Disconnect
  User** now disable for accounts that aren't allowed to use them — instead
  of letting you try and hit a permission error. A convenience only; the
  server still enforces every privilege.

### Fixed
- Access privileges are now read in the canonical Hotline bit order, so the
  privilege-aware controls work correctly against classic Hotline servers,
  not just Heidrun's own server.

### Developer
- The protocol console labels the User Access push (TX 354) as `userAccess`
  rather than the misleading `userList`.

## [1.0.3] — 2026-06-07

### Fixed
- The user list could appear empty when connecting to some servers —
  classic Hotline/HXD servers that send a "user access" privileges
  message right after login. The roster now stays populated.
- Developer protocol console: a reply on a second simultaneous
  connection no longer shows as unknown (`???`) when both connections
  reuse the same task number.

## [1.0.2] — 2026-06-06

### Changed
- Errors now surface through one consistent alert. Failures that used to
  pass silently now tell you what happened — most visibly a chat or private
  message the server rejects (e.g. when your account isn't allowed to send),
  plus failed file, news, and account-admin actions and bookmark
  import/export.

### Fixed
- Roster desync after an automatic reconnect (e.g. when the server
  restarts): a user who joined during the reconnect could be missing from
  the user list even though chat showed them entering. The roster stays in
  sync now.

## [1.0.1] — 2026-06-05

### Added
- Undo / redo (⌘Z, ⇧⌘Z) in the chat, messages, and news composers.
- Drag to reorder bookmarks in the library.
- Copy support for the chat subject, status bar, and file-info fields.
- Keyboard shortcuts: ⌘I (user info), Spacebar (Quick Look), ⌘W.

### Changed
- Messages rebuilt on an AppKit conversation list, with Dock attention on
  incoming private messages.
- Threaded news rebuilt on AppKit panes with a persistent body divider.
- Account admin and the user editor reworked into a single unified view.
- Connection form no longer flashes on open; ⌘. cancels an in-progress
  connect. General animation and status-bar / banner layout polish.

### Fixed
- Window memory leaks: the per-window undo manager and the whole document
  scene (document, host state, table rows/cells, composers) are now
  released on window close instead of accumulating.

## [1.0.0] — 2026-05-31

Initial release. A complete Swift 6 port of the original 2002 Hotline
client, modernised for macOS 15+ while keeping wire compatibility with
classic Hotline 1.5 servers and Heidrun-server's extensions.

### Connection
- TLS connections with trust-on-first-use SHA-256 certificate pinning.
- Per-server identity (nickname, numeric icon, emoji avatar — single
  per-bookmark setting; default identity lives in Settings → Identity).
- Bookmarks live as `.heidrunbookmark` document files you can open
  from Finder, the Dock recents menu, the File → Open dialog, or by
  double-clicking in the bookmark library. Opening a file auto-
  connects to the server it describes; ⌘S saves edits with proper
  document-edited indication. Multi-bookmark connect — select
  several in the library and open them all at once, each in its own
  window. Connection → Bookmark (⌘D) toggles the focused window
  into / out of the bookmark library.
- Recent-servers list + tracker browser (UDP registration on 5499 plus
  TCP listing on 5498).
- Auto-reconnect with configurable retry count + delay.
- Session restoration on launch — re-opens the servers that were
  connected at quit (toggle in Settings).
- Confirm-before-disconnect prompt on Cmd+W / Cmd+Q while connected.
  Return confirms; Escape cancels. Closing the last window
  disconnects the session and keeps Heidrun running (Cmd+Q to quit).
- Touch ID password storage (opt-in) for saved server credentials.

### Chat & messaging
- Public chat with a selectable transcript (drag any selection out
  to Finder as a plain-text file). `hotline://`, `heidrun://`, and
  `http(s)://` URLs are clickable in chat, private messages, and
  news bodies — `hotline://` / `heidrun://` open a new connection
  in-app, http(s) hands off to the default browser.
- `/clear` slash command — wipes the local transcript without
  disconnecting or affecting other clients (replaced with a single
  system-trace line so the panel doesn't read as empty).
- Private chats — create, invite, accept, leave, change subject.
- Private messages with per-correspondent conversation threading.
- Broadcast banner (server-wide messages).
- Sound effects + system notifications for every event class, with
  per-cue Settings toggles.

### Files
- Browse + sort with per-row Finder icons derived from each file's
  HFS type / creator (installed-app associations honoured —
  `.sit` shows the StuffIt icon if installed, `.psd` shows the
  Photoshop icon, and so on).
- Drag-from / drag-to Finder for single-file transfers.
- Folder bulk transfers — download or upload an entire subtree
  in one operation, with HFS type / creator preserved.
- Mac resource forks round-trip end-to-end against Heidrun servers.
  Downloads write the rsrc to the file's native macOS resource
  fork (`..namedfork/rsrc`) so Finder, Get Info, and classic Mac
  apps see the file correctly; uploads read it back the same way.
  Negotiated via the `0xE002` Heidrun protocol extension and
  degrades gracefully (data-fork-only) against non-Heidrun servers.
- HFS type / creator codes stamped on uploads now come from each
  file's `com.apple.FinderInfo` xattr — classic Mac files (the kind
  that carry a real resource fork) keep their authentic codes
  (`APPL` / `DTSL`, `TEXT` / `ttxt`, etc.) instead of falling back
  to a generic `BINA` / `????` extension guess. The extension table
  still resolves modern files whose FinderInfo is absent or empty.
- Get Info on a remote file shows the resource-fork size alongside
  the data-fork size whenever the server reports one — a quick way
  to spot which files on a Heidrun server still carry a real rsrc
  without round-tripping them first.
- Replace / Resume / Cancel prompt when an upload collides with an
  existing server file.
- Partial-download resume via the project's own `.heidrunpart`
  sidecar files (re-opens, asks before continuing).
- Quick Look previews for selected files without downloading.

### News
- Plain bulletin-board news (read + post).
- Threaded news (browse bundles + categories, read posts, post
  top-level threads, reply with auto-derived "Re: <parent title>"
  one level deep).
- Per-post / per-thread / per-folder copy + export.

### Appearance & accessibility
- Three-step content density preset
  (**Compact** · **Standard** · **Comfortable**) with a per-preset
  body-size override (9–20pt fine-tuning) in
  Settings → Appearance.
- Light + Dark mode throughout (semantic system colours; no
  hard-coded palette).
- German + Japanese localizations alongside English.

### Window chrome
- Unified compact toolbar (icon-only) on host windows.
- Toolbar auto-hides on hover in full-screen mode.
- Sidebar wrapped in a GroupBox with a slightly wider default
  column for a cleaner read. The host sidebar's feature picker is
  an NSTableView for native row-height consistency with the
  Appearance density preset.
- Status bar shows the active login.
- Connect-form titlebar matches the host window chrome; the
  Heidrun glyph is rendered crisply at toolbar size.

### Developer
- Protocol Console window — wire-level transaction inspector
  showing every TX in + out, with class-ID-aware reply correlation.
  Off by default; enable in Settings → Developer.

### Documentation
- DMG ships with a `Documentation/` folder containing the README,
  this changelog, `LICENSE` (GPL-2.0), `NOTICE`, and
  `THIRD_PARTY_LICENSES`.
