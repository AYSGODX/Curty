# Security model

Curty is sandboxed. It has no telemetry, private frameworks, injected libraries, accessibility event injection, or arbitrary script runner.

Its only network access is outbound https to fetch the album cover of the playing track, confined to `ArtworkLoader.swift` behind a host allowlist. `Scripts/security-check.sh` fails the build if network code appears anywhere else or if that allowlist is removed.

## Consent boundaries

- Clipboard observation is enabled by default and can be paused from the menu bar.
- Clipboard history is memory-only and is cleared on quit, screen sleep, and session lock.
- Images are disabled by default. Enabling images adds bounded previews to memory; writing one to disk is a separate click.
- Calendar access is requested only from the Calendar screen. Events are projected into memory and never persisted.
- Meeting links must use HTTPS and an approved meeting-provider host.
- Music/Spotify automation starts automatically and uses a fixed command allowlist.
- Launch at login is never enabled automatically.
- The notch stays inactive while the Dock stacks extra screen-covering windows, which is how Mission Control and App Exposé are recognised without guessing at fixed system internals. This reads on-screen window size and owner only — no titles, no contents, no screen capture, and no Screen Recording permission.

## File access

External shelf files are represented by read-only security-scoped bookmarks. Removing an item forgets the bookmark and never deletes the original file. Clipboard images explicitly saved by the user are stored in the app container with a 250 MB quota.

## Distribution

Public builds must be signed with Developer ID, use Hardened Runtime, be notarized and stapled, and pass the verification script. Ad-hoc builds are development-only and must not be shared as trusted releases.
