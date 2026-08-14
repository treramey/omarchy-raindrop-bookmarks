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
mkdir -p "$fake_bin" "$fake_cache"
printf '%s\n' 'test-token' > "$temporary_dir/token"
cat > "$temporary_dir/api.json" <<'JSON'
{"items":[
  {"_id":1,"cover":"https://127.0.0.1/private.png"},
  {"_id":2,"cover":"https://1.1.1.1/public.png"}
]}
JSON

cat > "$fake_bin/curl" <<'CURL'
#!/bin/bash
set -euo pipefail

arguments=("$@")
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
    require_pair --max-filesize 10485760
    cat "$API_FIXTURE"
    ;;
  https://1.1.1.1/public.png)
    require_pair --resolve '1.1.1.1:443:1.1.1.1'
    require_pair --max-filesize 5242880
    cp "$IMAGE_FIXTURE" "$output"
    ;;
  *)
    : > "$SSRF_MARKER"
    exit 91
    ;;
esac
CURL
chmod +x "$fake_bin/curl"

PATH="$fake_bin:$PATH" \
  API_FIXTURE="$temporary_dir/api.json" \
  IMAGE_FIXTURE="$temporary_dir/allowed.png" \
  CURL_LOG="$temporary_dir/curl.log" \
  SSRF_MARKER="$temporary_dir/ssrf-attempted" \
  "$repo_dir/cover-sync" "$temporary_dir/token" "$fake_cache" \
  > "$temporary_dir/index.tsv"

[[ ! -e "$temporary_dir/ssrf-attempted" ]]
[[ ! -e "$fake_cache/1.png" ]]
[[ -s "$fake_cache/2.png" ]]
[[ $(wc -l < "$temporary_dir/curl.log") -eq 2 ]]

printf 'security checks passed: %d unsafe URLs rejected\n' "${#rejects[@]}"
