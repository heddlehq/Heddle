#!/usr/bin/env bash
# Turns the `heddle` release into what `heddle install` downloads, and builds that
# command.
#
#     MIX_ENV=prod mix release heddle
#     scripts/package_release.sh linux-x64
#
# Writes dist/heddle-<target>.tar.gz and dist/heddle-cli-<target>, each with its
# .sha256. Every platform uses tar.gz because Windows 10 and later ship a tar that
# reads it.
set -euo pipefail

POSTGRES_VERSION=17.11.0

target="${1:?usage: package_release.sh <linux-x64|linux-arm64|macos-arm64|windows-x64>}"

case "$target" in
  linux-x64) postgres_platform=linux-amd64 ;;
  linux-arm64) postgres_platform=linux-arm64v8 ;;
  macos-arm64) postgres_platform=darwin-arm64v8 ;;
  windows-x64) postgres_platform=windows-amd64 ;;
  *) echo "Unknown target: $target" >&2; exit 1 ;;
esac

release=_build/prod/rel/heddle
[ -d "$release" ] || { echo "No release at $release. Run: MIX_ENV=prod mix release heddle" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

artifact="embedded-postgres-binaries-$postgres_platform"
url="https://repo1.maven.org/maven2/io/zonky/test/postgres/$artifact/$POSTGRES_VERSION/$artifact-$POSTGRES_VERSION.jar"

echo "Downloading Postgres $POSTGRES_VERSION for $postgres_platform"
curl -fsSL --retry 3 -o "$work/postgres.jar" "$url"
unzip -q "$work/postgres.jar" -d "$work/jar"

rm -rf "$release/pgsql"
mkdir -p "$release/pgsql"
tar -xJf "$work"/jar/postgres-*.txz -C "$release/pgsql"

# Linux distributions patch OpenSSL and ncurses differently: Fedora's libcrypto
# has no SM4, so a build linked against Debian's won't even boot there. Ship the
# ones the VM was built with and point its binaries at them.
if [[ "$target" == linux-* ]]; then
  rm -rf "$release/native"
  mkdir -p "$release/native"

  beam="$(ls "$release"/erts-*/bin/beam.smp)"
  crypto_dir="$(ls -d "$release"/lib/crypto-*/priv/lib)"

  for library in libcrypto.so.3 libtinfo.so.6; do
    source_path="$(ldd "$beam" "$crypto_dir/crypto.so" | awk -v lib="$library" '$1 == lib { print $3; exit }')"
    [ -n "$source_path" ] || { echo "$library is not linked. Check the build." >&2; exit 1; }
    cp -L "$source_path" "$release/native/"
  done

  patchelf --set-rpath '$ORIGIN/../../native' "$beam"
  for nif in "$crypto_dir"/*.so; do
    patchelf --set-rpath '$ORIGIN/../../../../native' "$nif"
  done
fi

# Neither the VM nor Postgres ships the Visual C++ runtime. CI runners have it
# installed, so a build without these would pass here and fail on a clean PC.
if [ "$target" = windows-x64 ]; then
  for dll in vcruntime140.dll vcruntime140_1.dll msvcp140.dll; do
    cp "/c/Windows/System32/$dll" "$release/pgsql/bin/"
    cp "/c/Windows/System32/$dll" "$(ls -d "$release"/erts-*/bin)/"
  done
fi

# A VM linked to Homebrew's OpenSSL would only boot on machines that have it.
if [ "$target" = macos-arm64 ]; then
  if otool -L "$release"/lib/crypto-*/priv/lib/crypto.so | grep -E '/opt/|/usr/local/'; then
    echo "crypto.so links a library that won't exist on other machines." >&2
    exit 1
  fi
fi

cp VERSION "$release/"

checksum() {
  (cd dist && { sha256sum "$1" > "$1.sha256" 2>/dev/null || shasum -a 256 "$1" > "$1.sha256"; })
  echo "dist/$1: $(du -h "dist/$1" | cut -f1)"
}

mkdir -p dist
archive="heddle-$target.tar.gz"
tar -czf "dist/$archive" -C "$release" .
checksum "$archive"

# No cgo, so one binary runs on any Linux, musl included: that's how a machine that
# can't run the release still gets offered Docker or Treadle.
cli="heddle-cli-$target"
[ "$target" = windows-x64 ] && cli="$cli.exe"
(
  cd cli
  CGO_ENABLED=0 go build -trimpath \
    -ldflags "-s -w -X github.com/heddlehq/heddle/cli/internal/commands.Version=$(cat ../VERSION)" \
    -o "../dist/$cli" ./cmd/heddle
)
checksum "$cli"
