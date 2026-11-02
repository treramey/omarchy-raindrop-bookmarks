#!/bin/bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
temporary_dir=$(mktemp -d)
trap 'rm -rf "$temporary_dir"' EXIT

mkdir -p "$temporary_dir/bin" "$temporary_dir/headers" "$temporary_dir/empty-bin"
cat > "$temporary_dir/bin/curl" <<'CURL'
#!/bin/bash
set -euo pipefail

arguments=("$@")
[[ ${arguments[0]:-} == -q ]]

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
require_pair --max-filesize 1048576
require_pair --connect-timeout 5
require_pair --max-time 15
require_pair --write-out '%{http_code}'
require_pair --url 'https://api.raindrop.io/rest/v1/user'

header=""
response_headers=""
for ((index = 0; index + 1 < ${#arguments[@]}; index++)); do
  case "${arguments[index]}" in
    --header) header=${arguments[index + 1]#@} ;;
    --dump-header) response_headers=${arguments[index + 1]} ;;
  esac
  [[ "${arguments[index]}" != *"$EXPECTED_TOKEN"* ]]
done
[[ -n "$header" && $(< "$header") == "Authorization: Bearer $EXPECTED_TOKEN" ]]
[[ $(stat -c %a "$header") == 600 ]]
[[ -n "$response_headers" ]]
printf '%b' "${MOCK_RESPONSE_HEADERS:-}" > "$response_headers"
[[ -z ${CURL_LOG:-} ]] || printf 'called\n' >> "$CURL_LOG"
printf '%s' "${MOCK_HTTP_STATUS:-200}"
exit "${MOCK_CURL_EXIT:-0}"
CURL
chmod +x "$temporary_dir/bin/curl"

legacy_output=$(printf 'submitted-token\n' | PATH="$temporary_dir/bin:$PATH" EXPECTED_TOKEN='submitted-token' \
  "$repo_dir/validate-token")
[[ -z "$legacy_output" ]]

printf 'saved-token\n' > "$temporary_dir/token"
legacy_output=$(PATH="$temporary_dir/bin:$PATH" EXPECTED_TOKEN='saved-token' \
  "$repo_dir/validate-token" --file "$temporary_dir/token")
[[ -z "$legacy_output" ]]

file_json=$(PATH="$temporary_dir/bin:$PATH" EXPECTED_TOKEN='saved-token' \
  "$repo_dir/validate-token" --json --file "$temporary_dir/token")
jq -e '.status == "ok"' <<< "$file_json" >/dev/null
: > "$temporary_dir/empty-token"
if file_json=$("$repo_dir/validate-token" --json --file "$temporary_dir/empty-token" 2>/dev/null); then
  echo 'validate-token accepted an empty token file' >&2
  exit 1
fi
jq -e '.status == "input" and .code == "empty"' <<< "$file_json" >/dev/null

boundary_token=$(printf 'x%.0s' {1..8192})
printf '%s\n' "$boundary_token" | "$repo_dir/configure-token" "$temporary_dir/boundary-token"
file_json=$(PATH="$temporary_dir/bin:$PATH" EXPECTED_TOKEN="$boundary_token" \
  "$repo_dir/validate-token" --json --file "$temporary_dir/boundary-token")
jq -e '.status == "ok"' <<< "$file_json" >/dev/null
[[ $("$repo_dir/token-fingerprint" "$temporary_dir/boundary-token") == "$(printf '%s' "$boundary_token" | sha256sum | cut -d' ' -f1)" ]]

mkfifo "$temporary_dir/fifo"
if timeout 1 "$repo_dir/validate-token" --file "$temporary_dir/fifo" >/dev/null 2>&1; then
  echo 'validate-token accepted a non-regular token file' >&2
  exit 1
fi

run_json() {
  local expected=$1 code=$2 token=$3
  shift 3
  local exit_code=0
  last_json=$(printf '%s\n' "$token" | env PATH="$temporary_dir/bin:$PATH" \
    TMPDIR="$temporary_dir/headers" EXPECTED_TOKEN="$token" CURL_LOG="$temporary_dir/curl.log" \
    MOCK_HTTP_STATUS=200 MOCK_CURL_EXIT=0 MOCK_RESPONSE_HEADERS='' "$@" \
    "$repo_dir/validate-token" --json 2> "$temporary_dir/error") || exit_code=$?
  if [[ "$expected" == ok ]]; then [[ "$exit_code" -eq 0 ]]; else [[ "$exit_code" -ne 0 ]]; fi
  jq -e --arg status "$expected" --arg code "$code" '
    .status == $status and .code == $code
    and (.retryAfterSeconds | type == "number" and floor == . and . >= 0 and . <= 86400)
  ' <<< "$last_json" >/dev/null
  [[ -z $(find "$temporary_dir/headers" -type f -print -quit) ]]
  ! grep -Fq 'secret-test-token' "$temporary_dir/error"
}

run_json ok '' secret-test-token
for status in 401 403; do
  run_json auth rejected secret-test-token MOCK_HTTP_STATUS="$status" MOCK_CURL_EXIT=22
done
run_json service http secret-test-token MOCK_HTTP_STATUS=503 MOCK_CURL_EXIT=22
run_json service response secret-test-token MOCK_HTTP_STATUS=302
run_json timeout request secret-test-token MOCK_HTTP_STATUS=000 MOCK_CURL_EXIT=28
for code in 6 7 35 60; do
  run_json network connection secret-test-token MOCK_HTTP_STATUS=000 MOCK_CURL_EXIT="$code"
done
run_json service response-size secret-test-token MOCK_CURL_EXIT=63
run_json local io secret-test-token MOCK_CURL_EXIT=23
run_json local dependency secret-test-token PATH="$temporary_dir/empty-bin"
run_json local io secret-test-token TMPDIR="$temporary_dir/missing-directory"

calls_before=$(wc -l < "$temporary_dir/curl.log")
run_json input empty ''
run_json input size "$(printf 'x%.0s' {1..8193})"
run_json input size "$(printf 'é%.0s' {1..4097})"
run_json input multiline $'first\nsecond'
run_json input multiline $'first\rsecond'
[[ $(wc -l < "$temporary_dir/curl.log") -eq "$calls_before" ]]

run_json rate-limit http secret-test-token MOCK_HTTP_STATUS=429 MOCK_CURL_EXIT=22
[[ $(jq -r .retryAfterSeconds <<< "$last_json") -eq 60 ]]
run_json rate-limit http secret-test-token MOCK_HTTP_STATUS=429 MOCK_CURL_EXIT=22 \
  MOCK_RESPONSE_HEADERS=$'Retry-After: 120\r\n'
[[ $(jq -r .retryAfterSeconds <<< "$last_json") -eq 120 ]]
run_json rate-limit http secret-test-token MOCK_HTTP_STATUS=429 MOCK_CURL_EXIT=22 \
  MOCK_RESPONSE_HEADERS=$'retry-after: 0\r\n'
[[ $(jq -r .retryAfterSeconds <<< "$last_json") -eq 1 ]]
run_json rate-limit http secret-test-token MOCK_HTTP_STATUS=429 MOCK_CURL_EXIT=22 \
  MOCK_RESPONSE_HEADERS=$'Retry-After: 999999999\r\n'
[[ $(jq -r .retryAfterSeconds <<< "$last_json") -eq 86400 ]]
reset=$(( $(date +%s) + 120 ))
run_json rate-limit http secret-test-token MOCK_HTTP_STATUS=429 MOCK_CURL_EXIT=22 \
  MOCK_RESPONSE_HEADERS="$(printf 'Retry-After: invalid-date\r\nX-RateLimit-Reset: %s\r\n' "$reset")"
retry=$(jq -r .retryAfterSeconds <<< "$last_json")
(( retry >= 118 && retry <= 120 ))
run_json rate-limit http secret-test-token MOCK_HTTP_STATUS=429 MOCK_CURL_EXIT=22 \
  MOCK_RESPONSE_HEADERS="$(printf 'Retry-After: %s\r\n' "$(date -u -d "@$reset" '+%a, %d %b %Y %H:%M:%S GMT')")"
retry=$(jq -r .retryAfterSeconds <<< "$last_json")
(( retry >= 118 && retry <= 120 ))

echo "token validation checks passed"
