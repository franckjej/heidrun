# AGENTS.md

Onboarding notes for AI coding assistants (Claude Code, Cursor, Codex,
Aider, etc.) working on Heidrun. Read top-to-bottom on first touch;
later sessions can grep for the section that fits.

## What this is

A Swift 6 port of **Heidrun**, the modular Mac Hotline-protocol client
originally written by Göran Granström in 2002. The app is a SwiftUI /
AppKit shell on top of four sibling Swift Package Manager modules. The
wire protocol matches classic Hotline 1.x servers plus a small set of
Heidrun-specific extensions (resource-fork round-trip, TLS sibling
ports, file metadata).

Target platform: **macOS 15 (Sequoia)** or later, signed + notarized
for Apple Silicon and Intel.

## Repo layout

```
Heidrun.xcodeproj/             generated — NOT in the repo
Heidrun/                       app target sources (@main App, AppDelegate, Settings, …)
HeidrunAppTests/                Xcode test bundle (Swift Testing)
Packages/
  HeidrunCore/                 protocol/models/network (own Package.swift)
  HeidrunUI/                   shared UI primitives, design tokens, icons, sounds
  HeidrunModules/              six feature libraries in one Package.swift
  HeidrunIconConverter/        standalone dev tool (offline icon extraction)
docs/                          public-facing feature overviews
project.yml                    xcodegen spec — regenerate Heidrun.xcodeproj from this
_IconWerk/                     source PNGs used by the DMG packaging pipeline
Tools/                         build-time generators (emoji catalog, etc.)
dmg_settings.py                dmgbuild config for release packaging
```

`Heidrun.xcodeproj/` is generated and gitignored. Run `xcodegen generate`
after clone, after pulling, and after editing `project.yml` or
adding/removing sources.

## Build, test, run

Apple-platform CLIs (`xcodebuild`, `swift test`) are the canonical
invocations; if you're driving a tool that wraps them (XcodeBuildMCP,
the Xcode IDE, etc.), prefer the wrapper for structured output.

```bash
# One-time after clone or pull
xcodegen generate

# Build + run the app
xcodebuild -project Heidrun.xcodeproj -scheme Heidrun -configuration Debug build
# Or open Heidrun.xcodeproj in Xcode and hit ⌘R.

# Tests
xcodebuild -project Heidrun.xcodeproj -scheme Heidrun test     # app shell
swift test --package-path Packages/HeidrunCore                 # core / protocol
swift test --package-path Packages/HeidrunUI                   # shared UI
swift test --package-path Packages/HeidrunModules              # features

# Lint (config lives at .swiftlint.yml; CI expects zero warnings)
swiftlint --strict
```

A `.swiftlint.yml` is checked in at the repo root. CI builds + the
release pipeline both expect zero warnings; treat the linter as a
gate, not a suggestion.

Release DMG (signed + notarized): see `dmg_settings.py` and the
canonical pipeline in this file's git history — `xcodebuild archive`,
`sips`/`tiffutil` for the retina background, `dmgbuild`, `codesign`,
`xcrun notarytool submit --wait`, `xcrun stapler staple`.

## Architecture

### One library per feature

The original Heidrun's `.heimod` NSBundle plugin system is replaced by
one SwiftPM library product per feature, all defined in
`Packages/HeidrunModules/Package.swift`. The SwiftUI host
(`Heidrun/`) imports each library and registers its type in
`Heidrun/FeatureRegistry.swift`. **Dropping a feature = dropping the
`import` line, the registry entry, and the linked product in
`project.yml`** (then `xcodegen generate`). No string-keyed identifier
lookups, no dynamic loading.

Each feature is a triplet under `Packages/HeidrunModules/Sources/X/`:

- `XViewModel` — `@Observable @MainActor`, takes the `events` stream and a
  sender closure from `HotlineClient` so unit tests can inject doubles.
- `XView` — SwiftUI view.
- `XFeature` — caseless `enum` conforming to `HeidrunUI.HeidrunFeature`;
  provides `identifier`, `displayName`, `systemImage`,
  `makeContentView(client:)`. The protocol is used through its
  metatype, never instantiated.

`HeidrunUI` only holds the `HeidrunFeature` protocol — shared
primitives go here, not in `HeidrunCore`.

### Core (`Packages/HeidrunCore/Sources/HeidrunCore/`)

- `Protocol/` — wire-level value types (`PacketHeader`, `PacketObject`,
  `TransactionType`, `RemotePath`, `ConnectionSettings`, `ByteIO`
  helpers, `HotlineError`, …). Pure value layer.
- `Models/` — domain types (`User`, `RemoteFile`, `News`, `Icon`, `Task`).
- `Network/` — the actor-based runtime: `HotlineNetworkClient` (the
  production `HotlineClient` conformance, built on `NWConnection`),
  `EventBroadcaster` (multicast async stream), `PacketCodec`,
  per-payload codecs, and the transfer side-channel
  (`FileTransferActor`, `UploadFraming`, `FolderUploadFraming`,
  `FolderDownloadDecoder`, `HotlineTransferHandshake`, `ResumeInfo`,
  `HotlineDate`).

