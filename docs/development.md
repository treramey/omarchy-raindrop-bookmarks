# Development

Test onboarding from the current checkout:

```sh
scripts/test-onboarding.sh
```

The script restores your installed plugin and token when you finish. It does
not back up or restore bookmark snapshots or cover caches. Connecting during
the test can replace those files with data for the test token.

Or run the checks directly:

```sh
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" RaindropBookmarks.qml BookmarkBrowser.qml RaindropConnection.qml
for script in configure-token validate-token token-fingerprint load-bookmarks bookmark-sync clear-bookmarks cover-sync scripts/*.sh tests/*.sh; do
  bash -n "$script" || break
done
python3 -m py_compile validate-cover-url bookmark-json
python3 tests/bookmark-json.py
tests/configure-token.sh
tests/validate-token.sh
tests/raindrop-connection.sh
tests/bookmark-sync.sh
tests/security.sh
tests/bookmark-browser.sh
tests/quickshell-theme.sh
```

`tests/security.sh` uses ImageMagick to generate and inspect test images.
ImageMagick is a development-test tool, not a plugin runtime requirement.
Bookmark and cover metadata at runtime use Python's standard JSON library.

Runtime changes require a Changesets entry (`pnpm changeset`). The release
pull request updates `package.json` and `manifest.json`. Use Conventional
Commit subjects.

Changesets tooling requires `pnpm install`. Its local `node_modules` tree
contains symlinks, which Omarchy's plugin validator rejects. Remove it
before validating the plugin folder:

```sh
rm -rf node_modules
omarchy plugin validate .
```

See the Omarchy marketplace guides for
[development](https://omarchyplugins.com/develop.html) and
[publishing](https://omarchyplugins.com/publish.html).
