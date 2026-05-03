# Furwall

**Furwall blocks catasstrophes.**

A tiny menu-bar app for macOS that watches the front camera while you’re at the keyboard or mouse. If no human face or upper body is visible, it drops keyboard input until you come back. The cat can walk across your laptop all it wants—your code, your half-written message, your unsent email all stay intact.

When it blocks, it saves a JPEG of the purrpetrator. We call those *catpures*.

---

## How it works

- The FaceTime camera turns on **only while you’re typing or moving the mouse**, and powers down 30 seconds after the last keystroke. The green camera dot mirrors that.
- Apple’s Vision framework runs face + upper-body detection locally. **No frames ever leave your Mac.**
- A `CGEventTap` at the head of the keyboard event stream drops keystrokes when no human is present. Mouse events are never tapped, so you can always reach the menu bar to pause or quit.

The one network call: when you click **Donate**, Furwall opens the charity’s page and increments an anonymous global click count. The body is one short slug — `alleycat` or `petsmart` — no user identifiers, cookies, or analytics. The Worker source and KV setup are in [`cloudflare/`](cloudflare/).

## Install

1. Download `Furwall.dmg` from [Releases](https://github.com/olliewagner/furwall/releases).
2. Drag `Furwall.app` to `Applications`.
3. Open it. Walk through the welcome window—it asks for two permissions:
   - **Camera**—to check for a human face.
   - **Accessibility**—to drop keystrokes when no one’s there.
4. The menu bar gets a cat icon. You’re done.

> The DMG is signed with my Apple Developer ID and notarized by Apple.

## Permissions

| Permission | Why | What’s stored |
|---|---|---|
| Camera | Local face/body detection | Camera frames are kept in memory only. The most recent frame is saved as a JPEG **only when a block happens**, to `~/.furwall/catpures/`. A second Vision pass classifies the saved frame; if it isn't a cat, the JPEG is deleted. |
| Accessibility | Required to **drop** keystrokes—a sandboxed `CGEventTap` in `.listenOnly` mode could observe keys (Input Monitoring is enough), but dropping requires `.defaultTap`, which requires Accessibility, which the App Sandbox blocks. So Furwall ships unsandboxed. | None. The event tap reads keycodes, drops the event, and never persists anything keystroke-shaped. |

You can read every byte the app writes:

```
~/.furwall/events.jsonl   — append-only log: { ts, type: "block" | "panic", catpure?: <path>, cat?: bool, human?: bool }
~/.furwall/catpures/      — cat-confirmed JPEGs (frames the post-hoc classifier doesn't confirm as a cat are deleted)
```

## Fail Safe

Three independent escape hatches—any one gets you out:

1. **Mash Escape five times in 1.5 seconds.** Pauses Furwall for 5 minutes, fires a notification.
2. **Click the menu bar icon → Quit Furwall.** The mouse is never blocked.
3. **System Settings → Privacy & Security → Accessibility → toggle Furwall off.** Permanent.

If you somehow lock yourself out worse than that:

```
# from a Terminal window or another machine via SSH
pkill -f Furwall
```

## Menu

The menu bar icon is the canonical lock/unlock indicator—orange cat-with-slash when blocking, faded cat when allowed. Click it for:

- **Stats**—N cats blocked today, verified post-hoc by a second Vision pass on each catpure.
- **Reveal Catpures**—opens `~/.furwall/catpures/` in Finder.
- **Resume**—only appears when the Escape-mash auto-pause is active.
- **Open at Login**—toggle.
- **Donate to Help Animals…**—picker for two animal-welfare charities (as of this writing: 4-star Charity Navigator, ≥85% to programs, public Candid Platinum/Gold seal, evergreen donate URLs); opens each org’s own page in your browser.
- **About Furwall…** and **Quit Furwall**.

## False positives

Backlit windows, glasses, deep shadows, or extreme head-down typing posture can occasionally fool the face/body detector. When that happens:

- If Vision can’t keep up at all (camera grabbed by another app, hardware hiccup), Furwall fails open after 10 seconds—the keyboard stays unlocked rather than soft-bricking your machine.
- The Escape mash always works (5 presses in 1.5 seconds → 5-minute pause).
- A glance back at the camera unlocks the keyboard within ~1 second (Vision samples at ~1 Hz while the camera's awake).

## Build from source

Requires Xcode 16+ on macOS 15+.

```bash
git clone https://github.com/olliewagner/furwall.git
cd Furwall
open Furwall.xcodeproj
```

Then ⌘R in Xcode.

If you're forking to distribute your own build, change `SUFeedURL` and `SUPublicEDKey` in `Resources/Info.plist` to point at your own appcast and signing key — otherwise Sparkle in your fork will try (and fail) to update users from this repo's release feed.

## Credits

Built by [Ollie Wagner](https://github.com/olliewagner). QA Cats: Pepper and Beets.

## License

MIT.
