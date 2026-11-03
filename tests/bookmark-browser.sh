#!/bin/bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
shell_dir=${OMARCHY_PATH:-/usr/share/omarchy}/shell
work_dir=$(mktemp -d)
trap 'rm -rf -- "$work_dir"' EXIT

mkdir -p "$work_dir/config" "$work_dir/home"
for module in Commons Ui services; do
  ln -s "$shell_dir/$module" "$work_dir/config/$module"
done
cp "$repo_dir/BookmarkBrowser.qml" "$work_dir/config/"
cp "$repo_dir/tests/bookmark-browser.qml" "$work_dir/config/shell.qml"

# Render the real components offscreen. Never open an overlay on the user's
# desktop or read their bookmarks, credentials, cache, or active theme files.
if ! HOME="$work_dir/home" XDG_CONFIG_HOME="$work_dir/home/.config" \
  XDG_DATA_HOME="$work_dir/home/.local/share" XDG_CACHE_HOME="$work_dir/home/.cache" \
  QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
  timeout 10s quickshell --no-color -p "$work_dir/config" > "$work_dir/output" 2>&1; then
  cat "$work_dir/output"
  exit 1
fi
cat "$work_dir/output"
if grep -Eq '(TypeError|ReferenceError|Binding loop|Unable to assign)' "$work_dir/output"; then
  exit 1
fi
grep -q 'Bookmark browser checks passed' "$work_dir/output"
