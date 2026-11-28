#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "${DEVELOPER_DIR:-}" ]; then
  DEVELOPER_DIR="$(/usr/bin/xcode-select -p)"
  if [ "$DEVELOPER_DIR" = "/Library/Developer/CommandLineTools" ]; then
    for candidate in /Volumes/*/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer; do
      if [ -d "$candidate" ]; then
        DEVELOPER_DIR="$candidate"
        break
      fi
    done
  fi
fi
export DEVELOPER_DIR
export NANZIP_7ZZ="${NANZIP_7ZZ:-$ROOT/.tools/7zip/26.06/7zz}"
if [ ! -x "$NANZIP_7ZZ" ]; then
  "$ROOT/Scripts/fetch-7zz.sh"
fi
/usr/bin/swift test --package-path "$ROOT" --scratch-path "${NANZIP_SCRATCH:-$HOME/Library/Developer/NanZipBuildTests}"
