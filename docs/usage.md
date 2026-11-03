# Usage tips

## Keyboard shortcut

To open Raindrop Bookmarks with `Super + Shift + R`, add this binding to
`~/.config/hypr/bindings.lua`:

```lua
hl.unbind("SUPER + SHIFT + R")
o.bind(
  "SUPER + SHIFT + R",
  "Raindrop bookmarks",
  "omarchy-shell shell toggle io.github.treramey.raindrop-bookmarks '{}'"
)
```

This replaces any existing `Super + Shift + R` binding. Choose another key
combination if you use it for something else. Then reload Hyprland:

```sh
hyprctl reload
```

You can also click `Actions` to refresh bookmarks or reconnect Raindrop.
Click outside the card to close the overlay.

## Connection errors

The form distinguishes rejected tokens, invalid input, connection failures,
Raindrop service errors, and local installation or save failures. A rejected
replacement never overwrites your saved token. If saving fails, the form lets
you retry.

If the form says `Finishing check…`, wait for the current check to finish
before submitting another token. Active attempts continue after you close the
overlay; reopening it does not restart them.

Rate limits show a retry countdown and disable Connect until the wait ends.
Token checks have a 20-second deadline, and saves have a 5-second deadline.

If a refresh fails, the last complete bookmark download remains available.
Use `Ctrl+R` to retry a refresh, or choose `Reconnect Raindrop` from
`Actions` if the saved token is no longer valid.
