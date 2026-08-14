# Raindrop Bookmarks for Omarchy

A keyboard-first Omarchy Quattro overlay for fuzzy-searching your
[Raindrop.io](https://raindrop.io/) bookmarks. Bookmark covers are cached as
small PNG thumbnails, with a letter tile used whenever no usable cover exists.

## Requirements

- Omarchy Quattro
- `curl`, `jq`, `file`, `python3`, `timeout`, and ImageMagick's `magick`
- A Raindrop.io test token from
  [Settings → Integrations](https://app.raindrop.io/settings/integrations)

Install the non-default dependencies with:

```sh
omarchy pkg add jq imagemagick python
```

## Configure

Store your Raindrop token outside the plugin repository:

```sh
install -d -m 700 ~/.config/raindrop
printf '%s\n' 'YOUR_RAINDROP_TEST_TOKEN' > ~/.config/raindrop/token
chmod 600 ~/.config/raindrop/token
```

Set `RAINDROP_TOKEN_FILE` before starting Omarchy Shell if you prefer another
token location.

## Install

```sh
omarchy plugin add https://github.com/treramey/omarchy-raindrop-bookmarks.git --enable
```

Open the overlay from a terminal:

```sh
omarchy-shell shell summon io.github.treramey.raindrop-bookmarks '{}'
```

## Use

- Type to fuzzy-search titles, domains, tags, and URLs.
- Use `Up`, `Down`, `Page Up`, and `Page Down` to move through results.
- Press `Enter` to open the selected bookmark.
- Press `Escape` to clear the query, then press it again to close the overlay.
- Click outside the card to close it.

## Data and security

Omarchy plugins run unsandboxed with your user permissions. This plugin:

- reads only the configured Raindrop token file;
- sends that token only to `https://api.raindrop.io`;
- downloads only HTTPS cover URLs on port 443 whose DNS answers are all public;
- pins each cover request to its validated address, disables redirects and
  proxies, and enforces strict connection, transfer-time, and 5 MiB limits;
- accepts only PNG, JPEG, GIF, and WebP covers and processes them under a
  restrictive ImageMagick resource and codec policy;
- stores generated thumbnails under
  `~/.cache/omarchy-shell/raindrop-bookmarks/covers`; and
- opens selected links through `xdg-open`.

The token is never copied into the plugin directory. Cover thumbnails older
than 30 days are removed during synchronization.

## Remove

```sh
omarchy plugin remove io.github.treramey.raindrop-bookmarks
rm -rf ~/.cache/omarchy-shell/raindrop-bookmarks
```

Removal intentionally leaves `~/.config/raindrop/token` in place because it is
user-owned configuration that may be shared by other Raindrop tools.

## Development

```sh
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" RaindropBookmarks.qml
bash -n cover-sync
tests/security.sh
```

The implementation follows the Omarchy marketplace
[development](https://omarchyplugins.com/develop.html) and
[publishing](https://omarchyplugins.com/publish.html) guides.
