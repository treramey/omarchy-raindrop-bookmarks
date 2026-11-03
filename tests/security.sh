#!/bin/bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
guard="$repo_dir/validate-cover-url"
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
helper_hash=$(sha256sum "$repo_dir/cover-thumbnail.cpp" | cut -d ' ' -f 1)
qt_version=$(pkg-config --modversion Qt6Gui)
helper_name=".cover-thumbnail-$qt_version-$helper_hash"

cat > "$temporary_dir/denied.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16">
  <rect width="16" height="16" fill="navy"/>
</svg>
SVG

fake_bin="$temporary_dir/bin"
fake_cache="$temporary_dir/cache"
snapshot_dir="$temporary_dir/snapshot"
snapshot_path="$snapshot_dir/bookmarks.json"
mkdir -p "$fake_bin" "$fake_cache" "$snapshot_dir"
printf '%s\n' 'test-token' > "$temporary_dir/token"
token_fingerprint=$("$repo_dir/token-fingerprint" "$temporary_dir/token")
python3 - "$token_fingerprint" "$snapshot_path" <<'PY'
import json
import sys
with open(sys.argv[2], "w") as output:
    json.dump({"version": 1, "tokenFingerprint": sys.argv[1], "syncedAt": 1,
               "bookmarks": [{"_id": 1, "cover": "https://127.0.0.1/private.png"},
                             {"_id": 2, "cover": "https://1.1.1.1/public.png"},
                             {"_id": "12\u0000", "cover": "https://1.1.1.1/public.png"}]}, output)
PY
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

# Inspect the actual parser boundary before execing the compiled Qt helper.
export THUMBNAIL_LIMIT_LOG="$temporary_dir/thumbnail-limits.log"
export EXPECTED_IMAGE_MEMORY_KIB=262144
cat > "$temporary_dir/check-thumbnail-limit" <<'THUMBNAIL'
#!/usr/bin/env python3
import os
import resource
import sys

with open(os.environ["THUMBNAIL_LIMIT_LOG"], "a") as log:
    log.write("decode\n")
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
os.execv(os.environ["REAL_THUMBNAIL"], [os.environ["REAL_THUMBNAIL"], *sys.argv[1:]])
THUMBNAIL
chmod +x "$temporary_dir/check-thumbnail-limit"

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
[[ ! -e "$fake_cache/12.png" ]]
[[ -s "$fake_cache/2.png" ]]
[[ $(wc -l < "$temporary_dir/curl.log") -eq 1 ]]
[[ $(magick identify -format '%m %w %h' "$fake_cache/2.png") == 'PNG 16 16' ]]

# First-use compilation failure must not discard an older cached thumbnail.
mkdir "$temporary_dir/cache-build-failed"
cp "$fake_cache/2.png" "$temporary_dir/cache-build-failed/2.png"
printf '#!/bin/sh\nexit 1\n' > "$fake_bin/g++"
chmod +x "$fake_bin/g++"
sync_cover_fixture "$temporary_dir/allowed.png" "$temporary_dir/cache-build-failed" \
  "$temporary_dir/index-build-failed.tsv" 2>/dev/null
rm "$fake_bin/g++"
grep -q $'^2\t' "$temporary_dir/index-build-failed.tsv"
[[ ! -e "$temporary_dir/cache-build-failed/3.png" ]]
[[ -z $(find "$temporary_dir/cache-build-failed" -maxdepth 1 -name '.cover-thumbnail-build-??????' -print -quit) ]]

# A held build lock must have a bounded wait and retain the cached index.
mkdir "$temporary_dir/cache-lock-failed"
cp "$fake_cache/2.png" "$temporary_dir/cache-lock-failed/2.png"
export FLOCK_MARKER="$temporary_dir/flock-bounded"
cat > "$fake_bin/flock" <<'FLOCK'
#!/bin/sh
if [ "$1" = -x ] && [ "$2" = -w ] && [ "$3" = 35 ] && [ "$4" = 9 ]; then
  : > "$FLOCK_MARKER"
fi
exit 1
FLOCK
chmod +x "$fake_bin/flock"
sync_cover_fixture "$temporary_dir/allowed.png" "$temporary_dir/cache-lock-failed" \
  "$temporary_dir/index-lock-failed.tsv" 2>/dev/null
rm "$fake_bin/flock"
[[ -e "$FLOCK_MARKER" ]]
grep -q $'^2\t' "$temporary_dir/index-lock-failed.tsv"

