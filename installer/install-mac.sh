#!/bin/bash
# Balatro Duel & Co-op - installer for macOS.
# Installs Lovely (mod loader), Steamodded (mod framework) and the Balatro Duel & Co-op mod.
# Already-installed Lovely/Steamodded are left alone.
#
# Run it in Terminal, either straight from the web:
#   curl -fsSL https://github.com/maxmoundas/balatro-duel-coop/releases/latest/download/install-mac.sh | bash
# or from the unzipped BalatroDuelCoop-Setup folder:
#   bash files/install-mac.sh
#
# On macOS, Lovely is loaded by a small launcher that takes the place of the game's
# executable (Balatro.app/Contents/MacOS/love; the real one is kept as love-original).
# That way launching from Steam, and accepting a Steam invite while the game is closed,
# both start the modded game.

set -euo pipefail

# Versions the mod was tested with (same as the Windows installer).
LOVELY_VERSION='v0.10.0'
SMODS_URL='https://github.com/Steamodded/smods/archive/refs/tags/26.1002.0.zip'
# BMP_PACKAGE_URL overrides where the package comes from (e.g. file:///path/to/zip for testing).
PACKAGE_URL="${BMP_PACKAGE_URL:-https://github.com/maxmoundas/balatro-duel-coop/releases/latest/download/BalatroDuelCoop-Setup.zip}"

# Run from the unzipped package, or piped from curl? In the second case, download the
# package and run the copy of this script inside it.
src="${BASH_SOURCE[0]:-}"
if [ -z "$src" ] || [ ! -f "$src" ] || [ ! -f "$(dirname "$src")/common-mac.sh" ]; then
  tmp="$(mktemp -d -t bmp)"
  echo 'Downloading Balatro Duel & Co-op...'
  curl -fL --retry 3 --progress-bar -o "$tmp/package.zip" "$PACKAGE_URL" || { echo 'Download failed (are you online?)' >&2; exit 1; }
  unzip -q "$tmp/package.zip" -d "$tmp/package"
  script="$(find "$tmp/package" -name install-mac.sh | head -n 1)"
  [ -n "$script" ] || { echo 'install-mac.sh not found in the download' >&2; exit 1; }
  status=0; bash "$script" "$@" || status=$?
  rm -rf "$tmp"
  exit $status
fi
here="$(cd "$(dirname "$src")" && pwd)"
. "$here/common-mac.sh"

work="$(mktemp -d -t bmp)"
trap 'rm -rf "$work"' EXIT

download() { # url dest
  curl -fL --retry 3 --progress-bar -o "$2" "$1" || die "Download failed: $1 (are you online?)"
}

main() {
  printf '%sBalatro Duel & Co-op installer (macOS)%s\n' "$YELLOW" "$RESET"

  wait_balatro_closed

  step 'Finding Balatro'
  local game; game="$(get_balatro_dir)"
  done_ "$game"
  [ -w "$game" ] || die "Can't write to $game."

  step 'Lovely (mod loader)'
  if [ -f "$game/liblovely.dylib" ]; then
    done_ 'already installed'
  else
    local arch=x86_64
    [ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = 1 ] && arch=aarch64
    download "https://github.com/ethangreen-dev/lovely-injector/releases/download/$LOVELY_VERSION/lovely-$arch-apple-darwin.tar.gz" "$work/lovely.tar.gz"
    mkdir -p "$work/lovely"
    tar -xzf "$work/lovely.tar.gz" -C "$work/lovely"
    local dylib; dylib="$(find "$work/lovely" -name liblovely.dylib | head -n 1)"
    [ -n "$dylib" ] || die 'liblovely.dylib not found in the Lovely download'
    cp "$dylib" "$game/liblovely.dylib"
    done_ "installed ($arch)"
  fi
  xattr -d com.apple.quarantine "$game/liblovely.dylib" 2>/dev/null || true

  step 'Lovely launcher (so Steam starts the modded game)'
  install_launcher "$game"

  mkdir -p "$MODS_DIR"

  step 'Steamodded (mod framework)'
  local existing; existing="$(find_smods | head -n 1)"
  if [ -n "$existing" ]; then
    done_ "already installed ($(basename "$existing"))"
  else
    download "$SMODS_URL" "$work/smods.zip"
    mkdir -p "$work/smods"
    unzip -q "$work/smods.zip" -d "$work/smods"
    local root; root="$(find "$work/smods" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    [ -n "$root" ] || die 'Steamodded download was empty'
    mv "$root" "$MODS_DIR/smods"
    done_ 'installed'
  fi

  step 'Balatro Duel & Co-op mod'
  local src="$here/BalatroDuelCoop"
  [ -f "$src/main.lua" ] || die 'BalatroDuelCoop folder is missing next to this installer. Unzip the whole package first.'
  rm -rf "$MODS_DIR/BalatroDuelCoop"
  cp -R "$src" "$MODS_DIR/BalatroDuelCoop"
  xattr -dr com.apple.quarantine "$MODS_DIR/BalatroDuelCoop" "$MODS_DIR/smods" 2>/dev/null || true
  # Builds before the rename installed to Mods/BalatroMultiplayer; two copies would both load.
  if [ -d "$MODS_DIR/BalatroMultiplayer" ]; then
    rm -rf "$MODS_DIR/BalatroMultiplayer"
    done_ 'removed old BalatroMultiplayer folder'
  fi
  done_ 'installed'

  printf '\n%sAll done! Launch Balatro from Steam and click MULTIPLAYER on the main menu.%s\n' "$GREEN" "$RESET"
  echo 'Your friend can now invite you from their lobby (Invite Steam Friends).'
  echo 'If a Balatro update ever makes the MULTIPLAYER button disappear, run this installer again.'
}

main "$@"
