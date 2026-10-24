# Nexus

A keyboard-driven launcher for macOS. Press **⌥Space**, type, press **↵**.
Everything runs on your Mac: no account, no telemetry, no server.

Native Swift (SwiftUI + AppKit). Opening the window takes about 6–10 ms on a warm start (CPU side, measured
from the hotkey handler to a forced layout and draw; see `make bench`).

## What it does

**Launcher.** Fuzzy app search with frecency, and every feature below as a command. Commands are ranked by how well
they match, then by how often you use them. ⌘K opens an action menu for the highlighted row.

**Calculator, right in the search box.** Math, units (`5 km to miles`), dates and times (`25 dec - today`,
`9:30 - 6:45`, `3pm ist to utc`), named dates (`days until christmas`), epoch timestamps with microseconds
(paste `1792767344123456`), and optional currency conversion (`100 usd to inr`, off by default).

**Clipboard history** (⌘⇧V). Text, links, images and files. Searchable, with a preview, partial paste (select part of
the text in the preview), plain-text paste by default, pinning, and configurable retention. Password managers and
concealed content are never recorded.

**Snippets** (⌘⇧S). Text, code blocks and terminal commands (with Paste and Run). Placeholders: `{clipboard}`,
`{date}`, `{time}`, `{datetime}`. *Secret* snippets live in the Keychain, are masked everywhere, and need Touch ID or
your password to edit or reveal. JSON import and export (secrets are never exported).

**2FA codes** (⌃V). TOTP with SHA1/256/512, 6–8 digits, any period. Add by secret, `otpauth://` link, or a screenshot
of the QR code. Secrets are stored in the Keychain.

**Menu bar.** Caffeinate (keep awake, indefinitely or for a set time) and Open Ports (see and kill what is listening).

**System.** Quit or force-quit apps, lock, sleep, empty the Trash, toggle dark mode.

**Developer tools.** UUID v4/v7, MongoDB ObjectId, ULID, nanoid, passwords; base64, URL encode, hashes, JWT decode,
MessagePack encode/decode (`packb` / `unpackb`, accepts hex, base64 or a Python bytes literal), color converter, case converter; HTTP status lookup, number base converter, lorem ipsum, cron explainer with next run
times, a live regex tester, clipboard text transforms (format JSON, JSON to YAML, sort and dedupe lines…), a clipboard
diff, a QR code generator, Docker container controls, and local network info.

**Script commands.** Drop a script in `~/Library/Application Support/Nexus/Scripts` with a header and it becomes a
command. See below.

## Install

Requires macOS 14 or later (Apple Silicon or Intel).

### Download

1. Download `Nexus.dmg` from the [latest release](https://github.com/harshitgarg02/nexus/releases/latest).
2. Open the DMG and drag **Nexus** into **Applications**.
3. The app isn't notarized, so the first launch is blocked by Gatekeeper. Right-click **Nexus** → **Open** → **Open**,
   or run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Nexus.app
   ```
4. Press **⌥Space** to open the launcher. Nexus runs from the menu bar, with no Dock icon.

### Build from source

Needs Xcode (or the Command Line Tools with Swift 6).

```bash
make install     # build, sign, copy to /Applications, launch
make run         # build and launch from build/
make test        # run the test suite
make universal   # Intel + Apple Silicon build in build/universal
make dmg         # shareable disk image (universal)
make bench       # open-latency benchmark
```

### Signing and permissions

By default the app is signed ad hoc (`-`), which is fine for running it yourself. macOS ties **Accessibility** and
**Keychain** permissions to the app's signature, so with ad-hoc signing they can reset after a rebuild. For a stable
identity, create a code-signing certificate (Keychain Access → Certificate Assistant → Create a Certificate →
*Code Signing*), then put this in a git-ignored `Makefile.local`:

```make
IDENTITY := My Certificate Name
BUNDLE_ID := com.yourname.nexus   # optional; it also namespaces the Keychain items
```

The app isn't notarized (that needs a paid Apple Developer account), so downloaded builds show a Gatekeeper warning
(see [Download](#download)).

**Accessibility** is needed only to paste into other apps (Nexus sends ⌘V for you). Without it, items are copied instead.

## Shortcuts

| Action | Default |
|---|---|
| Open Nexus | ⌥Space |
| Clipboard history | ⌘⇧V |
| Snippets | ⌘⇧S |
| 2FA codes | ⌃V |

All are configurable in Settings → Hotkeys. The recorder captures combinations that other apps normally swallow.
Global hotkeys override the same shortcut in every app, including terminals (⌃V).

## Typed shortcuts

```
uuid · objectid · ulid · nanoid · password 20 · hex 32 · random 1 100
base64 text · unbase64 … · urlencode text · urldecode … · sha256 text · md5 · hash text
packb {"a":1} · unpackb 81a16101 (MessagePack, hex or base64)
jwt <token> (or paste one) · #ff5733 / rgb(…) / hsl(…) · camel / snake / kebab / pascal / constant text · case text
http 404 · base 255 · lorem 3 · cron */5 * * * * · regex /[0-9]+/ text · netinfo
```

Most keywords only trigger with text after them, so a bare word such as `hex` or `password` still searches apps.

## Script commands

```bash
#!/bin/bash
# @nexus.title Say Hello
# @nexus.description What it does
# @nexus.icon hand.wave          (an SF Symbol)
# @nexus.mode output             (output | clipboard | paste | silent)
# @nexus.keywords hi, greet
# @nexus.argument Your name      (optional; passed as $1)
echo "Hello, ${1:-world}!"
```

Files must be executable. Scripts run with your permissions and a 30-second limit, so only keep scripts you trust in
that folder. Files without a `@nexus.title` are ignored.

## Privacy

- All data stays in `~/Library/Application Support/Nexus` (clipboard history, snippets, 2FA entry names, settings).
- Secret values (secret snippets and 2FA keys) are stored only in the macOS Keychain.
- The only network requests: **currency rates** from `open.er-api.com` (only if you turn that on) and **Look Up Public IP**
  via `api.ipify.org` (only when you run that command). Nothing else leaves your Mac.

## Layout

```
Sources/NexusCore   Pure logic, no UI: calculator, parsers, stores, generators. Fully unit-tested.
Sources/Nexus       The app: overlay, screens, settings, menu-bar items.
Tests/              Unit tests for NexusCore (known vectors for TOTP, hashes, cron, QR round-trips, …).
Resources/          Info.plist and the app icon (regenerate with `make icon`).
```

## License

MIT. See [LICENSE](LICENSE).
