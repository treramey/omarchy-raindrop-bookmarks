# io.github.treramey.raindrop-bookmarks

## 1.3.0

### Minor Changes

- 6f286b8: Introduce a Raycast-inspired search-first bookmark browser with tag accessories, an action menu, and native text input. Keep Omarchy's live theme styling and add Ctrl+K for actions and Ctrl+R for refresh.

### Patch Changes

- 6f286b8: Limit cover image parsers to 256 MiB of virtual address space before reading untrusted image metadata, while preserving stricter inherited limits. Skip parsing if the limit cannot be applied.
- 6f286b8: Keep token validation and saving tied to one immutable attempt so background checks cannot authorize replacement credentials. Recover from helper-start failures and timeouts, distinguish connection and input errors, and respect rate-limit retry countdowns.
- 6f286b8: Add horizontal padding inside shortcut boxes so key labels have space on both sides. Keep the Enter key hint compact and show Ctrl and K in separate boxes.

## 1.2.1

### Patch Changes

- c87b438: Qualify the Omarchy color singleton to restore bookmark and onboarding theme colors on updated Qt and Quickshell installations.

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
