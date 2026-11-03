#!/bin/bash
set -euo pipefail
umask 077

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
shell_dir=${OMARCHY_PATH:-/usr/share/omarchy}/shell
work_dir=$(mktemp -d)
trap 'rm -rf -- "$work_dir"' EXIT
mkdir -p "$work_dir/config" "$work_dir/home" "$work_dir/helpers" "$work_dir/empty-bin"
for module in Commons Ui services; do
  ln -s "$shell_dir/$module" "$work_dir/config/$module"
done
cp "$repo_dir/"*.qml "$repo_dir/FuzzySearch.js" "$work_dir/config/"
cp "$repo_dir/tests/raindrop-connection.qml" "$work_dir/config/shell.qml"

# Stub only the project's validation-helper protocol, not the Raindrop API.
# The actual atomic credential writer is used for successful save attempts.
cat > "$work_dir/helpers/validator" <<'VALIDATOR'
#!/bin/bash
set -euo pipefail
name=${0##*/}
[[ ${1:-} == --json ]]
shift
if [[ ${1:-} == --file ]]; then
  [[ $(cat -- "$2") == old-valid-token ]]
else
  IFS= read -r token
  [[ "$token" == validated-token || "$name" == auth ]]
fi
printf '%s\n' "$name" >> "$TEST_CONNECTION_DIR/calls"
case "$name" in
  hang) sleep 5; printf 'late validation\n' > "$TEST_CONNECTION_DIR/leaked-validation" ;;
  malformed) printf 'not json\n'; exit 0 ;;
  false-ok) printf '{"status":"ok","code":"","retryAfterSeconds":0}\n'; exit 1 ;;
  rate) printf '{"status":"rate-limit","code":"http","retryAfterSeconds":2}\n'; exit 1 ;;
  auth) printf '{"status":"auth","code":"rejected","retryAfterSeconds":0}\n'; exit 1 ;;
  network|service) printf '{"status":"%s","code":"request","retryAfterSeconds":0}\n' "$name"; exit 1 ;;
esac
printf '{"status":"ok","code":"","retryAfterSeconds":0}\n'
VALIDATOR
for helper in ok auth network service rate hang malformed false-ok; do
  cp "$work_dir/helpers/validator" "$work_dir/helpers/$helper"
done
cat > "$work_dir/helpers/writer-hang" <<'WRITER'
#!/bin/bash
sleep 5
printf 'late writer\n' > "$TEST_CONNECTION_DIR/leaked-writer"
WRITER
printf '#!/bin/bash\nexit 0\n' > "$work_dir/helpers/noop"
chmod +x "$work_dir/helpers/noop"
printf 'parent is a regular file\n' > "$work_dir/not-a-directory"
for file in race-token stored-token root-token; do
  printf 'old-valid-token\n' > "$work_dir/$file"
done

run_fixture() {
  local config=$1 platform=$2
  shift 2
  if ! env HOME="$work_dir/home" XDG_CONFIG_HOME="$work_dir/home/.config" \
    XDG_DATA_HOME="$work_dir/home/.local/share" XDG_CACHE_HOME="$work_dir/home/.cache" \
    QT_QPA_PLATFORM="$platform" QT_QUICK_BACKEND=software TEST_CONNECTION_DIR="$work_dir" \
    TEST_REPO_DIR="$repo_dir" "$@" /usr/bin/timeout 30s /usr/bin/quickshell --no-color \
    -p "$config" > "$work_dir/output" 2>&1; then
    cat "$work_dir/output"
    return 1
  fi
  cat "$work_dir/output"
  ! grep -Eq '(TypeError|ReferenceError|Binding loop|Unable to assign)' "$work_dir/output"
  grep -q 'Raindrop connection checks passed' "$work_dir/output"
}

run_fixture "$work_dir/config" offscreen
[[ $(< "$work_dir/race-token") == old-valid-token ]]
[[ $(< "$work_dir/stored-token") == old-valid-token ]]
for file in success-token duplicate-token recovered-helper-token recovered-save-token rate-retry-token; do
  [[ $(< "$work_dir/$file") == validated-token ]]
  [[ $(stat -c %a "$work_dir/$file") == 600 ]]
done
[[ $(grep -c '^rate$' "$work_dir/calls") -eq 1 ]]
[[ ! -e "$work_dir/timeout-token" && ! -e "$work_dir/leaked-validation" && ! -e "$work_dir/leaked-writer" ]]

# Exercise a true QProcess failed-to-start, rather than just bash exiting127.
run_fixture "$work_dir/config" offscreen PATH="$work_dir/empty-bin" TEST_MISSING_LAUNCHER=1

# The integration fixture loads the real overlay without ever opening its
# PanelWindow. Its backend requires Wayland even when that window is hidden.
cp "$repo_dir/tests/raindrop-onboarding.qml" "$work_dir/config/shell.qml"
run_fixture "$work_dir/config" wayland
[[ $(< "$work_dir/root-token") == validated-token ]]
