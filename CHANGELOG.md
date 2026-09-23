# io.github.treramey.raindrop-bookmarks

## 1.2.0

### Minor Changes

- 20f99cc: Persist Raindrop bookmarks locally for offline search and refresh them in the background.

### Patch Changes

- 20f99cc: Give the bookmark panel consistent outer padding, roomier section spacing, and aligned search and row insets.
- 20f99cc: Separate header labels, bookmark rows, and keyboard hints with consistent spacing while retaining the bottom-aligned footer.
- 20f99cc: Align the bookmark panel with Omarchy styling using a compact header, aligned actions, section dividers, and a shorter saved timestamp.
- 20f99cc: Prioritize search with a compact header, denser results, clearer selection, relative sync status, and keyboard hints.
- ab85347: Debounce bookmark search while typing and skip expensive fuzzy scoring for fields that cannot match long queries.
- 20f99cc: Use all available height for bookmark results and keep keyboard hints at the bottom of the panel.
- 20f99cc: Fix Refresh button bindings and preserve selection and freshness during token checks.
- 20f99cc: Stop snapping bookmark scrolling to row boundaries so touchpad gestures can settle smoothly between rows.

## 1.1.0

### Minor Changes

- 0ee6088: Add a guided in-overlay setup that securely saves and verifies a Raindrop token, with clear connection and recovery states.

### Patch Changes

- 16ba2f8: Simplify the onboarding success message while bookmarks load.

## 1.0.3

### Patch Changes

- 72227c8: Keep the first search result selected when filtering under a stationary pointer.
