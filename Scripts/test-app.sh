#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${NANZIP_APP:-$ROOT/build/NanZip.app}"
BIN="$APP/Contents/MacOS/NanZip"

if [ ! -x "$BIN" ]; then
  echo "Built app not found: $APP" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP"
"$BIN" --xpc-ping-test
"$BIN" --xpc-internal-test
"$BIN" --keychain-test
echo "NanZip app integration tests passed."
