#!/usr/bin/env bash
# Installs a packaged archive somewhere awkward and checks that it really boots.
#
#     scripts/smoke_release.sh dist/heddle-linux-x64.tar.gz
set -euo pipefail

archive="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"

export HEDDLE_NO_BROWSER=1

case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) windows=true ;;
  *) windows=false ;;
esac

temp="${RUNNER_TEMP:-$(mktemp -d)}"
# GNU tar reads the colon in D:\ as a remote host.
[ "$windows" = true ] && temp="$(cygpath -u "$temp")"

# The launcher finds this folder by itself, as it does after a real install.
home="$temp/Heddle Install"

# install.ps1 keeps Heddle out of a user folder with an accent. Nothing in it may
# depend on that folder either.
if [ "$windows" = true ]; then
  LOCALAPPDATA="$(cygpath -w "$temp/Usuário João")"
  export LOCALAPPDATA
  mkdir -p "$temp/Usuário João"
fi

app="$home/app"
log="$home/smoke.log"
mkdir -p "$app"
tar -xzf "$archive" -C "$app"

stop() {
  if [ "$windows" = true ]; then
    taskkill //F //IM erl.exe //T >/dev/null 2>&1 || true
    taskkill //F //IM beam.smp.exe //T >/dev/null 2>&1 || true
    cmd //c "$(cygpath -w "$app/heddle.cmd")" stop >/dev/null 2>&1 || true
  else
    kill -TERM "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
}

if [ "$windows" = true ]; then
  cmd //c "$(cygpath -w "$app/heddle.cmd")" > "$log" 2>&1 &
else
  "$app/heddle" > "$log" 2>&1 &
fi
pid=$!
trap stop EXIT

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

echo "Smoke test passed on port $port."
