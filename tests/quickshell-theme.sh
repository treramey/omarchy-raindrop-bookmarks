#!/bin/bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
shell_dir=${OMARCHY_PATH:-/usr/share/omarchy}/shell
work_dir=$(mktemp -d)
trap 'rm -rf -- "$work_dir"' EXIT

# Use the real installed shell modules and Qt runtime without opening a window
# or accessing the user's token, cache, or theme.
mkdir -p "$work_dir/config" "$work_dir/home"
for module in Commons Ui services; do
  ln -s "$shell_dir/$module" "$work_dir/config/$module"
done
cp "$repo_dir/RaindropBookmarks.qml" "$repo_dir/FuzzySearch.js" "$work_dir/config/"
cp "$repo_dir/tests/quickshell-theme.qml" "$work_dir/config/shell.qml"

if ! HOME="$work_dir/home" XDG_CONFIG_HOME="$work_dir/home/.config" \
  XDG_DATA_HOME="$work_dir/home/.local/share" XDG_CACHE_HOME="$work_dir/home/.cache" \
  QT_QPA_PLATFORM=wayland timeout 10s quickshell --no-color -p "$work_dir/config" \
  >"$work_dir/output" 2>&1; then
  cat "$work_dir/output"
  exit 1
fi
cat "$work_dir/output"
if grep -Eq 'RaindropBookmarks.qml.*(TypeError|Unable to assign)|Raindrop theme mismatch' "$work_dir/output"; then
  exit 1
fi
grep -q 'Raindrop theme bindings passed' "$work_dir/output"