The public surface for consumers is the `HotlineClient` protocol in
`Packages/HeidrunCore/Sources/HeidrunCore/HotlineClient.swift`: every
operation is `async throws`; server-pushed events arrive on the
`events: AsyncStream<HotlineEvent>` property; multiple subscribers
are supported via `EventBroadcaster`.

### Hotline wire-protocol gotchas

When implementing or modifying transactions, these are the traps that
have bitten ports before. Hard-won knowledge — read before touching.

- **All multi-byte ints are big-endian.**
- **String encoding** defaults to `.macOSRoman`; overridable via
  `HotlineNetworkClient.connect(settings:stringEncoding:)`.
- **Login/password obfuscation** = XOR every byte with `0xFF`. Applied
  to login(105) and password(106) on auth + account-admin transactions
  **except `openLogin` (352) where login goes plain**.
- **Path encoding** (used by objIDs 202, 212, 325): `UInt16 component-
  Count` + per-component `(UInt16 0 pad, UInt8 length, name bytes)`.
- **HTXF handshake variants:** file download is `"HTXF"` + UInt32
  transferID + UInt32 transferSize + UInt32 reserved (0). Folder
  upload swaps the trailing 4 bytes for `UInt16 1, 0`. Folder download
  is 18 bytes adding a `UInt16 3` sentinel.
- **Hotline timestamps** are seconds since `1904-01-01 00:00:00 UTC`
  (classic Mac epoch). See `HotlineDate` and
  `UploadFraming.secondsSince1904`.
- **`modifyLogin` password convention:** `password: String?` — `nil`
  omits the field (legacy `noPass`), `""` sends a single `0x00` byte
  (legacy `emptyPass`).
- **File upload framing:** `FILP` 40-byte header (forkCount=3) →
  `INFO` block (74 + nameLen) with HFS type/creator + 1904-epoch
  dates + name → `DATA` fork hdr (16 B) + data fork → `MACR` fork hdr
  (16 B) + resource fork.
- **NWConnection finalize race:** the `.contentProcessed` send
  completion fires when bytes are *queued*, not *flushed*; calling
  `connection.cancel()` immediately after the final send discards
  whatever is still in the queue. Always end uploads with
  `send(content:, isComplete: true, ...)` and let NWConnection close
  naturally — never `cancel()` as the finish step.
- **NSWindow window-close cleanup with SwiftUI DocumentGroup:**
  `.onDisappear` on a doc scene's root view is unreliable for
  user-initiated closes. Hook `NSWindowDelegate.windowWillClose(_:)`
  for any per-window resource that must release at close.

### Testing pattern

Each feature has a sibling test target in its package; core
protocol/codec tests are in `Packages/HeidrunCore/Tests/Heidrun-
CoreTests/`. The Xcode app target's tests live at `HeidrunAppTests/`.
Tests use **Swift Testing** (`#expect` / `#require`), not XCTest.

ViewModels are tested by feeding a fake events stream and asserting
on captured sender-closure invocations — no `HotlineClient` mock
library, just function-typed closures. Integration tests use a local
`NWListener`-based fake server to exercise the full wire pipeline
without needing a real Hotline server.

## UI conventions

- **Icons: prefer the outline variant over the filled variant.** When
  picking SF Symbols (or any equivalent set), reach for the
  stroked/outline form — e.g. `arrow.down.circle`, not
  `arrow.down.circle.fill`; `power`, not `power.circle.fill`. Filled
  glyphs are reserved for cases where the symbol must read as a solid
  status badge (an error or completion marker that doubles as a
  colored chip).
- **Spacing tokens.** Reach for `CommonTools.Spacing`
  (`xxxsmall`/`xxsmall`/`xsmall`/`small`/`medium`/`large`/`xlarge`).
  Image-asset pixel sizes are the only exception.
- **Light + Dark mode.** Every new view must work in both modes; use
  semantic colors (`.labelColor` / `.secondary` / `.accentColor` /
  `.background.secondary`) — never hardcoded black/white. Verify by
  toggling System Appearance while the app is running.

## Code style

**Identifiers must be descriptive and at least 3 characters long.**
Applies to local variables, properties, function parameters, closure
parameters, case-binding names, and tuple element labels. Follow the
[Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/);
clarity at the point of use beats brevity.

- ❌ `let fm = FileManager.default` / `let vm = ...` /
     `case .failure(let e):` / `{ s in ... }`
- ✅ `let fileManager = FileManager.default` / `let viewModel = ...` /
     `case .failure(let error):` / `{ socket in ... }`

Narrow exemptions (the only short names allowed): generic type
parameters (`T`, `U`, `Element`, `Failure`); anonymous closure
shorthand (`$0`, `$1`); the Swift argument label `id:` in calls like
`ForEach(items, id: \.self)`; and math/coordinate components (`x`,
`y`, `z` for a `CGPoint`/`SIMD`, loop counters in 1–2 line numeric
loops). When in doubt, expand.

Apply this when writing new code and when touching existing code —
rename short identifiers in any file you modify.

## Tag / version convention

Releases tag as bare semver (`1.0.0`, `1.0.0-rc15`), never with a
`v-` prefix. SPM pins in `project.yml` and `Package.swift` use the
same bare form via `exactVersion:` / `exact:`.

Pre-release semver compares lexically (`"rc10" < "rc9"` because
`'1' < '9'`). Always pin pre-releases with `exact:` /
`exactVersion:`; never `from:`.
