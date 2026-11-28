#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${SEVENZIP_VERSION:-26.06}"
DEST="$ROOT/.tools/7zip/$VERSION"
ARCH="$(uname -m)"

if [ "$ARCH" = "arm64" ]; then
  ASSET="7z2606-mac.tar.xz"
  SHA256="b6f17920b4240940461dac8ef4009891881ac44d2a5ead625ede2ec8472185dd"
else
  ASSET="7z2606-mac-x64.tar.xz"
  SHA256="3af68b124052da7fc2a246c96b0bea6a68bfee389baa788f4cead1a133445586"
fi

URL="https://github.com/ip7z/7zip/releases/download/$VERSION/$ASSET"
ARCHIVE="$DEST/$ASSET"

mkdir -p "$DEST"
if [ ! -x "$DEST/7zz" ]; then
  curl -fL --retry 3 --connect-timeout 20 -o "$ARCHIVE" "$URL"
  ACTUAL="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
  if [ "$ACTUAL" != "$SHA256" ]; then
    echo "7-Zip checksum mismatch" >&2
    exit 1
  fi
  tar -xJf "$ARCHIVE" -C "$DEST" 7zz
  chmod 755 "$DEST/7zz"
fi

"$DEST/7zz" i | head -1
