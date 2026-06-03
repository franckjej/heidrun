# Notice

Heidrun is a Swift 6 port and modernisation of the original
**Heidrun Hotline client** for Mac OS X (Göran Granström — "GG" — 2002).
The original was distributed as a small application shell plus a set
of plug-in modules (chat, news, files, messages, admin, agreement, …).
Each module's source carries an explicit `COPYING` file with the
**GNU General Public License v2** text; the surrounding application
shell + module framework did not carry an explicit license
declaration, but the project's intent — extending an open-source
Hotline ecosystem on the classic Mac — is best honoured by treating
the whole heritage as GPL-2.0. This port is licensed under
**GPL-2.0** for the same reason. See `LICENSE` for the full text.

The Swift port is an independent reimplementation written from the
original codebase's wire protocol and high-level structure; no
Objective-C was translated line-for-line, and the cross-platform
SwiftNIO networking layer was written from scratch. Inspiration
credit flows entirely to GG.

## If you are Göran Granström

If you'd like the licensing of this port clarified, written
differently, rolled into a different scheme entirely — a relicense,
a `NOTICE` update, a request to take the port down, anything —
please get in touch.

Both of your previously-known contact channels are no longer
reachable: `granma@netsafir.com` (2002, school-hosted) and
`kontakt@analogtro.com` (later, company domain, now defunct). We'd
welcome a new one.

Open an issue at the
[heidrun-swift GitHub repository](https://github.com/franckjej/heidrun-swift),
or email the maintainer at the address listed in the project README.
