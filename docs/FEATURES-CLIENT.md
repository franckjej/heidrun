# Heidrun — the Client

*A feature tour for Hotline people, written by one of us.*

If you ever spent a late night picking your user icon, hammering a tracker for a
server that wasn't full, and waiting on a queue for that one file — this is for
you. Heidrun is a Hotline client, rebuilt from the ground up for modern macOS,
but it still speaks the same wire protocol the old Mac clients did. Same world,
new boat. Here's what's aboard.

---

## Getting on a server

- **The Connect window you remember.** Name, Address, Port, Nickname, Login,
  Password — laid out the way Hotline always did it. Leave Login and Password
  blank to walk in as a guest.
- **Bookmarks.** Save the servers you keep coming back to. Double-click a
  bookmark to connect straight away. Right-click to duplicate or delete.
- **Import / export your bookmarks.** Bring your old list in (legacy Heidrun
  `.htl` format), or export to share — as a Heidrun bookmark file or plain CSV.
- **Recent servers.** A dropdown of where you've been lately, so you don't have
  to retype an address you hit yesterday.
- **Pick your nickname per connection**, and it defaults to your Mac's name so
  you're never "unnamed" by accident.
- **Auto-reconnect.** Set it per bookmark or globally: never reconnect, always
  reconnect, or follow the default. It only kicks in when a live connection
  *drops* — a kick or a bad login is never retried, the way it should be.
- **Reopen on launch.** Quit with servers open and have them come back next time
  you start the app.

## Trackers

- **Browse trackers** in their own window or right from the Connect sheet.
- **Live server list** with Name, Address, Port, and user counts — sortable by
  any column.
- **Filter as you type** to cut a big tracker down to the one you're after.
- **Edit your tracker list.** Add or remove tracker hosts; the app ships with
  sensible defaults.
- **Double-click to connect** (or to drop the server into the Connect form).
- Honest error reporting — if a tracker times out or refuses, it tells you,
  rather than just spinning.

## Encrypted connections (the new bit)

Old Hotline traffic went over the wire in the clear. Heidrun adds **TLS** for
servers that support it:

- **"Use TLS" toggle** right next to the port. Flip it and the port jumps to the
  server's TLS sibling (5500 ↔ 5502) automatically.
- **Trust-on-first-use** for self-signed certs — the kind community servers
  actually run. First connect, you're shown the certificate's SHA-256
  fingerprint and you decide whether to trust it.
- **Pinning.** Once you trust a server's cert, Heidrun remembers it (pinned into
  the bookmark). If it ever changes, you get warned instead of silently
  reconnecting to who-knows-what.
- **"Forget" button** to clear a pinned cert and re-prompt on the next connect.
- **Lock in the title bar.** 🔒 means you're encrypted, 🔓 means cleartext. No
  guessing.

## Your identity

- **Pick your icon** from the bundled Hotline icon catalog — the same little
  16×16 / 32×32 pixel icons, rendered crisp.
- **Pick a banner** for servers that show one.
- **Save your password** to the macOS Keychain if you want, and optionally
  **gate it behind Touch ID** so a saved password isn't handed out without you.

---

## Once you're in

### Chat

- **Public chat** — read the room, post your line (⌘-Return or the Send button).
- **Private chat rooms**, including setting and editing the room subject.
- **Join / leave notices** and **timestamps**, both of which you can switch off
  in Settings if you like a quieter log.
- **The user list** down the side: everyone online with their icon, nickname,
  and status.
- **Drag the transcript out** to a `.txt` file when you want to keep it.

### Private messages

- **A real conversations view** — threads down the left, the exchange on the
  right, unread dots so you don't miss a reply.
- Start a message straight from the user list in Chat.
- Heidrun **flips you to Messages automatically** when someone PMs you.
- Reply box disables itself when the other person has logged off, so you're not
  shouting into the void.

### Files

- **Browse the file tree** with breadcrumbs to find your way back up.
- **Download** single files or whole batches. If a file already exists locally,
  you get **Replace / Resume / Cancel**.
- **Resume interrupted downloads.** A half-finished transfer is kept as a
  `.heidrunpart` file; reopen it and Heidrun picks up where it left off (or lets
  you replace, delete, or reveal it in Finder).
- **Upload files and whole folders** — open dialog or just drag them in.
- **Make folders, rename, delete** (with a confirmation before anything
  destructive).
- **Get Info** on a file, including reading and editing its comment.
- **Quick Look** a file before you commit to downloading it.
- **Transfer drawer + Task Manager.** Watch every upload and download with
  progress, speed, and ETA; cancel what you don't want; clear out the finished
  ones.
- **A chime when a download finishes**, so you can walk away from the queue.

### News

Heidrun handles **both** flavors of Hotline news, and picks the right one for
the server:

- **Classic flat board** (Hotline pre-1.5 and Wired-style servers): the bulletin
  board as one running text, with a box to **post your own update**. New posts
  stream in live.
- **Threaded news** (Hotline 1.5+): categories and bundles down the left,
  threads and the post body on the right, with breadcrumbs to navigate.
  - **Start new threads**, **reply** (replies nest under their parent),
    **edit and delete your own posts**.
  - **Create and delete categories / bundles**.
  - **Copy a post or a whole thread**, or drag a post out as text.

### Server admin (if you've got the keys)

If your account has the privileges, Heidrun gives you a proper **account admin**
panel:

- **Account roster** with search, plus a button to create new accounts.
- **Edit logins, nicknames, and passwords.**
- **Privilege presets** — Guest / User / Moderator / Admin — or go Custom and
  flip individual rights across Files, Chat, News, Users, and Server.
- **Save / Revert / Delete / Duplicate**, with clear "unsaved changes" markers
  so you know what's dirty.

---

## The little things

- **Agreement screens** are shown the way they always were — you read it, you
  Accept, you're in.
- **System notifications** for the events you care about: connected,
  disconnected, private message, broadcast, private-chat invite, transfer done,
  news posted. Every one is individually toggleable.
- **Sound effects** for login, logout, chat, private messages, news, server
  messages, and finished transfers — with a master switch and per-cue preview
  buttons in Settings. (Yes, you can turn them off.)
- **Built-in Help** covering connecting, files & transfers, bookmarks, and
  settings.
- **Fully localized** — English, German, and Japanese, throughout.

---

*Built on Swift 6 and modern macOS, sandboxed and notarized, but it still feels
like Hotline. That was the whole point.*
