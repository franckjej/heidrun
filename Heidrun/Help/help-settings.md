# Settings

Settings live in the standard macOS Preferences window (**Heidrun → Settings…**, ⌘,). They're organised into a few groups.

## General

- **Default nickname** and **default icon** are pre-filled into the Connect form for new connections (bookmarks override them per server).
- **Reopen connections on launch** restores whatever servers you were connected to when you last quit. Disabling this clears the saved snapshot at quit and starts the next launch with no live windows.
- **Auto-reconnect on network drop** controls whether Heidrun retries a connection that died unexpectedly. The backoff schedule is fixed (the coordinator caps retries) — you can disable it entirely if you prefer manual control.

## Downloads

- **Download location** — the folder partial and finished downloads land in. Heidrun needs filesystem access to write there; the first time you change it the system asks for permission.
- **Retry failed downloads** automatically restarts a transfer once if the server drops the side-channel TCP. Honoured by the existing resume mechanism (the partial file's xattr remembers the source).
- **Use `.heidrunpart` extension while downloading** keeps Finder and Spotlight from treating an in-progress file as the real thing.

## Notifications

- **Show banners** controls whether Heidrun posts macOS notifications for chat, private messages, file completions, etc. Per-event toggles let you mute specific kinds without disabling all notifications.
- **Bounce Dock** flashes the Dock icon when something noteworthy happens while the app is in the background.

The first time Heidrun posts a notification, macOS prompts for permission — granted at the OS level, never inside the app.

## Privacy

- **Block private messages from non-contacts** ignores PMs from anyone you haven't deliberately exchanged messages with.
- **Send keepalive pings** keeps the connection lively on servers with strict idle timeouts. The protocol's ping (transaction 500) is sent every 30 seconds when enabled.

## Advanced

- **String encoding** defaults to **macOS Roman** for compatibility with old Hotline servers. Modern servers may speak UTF-8 — switch if you see garbled non-ASCII names or chat.
- **Resource fork policy** is "drop" — modern macOS doesn't use them and Heidrun doesn't round-trip them. The setting exists for completeness; leave it on the default.

Settings are stored in your app's `UserDefaults`; resetting to defaults via `defaults delete <bundle>` is **not** safe — that wipes bookmarks, saved sessions, and every other `@AppStorage` value. To reset window state alone, clear `~/Library/Saved Application State/<bundle>.savedState` instead.