# Keep the first compiled binary as the real parser; the cache entry becomes
# a wrapper so every subsequent cover checks its inherited address-space cap.
mv "$fake_cache/$helper_name" "$temporary_dir/real-thumbnail"
export REAL_THUMBNAIL="$temporary_dir/real-thumbnail"
cp "$temporary_dir/check-thumbnail-limit" "$fake_cache/$helper_name"
if "$REAL_THUMBNAIL" svg "$temporary_dir/denied.svg" "$temporary_dir/denied.png" 2>/dev/null; then
  echo "unsafe SVG format accepted" >&2
  exit 1
fi
if "$REAL_THUMBNAIL" jpeg "$temporary_dir/allowed.png" "$temporary_dir/wrong-format.png" 2>/dev/null; then
  echo "format mismatch accepted" >&2
  exit 1
fi
magick -size 9000x1 xc:white "$temporary_dir/too-wide.png"
if "$REAL_THUMBNAIL" png "$temporary_dir/too-wide.png" "$temporary_dir/too-wide-result.png" 2>/dev/null; then
  echo "oversized image dimensions accepted" >&2
  exit 1
fi
printf 'broken image' > "$temporary_dir/broken.png"
if "$REAL_THUMBNAIL" png "$temporary_dir/broken.png" "$temporary_dir/broken-result.png" 2>/dev/null; then
  echo "malformed PNG accepted" >&2
  exit 1
fi
magick -size 6000x6000 xc:white "$temporary_dir/too-large.png"
if "$REAL_THUMBNAIL" png "$temporary_dir/too-large.png" "$temporary_dir/too-large-result.png" 2>/dev/null; then
  echo "oversized image area accepted" >&2
  exit 1
fi
magick -size 120x40 xc:blue "$temporary_dir/plain.jpg"
python3 - "$temporary_dir/plain.jpg" "$temporary_dir/oriented.jpg" <<'PY'
from pathlib import Path
import struct
import sys

jpeg = Path(sys.argv[1]).read_bytes()
exif = (b"Exif\0\0II*\0\x08\0\0\0" + struct.pack("<H", 1)
        + struct.pack("<HHI", 0x0112, 3, 1) + struct.pack("<I", 6)
        + struct.pack("<I", 0))
Path(sys.argv[2]).write_bytes(jpeg[:2] + b"\xff\xe1"
                              + struct.pack(">H", len(exif) + 2) + exif + jpeg[2:])
PY
"$REAL_THUMBNAIL" jpeg "$temporary_dir/oriented.jpg" "$temporary_dir/oriented.png"
[[ $(magick identify -format '%w %h' "$temporary_dir/oriented.png") == '32 96' ]]
for dimensions in 1x97 97x1; do
  magick -size "$dimensions" xc:red "$temporary_dir/$dimensions.png"
  "$REAL_THUMBNAIL" png "$temporary_dir/$dimensions.png" "$temporary_dir/$dimensions-thumb.png"
done
[[ $(magick identify -format '%w %h' "$temporary_dir/1x97-thumb.png") == '1 96' ]]
[[ $(magick identify -format '%w %h' "$temporary_dir/97x1-thumb.png") == '96 1' ]]
magick -size 16x16 xc:red -set comment 'private image metadata' "$temporary_dir/text.png"
"$REAL_THUMBNAIL" png "$temporary_dir/text.png" "$temporary_dir/no-text.png"
! grep -aq 'private image metadata' "$temporary_dir/no-text.png"
magick -size 16x16 xc:red "$temporary_dir/red.gif"
magick -size 16x16 xc:blue "$temporary_dir/blue.gif"
magick "$temporary_dir/red.gif" "$temporary_dir/blue.gif" "$temporary_dir/animated.gif"
"$REAL_THUMBNAIL" gif "$temporary_dir/animated.gif" "$temporary_dir/first-frame.png"
[[ $(magick "$temporary_dir/first-frame.png" -format '%[pixel:p{0,0}]' info:) == 'srgba(255,0,0,1)' ]]

magick -size 16x16 xc:red "$temporary_dir/changed.png"
python3 - "$token_fingerprint" "$snapshot_path" <<'PY'
import json
import sys
with open(sys.argv[2], "w") as output:
    json.dump({"version": 1, "tokenFingerprint": sys.argv[1], "syncedAt": 2,
               "bookmarks": [{"_id": 2, "cover": "https://1.1.1.1/changed.png"}]}, output)
PY
sync_cover_fixture "$temporary_dir/allowed.png" "$fake_cache" "$temporary_dir/index-changed.tsv"
compare -metric AE "$fake_cache/2.png" "$temporary_dir/changed.png" null: \
  >/dev/null 2>&1
[[ $(cat "$THUMBNAIL_LIMIT_LOG") == decode ]]

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
python3 - "$snapshot_path" > "$snapshot_path.tmp" <<'PY'
import json
import sys
with open(sys.argv[1]) as source:
    snapshot = json.load(source)
