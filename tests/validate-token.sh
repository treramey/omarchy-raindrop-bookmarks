#!/bin/bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
temporary_dir=$(mktemp -d)
trap 'rm -rf "$temporary_dir"' EXIT

mkdir -p "$temporary_dir/bin"
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
require_pair --url 'https://api.raindrop.io/rest/v1/user'

for ((index = 0; index + 1 < ${#arguments[@]}; index++)); do
  if [[ ${arguments[index]} == --header ]]; then
    header=${arguments[index + 1]#@}
    [[ $(< "$header") == "Authorization: Bearer $EXPECTED_TOKEN" ]]
    exit 0
  fi
done
echo 'authorization header was not provided' >&2
exit 91
CURL
chmod +x "$temporary_dir/bin/curl"

PATH="$temporary_dir/bin:$PATH" EXPECTED_TOKEN='submitted-token' \
  printf 'submitted-token\n' | PATH="$temporary_dir/bin:$PATH" EXPECTED_TOKEN='submitted-token' \
  "$repo_dir/validate-token"

printf 'saved-token\n' > "$temporary_dir/token"
PATH="$temporary_dir/bin:$PATH" EXPECTED_TOKEN='saved-token' \
  "$repo_dir/validate-token" --file "$temporary_dir/token"

mkfifo "$temporary_dir/fifo"
if timeout 1 "$repo_dir/validate-token" --file "$temporary_dir/fifo" >/dev/null 2>&1; then
  echo 'validate-token accepted a non-regular token file' >&2
  exit 1
fi

echo "token validation checks passed"
