#!/bin/bash
set -euo pipefail

if [[ ! -t 0 ]]; then
  echo "Run this script from an interactive terminal." >&2
  exit 1
fi

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
plugin_id=io.github.treramey.raindrop-bookmarks
plugin_dir="$config_home/omarchy/plugins/$plugin_id"
token_path=${RAINDROP_TOKEN_FILE:-$config_home/raindrop/token}
backup_dir=$(mktemp -d)
had_plugin=false
had_token=false
installed_test_plugin=false

restore() {
  local exit_code=$?
  trap - EXIT INT TERM

  if [[ "$installed_test_plugin" == true ]]; then
    echo
    echo "Restoring your plugin and token…"
    rm -rf -- "$plugin_dir"
    if [[ "$had_plugin" == true ]]; then
      mkdir -p -- "$(dirname -- "$plugin_dir")"
      mv -- "$backup_dir/plugin" "$plugin_dir"
    fi

    rm -f -- "$token_path"
    if [[ "$had_token" == true ]]; then
      mkdir -p -- "$(dirname -- "$token_path")"
      mv -- "$backup_dir/token" "$token_path"
    fi

    omarchy-restart-shell || true
  fi

  rm -rf -- "$backup_dir"
  exit "$exit_code"
}
trap restore EXIT INT TERM

echo "Running checks…"
(
  cd -- "$repo_dir"
  bash -n configure-token cover-sync tests/configure-token.sh tests/security.sh
  python3 -m py_compile validate-cover-url
  qmllint -I "$OMARCHY_PATH/shell" RaindropBookmarks.qml
  tests/configure-token.sh
  tests/security.sh
  omarchy plugin validate .
)

mkdir -p -- "$(dirname -- "$plugin_dir")"
installed_test_plugin=true
if [[ -e "$plugin_dir" || -L "$plugin_dir" ]]; then
  mv -- "$plugin_dir" "$backup_dir/plugin"
  had_plugin=true
fi

if [[ -e "$token_path" || -L "$token_path" ]]; then
  mv -- "$token_path" "$backup_dir/token"
  had_token=true
fi

mkdir -p -- "$plugin_dir"
cp -a -- "$repo_dir/." "$plugin_dir/"
rm -rf -- "$plugin_dir/.git" "$plugin_dir/node_modules"

echo "Restarting Omarchy Shell with the local plugin…"
omarchy-restart-shell
sleep 2
omarchy-shell shell summon "$plugin_id" '{}'

cat <<'EOF'

The onboarding overlay should now be open.

Check that:
  1. The Connect Raindrop screen appears.
  2. Get Raindrop token closes the overlay and opens Raindrop integrations.
  3. Connect Raindrop stays disabled until you enter a token.
  4. A valid token loads your bookmarks.

Your existing plugin and token are safely backed up for this test.
EOF

read -r -p "Press Enter when finished to restore them… "