snapshot["bookmarks"] = [{"_id": 3, "cover": "https://1.1.1.1/public.png"}]
json.dump(snapshot, sys.stdout)
PY
mv "$snapshot_path.tmp" "$snapshot_path"
sync_cover_fixture "$temporary_dir/metadata.png" "$fake_cache" "$temporary_dir/index-metadata.tsv"
[[ $(sed -n '2p' "$THUMBNAIL_LIMIT_LOG") == decode ]]
[[ -s "$fake_cache/2.png" ]]
grep -q $'^2\t' "$temporary_dir/index-metadata.tsv"
# libpng versions may discard excessive text and still produce a safe thumbnail.
if [[ -e "$fake_cache/3.png" ]]; then
  [[ $(stat -c %s "$fake_cache/3.png") -lt 65536 ]]
fi
[[ -z $(find "$fake_cache" -maxdepth 1 -name '.download-*' -print -quit) ]]

# Exercise real decoders on larger covers. Run each format with the
# default cap and with stricter inherited soft and hard caps. A soft-only cap
# catches accidentally raising the user's limit when the hard cap allows it.
for format in png jpg gif webp; do
  fixture="$temporary_dir/cover.$format"
  magick -size 1024x768 gradient:'#17324d-#e0a34f' -depth 8 "$fixture"
  [[ $(stat -c %s "$fixture") -lt 5242880 ]]
  for limits in default soft hard; do
    cache="$temporary_dir/cache-$format-$limits"
    index="$temporary_dir/index-$format-$limits.tsv"
    mkdir -p "$cache"
    cp "$temporary_dir/check-thumbnail-limit" "$cache/$helper_name"
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
    if [[ -e "$cache/3.png" ]]; then
      [[ $(magick identify -format '%m %w %h' "$cache/3.png") == 'PNG 96 72' ]]
      grep -q $'^3\t' "$index"
    else
      # A stricter inherited cap may not leave Qt enough address space. It
      # must fail closed rather than publish a partial thumbnail.
      [[ "$limits" != default ]]
      ! grep -q $'^3\t' "$index"
    fi
    [[ -z $(find "$cache" -maxdepth 1 -name '.download-*' -print -quit) ]]
  done
done

# A stalled decoder must be killed at the 10-second image deadline. Preserve
# the last published image and remove partial download files on timeout.
timeout_cache="$temporary_dir/cache-timeout"
mkdir "$timeout_cache"
cp "$fake_cache/2.png" "$timeout_cache/2.png"
printf '#!/bin/sh\nsleep 20\n' > "$timeout_cache/$helper_name"
chmod +x "$timeout_cache/$helper_name"
export REAL_TIMEOUT
REAL_TIMEOUT=$(command -v timeout)
export TIMEOUT_HELPER="$timeout_cache/$helper_name"
export TIMEOUT_MARKER="$temporary_dir/ten-second-timeout"
cat > "$fake_bin/timeout" <<'TIMEOUT'
#!/bin/sh
if [ "$1" = '--kill-after=2' ] && [ "$2" = 10 ] && [ "$3" = "$TIMEOUT_HELPER" ]; then
  : > "$TIMEOUT_MARKER"
fi
exec "$REAL_TIMEOUT" "$@"
TIMEOUT
chmod +x "$fake_bin/timeout"
start_time=$SECONDS
sync_cover_fixture "$temporary_dir/allowed.png" "$timeout_cache" "$temporary_dir/index-timeout.tsv"
rm "$fake_bin/timeout"
[[ -e "$TIMEOUT_MARKER" ]]
(( SECONDS - start_time < 18 ))
grep -q $'^2\t' "$temporary_dir/index-timeout.tsv"
[[ ! -e "$timeout_cache/3.png" ]]
[[ -z $(find "$timeout_cache" -maxdepth 1 -name '.download-*' -print -quit) ]]

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
  calls_before=$(wc -l < "$THUMBNAIL_LIMIT_LOG")
  BASH_ENV="$temporary_dir/fail-ulimit.bash" FAIL_ULIMIT_OPTION="$option" \
    sync_cover_fixture "$temporary_dir/allowed.png" "$cache" "$index"
  [[ $(wc -l < "$THUMBNAIL_LIMIT_LOG") -eq "$calls_before" ]]
  [[ ! -e "$cache/3.png" ]]
  grep -q $'^2\t' "$index"
  [[ -z $(find "$cache" -maxdepth 1 -name '.download-*' -print -quit) ]]
done

! grep -q 'https://api.raindrop.io/' "$temporary_dir/curl.log"

printf 'security checks passed: %d unsafe URLs rejected\n' "${#rejects[@]}"
