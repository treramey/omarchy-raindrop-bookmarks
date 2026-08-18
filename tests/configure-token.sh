#!/bin/bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
temporary_dir=$(mktemp -d)
trap 'rm -rf "$temporary_dir"' EXIT

token_path="$temporary_dir/config/raindrop/token"
printf '%s\n' 'test token with spaces' | "$repo_dir/configure-token" "$token_path"

[[ $(< "$token_path") == 'test token with spaces' ]]
[[ $(stat -c %a "$temporary_dir/config/raindrop") == 700 ]]
[[ $(stat -c %a "$token_path") == 600 ]]

printf '%s\n' 'do not replace' > "$temporary_dir/victim"
rm -f "$token_path"
ln -s "$temporary_dir/victim" "$token_path"
printf '%s\n' 'replacement token' | "$repo_dir/configure-token" "$token_path"
[[ ! -L "$token_path" ]]
[[ $(< "$token_path") == 'replacement token' ]]
[[ $(< "$temporary_dir/victim") == 'do not replace' ]]

if printf '\n' | "$repo_dir/configure-token" "$token_path" >/dev/null 2>&1; then
  echo "configure-token accepted an empty token" >&2
  exit 1
fi
if printf 'token\r\n' | "$repo_dir/configure-token" "$token_path" >/dev/null 2>&1; then
  echo "configure-token accepted a carriage return" >&2
  exit 1
fi

echo "token configuration checks passed"
