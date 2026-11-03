# Local data and cover handling

Omarchy plugins run unsandboxed with your user permissions. This plugin:

- reads credentials only from the configured Raindrop token file and sends
  that token only to `https://api.raindrop.io`;
- stores the last complete bookmark response under
  `${XDG_DATA_HOME:-$HOME/.local/share}/omarchy-shell/raindrop-bookmarks`;
- binds saved bookmarks to a local SHA-256 fingerprint of the token without
  storing the token in the snapshot;
- downloads only HTTPS cover URLs on port 443 whose DNS answers are all public;
- pins each cover request to its validated address, disables redirects and
  proxies, and enforces connection, transfer-time, and 5 MiB size limits;
- accepts only PNG, JPEG, GIF, and WebP covers, and processes the first frame
  in an isolated Qt helper with format and dimension checks;
- caps the helper's virtual address space at 256 MiB before decoding, preserves
  stricter inherited limits, and applies a 10-second deadline. Failed or
  oversized conversions leave existing thumbnails unchanged;
- stores thumbnails under
  `${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-shell/raindrop-bookmarks/covers`; and
- opens selected links through `xdg-open`.

The plugin never copies the token into its directory or exposes it in a process
argument. It attempts to refresh thumbnails at least seven days old during
cover sync and deletes thumbnail files older than 30 days. These checks do not
run on a timer. A failed bookmark refresh keeps the last successful snapshot.

## Clear local data

Stop Omarchy Shell before clearing data. Closing the overlay does not stop
background syncs. The command deletes saved snapshots and covers, but does not
clear bookmarks already held in a running shell's memory. An active sync can
recreate the files. Start Omarchy Shell again when finished; opening the
plugin can download bookmarks again while a token remains configured.

```sh
"${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/io.github.treramey.raindrop-bookmarks/clear-bookmarks"
```

This does not remove the token file. By default it is
`${XDG_CONFIG_HOME:-$HOME/.config}/raindrop/token`. If you set
`RAINDROP_TOKEN_FILE`, check that location instead. Remove the token
yourself only if other tools do not need it.
