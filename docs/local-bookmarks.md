# Persistent local bookmarks

## Goal

Show previously downloaded bookmarks without waiting for the network. Keep search usable across shell restarts and offline periods.

## Agreed decisions

- Retain the last successful snapshot indefinitely, until replaced or explicitly cleared.
- Refresh in the background on open if the last successful sync is at least five minutes old. Provide manual refresh. Do not introduce periodic polling or a system service.
- Apply refreshed results immediately. Preserve the query and selected bookmark by ID. If it was deleted, select the nearest remaining row.
- Store a versioned JSON snapshot under `$XDG_DATA_HOME/omarchy-shell/raindrop-bookmarks`, falling back to `~/.local/share`. Use private permissions and atomic replacement after every page succeeds. Keep thumbnails in the existing disposable cache.
- Bind snapshots to a local token fingerprint. Never store the token in the snapshot. Changed or missing tokens hide previous data. Accept a fresh sync after token rotation, even for the same account.
- Consolidate bookmark fetching now. Cover processing consumes bookmark metadata from the shared sync owner. Existing covers appear without waiting for new downloads. Preserve every existing cover security control.
- Publish complete snapshots only, including an empty successful library. Show loading only without a valid snapshot. Explain corrupt or incompatible local data and download again.
- Show local data before online token validation. An unchanged token keeps saved bookmarks searchable even after a 401. Provide nonblocking sync status, last success time, Refresh, and reconnect controls.
- Document an explicit data-clearing command instead of adding a settings screen.
- Finish started syncs while the overlay is closed and the plugin remains loaded. Allow one sync per token, invalidate old in-flight results on token changes, and retain saved data on failure.
- Use a bounded failure cooldown and respect API rate-limit reset. Retry on a later open or manual refresh, not an endless retry loop.
- Use a 60-second cooldown for ordinary failures. Manual refresh can bypass this cooldown, but cannot bypass a server rate-limit reset.
- Use full paginated refreshes. Bound response sizes, total work, and disk reads. Exceeding a bound reports failure and preserves the previous snapshot, never a truncated replacement.
- Persistent local bookmark storage is implemented by `bookmark-sync` and `load-bookmarks`.

## Important tradeoffs

- Offline results can include remotely deleted bookmarks until the next successful refresh.
- Updating an open list can move rows, even when selection is preserved.
- Full refreshes require pagination. Raindrop allows at most 50 items per page.
- Strict token binding trades seamless token rotation for account isolation.
- Durable local data contains private bookmark metadata. It is not encrypted by this feature and needs a documented removal command.
- Consolidating cover metadata expands testing scope but removes duplicate API requests.

## Relevant user reasoning

Once bookmarks have been downloaded, users should not have to wait through another loading screen to use them.

## Open questions

- No open product decisions. Select exact resource limits from measured fixtures during implementation and document them.

## Implementation notes

- Snapshots use version `1`, a SHA-256 token fingerprint, a Unix sync timestamp, and the complete bookmark array.
- The sync bounds are 200 pages, 10,000 bookmarks, 200 MiB of API responses, and a 50 MiB snapshot. Each page remains limited to 10 MiB.
- `clear-bookmarks` removes the persistent snapshot, sync state, and disposable cover cache. Run it from the installed plugin directory when local data must be removed.
- Snapshot lifecycle and background refresh tests cover offline restart data, empty libraries, interrupted pagination, token changes, cooldowns, rate limits, and shared cover metadata.
- Run `bash -n cover-sync tests/security.sh`, `python3 -m py_compile validate-cover-url`, and `tests/security.sh` after network, cache, or image changes. Run token tests and QML checks. Validate the plugin without a local `node_modules/` directory.

## Evidence

- `RaindropBookmarks.qml` owns in-memory bookmarks, snapshot loading, token validation, selection preservation, and five-minute freshness.
- `bookmark-sync` owns full bookmark pagination, snapshot publication, token binding, cooldowns, and rate-limit state.
- `cover-sync` consumes bookmark metadata from the shared snapshot and stores disposable thumbnails without fetching bookmark pages again.
- `manifest.json` keeps the overlay loaded so background refreshes can finish, while the snapshot persists data across shell restarts.
- API pagination: https://developer.raindrop.io/v1/raindrops/multiple
- API rate limits: https://developer.raindrop.io/
