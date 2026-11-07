#!/usr/bin/env bash
# Installs a packaged archive somewhere awkward, checks that the `heddle` command
# really boots it, and that `heddle stop` leaves nothing running.
#
#     scripts/smoke_release.sh dist/heddle-linux-x64.tar.gz dist/heddle-cli-linux-x64
set -euo pipefail

archive="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cli="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"

export HEDDLE_NO_BROWSER=1

case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) windows=true ;;
  *) windows=false ;;
esac

temp="${RUNNER_TEMP:-$(mktemp -d)}"
# GNU tar reads the colon in D:\ as a remote host.
[ "$windows" = true ] && temp="$(cygpath -u "$temp")"

home="$temp/Heddle Install"
export HEDDLE_HOME="$home"

# `heddle install` keeps Heddle out of a user folder with an accent. Nothing in it
# may depend on that folder either.
if [ "$windows" = true ]; then
  LOCALAPPDATA="$(cygpath -w "$temp/Usuário João")"
  export LOCALAPPDATA
  mkdir -p "$temp/Usuário João"
fi

app="$home/app"
log="$home/smoke.log"
mkdir -p "$app"
tar -xzf "$archive" -C "$app"

[ "$windows" = true ] && HEDDLE_HOME="$(cygpath -w "$home")"

chmod +x "$cli"
"$cli" start > "$log" 2>&1 &
pid=$!
trap '"$cli" stop >/dev/null 2>&1 || true' EXIT

for _ in $(seq 1 180); do
  grep -q 'Heddle is running' "$log" && break
  kill -0 "$pid" 2>/dev/null || break
  sleep 1
done

cat "$log"

port="$(grep -oE 'localhost:[0-9]+' "$log" | head -1 | cut -d: -f2)"
[ -n "$port" ] || { echo "Heddle never came up." >&2; exit 1; }

status="$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$port/setup")"
[ "$status" = 200 ] || { echo "/setup answered $status." >&2; exit 1; }

if grep -q 'Pythonx init skipped' "$log"; then
  echo "Python did not initialize." >&2
  exit 1
fi

"$cli" status

# Stopping has to take the whole thing down, and end the foreground command with it.
"$cli" stop
wait "$pid"

status="$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$port/setup" || true)"
[ "$status" = 000 ] || { echo "Still answering after heddle stop: $status." >&2; exit 1; }

if [ "$windows" = false ] && pgrep -f "$app/" >/dev/null; then
  echo "heddle stop left something running:" >&2
  pgrep -fa "$app/" >&2
  exit 1
fi

echo "Smoke test passed on port $port."
