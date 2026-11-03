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

# Inspect the actual parser boundary and then exec the real ImageMagick binary.
# Check the limit before allocating so a regression cannot exhaust the test host.
export REAL_MAGICK
REAL_MAGICK=$(command -v magick)
export MAGICK_LIMIT_LOG="$temporary_dir/magick-limits.log"
export EXPECTED_IMAGE_MEMORY_KIB=262144
cat > "$fake_bin/magick" <<'MAGICK'
#!/usr/bin/env python3
import os
import resource
import sys

with open(os.environ["MAGICK_LIMIT_LOG"], "a") as log:
    log.write("identify\n" if sys.argv[1] == "identify" else "convert\n")
limit_bytes = int(os.environ["EXPECTED_IMAGE_MEMORY_KIB"]) * 1024
soft, hard = resource.getrlimit(resource.RLIMIT_AS)
if not (0 < soft <= hard <= limit_bytes):
    sys.exit("image parser lacks a hard address-space limit")
try:
    bytearray(limit_bytes)
except MemoryError:
    pass
else:
    sys.exit("image parser allocation exceeded its memory budget")
os.execv(os.environ["REAL_MAGICK"], [os.environ["REAL_MAGICK"], *sys.argv[1:]])
MAGICK
chmod +x "$fake_bin/magick"

sync_cover_fixture() {
  local image=$1
  local cache=$2
  local index=$3
  PATH="$fake_bin:$PATH" \
    IMAGE_FIXTURE="$image" \
    CHANGED_IMAGE_FIXTURE="$temporary_dir/changed.png" \
    CURL_LOG="$temporary_dir/curl.log" \
    SSRF_MARKER="$temporary_dir/ssrf-attempted" \
    API_MARKER="$temporary_dir/api-requested" \
    "$repo_dir/cover-sync" "$temporary_dir/token" "$cache" "$snapshot_path" --force \
    > "$index"
}

sync_cover_fixture "$temporary_dir/allowed.png" "$fake_cache" "$temporary_dir/index.tsv"

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
sync_cover_fixture "$temporary_dir/allowed.png" "$fake_cache" "$temporary_dir/index-changed.tsv"
compare -metric AE "$fake_cache/2.png" "$temporary_dir/changed.png" null: \
  >/dev/null 2>&1

[[ $(cat "$MAGICK_LIMIT_LOG") == $'identify\nconvert\nidentify\nconvert' ]]

# A tiny PNG can retain hundreds of MiB of decompressed text before pixel
# conversion. Keep the real decoder under the checked cap even in a broken build.
python3 - "$temporary_dir/allowed.png" "$temporary_dir/metadata.png" <<'PY'
from pathlib import Path
import struct
import sys
import zlib

png = Path(sys.argv[1]).read_bytes()
compressed = zlib.compress(b"x" * (4 * 1024 * 1024))
with Path(sys.argv[2]).open("wb") as output:
    output.write(png[:33])  # Signature and IHDR.
    for index in range(80):
        data = f"Comment{index}".encode() + b"\0\0" + compressed
        chunk = b"zTXt" + data
        output.write(struct.pack(">I", len(data)))
        output.write(chunk)
        output.write(struct.pack(">I", zlib.crc32(chunk)))
    output.write(png[33:])
PY
[[ $(stat -c %s "$temporary_dir/metadata.png") -lt 5242880 ]]
jq '.bookmarks = [{_id: 3, cover: "https://1.1.1.1/public.png"}]' \
  "$snapshot_path" > "$snapshot_path.tmp"
mv "$snapshot_path.tmp" "$snapshot_path"
sync_cover_fixture "$temporary_dir/metadata.png" "$fake_cache" "$temporary_dir/index-metadata.tsv"
[[ $(sed -n '5p' "$MAGICK_LIMIT_LOG") == identify ]]
[[ -s "$fake_cache/2.png" ]]
grep -q $'^2\t' "$temporary_dir/index-metadata.tsv"
# libpng versions may discard excessive text and still produce a safe thumbnail.
if [[ -e "$fake_cache/3.png" ]]; then
  [[ $(stat -c %s "$fake_cache/3.png") -lt 65536 ]]
fi
[[ -z $(find "$fake_cache" -maxdepth 1 -name '.download-*' -print -quit) ]]

# Exercise real decoders on multi-megapixel covers. Run each format with the
# default cap and with stricter inherited soft and hard caps. A soft-only cap
# catches accidentally raising the user's limit when the hard cap allows it.
for format in png jpg gif webp; do
  fixture="$temporary_dir/cover.$format"
  magick -size 2048x1536 gradient:'#17324d-#e0a34f' -depth 8 "$fixture"
  [[ $(stat -c %s "$fixture") -lt 5242880 ]]
  for limits in default soft hard; do
    cache="$temporary_dir/cache-$format-$limits"
    index="$temporary_dir/index-$format-$limits.tsv"
    (
      if [[ "$limits" == soft ]]; then
        ulimit -Sv 196608
      elif [[ "$limits" == hard ]]; then
        ulimit -v 196608
      fi
      if [[ "$limits" != default ]]; then
        export EXPECTED_IMAGE_MEMORY_KIB=196608
      fi
      sync_cover_fixture "$fixture" "$cache" "$index"
    )
    [[ $(magick identify -format '%m %w %h' "$cache/3.png") == 'PNG 96 72' ]]
    grep -q $'^3\t' "$index"
    [[ -z $(find "$cache" -maxdepth 1 -name '.download-*' -print -quit) ]]
  done
done

# Inject failure at the Bash resource-limit boundary. Neither query nor set
# failure may launch the parser or discard a previously cached thumbnail.
cat > "$temporary_dir/fail-ulimit.bash" <<'LIMIT'
ulimit() {
  if [[ "$1" == "$FAIL_ULIMIT_OPTION" ]]; then
    return 1
  fi
  builtin ulimit "$@"
}
LIMIT
for option in -Sv -v; do
  cache="$temporary_dir/cache-failed-$option"
  index="$temporary_dir/index-failed-$option.tsv"
  mkdir "$cache"
  cp "$fake_cache/2.png" "$cache/2.png"
  calls_before=$(wc -l < "$MAGICK_LIMIT_LOG")
  BASH_ENV="$temporary_dir/fail-ulimit.bash" FAIL_ULIMIT_OPTION="$option" \
    sync_cover_fixture "$temporary_dir/allowed.png" "$cache" "$index"
  [[ $(wc -l < "$MAGICK_LIMIT_LOG") -eq "$calls_before" ]]
  [[ ! -e "$cache/3.png" ]]
  grep -q $'^2\t' "$index"
  [[ -z $(find "$cache" -maxdepth 1 -name '.download-*' -print -quit) ]]
done

! grep -q 'https://api.raindrop.io/' "$temporary_dir/curl.log"

printf 'security checks passed: %d unsafe URLs rejected\n' "${#rejects[@]}"
