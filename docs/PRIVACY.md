# Privacy

Curty does not contain analytics, advertising, cloud sync, or update tracking.

It makes exactly one kind of network request: fetching the album cover for the track that is already playing, from the link the player itself reports. Spotify publishes covers as a link rather than as image data, so there is no offline way to show one. The request is https only, goes only to the player's own image host, carries no identifiers Curty adds, and is skipped entirely when a cover is already in memory. Turning the media integration off stops it completely.

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
| Window size and owner, to notice Mission Control | On | Read on demand, never stored |
| Album cover of the current track | Follows the media integration | Fetched from the player's image host, memory only |

Language packs for Apple Translation may be downloaded by macOS after a user action in the system-provided flow. Curty itself has no network entitlement.
