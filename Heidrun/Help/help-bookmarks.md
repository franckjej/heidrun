# Bookmarks

Bookmarks are saved connection settings — a one-click way back into a server you visit regularly.

## Creating a bookmark

From the Bookmarks menu pick **Add Bookmark…** while connected, or open **Bookmarks → Manage…** and click **+**. A bookmark captures:

- Server name and address (`host:port`).
- Login, nickname, and icon ID.
- Whether the password is remembered (stored in the macOS Keychain, not in the bookmark file itself).

You can edit any field later from the manage window. **Auto-connect at launch** is a per-bookmark flag — leave it off unless you really want Heidrun to dial that server every time it opens.

## Opening a bookmark

- The **Bookmarks** menu lists every saved bookmark; pick one to open a new connection window with its settings pre-filled.
- A keyboard shortcut can be assigned per bookmark via the manage window.
- Bookmarks also accept drag-and-drop reordering, and Heidrun preserves whatever order you set.

## Sharing & importing

Bookmarks export to a `.heidrunbookmarks` file from the manage window's **Export…** action. Double-clicking such a file imports it — Heidrun shows what's inside before adding anything to your list. The legacy `.hlbm` format the original Heidrun used is also recognised.

## Where they live

Internally bookmarks are stored in your app sandbox alongside other Heidrun state, and the **Remember password** flag puts the password in the macOS Keychain under a key derived from `(address, port, login)`. Deleting a bookmark removes the entry; the keychain item is purged on the next save.
