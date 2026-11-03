# Raindrop Bookmarks for Omarchy

Search your [Raindrop.io](https://raindrop.io/) bookmarks from a keyboard-first
Omarchy Quattro overlay. It follows your Omarchy theme, keeps bookmarks for
offline search, and shows cached covers or letter tiles.

![Raindrop Bookmarks overlay showing saved bookmarks](assets/raindrop-bookmarks.png)

## Install

Requires Omarchy Quattro and its standard `curl`, `file`, `timeout`, Python 3,
Qt 6, and C++ build tools.

```sh
omarchy plugin add https://github.com/treramey/omarchy-raindrop-bookmarks.git --enable
```

Open the overlay from a terminal:

```sh
omarchy-shell shell toggle io.github.treramey.raindrop-bookmarks '{}'
```

For an optional keyboard shortcut, see [usage tips](docs/usage.md).

## Connect Raindrop

Open the overlay and paste your Raindrop **Test token** when prompted. The form
links to the Raindrop integrations page where you can create one. The plugin
checks the token before saving it to
`${XDG_CONFIG_HOME:-$HOME/.config}/raindrop/token` with private permissions.
Set `RAINDROP_TOKEN_FILE` before starting Omarchy Shell if you want a different
absolute path.

If the connection fails, see [connection help](docs/usage.md#connection-errors).

## Use

- Type to search titles, domains, tags, and URLs.
- Use `Up`, `Down`, `Page Up`, and `Page Down` to move. Press `Enter` to open a bookmark.
- Press `Ctrl+K` for actions, including reconnecting. Press `Ctrl+R` to refresh.
- Press `Escape` to close actions, clear the search, or close the overlay.

The plugin saves the last complete bookmark download for offline search. It
refreshes in the background when you open the overlay if the last successful
download is at least five minutes old. A failed refresh keeps your saved
bookmarks. Covers are cached separately; missing or unusable covers show a
letter tile.

## Data and covers

Omarchy includes the runtime tools. On the first cover sync, the plugin
compiles its included Qt thumbnail helper into the disposable cover cache.
You do not need to install an image converter or download a binary. If the
compiler or Qt development files are missing, existing covers stay visible,
but new thumbnails cannot be made until those tools are restored.

Omarchy plugins run with your user permissions, not in a sandbox. This plugin
sends your token to the Raindrop API, stores a private local bookmark snapshot,
downloads covers from validated public HTTPS addresses, and opens selected
bookmarks with `xdg-open`. The token is not stored in the bookmark snapshot.
See [data, cover limits, and clearing instructions](docs/privacy.md).

## Remove

Stop Omarchy Shell before clearing saved bookmarks and covers. Then run:

```sh
"${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/io.github.treramey.raindrop-bookmarks/clear-bookmarks"
omarchy plugin remove io.github.treramey.raindrop-bookmarks
```

Removal leaves your Raindrop token file in place. Delete it yourself if no
other tool uses it. See [what gets cleared](docs/privacy.md#clear-local-data).

For tests and contributor setup, see [development](docs/development.md).
