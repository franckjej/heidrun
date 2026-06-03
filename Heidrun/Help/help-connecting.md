# Connecting & Agreements

Heidrun connects to Hotline servers over TCP. Every connection starts from the **Connect** window — accessed from the Connection menu, from a bookmark, or by opening a saved `.heidrunbookmarks` file.

## Filling in the form

- **Server** is the host name or IP address. Optional `:port` suffix; the default is `5500`.
- **Login** and **Password** identify your account. For guest access leave both blank.
- **Nickname** and **Icon** are what other users on the server will see. Pick an icon with the small grid button next to the name.
- **Remember password** stores the password in the macOS Keychain so subsequent connects don't prompt.

## What happens behind the scenes

When you press **Connect**, Heidrun:

1. Opens the TCP socket and waits up to 15 seconds for the server to accept.
2. Sends the Hotline magic-byte handshake.
3. Sends your login and password (XOR-obfuscated as the protocol requires).
4. If the server pushes an agreement banner, the agreement sheet appears over the host window so you can read and accept (or decline) it.

If the server doesn't push an agreement, Heidrun goes straight to the host view — no waiting for a timeout.

## Agreements

Servers can require you to acknowledge an agreement (rules, code of conduct, motd) before chatting. The agreement sheet shows:

- The full text the server sent.
- **Accept** — dismisses the sheet; you stay connected.
- **Decline** — disconnects immediately.

Some servers send an "auto-agree" flag, which lets compliant clients skip the prompt. Heidrun still shows the sheet for transparency, but Accept is the obvious default.

## Auto-reconnect & session restoration

When a connection drops unexpectedly, Heidrun's auto-reconnect policy retries with backoff if the failure looks recoverable. If you Quit while still connected, those connections are restored automatically on the next launch — disable this in **Settings → General** if you'd rather start fresh each time.

## Troubleshooting

- **"Couldn't connect"** after 15 seconds usually means the host or port is wrong, the server is offline, or a firewall is dropping the SYN.
- **Authentication failure** at login indicates a bad password or a missing/banned account — verify with the server admin.
- **Disconnects mid-session** are sometimes the server's idle timeout. Heidrun sends a keep-alive ping every 30 seconds to keep the socket lively, but old servers may still drop quiet clients.
