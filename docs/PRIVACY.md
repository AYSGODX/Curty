# Privacy

Curty does not contain analytics, advertising, cloud sync, update tracking, or network code.

| Data | Default | Storage |
| --- | --- | --- |
| Clipboard text and file references | On | Memory only |
| Clipboard images | Off | Memory; explicit save only |
| Shelf access | User-selected files only | Security-scoped bookmarks |
| Snippets | User-created | App container, mode `0600` |
| Scratch notes | User-created | App container, mode `0600` |
| Calendar events | Off until permission | Memory only, next 24 hours |
| Translation text | Explicit input | Not retained by Curty |
| Music/Spotify state | On; macOS Automation permission may be required | Memory only |

Language packs for Apple Translation may be downloaded by macOS after a user action in the system-provided flow. Curty itself has no network entitlement.
