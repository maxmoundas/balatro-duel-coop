#!/bin/bash
# macOS/Linux counterpart of build-friend-package.ps1: builds dist/BalatroMultiplayer-Setup.zip
# (the same package: Install.bat for Windows, install-mac.sh for macOS).
# Optional: --server host:port bakes in a dedicated server instead of in-game hosting.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
server=''
[ "${1:-}" = --server ] && server="${2:-}"

dist="$root/dist"
stage="$dist/BalatroMultiplayer-Setup"
rm -rf "$stage"
mkdir -p "$stage"
cp "$root"/installer/* "$stage/"
cp -R "$root/mod/BalatroMultiplayer" "$stage/BalatroMultiplayer"

if [ -n "$server" ]; then
  [[ "$server" =~ ^(.+):([0-9]+)$ ]] || { echo 'Server must look like host:port' >&2; exit 1; }
  sed -i.bak -e "s/server_host = ''/server_host = '${BASH_REMATCH[1]}'/" -e "s/server_port = '8788'/server_port = '${BASH_REMATCH[2]}'/" "$stage/BalatroMultiplayer/config.lua"
  rm -f "$stage/BalatroMultiplayer/config.lua.bak"
fi

rm -f "$dist/BalatroMultiplayer-Setup.zip"
(cd "$stage" && zip -qrX "$dist/BalatroMultiplayer-Setup.zip" . -x '.DS_Store')
echo "Built $dist/BalatroMultiplayer-Setup.zip"
