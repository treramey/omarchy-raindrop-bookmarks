#!/bin/bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
temporary_dir=$(mktemp -d)
trap 'rm -rf "$temporary_dir"' EXIT

fake_bin="$temporary_dir/bin"
data_home="$temporary_dir/data"
cache_home="$temporary_dir/cache"
mkdir -p "$fake_bin" "$data_home" "$cache_home"

cat > "$fake_bin/curl" <<'CURL'
#!/bin/bash
set -euo pipefail

arguments=("$@")
[[ ${arguments[0]:-} == -q ]]
url=""
output=""
headers=""
for ((index = 0; index + 1 < ${#arguments[@]}; index++)); do
  case "${arguments[index]}" in
    --url) url=${arguments[index + 1]} ;;
    --output) output=${arguments[index + 1]} ;;
    --dump-header) headers=${arguments[index + 1]} ;;
  esac
done

printf '%s\n' "$url" >> "$CURL_LOG"
require_pair() {
  local option=$1
  local expected=$2
  local index
  for ((index = 0; index + 1 < ${#arguments[@]}; index++)); do
    if [[ ${arguments[index]} == "$option" && ${arguments[index + 1]} == "$expected" ]]; then
      return 0
    fi
  done
  printf 'missing curl option: %s %s\n' "$option" "$expected" >&2
  exit 90
}
require_pair --proto '=https'
require_pair --proto-redir '=https'
require_pair --max-redirs 0
require_pair --noproxy '*'
require_pair --connect-timeout 5
require_pair --max-time 20
require_pair --max-filesize 10485760
for ((index = 0; index + 1 < ${#arguments[@]}; index++)); do
  if [[ ${arguments[index]} == --header ]]; then
    header=${arguments[index + 1]#@}
    [[ $(< "$header") == 'Authorization: Bearer sync-token' ]]
    break
  fi
done
printf 'HTTP/1.1 200 OK\r\n\r\n' > "$headers"
if [[ ${RATE_LIMIT_MODE:-} == true ]]; then
  printf 'HTTP/1.1 429 Too Many Requests\r\nRetry-After: 120\r\n\r\n' > "$headers"
  exit 22
fi
if [[ ${FAIL_PAGE:-} == 1 && "$url" == *'page=1' ]]; then
  exit 22
fi

if [[ ${EMPTY_MODE:-} == true ]]; then
  printf '{"items":[]}\n' > "$output"
elif [[ "$url" == *'page=0' ]]; then
  python3 - <<'PY' > "$output"
import json
print(json.dumps({"items": [{"_id": index, "title": f"Bookmark {index}", "link": "https://example.com/"} for index in range(50)]}))
PY
else
  printf '%s\n' '{"items":[{"_id":50,"title":"Bookmark 50","link":"https://example.com/50"}]}' > "$output"
fi
CURL
chmod +x "$fake_bin/curl"

token_path="$temporary_dir/token"
snapshot_path="$data_home/omarchy-shell/raindrop-bookmarks/bookmarks.json"
printf '%s\n' 'sync-token' > "$token_path"

PATH="$fake_bin:$PATH" CURL_LOG="$temporary_dir/curl.log" \
  XDG_DATA_HOME="$data_home" \
  "$repo_dir/bookmark-sync" "$token_path" "$snapshot_path"

[[ $(jq '.version' "$snapshot_path") == 1 ]]
[[ $(jq '.bookmarks | length' "$snapshot_path") == 51 ]]
[[ $(jq -r '.tokenFingerprint' "$snapshot_path") != 'sync-token' ]]
[[ $(stat -c %a "$snapshot_path") == 600 ]]
[[ $(stat -c %a "$(dirname "$snapshot_path")") == 700 ]]
[[ $(PATH="$fake_bin:$PATH" "$repo_dir/load-bookmarks" "$token_path" "$snapshot_path" | jq '.bookmarks | length') == 51 ]]

printf '%s\n' 'different-token' > "$temporary_dir/different-token"
if "$repo_dir/load-bookmarks" "$temporary_dir/different-token" "$snapshot_path" >/dev/null 2>&1; then
  echo 'load-bookmarks accepted a snapshot for a different token' >&2
  exit 1
fi

cp "$snapshot_path" "$temporary_dir/previous-snapshot"
if PATH="$fake_bin:$PATH" FAIL_PAGE=1 CURL_LOG="$temporary_dir/curl.log" \
    "$repo_dir/bookmark-sync" "$token_path" "$snapshot_path"; then
  echo 'bookmark-sync accepted an interrupted refresh' >&2
  exit 1
fi
cmp "$temporary_dir/previous-snapshot" "$snapshot_path"

curl_count=$(wc -l < "$temporary_dir/curl.log")
if PATH="$fake_bin:$PATH" CURL_LOG="$temporary_dir/curl.log" \
    "$repo_dir/bookmark-sync" "$token_path" "$snapshot_path"; then
  echo 'bookmark-sync ignored the failure cooldown' >&2
  exit 1
fi
[[ $(wc -l < "$temporary_dir/curl.log") == "$curl_count" ]]

PATH="$fake_bin:$PATH" EMPTY_MODE=true CURL_LOG="$temporary_dir/curl.log" \
  "$repo_dir/bookmark-sync" "$token_path" "$snapshot_path" --manual
[[ $(jq '.bookmarks | length' "$snapshot_path") == 0 ]]

if PATH="$fake_bin:$PATH" RATE_LIMIT_MODE=true CURL_LOG="$temporary_dir/curl.log" \
    "$repo_dir/bookmark-sync" "$token_path" "$snapshot_path" --manual; then
  echo 'bookmark-sync accepted a rate-limited refresh' >&2
  exit 1
fi
rate_limit_reset=$(jq -r '.rateLimitReset' "$(dirname "$snapshot_path")/sync-state.json")
[[ "$rate_limit_reset" =~ ^[0-9]+$ && "$rate_limit_reset" -gt "$(date +%s)" ]]
curl_count=$(wc -l < "$temporary_dir/curl.log")
if PATH="$fake_bin:$PATH" RATE_LIMIT_MODE=true CURL_LOG="$temporary_dir/curl.log" \
    "$repo_dir/bookmark-sync" "$token_path" "$snapshot_path" --manual; then
  echo 'bookmark-sync ignored the rate-limit reset' >&2
  exit 1
fi
[[ $(wc -l < "$temporary_dir/curl.log") == "$curl_count" ]]

XDG_DATA_HOME="$data_home" XDG_CACHE_HOME="$cache_home" \
  "$repo_dir/clear-bookmarks"
[[ ! -e "$data_home/omarchy-shell/raindrop-bookmarks" ]]
[[ ! -e "$cache_home/omarchy-shell/raindrop-bookmarks" ]]
