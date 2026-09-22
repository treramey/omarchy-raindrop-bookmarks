#!/bin/bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
guard="$repo_dir/validate-cover-url"
policy_dir="$repo_dir/imagemagick"
temporary_dir=$(mktemp -d)
trap 'rm -rf "$temporary_dir"' EXIT

rejects=(
  'http://example.com/image.png'
  'file:///etc/passwd'
  'https://localhost/image.png'
  'https://127.0.0.1/image.png'
  'https://10.0.0.1/image.png'
  'https://169.254.169.254/latest/meta-data/'
  'https://0.0.0.0/image.png'
  'https://[::1]/image.png'
  'https://user:pass@8.8.8.8/image.png'
  'https://8.8.8.8:8443/image.png'
  'https://2130706433/image.png'
  'https://0177.0.0.1/image.png'
  'https://8.8.8.8./image.png'
  'https://8.8.8.8%00.example/image.png'
  'https://8.8.8.8:443@127.0.0.1/image.png'
  $'https://8.8.8.8/image.png\nfile:///etc/passwd'
  'https:\8.8.8.8\image.png'
)

for url in "${rejects[@]}"; do
  if "$guard" "$url" >/dev/null 2>&1; then
    printf 'unsafe URL accepted: %q\n' "$url" >&2
    exit 1
  fi
done

accepted=$("$guard" 'https://1.1.1.1:443/image.png#ignored')
[[ "$accepted" == $'1.1.1.1\t1.1.1.1\thttps://1.1.1.1/image.png' ]]

magick -size 16x16 xc:navy "$temporary_dir/allowed.png"
MAGICK_CONFIGURE_PATH="$policy_dir" \
  magick "$temporary_dir/allowed.png" "PNG:$temporary_dir/output.png"

cat > "$temporary_dir/denied.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16">
  <rect width="16" height="16" fill="navy"/>
</svg>
SVG
if MAGICK_CONFIGURE_PATH="$policy_dir" \
    magick "$temporary_dir/denied.svg" "$temporary_dir/output-svg.png" \
    >/dev/null 2>&1; then
  echo "unsafe SVG coder accepted" >&2
  exit 1
fi

magick -size 9000x1 xc:white "$temporary_dir/too-wide.png"
if MAGICK_CONFIGURE_PATH="$policy_dir" \
    magick identify -ping "$temporary_dir/too-wide.png" >/dev/null 2>&1; then
  echo "oversized image dimensions accepted" >&2
  exit 1
fi

fake_bin="$temporary_dir/bin"
fake_cache="$temporary_dir/cache"
snapshot_dir="$temporary_dir/snapshot"
snapshot_path="$snapshot_dir/bookmarks.json"
mkdir -p "$fake_bin" "$fake_cache" "$snapshot_dir"
printf '%s\n' 'test-token' > "$temporary_dir/token"
token_fingerprint=$("$repo_dir/token-fingerprint" "$temporary_dir/token")
jq -n --arg token_fingerprint "$token_fingerprint" '{
  version: 1,
  tokenFingerprint: $token_fingerprint,
  syncedAt: 1,
  bookmarks: [
    {_id: 1, cover: "https://127.0.0.1/private.png"},
    {_id: 2, cover: "https://1.1.1.1/public.png"}
  ]
}' > "$snapshot_path"
chmod 600 "$snapshot_path"

cat > "$fake_bin/curl" <<'CURL'
#!/bin/bash
set -euo pipefail

arguments=("$@")
[[ ${arguments[0]:-} == -q ]] || {
  echo "curl must ignore user configuration with -q as its first argument" >&2
  exit 89
}
url=""
output=""

require_pair() {
  local option=$1
  local expected=$2
  local index
  for ((index = 0; index + 1 < ${#arguments[@]}; index++)); do
    if [[ "${arguments[index]}" == "$option" \
        && "${arguments[index + 1]}" == "$expected" ]]; then
      return 0
    fi
  done
  printf 'curl is missing %s %s\n' "$option" "$expected" >&2
  exit 90
}

for ((index = 0; index + 1 < ${#arguments[@]}; index++)); do
  case "${arguments[index]}" in
    --url) url=${arguments[index + 1]} ;;
    --output) output=${arguments[index + 1]} ;;
  esac
done

printf '%s\n' "$url" >> "$CURL_LOG"
require_pair --proto '=https'
require_pair --proto-redir '=https'
require_pair --max-redirs 0
require_pair --noproxy '*'

case "$url" in
  https://api.raindrop.io/*)
    : > "$API_MARKER"
    exit 91
    ;;
  https://1.1.1.1/public.png)
    require_pair --resolve '1.1.1.1:443:1.1.1.1'
    require_pair --max-filesize 5242880
    cp "$IMAGE_FIXTURE" "$output"
    ;;
  https://1.1.1.1/changed.png)
    require_pair --resolve '1.1.1.1:443:1.1.1.1'
    require_pair --max-filesize 5242880
    cp "$CHANGED_IMAGE_FIXTURE" "$output"
    ;;
  *)
    : > "$SSRF_MARKER"
    exit 91
    ;;
esac
CURL
chmod +x "$fake_bin/curl"

PATH="$fake_bin:$PATH" \
  IMAGE_FIXTURE="$temporary_dir/allowed.png" \
  CURL_LOG="$temporary_dir/curl.log" \
  SSRF_MARKER="$temporary_dir/ssrf-attempted" \
  API_MARKER="$temporary_dir/api-requested" \
  "$repo_dir/cover-sync" "$temporary_dir/token" "$fake_cache" "$snapshot_path" --force \
  > "$temporary_dir/index.tsv"

[[ ! -e "$temporary_dir/ssrf-attempted" ]]
[[ ! -e "$temporary_dir/api-requested" ]]
[[ ! -e "$fake_cache/1.png" ]]
[[ -s "$fake_cache/2.png" ]]
[[ $(wc -l < "$temporary_dir/curl.log") -eq 1 ]]

magick -size 16x16 xc:red "$temporary_dir/changed.png"
jq -n --arg token_fingerprint "$token_fingerprint" '{
  version: 1,
  tokenFingerprint: $token_fingerprint,
  syncedAt: 2,
  bookmarks: [{_id: 2, cover: "https://1.1.1.1/changed.png"}]
}' > "$snapshot_path"
PATH="$fake_bin:$PATH" \
  IMAGE_FIXTURE="$temporary_dir/allowed.png" \
  CHANGED_IMAGE_FIXTURE="$temporary_dir/changed.png" \
  CURL_LOG="$temporary_dir/curl.log" \
  SSRF_MARKER="$temporary_dir/ssrf-attempted" \
  API_MARKER="$temporary_dir/api-requested" \
  "$repo_dir/cover-sync" "$temporary_dir/token" "$fake_cache" "$snapshot_path" --force \
  > "$temporary_dir/index-changed.tsv"
compare -metric AE "$fake_cache/2.png" "$temporary_dir/changed.png" null: \
  >/dev/null 2>&1

! grep -q 'https://api.raindrop.io/' "$temporary_dir/curl.log"

printf 'security checks passed: %d unsafe URLs rejected\n' "${#rejects[@]}"
