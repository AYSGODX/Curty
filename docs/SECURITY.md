# Security model

Curty is sandboxed. It has no telemetry, private frameworks, injected libraries, accessibility event injection, or arbitrary script runner.

## Consent boundaries

- Clipboard observation is enabled by default and can be paused from the menu bar.
- Clipboard history is memory-only and is cleared on quit, screen sleep, and session lock.
- Images are disabled by default. Enabling images adds bounded previews to memory; writing one to disk is a separate click.
- Calendar access is requested only from the Calendar screen. Events are projected into memory and never persisted.
- Meeting links must use HTTPS and an approved meeting-provider host.
- Music/Spotify automation starts automatically and uses a fixed command allowlist.
- Launch at login is never enabled automatically.
- The panel opens only after the pointer rests in the notch, so passing through it on the way elsewhere does not summon it. Curty does not inspect other applications' windows to decide this.

## File access

External shelf files are represented by read-only security-scoped bookmarks. Removing an item forgets the bookmark and never deletes the original file. Clipboard images explicitly saved by the user are stored in the app container with a 250 MB quota.

## Distribution

Public builds must be signed with Developer ID, use Hardened Runtime, be notarized and stapled, and pass the verification script. Ad-hoc builds are development-only and must not be shared as trusted releases.
