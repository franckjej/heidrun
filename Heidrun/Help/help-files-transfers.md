# Files & Transfers

The **Files** module is the connected user's view into the server's shared file tree. Browse, download, upload, rename, comment, and queue everything from one pane.

## Browsing the tree

- The left column is your current location; double-click a folder to descend.
- The path bar at the top shows where you are; click any segment to jump back.
- Each entry displays size, modification date, and (for files) the server's stored type / creator codes.

Right-clicking a row opens a context menu with Download, Show Info, Comment, Rename, and Delete actions — gated by your server-side privileges.

## Downloading

Use **Download** from the toolbar, context menu, or by double-clicking a file. Heidrun:

1. Asks the server for a transfer slot (transaction 202).
2. Opens a second TCP connection on the server's side-channel port.
3. Streams the file's data fork into a `.heidrunpart` file inside your Downloads folder. The `.heidrunpart` extension carries an extended-attribute payload that lets you resume the download later if the network drops.
4. Renames `.heidrunpart` to the final filename on success.

Cancel any active transfer from the **Task Manager** window — Heidrun sends transaction 214 so the server frees its queue slot immediately, no waiting for TCP to drop.

### Resuming

Double-clicking a `.heidrunpart` file in Finder opens Heidrun's Resume sheet: it shows the source server, remote path, how much you already have, and a Resume button that reconnects and continues from the right byte offset. Files Heidrun can't read (e.g., the xattr was stripped) get a separate prompt offering to Reveal or Delete.

## Uploading

Drag a file onto the Files pane or press **Upload**. Heidrun frames the file with the canonical `FILP / INFO / DATA / MACR` envelope and streams the data fork. Resource forks are intentionally dropped — modern macOS doesn't use them.

For folders, Heidrun walks the directory tree client-side and uploads each item with the folder upload handshake variant.

## Task Manager

The **Task Manager** window (⌥⌘T) lists every connection and every in-flight or recently-finished transfer across them.

- **Servers pane** — one row per open connection. Buttons bring the host window forward, disconnect, reconnect, or remove a tombstone.
- **Transfers pane** — running, completed, or failed transfers from any server. Selection lets you cancel a running transfer, resume a failed download, or reveal a finished one in Finder.
- The footer shows aggregate ↓ / ↑ byte rates across all connections.

## Privileges

Many file actions require server privileges:

- **Download files / folders** — read access.
- **Upload files / folders** — write access in the current path.
- **Rename / Move / Delete** — admin-style flags.
- **Comment** — sysop typically.

When a button is greyed out or an action errors with "no permission", check your account on the server.
