#!/bin/bash
# macOS/Linux counterpart of build-friend-package.ps1: builds dist/BalatroDuelCoop-Setup.zip
# (the same package: Install.bat for Windows, install-mac.sh for macOS).
# Also builds the release zips for mod managers and listings (skipped with --server):
#   dist/BalatroDuelCoop.zip              the mod folder only (Mod Index / Balatro Mod Manager, Nexus)
#   dist/BalatroDuelCoop-Thunderstore.zip manifest.json, icon.png, README.md + the mod's files at the root
# Optional: --server host:port bakes in a dedicated server instead of in-game hosting.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
server=''
[ "${1:-}" = --server ] && server="${2:-}"

dist="$root/dist"
stage="$dist/BalatroDuelCoop-Setup"
rm -rf "$stage"
mkdir -p "$stage"
# Only what Windows players double-click (and the README) sits at the top; the scripts they
# run, the Mac scripts and the mod itself go in files/.
mkdir -p "$stage/files"
for f in "$root"/installer/*; do
  case "$(basename "$f")" in
    Install.bat|Uninstall.bat|README.txt) cp "$f" "$stage/" ;;
    *) cp "$f" "$stage/files/" ;;
  esac
done
cp -R "$root/mod/BalatroDuelCoop" "$stage/files/BalatroDuelCoop"

if [ -n "$server" ]; then
  [[ "$server" =~ ^(.+):([0-9]+)$ ]] || { echo 'Server must look like host:port' >&2; exit 1; }
  sed -i.bak -e "s/server_host = ''/server_host = '${BASH_REMATCH[1]}'/" -e "s/server_port = '8788'/server_port = '${BASH_REMATCH[2]}'/" "$stage/files/BalatroDuelCoop/config.lua"
  rm -f "$stage/files/BalatroDuelCoop/config.lua.bak"
fi

rm -f "$dist/BalatroDuelCoop-Setup.zip"
(cd "$stage" && zip -qrX "$dist/BalatroDuelCoop-Setup.zip" . -x '.DS_Store')
echo "Built $dist/BalatroDuelCoop-Setup.zip"
[ -n "$server" ] && exit 0

# The version lives in the mod's json; the Thunderstore manifest must match it.
version="$(sed -n 's/^[[:space:]]*"version":[[:space:]]*"\([^"]*\)".*/\1/p' "$root/mod/BalatroDuelCoop/BalatroDuelCoop.json")"
ts_version="$(sed -n 's/^[[:space:]]*"version_number":[[:space:]]*"\([^"]*\)".*/\1/p' "$root/publish/thunderstore/manifest.json")"
[ "$version" = "$ts_version" ] || { echo "Version mismatch: mod json says $version, publish/thunderstore/manifest.json says $ts_version" >&2; exit 1; }

rm -f "$dist/BalatroDuelCoop.zip"
(cd "$root/mod" && zip -qrX "$dist/BalatroDuelCoop.zip" BalatroDuelCoop -x '*.DS_Store')
echo "Built $dist/BalatroDuelCoop.zip"

ts="$dist/BalatroDuelCoop-Thunderstore"
rm -rf "$ts" "$ts.zip"
cp -R "$root/mod/BalatroDuelCoop" "$ts"
cp "$root/publish/thunderstore/manifest.json" "$root/publish/thunderstore/icon.png" "$root/publish/thunderstore/README.md" "$ts/"
(cd "$ts" && zip -qrX "$ts.zip" . -x '.DS_Store')
echo "Built $ts.zip (version $version)"
