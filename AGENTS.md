## Changesets

- Pull requests changing plugin runtime files MUST include `.changeset/<descriptive-name>.md`.
- Use package `io.github.treramey.raindrop-bookmarks`: `patch` for fixes/chores, `minor` for features, and `major` for breaking changes.
- Documentation, tests, and internal CI-only changes are exempt. Use `pnpm changeset --empty` for runtime changes with no user-visible impact.
- Do not edit release versions manually; the release PR synchronizes `package.json` and `manifest.json`.

## Commits

- Use Conventional Commit subjects such as `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, and `chore:`.
- Use `!` or a `BREAKING CHANGE:` footer for breaking changes.

## Safety

- Preserve the cover pipeline's SSRF, DNS-pinning, curl, file-size, timeout, codec, and ImageMagick resource controls.
- Run `bash -n cover-sync tests/security.sh`, `python3 -m py_compile validate-cover-url`, and `tests/security.sh` after changing network, cache, or image handling.
