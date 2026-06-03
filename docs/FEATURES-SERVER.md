# Heidrun — the Server

*A feature tour for Hotline people, written by one of us.*

Running a Hotline server used to mean an old Mac in the corner that you didn't
dare reboot. Heidrun Server is the other half of the project: a real
Hotline-protocol server you can actually keep online — it runs on Linux, ships
in a container, and speaks to the clients you already know. Put up a board, host
some files, keep the community going. Here's what it does.

---

## It's a real Hotline server

- **Speaks the Hotline wire protocol**, so the classic Mac clients, modern
  clients, and Heidrun's own client all connect and behave the way you'd expect.
- **Runs on Linux** — no vintage hardware required. Built in Swift, deployed as a
  Docker container.
- **Container-first.** Comes with a `Dockerfile`, a `docker compose` setup, and
  deployment scripts, so "stand up a server" is a short job, not a weekend.

## Accounts & access

- **Account database** kept in SQLite — proper persistent accounts, not a flat
  file you have to hand-edit and pray over.
- **Privilege presets** so new accounts get sensible rights out of the box —
  Guest, User, Moderator, Admin — with the full set of Hotline privileges
  underneath (Files, Chat, News, Users, Server) for when you want to dial it in.
- **Guests welcome** (or not) — your call, per your privilege setup.

## The board (News)

Heidrun Server runs the news board the way *your* community wants it:

- **Threaded news** (Hotline 1.5+): categories, bundles, threads, replies.
- **Classic flat board** for that pre-1.5 / BBS feel — one running bulletin
  list. Flip the **`news_mode`** operator toggle and the server even caps the
  version it advertises so clients fall back to the plain board automatically.
- **News persists** to a JSON snapshot alongside the database, so a restart
  doesn't wipe the board.
- **One-shot reset knob** (`HEIDRUN_NEWS_RESET`) for when you genuinely want to
  start the board fresh — documented, deliberate, not a footgun.

## Files

- **Hosts the file tree** clients browse, download from, and (with rights) upload
  to.
- **Folder transfers** — whole folders go up and down in bulk, not one
  painstaking file at a time.
- **Persistent file metadata.** File comments stick around, and classic Mac
  **HFS type/creator codes** are preserved, so files keep their identity the way
  Hotline always cared about.

## Encryption (the modern addition)

- **TLS sibling ports** (5502 / 5503) running alongside the classic cleartext
  ports, built on SwiftNIO's TLS stack.
- **Self-signed certificate friendly** — pair it with the Heidrun client's
  trust-on-first-use and pinning, and a community server gets real encryption
  without paying a certificate authority.

## On the trackers

- **Registers itself with trackers over UDP**, the way the spec actually
  specifies — so your server shows up in the public lists where people go
  looking for somewhere to hang out.

## Presentation

- **Server banner** support — push your server's banner/identity (transID 212)
  out to clients that display it.
- **Private message seeding** and the rest of the everyday handlers wired up, so
  the live experience on the server feels complete, not skeletal.

## Operating it

- **Time zone aware** (`tzdata` / `TZ`), so timestamps on your board and logs
  read correctly wherever your box lives.
- **Diagnostic dispatch logging**, including the remote host on each request, for
  when you need to see what's actually hitting the server.
- **Tagged releases** and a documented deployment path for putting it on real
  hosting.

---

*Same protocol, same community, hardware that won't die on you. That's the idea:
keep Hotline alive somewhere that can stay online.*
